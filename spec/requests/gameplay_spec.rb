require "rails_helper"

RSpec.describe "Gameplay API" do
  let(:user) { create(:user) }
  let(:game) { create(:game, questions_per_session: 2, steps_per_session: 2) }

  def login
    post session_path, params: { email: user.email, password: "password123" }
  end

  def create_bug_hunt_questions(count = 3)
    count.times do |i|
      create(:question, game: game,
             content: { "language" => "ruby", "code_lines" => [ "a#{i}", "b#{i}" ],
                        "bug_types" => [ "sql_injection", "xss" ] },
             answer_key: { "buggy_line" => 1, "bug_type" => "sql_injection",
                           "explanation" => "..." })
    end
  end

  before { login }

  describe "POST /api/v1/games/:slug/sessions" do
    it "tạo lượt mới bắt đầu từ 0 điểm và trả bước đầu tiên (BR-05)" do
      create_bug_hunt_questions

      post api_v1_game_sessions_path(slug: game.slug), as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["score"]).to eq(0)
      expect(body["attempt_number"]).to eq(1)
      expect(body["total_positions"]).to eq(2)
      expect(body["current"]["position"]).to eq(1)
    end

    it "không bao giờ trả answer_key về client (BR-03)" do
      create_bug_hunt_questions

      post api_v1_game_sessions_path(slug: game.slug), as: :json

      expect(response.body).not_to include("answer_key")
      expect(response.body).not_to include("buggy_line")
    end

    it "trả 422 khi ngân hàng câu hỏi không đủ" do
      create_bug_hunt_questions(1)

      post api_v1_game_sessions_path(slug: game.slug), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("NO_QUESTIONS_AVAILABLE")
    end

    it "tăng attempt_number ở lượt kế tiếp (BR-10)" do
      create_bug_hunt_questions(4)

      post api_v1_game_sessions_path(slug: game.slug), as: :json
      first_id = response.parsed_body["session_id"]
      GameSession.find(first_id).abandon!(GameSession::USER_QUIT)

      post api_v1_game_sessions_path(slug: game.slug), as: :json

      expect(response.parsed_body["attempt_number"]).to eq(2)
    end

    it "yêu cầu đăng nhập" do
      delete session_path
      create_bug_hunt_questions

      post api_v1_game_sessions_path(slug: game.slug), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/sessions/:id/answers" do
    let(:session_id) do
      create_bug_hunt_questions
      post api_v1_game_sessions_path(slug: game.slug), as: :json
      response.parsed_body["session_id"]
    end

    def submit(position:, answer: { line: 1, bug_type: "sql_injection" }, elapsed_ms: 1_000)
      post api_v1_session_answers_path(id: session_id),
           params: { position: position, answer: answer, elapsed_ms: elapsed_ms }, as: :json
    end

    it "chấm ở server và cộng dồn điểm (BR-02, BR-31)" do
      submit(position: 1)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["awarded_score"]).to eq(10)
      expect(body["total_score"]).to eq(10)
      expect(body["finished"]).to be false
      expect(body["next"]["position"]).to eq(2)
    end

    it "bỏ qua điểm client tự gửi lên (BR-02)" do
      submit(position: 1, answer: { line: 99, bug_type: "xss", score: 100 })

      expect(response.parsed_body["awarded_score"]).to eq(0)
      expect(response.parsed_body["total_score"]).to eq(0)
    end

    it "trả 409 khi nộp lại cùng một position (§9)" do
      submit(position: 1)
      submit(position: 1)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("POSITION_CONFLICT")
    end

    it "trả 409 khi nộp lệch thứ tự" do
      submit(position: 2)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("POSITION_CONFLICT")
    end

    it "kết thúc lượt sau bước cuối và trả summary (BR-30)" do
      submit(position: 1)
      submit(position: 2)

      body = response.parsed_body
      expect(body["finished"]).to be true
      expect(body["next"]).to be_nil
      expect(body["summary"]["score"]).to eq(20)
      expect(body["summary"]["is_new_best"]).to be true

      session = GameSession.find(session_id)
      expect(session.state).to eq(GameSession::FINISHED)
      expect(session.finished_at).to be_present
    end

    it "không cho nộp tiếp sau khi lượt đã kết thúc" do
      submit(position: 1)
      submit(position: 2)
      submit(position: 3)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("SESSION_FINISHED")
    end

    it "không cho thao tác trên lượt của người khác (spec §12)" do
      other_session = create(:game_session, user: create(:user), game: game)

      post api_v1_session_answers_path(id: other_session.id),
           params: { position: 1, answer: { line: 1, bug_type: "xss" } }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "kẹp elapsed_ms theo thời gian server đo được (BR-21)" do
      # Client khai 0ms để ăn hệ số 1.0, nhưng server đo thời gian thật.
      create_bug_hunt_questions
      post api_v1_game_sessions_path(slug: game.slug), as: :json
      sid = response.parsed_body["session_id"]
      GameSession.find(sid).update!(started_at: 90.seconds.ago)

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { line: 1, bug_type: "sql_injection" },
                     elapsed_ms: 0 }, as: :json

      # 90 giây > 60 giây nên hệ số 0.5 → floor(10 * 0.5) = 5
      expect(response.parsed_body["awarded_score"]).to eq(5)
    end
  end

  describe "PROD Roulette — hành động không thể thu hồi (BR-29, §8.2)" do
    let(:roulette) { create(:game, :scenario_based, steps_per_session: 3) }

    before do
      create(:question, game: roulette,
             content: { "scenario" => "test", "nodes" => [] },
             answer_key: { "option_effects" => {
               "safe" => { "points" => 10, "irreversible" => false, "consequence_text" => "ok" },
               "fatal" => { "points" => 10, "irreversible" => true,
                            "consequence_text" => "Email đã gửi thật" }
             } })
    end

    it "kết thúc lượt ngay và giữ điểm các bước trước (BR-31)" do
      post api_v1_game_sessions_path(slug: roulette.slug), as: :json
      sid = response.parsed_body["session_id"]

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { node_key: "n1", option_key: "safe" } }, as: :json
      expect(response.parsed_body["total_score"]).to eq(10)

      post api_v1_session_answers_path(id: sid),
           params: { position: 2, answer: { node_key: "n2", option_key: "fatal" } }, as: :json

      body = response.parsed_body
      expect(body["awarded_score"]).to eq(0)
      expect(body["total_score"]).to eq(10)
      expect(body["finished"]).to be true
      expect(body["explanation"]).to include("Email đã gửi thật")
    end
  end

  describe "Spec Detective — AI chưa sẵn sàng (§8.5, BR-33)" do
    let(:detective) do
      create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective",
             questions_per_session: 1, steps_per_session: 1)
    end

    it "trả 503 và đánh dấu lượt là system_error, không tính điểm" do
      create(:question, game: detective, content: { "requirement_text" => "xử lý nhanh" },
             answer_key: { "ambiguous_points" => [ "nhanh" ] })

      post api_v1_game_sessions_path(slug: detective.slug), as: :json
      sid = response.parsed_body["session_id"]

      post api_v1_session_answers_path(id: sid),
           params: { position: 1,
                     answer: { ambiguous_points: [ "nhanh" ], questions: "Nhanh là bao lâu?" } },
           as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["code"]).to eq("GRADING_UNAVAILABLE")

      session = GameSession.find(sid)
      expect(session.state).to eq(GameSession::ABANDONED)
      expect(session.abandoned_reason).to eq(GameSession::SYSTEM_ERROR)
      expect(GameSession.finished).to be_empty
    end
  end

  describe "POST /api/v1/sessions/:id/abandon (§8.4)" do
    it "đánh dấu user_quit và không tính vào leaderboard" do
      create_bug_hunt_questions
      post api_v1_game_sessions_path(slug: game.slug), as: :json
      sid = response.parsed_body["session_id"]

      post api_v1_session_abandon_path(id: sid), as: :json

      expect(response).to have_http_status(:no_content)
      session = GameSession.find(sid)
      expect(session.abandoned_reason).to eq(GameSession::USER_QUIT)
      expect(GameSession.finished).to be_empty
    end
  end

  describe "POST /api/v1/questions/:id/reports (BR-17)" do
    it "ghi nhận báo cáo" do
      question = create(:question, game: game)

      post api_v1_question_reports_path(id: question.id),
           params: { reason: "Đáp án sai" }, as: :json

      expect(response).to have_http_status(:created)
      expect(QuestionReport.last.status).to eq(QuestionReport::OPEN)
    end

    it "chặn báo trùng cùng một câu" do
      question = create(:question, game: game)
      post api_v1_question_reports_path(id: question.id), params: { reason: "a" }, as: :json
      post api_v1_question_reports_path(id: question.id), params: { reason: "b" }, as: :json

      expect(response).to have_http_status(:conflict)
    end
  end
end
