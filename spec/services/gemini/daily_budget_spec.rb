require "rails_helper"

RSpec.describe Gemini::DailyBudget do
  include ActiveSupport::Testing::TimeHelpers

  let(:game) do
    create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective",
           questions_per_session: 5, steps_per_session: 5)
  end
  let(:session) { create(:game_session, game: game) }

  # Mỗi lời gọi Gemini là một dòng ai_gradings (BR-19), kể cả lời gọi lỗi — nên dựng dữ liệu
  # ở đúng tầng đó thay vì đếm số lượt chơi.
  def record_calls(count, at: Time.current, error: nil)
    count.times do
      answer = create(:session_answer_record, session: session,
                      question: create(:question, game: game))
      AiGrading.create!(session_answer: answer, model: "gemini-test", prompt: "p",
                        response: error ? "" : "{}", score: error ? nil : 10,
                        error: error, created_at: at)
    end
  end

  it "chưa gọi lần nào thì còn nguyên hạn mức" do
    expect(described_class.new.used).to eq(0)
    expect(described_class.new.remaining).to eq(described_class::DAILY_REQUEST_LIMIT)
  end

  it "đếm cả lời gọi THẤT BẠI vì lần lỗi cũng tiêu hạn mức của Google" do
    record_calls(2)
    record_calls(3, error: "Gemini::Client::RequestFailed: timeout")

    expect(described_class.new.used).to eq(5)
  end

  it "bỏ qua lời gọi ngoài cửa sổ 24 giờ" do
    record_calls(4, at: 25.hours.ago)
    record_calls(2, at: 23.hours.ago)

    expect(described_class.new.used).to eq(2)
  end

  it "cửa sổ trượt theo thời gian, không reset theo mốc nửa đêm" do
    record_calls(described_class::DAILY_REQUEST_LIMIT)
    expect(described_class.new.enough_for_session?(game)).to be false

    travel(described_class::WINDOW + 1.minute) do
      expect(described_class.new.used).to eq(0)
      expect(described_class.new.enough_for_session?(game)).to be true
    end
  end

  describe "#sessions_left" do
    it "chia hạn mức còn lại cho số bước của một lượt" do
      record_calls(5)

      # 20 - 5 = 15 request còn lại, mỗi lượt 5 bước → 3 lượt
      expect(described_class.new.sessions_left(game)).to eq(3)
    end

    it "làm tròn XUỐNG: không cho vào lượt mà giữa đường hết hạn mức" do
      record_calls(18)

      # Còn 2 request, chưa đủ cho một lượt 5 bước
      expect(described_class.new.remaining).to eq(2)
      expect(described_class.new.sessions_left(game)).to eq(0)
      expect(described_class.new.enough_for_session?(game)).to be false
    end
  end

  it "remaining không âm khi đã gọi vượt hạn mức" do
    record_calls(described_class::DAILY_REQUEST_LIMIT + 3)

    expect(described_class.new.remaining).to eq(0)
  end
end
