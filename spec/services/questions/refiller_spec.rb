require "rails_helper"

RSpec.describe Questions::Refiller do
  # Game duy nhất trong test là Estimate Poker: không phân đề theo ngôn ngữ nên mỗi game
  # đúng một mục tiêu, và không phải dựng bank theo từng ngôn ngữ như Bug Hunt.
  let(:game) do
    create(:game, slug: Game::ESTIMATE_POKER, name: "Estimate Poker",
           questions_per_session: 2, steps_per_session: 2)
  end

  # goal = questions_per_session * TARGET_MULTIPLIER. Tính từ hằng số chứ không viết số
  # cứng: 2026-08-25 nâng multiplier 3 -> 10 và hai test "đã đủ đề" dựng sẵn 6 câu đã đổi
  # nghĩa thành thiếu đề, mà không có gì trong test báo là chúng đang kiểm sai thứ.
  def goal
    game.questions_per_session * described_class::TARGET_MULTIPLIER
  end

  def create_questions(count)
    count.times do |i|
      create(:question, game: game,
             content: { "task_description" => "task #{i}-#{SecureRandom.hex(3)}" },
             answer_key: { "actual_hours" => 8 })
    end
  end

  def fake_generator(records)
    batch = Questions::Generator::Batch.new(records: records, model: "gemini-test", prompts: [ "p" ])
    instance_double(Questions::Generator, call: batch)
  end

  # bank_dir trỏ vào tmp: không ghi rác vào db/question_banks của repo khi chạy test.
  let(:bank_dir) { Rails.root.join("tmp", "question_banks_spec", SecureRandom.hex(4)) }

  # generated ghi NHÃN của từng mục tiêu đã gọi Gemini chứ không chỉ đếm số lần: từ khi trần
  # là 3 mục tiêu thì phải kiểm được ĐÚNG mục tiêu nào được chọn, không chỉ chọn mấy cái.
  def refiller(records: [], per_run: 10, max_targets: described_class::MAX_TARGETS_PER_RUN)
    generated = []
    builder = lambda do |game, language|
      generated << [ game.slug, language ].compact.join("/")
      fake_generator(records)
    end

    [ described_class.new(per_run: per_run, max_targets: max_targets,
                          generator_builder: builder, bank_dir: bank_dir),
      generated ]
  end

  def valid_record(index)
    { "content" => { "task_description" => "sinh #{index}-#{SecureRandom.hex(3)}" },
      "answer_key" => {
        "actual_hours" => 12.0,
        "breakdown" => [ { "step" => "Làm việc đó", "hours" => 12.0 } ]
      } }
  end

  describe "trần 2 — chỉ sinh khi thiếu" do
    it "không gọi Gemini khi ngân hàng đã đạt ngưỡng" do
      create_questions(goal)
      service, generated = refiller

      outcomes = service.call

      expect(generated).to be_empty
      expect(outcomes.map(&:status)).to eq([ :nothing_to_do ])
    end

    it "câu bị ẩn KHÔNG tính vào ngưỡng (BR-16)" do
      create_questions(goal)
      Question.where(game: game).limit(2).update_all(hidden: true)
      service, generated = refiller(records: [ valid_record(1) ])

      service.call

      expect(generated.size).to eq(1)
    end
  end

  describe "trần 1 — không nạp đề khi còn lượt đang chơi (BR-36)" do
    before { create_questions(1) }

    it "bỏ qua game còn lượt in_progress" do
      create(:game_session, :question_served, game: game, user: create(:user),
             state: GameSession::IN_PROGRESS)
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(generated).to be_empty
      expect(outcomes.first.status).to eq(:skipped)
      expect(outcomes.first.detail).to include("1 lượt đang chơi")
      expect(Question.where(game: game).count).to eq(1)
    end

    # Gặp thật trên production: cả 6 mục tiêu thiếu đề đều có lượt đang mở, và vì mục tiêu
    # được CHỌN trước rồi mới kiểm nên lần chạy sinh 0 đề dù còn mục tiêu khác nạp được.
    it "mục tiêu bị chặn KHÔNG chiếm suất của mục tiêu nạp được" do
      other = create(:game, slug: Game::PROD_ROULETTE, name: "PROD Roulette",
                     questions_per_session: 1, steps_per_session: 10)
      # estimate_poker thiếu nhiều hơn nhưng đang có người chơi; prod_roulette nạp được.
      create_questions(1)
      create(:game_session, :question_served, game: game, user: create(:user),
             state: GameSession::IN_PROGRESS)

      scenario_record = {
        "content" => { "scenario" => "sự cố #{SecureRandom.hex(3)}",
                       "nodes" => [ { "key" => "n1", "prompt" => "làm gì?",
                                      "options" => [ { "key" => "a", "label" => "rollback" } ] } ] },
        "answer_key" => { "option_effects" => { "a" => { "points" => 10 } } }
      }
      service, generated = refiller(records: [ scenario_record ])

      outcomes = service.call

      expect(generated.size).to eq(1)
      expect(outcomes.map(&:status)).to contain_exactly(:done, :skipped)
      expect(outcomes.find { |o| o.status == :done }.label).to eq(other.slug)
      expect(outcomes.find { |o| o.status == :skipped }.label).to eq(game.slug)
    end

    # 2026-08-21: cả 5 lượt chặn refill trên production đều ở vị trí 0 và chưa phát câu nào —
    # người chơi bấm "Bắt đầu lượt" rồi rời đi, nhưng vẫn giữ in_progress tới 24 giờ.
    it "lượt chưa hiển thị câu nào KHÔNG chặn" do
      create(:game_session, game: game, user: create(:user), state: GameSession::IN_PROGRESS)
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(generated.size).to eq(1)
      expect(outcomes.first.status).to eq(:done)
    end

    it "lượt đang chờ phát câu KẾ TIẾP vẫn chặn" do
      # step_served_at nil nhưng đã qua 3 câu: AnswerSubmitter xoá mốc sau mỗi câu, nên nil
      # một mình KHÔNG có nghĩa là chưa hiển thị gì.
      create(:game_session, game: game, user: create(:user), state: GameSession::IN_PROGRESS,
             current_position: 3, step_served_at: nil)
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(generated).to be_empty
      expect(outcomes.first.status).to eq(:skipped)
    end

    it "vẫn chạy khi lượt duy nhất đã kết thúc" do
      create(:game_session, :finished, game: game, user: create(:user))
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(generated.size).to eq(1)
      expect(outcomes.first.status).to eq(:done)
    end
  end

  describe "trần 3 — tối đa MAX_TARGETS_PER_RUN mục tiêu mỗi lần chạy" do
    it "mục tiêu thiếu ít nhất bị hoãn khi số mục tiêu vượt trần" do
      # 4 game không phân ngôn ngữ, không game nào có đề — cả 4 đều thiếu.
      create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective",
             questions_per_session: 5, steps_per_session: 5)
      create(:game, slug: Game::PROD_ROULETTE, name: "PROD Roulette",
             questions_per_session: 1, steps_per_session: 10)
      create(:game, slug: Game::INCIDENT_ESCAPE_ROOM, name: "Incident Escape Room",
             questions_per_session: 1, steps_per_session: 8)
      game
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(generated.size).to eq(3)
      # Mục tiêu bị hoãn KHÔNG có outcome nào — không phải :skipped (đó là nghĩa "còn lượt
      # đang chơi"), chỉ đơn giản là để lần chạy sau.
      expect(outcomes.size).to eq(3)
      # Cả 4 mục tiêu playable = 0 nên tie-break quyết định: thiếu nhiều hơn trước —
      # spec_detective 50 > estimate_poker 20 > prod_roulette = escape_room 10.
      expect(generated).to include("spec_detective", "estimate_poker")
    end

    it "trần đọc từ tham số max_targets" do
      create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective",
             questions_per_session: 5, steps_per_session: 5)
      game
      service, generated = refiller(records: [ valid_record(1) ], max_targets: 1)

      service.call

      expect(generated).to eq([ "spec_detective" ])
    end

    it "trần mặc định là 3 — giữ tổng request trong hạn mức 20/ngày" do
      expect(described_class::MAX_TARGETS_PER_RUN).to eq(3)
    end
  end

  # Trạng thái thật trên production 2026-08-27: bug_hunt/php có 49 đề (goal 100, shortfall 51)
  # còn prod_roulette có 3 đề (goal 10, shortfall 7). Sắp theo shortfall giảm dần thì
  # prod_roulette không bao giờ được chọn — ai_generated của nó là 0 kể từ khi có Refiller.
  describe "ưu tiên mục tiêu ĐANG CÓ ÍT ĐỀ NHẤT" do
    let(:roulette) do
      create(:game, slug: Game::PROD_ROULETTE, name: "PROD Roulette",
             questions_per_session: 1, steps_per_session: 10)
    end

    def create_roulette_questions(count)
      count.times do |i|
        create(:question, game: roulette,
               content: { "scenario" => "kịch bản #{i}-#{SecureRandom.hex(3)}" },
               answer_key: { "recovery_node" => "recovered" })
      end
    end

    before do
      # estimate_poker: goal 100, có 49 -> thiếu 51 (mục tiêu GIÀU nhưng thiếu nhiều nhất).
      game.update!(questions_per_session: 10, steps_per_session: 10)
      create_questions(49)
      # prod_roulette: goal 10, có 3 -> thiếu 7 (mục tiêu NGHÈO nhưng thiếu ít hơn).
      create_roulette_questions(3)
    end

    it "chọn mục tiêu ít đề nhất dù nó thiếu ÍT hơn mục tiêu nhiều đề" do
      service, generated = refiller(records: [ valid_record(1) ], max_targets: 1)

      service.call

      expect(generated).to eq([ "prod_roulette" ])
    end

    it "ghi khoảng cách tới mục tiêu nhiều đề nhất vào detail" do
      service, = refiller(records: [ valid_record(1) ], max_targets: 1)

      outcome = service.call.find { |o| o.label == "prod_roulette" }

      expect(outcome.status).to eq(:done)
      expect(outcome.detail).to include("đang có 3 đề", "ít hơn mục tiêu nhiều đề nhất 46 đề")
    end
  end

  # Lỗi đã gặp thật trên production 2026-08-21: sessions_open? chỉ lọc theo game nên cả 4 mục
  # tiêu bug_hunt cùng bị chặn bởi cùng một tập 5 lượt, job xanh mà nạp 0 đề.
  describe "lượt đang chơi chỉ chặn ĐÚNG ngôn ngữ của nó" do
    let(:bug_hunt) do
      create(:game, slug: Game::BUG_HUNT, name: "Bug Hunt",
             questions_per_session: 2, steps_per_session: 2)
    end

    def create_bug_hunt_question(language)
      create(:question, game: bug_hunt,
             content: { "language" => language, "code_lines" => [ "x = #{SecureRandom.hex(3)}" ],
                        "bug_types" => [ "sql_injection" ] },
             answer_key: { "buggy_line" => 1, "bug_type" => "sql_injection" })
    end

    def bug_hunt_record(language)
      { "content" => { "language" => language,
                       "code_lines" => [ "y = #{SecureRandom.hex(3)}" ],
                       "bug_types" => [ "sql_injection" ] },
        "answer_key" => { "buggy_line" => 1, "bug_type" => "sql_injection" } }
    end

    before do
      create_bug_hunt_question("java")
      create_bug_hunt_question("php")
    end

    def open_session(language)
      create(:game_session, :question_served, game: bug_hunt, user: create(:user),
             language: language, state: GameSession::IN_PROGRESS)
    end

    it "lượt bug_hunt/java KHÔNG chặn refill của bug_hunt/php" do
      open_session("java")
      service, generated = refiller(records: [ bug_hunt_record("php") ])

      outcomes = service.call

      expect(generated).to eq([ "bug_hunt/php" ])
      expect(outcomes.find { |o| o.label == "bug_hunt/java" }.status).to eq(:skipped)
      expect(outcomes.find { |o| o.label == "bug_hunt/php" }.status).to eq(:done)
      expect(Question.playable.where(game: bug_hunt, language: "php").count).to eq(2)
      expect(Question.playable.where(game: bug_hunt, language: "java").count).to eq(1)
    end

    it "đếm số lượt theo riêng ngôn ngữ đó trong thông báo skipped" do
      2.times { open_session("java") }
      open_session("php")
      service, generated = refiller(records: [ bug_hunt_record("php") ])

      outcomes = service.call

      expect(generated).to be_empty
      expect(outcomes.find { |o| o.label == "bug_hunt/java" }.detail).to include("2 lượt đang chơi")
      expect(outcomes.find { |o| o.label == "bug_hunt/php" }.detail).to include("1 lượt đang chơi")
    end

    it "lượt language NULL của game phân ngôn ngữ chặn MỌI ngôn ngữ" do
      open_session(nil)
      service, generated = refiller(records: [ bug_hunt_record("php") ])

      outcomes = service.call

      expect(generated).to be_empty
      expect(outcomes.map(&:status).uniq).to eq([ :skipped ])
    end
  end

  describe "nạp vào DB" do
    it "ghi file bank rồi import, đề mới vào DB được" do
      create_questions(1)
      service, = refiller(records: [ valid_record(1), valid_record(2) ])

      outcomes = service.call

      expect(outcomes.first.status).to eq(:done)
      expect(outcomes.first.detail).to include("2 mới")
      expect(Question.where(game: game).count).to eq(3)
      expect(Question.where(game: game, source: "ai_generated").count).to eq(3)
    end

    it "báo failed khi Gemini không trả đề nào dùng được" do
      create_questions(1)
      service, = refiller(records: [])

      outcomes = service.call

      expect(outcomes.first.status).to eq(:failed)
      expect(outcomes.first.detail).to include("không trả đề nào dùng được")
    end

    it "báo failed khi Gemini lỗi thay vì để exception vọt ra" do
      create_questions(1)
      builder = lambda do |_game, _language|
        instance_double(Questions::Generator).tap do |generator|
          allow(generator).to receive(:call).and_raise(Gemini::Client::RequestFailed, "timeout")
        end
      end
      service = described_class.new(generator_builder: builder, bank_dir: bank_dir)

      outcomes = service.call

      expect(outcomes.first.status).to eq(:failed)
      expect(outcomes.first.detail).to include("timeout")
    end

    it "đề sai cấu trúc bị Validator loại, không vào DB" do
      create_questions(1)
      bad = { "content" => { "task_description" => "x" }, "answer_key" => {} }
      service, = refiller(records: [ bad ])

      outcomes = service.call

      expect(outcomes.first.detail).to include("1 bị loại")
      expect(Question.where(game: game).count).to eq(1)
    end
  end

  after { FileUtils.rm_rf(bank_dir) }
end
