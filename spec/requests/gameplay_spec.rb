require "rails_helper"

RSpec.describe "Gameplay API" do
  let(:user) { create(:user) }
  let(:game) { create(:game, questions_per_session: 2, steps_per_session: 2) }

  def login
    post session_path, params: { email: user.email, password: "password123" }
  end

  def create_bug_hunt_questions(count = 3, language: "ruby")
    count.times do |i|
      create(:question, game: game,
             content: { "language" => language, "code_lines" => [ "a#{i}", "b#{i}" ],
                        "bug_types" => [ "sql_injection", "xss" ] },
             answer_key: { "buggy_line" => 1, "bug_type" => "sql_injection",
                           "explanation" => "..." })
    end
  end

  # Đề mang trọn danh sách 12 loại bug như đề thật, để kiểm tra phần rút bớt lựa chọn.
  def create_full_bug_hunt_questions(count = 3, language: "ruby")
    count.times do |i|
      create(:question, game: game,
             content: { "language" => language, "code_lines" => [ "full#{i}" ],
                        "bug_types" => Question::BUG_HUNT_TYPES },
             answer_key: { "buggy_line" => 1,
                           "bug_type" => Question::BUG_HUNT_TYPES[i % Question::BUG_HUNT_TYPES.size],
                           "explanation" => "..." })
    end
  end

  # Bug Hunt phân đề theo ngôn ngữ nên tạo lượt phải kèm language.
  def start_session(language: "ruby")
    post api_v1_game_sessions_path(slug: game.slug),
         params: { language: language }.compact, as: :json
  end

  before { login }

  describe "POST /api/v1/games/:slug/sessions" do
    it "tạo lượt mới bắt đầu từ 0 điểm và trả bước đầu tiên (BR-05)" do
      create_bug_hunt_questions

      start_session

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["score"]).to eq(0)
      expect(body["attempt_number"]).to eq(1)
      expect(body["total_positions"]).to eq(2)
      expect(body["current"]["position"]).to eq(1)
    end

    it "không bao giờ trả answer_key về client (BR-03)" do
      create_bug_hunt_questions

      start_session

      expect(response.body).not_to include("answer_key")
      expect(response.body).not_to include("buggy_line")
    end

    it "trả 422 khi ngân hàng câu hỏi không đủ" do
      create_bug_hunt_questions(1)

      start_session

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("NO_QUESTIONS_AVAILABLE")
    end

    it "trả 422 khi Bug Hunt không kèm ngôn ngữ" do
      create_bug_hunt_questions

      start_session(language: nil)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("INVALID_LANGUAGE")
    end

    it "trả 422 khi ngôn ngữ không có trong ngân hàng câu hỏi" do
      create_bug_hunt_questions

      start_session(language: "cobol")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("INVALID_LANGUAGE")
    end

    it "chốt ngôn ngữ đã chọn vào lượt và chỉ ra đề đúng ngôn ngữ đó" do
      create_bug_hunt_questions(2, language: "ruby")
      create_bug_hunt_questions(2, language: "java")

      start_session(language: "java")

      expect(response.parsed_body["language"]).to eq("java")
      expect(response.parsed_body["current"]["content"]["language"]).to eq("java")

      sid = response.parsed_body["session_id"]
      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { line: 1, bug_type: "sql_injection" } }, as: :json

      get api_v1_session_current_path(id: sid), as: :json
      expect(response.parsed_body["current"]["content"]["language"]).to eq("java")
      expect(GameSession.find(sid).language).to eq("java")
    end

    it "câu hiển thị cho client chính là câu server chấm" do
      create_bug_hunt_questions(6)

      start_session
      shown_id = response.parsed_body["current"]["question_id"]
      sid = response.parsed_body["session_id"]

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { line: 1, bug_type: "sql_injection" } }, as: :json

      expect(SessionAnswer.sole.question_id).to eq(shown_id)
    end

    it "chỉ hiện 4 loại bug và luôn có đáp án đúng trong đó" do
      create_full_bug_hunt_questions

      start_session

      types = response.parsed_body["current"]["content"]["bug_types"]
      expect(types.size).to eq(GameSessions::StepProvider::BUG_HUNT_TYPE_CHOICES)
      expect(types - Question::BUG_HUNT_TYPES).to be_empty
      shown_key = Question.find(response.parsed_body["current"]["question_id"])
                          .answer_key["bug_type"]
      expect(types).to include(shown_key)
    end

    it "tải lại giữa bước vẫn thấy đúng danh sách loại bug đó" do
      create_full_bug_hunt_questions

      start_session
      sid = response.parsed_body["session_id"]
      shown_types = response.parsed_body["current"]["content"]["bug_types"]

      get api_v1_session_current_path(id: sid), as: :json

      expect(response.parsed_body["current"]["content"]["bug_types"]).to eq(shown_types)
    end

    it "tải lại giữa bước vẫn thấy đúng câu đó (spec §13)" do
      create_bug_hunt_questions(6)

      start_session
      shown_id = response.parsed_body["current"]["question_id"]
      sid = response.parsed_body["session_id"]

      2.times do
        get api_v1_session_current_path(id: sid), as: :json
        expect(response.parsed_body["current"]["question_id"]).to eq(shown_id)
      end
    end

    it "tăng attempt_number ở lượt kế tiếp (BR-10)" do
      create_bug_hunt_questions(4)

      start_session
      first_id = response.parsed_body["session_id"]
      GameSession.find(first_id).abandon!(GameSession::USER_QUIT)

      start_session

      expect(response.parsed_body["attempt_number"]).to eq(2)
    end

    it "yêu cầu đăng nhập" do
      delete session_path
      create_bug_hunt_questions

      start_session

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/sessions/:id/answers" do
    let(:session_id) do
      create_bug_hunt_questions
      start_session
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
      start_session
      sid = response.parsed_body["session_id"]
      GameSession.find(sid).update!(step_served_at: 90.seconds.ago)

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { line: 1, bug_type: "sql_injection" },
                     elapsed_ms: 0 }, as: :json

      # 90 giây > 60 giây nên hệ số 0.5 → floor(10 * 0.5) = 5
      expect(response.parsed_body["awarded_score"]).to eq(5)
    end

    it "không tính thời gian đọc giải thích của câu trước vào câu sau (BR-21)" do
      # Trước cột `step_served_at`, elapsed_ms phía server được đo từ `answered_at` của câu
      # TRƯỚC. Client giữ phần giải thích trên màn hình tới khi người chơi bấm "Câu tiếp
      # theo", nên đọc giải thích 90 giây rồi trả lời câu sau trong 1 giây vẫn bị hệ số 0.5.
      create_bug_hunt_questions
      start_session
      sid = response.parsed_body["session_id"]
      submit_to(sid, position: 1)

      # Người chơi ngồi đọc giải thích 90 giây rồi mới bấm "Câu tiếp theo".
      SessionAnswer.sole.update!(answered_at: 90.seconds.ago)
      GameSession.find(sid).update!(started_at: 120.seconds.ago)
      get api_v1_session_current_path(id: sid), as: :json

      submit_to(sid, position: 2)

      expect(response.parsed_body["awarded_score"]).to eq(10)
    end

    it "tải lại trang không reset đồng hồ tốc độ (BR-21)" do
      create_bug_hunt_questions
      start_session
      sid = response.parsed_body["session_id"]
      GameSession.find(sid).update!(step_served_at: 90.seconds.ago)

      # F5 giữa bước gọi lại `GET current` — mốc phát đề phải giữ nguyên.
      get api_v1_session_current_path(id: sid), as: :json
      expect(GameSession.find(sid).step_served_at).to be_within(1.second).of(90.seconds.ago)

      submit_to(sid, position: 1, elapsed_ms: 0)

      expect(response.parsed_body["awarded_score"]).to eq(5)
    end

    it "response nộp đáp án KHÔNG kèm bước sau — client phải xin qua GET current" do
      create_bug_hunt_questions
      start_session
      sid = response.parsed_body["session_id"]

      submit_to(sid, position: 1)

      expect(response.parsed_body).not_to have_key("next")

      get api_v1_session_current_path(id: sid), as: :json
      expect(response.parsed_body["current"]["position"]).to eq(2)
    end

    def submit_to(sid, position:, answer: { line: 1, bug_type: "sql_injection" },
                  elapsed_ms: 1_000)
      post api_v1_session_answers_path(id: sid),
           params: { position: position, answer: answer, elapsed_ms: elapsed_ms }, as: :json
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

  describe "Spec Detective — chấm từ answer_key (BR-26)" do
    let(:detective) do
      create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective",
             questions_per_session: 1, steps_per_session: 1, max_score: 20)
    end

    def create_detective_question
      create(:question, game: detective,
             content: {
               "statements" => [ "Xử lý đơn nhanh.", "Lưu vào bảng orders.",
                                 "Thông báo nếu cần thiết." ],
               "clarifying_options" => [ { "key" => "a", "label" => "Nhanh là mấy giây?" },
                                         { "key" => "b", "label" => "Lưu ở bảng nào?" } ]
             },
             answer_key: { "ambiguous_statement_indexes" => [ 1, 3 ],
                           "best_option_key" => "a", "explanation" => "vì đo được" })
    end

    def start_detective
      create_detective_question
      post api_v1_game_sessions_path(slug: detective.slug), as: :json
      response.parsed_body["session_id"]
    end

    it "chấm không gọi Gemini và không ghi ai_gradings (BR-26)" do
      # Nổ nếu có bất kỳ lời gọi Gemini nào trên đường chơi — đó là điều 1.19 bỏ đi.
      allow_any_instance_of(Gemini::Client).to receive(:generate)
        .and_raise("không được gọi Gemini lúc chơi")
      sid = start_detective

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { statement_indexes: [ 1, 3 ], option_key: "a" } },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["awarded_score"]).to eq(20)
      expect(GameSession.find(sid).state).to eq(GameSession::FINISHED)
      expect(AiGrading.count).to eq(0)
    end

    it "trừ điểm tick sai" do
      sid = start_detective

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { statement_indexes: [ 1, 2 ], option_key: "a" } },
           as: :json

      expect(response.parsed_body["awarded_score"]).to eq(10)
    end

    it "không trả answer_key về client (BR-03)" do
      sid = start_detective

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { statement_indexes: [ 1 ], option_key: "b" } },
           as: :json

      expect(response.body).not_to include("answer_key")
      expect(response.body).not_to include("ambiguous_statement_indexes")
    end

    it "payload bước chơi chỉ gồm statements và clarifying_options" do
      start_detective

      expect(response.parsed_body["current"]["content"].keys)
        .to contain_exactly("statements", "clarifying_options")
    end

    it "vẫn trả 400 khi thiếu trường trong answer" do
      sid = start_detective

      post api_v1_session_answers_path(id: sid),
           params: { position: 1, answer: { statement_indexes: [ 1 ] } }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("VALIDATION_ERROR")
    end
  end

  # Lỗ đã trả 500 trước 1.20: `Questions::Drawer::NotEnoughQuestions` chỉ được rescue ở
  # endpoint TẠO LƯỢT, còn `GET current` và nộp đáp án thì để nó lọt ra → 500. Chạm được thật
  # khi admin ẩn câu giữa lúc có người đang chơi — chính luồng BR-16/BR-18 mà app khuyến khích
  # người chơi dùng. Từ 1.20 rescue nằm tập trung ở BaseController nên cả ba endpoint cùng
  # trả 422 NO_QUESTIONS_AVAILABLE.
  #
  # Ghi chú: nhánh `NoQuestionsAvailable` do StepProvider ném KHÔNG phải đường xảy ra ở đây.
  # `Drawer#call` luôn trả đúng `count` câu hoặc ném `NotEnoughQuestions` trước đó, nên
  # `fresh_question` không bao giờ hết ứng viên. Test dưới đây khoá lại hành vi thật.
  describe "ngân hàng câu hỏi hụt giữa lượt (BR-16/BR-18)" do
    before do
      create_bug_hunt_questions(2)
      login
      start_session
      @sid = response.parsed_body["session_id"]
      # Admin chấp nhận báo cáo → câu bị ẩn. Lượt đang mở vẫn trỏ vào pool sống.
      Question.where(game: game).update_all(hidden: true)
    end

    def submit_position_one
      post api_v1_session_answers_path(id: @sid),
           params: { position: 1, answer: { line: 1, bug_type: "sql_injection" } }, as: :json
    end

    it "nộp đáp án trả 422 NO_QUESTIONS_AVAILABLE chứ không phải 500" do
      submit_position_one

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("NO_QUESTIONS_AVAILABLE")
    end

    it "GET current cũng trả 422, không 500" do
      get api_v1_session_current_path(id: @sid), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("NO_QUESTIONS_AVAILABLE")
    end

    it "giữ lượt ở in_progress và không ghi câu trả lời nào — người chơi tự bỏ lượt" do
      submit_position_one

      session = GameSession.find(@sid)
      expect(session.state).to eq(GameSession::IN_PROGRESS)
      expect(session.abandoned_reason).to be_nil
      expect(session.session_answers.count).to eq(0)
      expect(session.score).to eq(0)
    end

    it "bỏ lượt vẫn hoạt động để người chơi thoát được" do
      post api_v1_session_abandon_path(id: @sid), as: :json

      expect(response).to have_http_status(:no_content)
      expect(GameSession.find(@sid).abandoned_reason).to eq(GameSession::USER_QUIT)
    end

    # Ranh giới đã ghi ở creator.rb: ngôn ngữ CÒN trong bank nhưng thiếu câu →
    # NO_QUESTIONS_AVAILABLE; ngôn ngữ không còn trong bank → INVALID_LANGUAGE. Ẩn HẾT câu
    # làm "ruby" biến mất khỏi bank nên đường thứ hai mới đúng, không phải đường thứ nhất.
    it "tạo lượt mới báo INVALID_LANGUAGE vì ẩn hết câu làm ngôn ngữ mất khỏi bank" do
      start_session

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("INVALID_LANGUAGE")
      expect(game.available_languages).to be_empty
    end
  end


  describe "POST /api/v1/sessions/:id/abandon (§8.4)" do
    it "đánh dấu user_quit và không tính vào leaderboard" do
      create_bug_hunt_questions
      start_session
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
