require "rails_helper"

RSpec.describe Questions::Refiller do
  # Game duy nhất trong test là Estimate Poker: không phân đề theo ngôn ngữ nên mỗi game
  # đúng một mục tiêu, và không phải dựng bank theo từng ngôn ngữ như Bug Hunt.
  let(:game) do
    create(:game, slug: Game::ESTIMATE_POKER, name: "Estimate Poker",
           questions_per_session: 2, steps_per_session: 2)
  end

  # goal = questions_per_session * TARGET_MULTIPLIER = 2 * 3 = 6
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

  def refiller(records: [], per_run: 10)
    generated = []
    builder = lambda do |_game, _language|
      generated << true
      fake_generator(records)
    end

    [ described_class.new(per_run: per_run, generator_builder: builder, bank_dir: bank_dir),
      generated ]
  end

  def valid_record(index)
    { "content" => { "task_description" => "sinh #{index}-#{SecureRandom.hex(3)}" },
      "answer_key" => { "actual_hours" => 12.0 } }
  end

  describe "trần 2 — chỉ sinh khi thiếu" do
    it "không gọi Gemini khi ngân hàng đã đạt ngưỡng" do
      create_questions(6)
      service, generated = refiller

      outcomes = service.call

      expect(generated).to be_empty
      expect(outcomes.map(&:status)).to eq([ :nothing_to_do ])
    end

    it "câu bị ẩn KHÔNG tính vào ngưỡng (BR-16)" do
      create_questions(6)
      Question.where(game: game).limit(2).update_all(hidden: true)
      service, generated = refiller(records: [ valid_record(1) ])

      service.call

      expect(generated.size).to eq(1)
    end
  end

  describe "trần 1 — không nạp đề khi còn lượt đang chơi (BR-36)" do
    before { create_questions(1) }

    it "bỏ qua game còn lượt in_progress" do
      create(:game_session, game: game, user: create(:user), state: GameSession::IN_PROGRESS)
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(generated).to be_empty
      expect(outcomes.first.status).to eq(:skipped)
      expect(outcomes.first.detail).to include("còn lượt đang chơi")
      expect(Question.where(game: game).count).to eq(1)
    end

    it "vẫn chạy khi lượt duy nhất đã kết thúc" do
      create(:game_session, :finished, game: game, user: create(:user))
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(generated.size).to eq(1)
      expect(outcomes.first.status).to eq(:done)
    end
  end

  describe "trần 3 — tối đa một mục tiêu mỗi lần chạy" do
    it "chỉ xử lý mục tiêu thiếu nhiều nhất khi nhiều game cùng thiếu" do
      other = create(:game, slug: Game::BUG_HUNT, name: "Bug Hunt",
                     questions_per_session: 10, steps_per_session: 10)
      create_questions(1)
      service, generated = refiller(records: [ valid_record(1) ])

      outcomes = service.call

      expect(outcomes.size).to eq(1)
      expect(generated.size).to eq(1)
      # Bug Hunt phân đề theo ngôn ngữ và bank rỗng nên không sinh ra mục tiêu nào.
      expect(other.available_languages).to be_empty
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
