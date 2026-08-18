require "rails_helper"

RSpec.describe "Scoring" do
  let(:user) { create(:user) }

  def session_for(game)
    create(:game_session, user: user, game: game)
  end

  describe Scoring::BugHunt do
    let(:game) { create(:game) }
    let(:question) do
      create(:question, game: game,
             answer_key: { "buggy_line" => 3, "bug_type" => "sql_injection",
                           "explanation" => "Nối chuỗi vào SQL." })
    end

    it "cho 10 điểm khi đúng cả dòng lẫn loại bug và trả lời nhanh (BR-25)" do
      result = described_class.new.call(
        session: session_for(game), question: question,
        answer: { "line" => 3, "bug_type" => "sql_injection" }, elapsed_ms: 5_000
      )

      expect(result.score).to eq(10)
    end

    it "cho 6 điểm khi đúng dòng nhưng sai loại" do
      result = described_class.new.call(
        session: session_for(game), question: question,
        answer: { "line" => 3, "bug_type" => "xss" }, elapsed_ms: 5_000
      )

      expect(result.score).to eq(6)
    end

    it "nhân hệ số tốc độ lên TỔNG điểm rồi mới làm tròn xuống (BR-21)" do
      result = described_class.new.call(
        session: session_for(game), question: question,
        answer: { "line" => 3, "bug_type" => "sql_injection" }, elapsed_ms: 45_000
      )

      # floor((6 + 4) * 0.8) = 8, không phải floor(6*0.8) + floor(4*0.8) = 7
      expect(result.score).to eq(8)
    end

    it "áp hệ số 0.5 khi trả lời quá 60 giây" do
      result = described_class.new.call(
        session: session_for(game), question: question,
        answer: { "line" => 3, "bug_type" => "sql_injection" }, elapsed_ms: 90_000
      )

      expect(result.score).to eq(5)
    end

    it "cho 0 điểm khi sai cả hai" do
      result = described_class.new.call(
        session: session_for(game), question: question,
        answer: { "line" => 1, "bug_type" => "xss" }, elapsed_ms: 1_000
      )

      expect(result.score).to eq(0)
    end
  end

  describe Scoring::EstimatePoker do
    let(:game) { create(:game, slug: Game::ESTIMATE_POKER, name: "Estimate Poker") }
    let(:question) do
      create(:question, game: game, answer_key: { "actual_hours" => 8, "reasoning" => "..." })
    end

    def score_for(hours)
      described_class.new.call(
        session: session_for(game), question: question,
        answer: { "hours" => hours }, elapsed_ms: nil
      ).score
    end

    it "chấm theo bậc sai số (BR-28)" do
      expect(score_for(8)).to eq(10)      # lệch 0%
      expect(score_for(9)).to eq(7)       # lệch 12.5%
      expect(score_for(11)).to eq(4)      # lệch 37.5%
      expect(score_for(20)).to eq(0)      # lệch 150%
    end

    it "từ chối ước lượng không hợp lệ" do
      expect { score_for(0) }.to raise_error(Scoring::Base::InvalidAnswer)
    end
  end

  describe Scoring::ProdRoulette do
    let(:game) { create(:game, :scenario_based) }
    let(:question) do
      create(:question, game: game, answer_key: {
        "option_effects" => {
          "safe" => { "points" => 10, "irreversible" => false, "consequence_text" => "Tốt" },
          "risky" => { "points" => 3, "irreversible" => false, "consequence_text" => "Tạm được" },
          "fatal" => { "points" => 10, "irreversible" => true,
                       "consequence_text" => "Email đã gửi thật, không thu hồi được" }
        }
      })
    end

    def result_for(option)
      described_class.new.call(
        session: session_for(game), question: question,
        answer: { "node_key" => "n1", "option_key" => option }, elapsed_ms: nil
      )
    end

    it "cho 10 điểm cho lựa chọn an toàn (BR-29)" do
      expect(result_for("safe").score).to eq(10)
      expect(result_for("safe")).not_to be_terminal
    end

    it "cho 3 điểm cho lựa chọn rủi ro nhưng khôi phục được" do
      expect(result_for("risky").score).to eq(3)
    end

    it "cho 0 điểm và kết thúc lượt khi chọn hành động không thể thu hồi" do
      result = result_for("fatal")

      # points trong answer_key là 10 nhưng irreversible ghi đè thành 0.
      expect(result.score).to eq(0)
      expect(result).to be_terminal
    end

    it "từ chối lựa chọn không có trong kịch bản" do
      expect { result_for("khong_ton_tai") }.to raise_error(Scoring::Base::InvalidAnswer)
    end
  end

  describe Scoring::IncidentEscapeRoom do
    it "tính thưởng thời gian theo bậc (BR-27)" do
      expect(described_class.time_bonus(10)).to eq(20)
      expect(described_class.time_bonus(15)).to eq(20)
      expect(described_class.time_bonus(25)).to eq(10)
      expect(described_class.time_bonus(31)).to eq(0)
    end
  end

  describe Scoring::SpecDetective do
    let(:game) { create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective") }
    let(:question) { create(:question, game: game) }

    it "báo GradingUnavailable vì cần Gemini (Phase 3)" do
      expect do
        described_class.new.call(
          session: session_for(game), question: question,
          answer: { "ambiguous_points" => [ "nhanh" ], "questions" => "Nhanh là bao lâu?" },
          elapsed_ms: nil
        )
      end.to raise_error(Scoring::Base::GradingUnavailable)
    end

    it "vẫn báo lỗi định dạng trước khi báo GradingUnavailable" do
      expect do
        described_class.new.call(
          session: session_for(game), question: question,
          answer: { "questions" => "thiếu ambiguous_points" }, elapsed_ms: nil
        )
      end.to raise_error(Scoring::Base::InvalidAnswer)
    end
  end

  describe Scoring::Base do
    it "chọn đúng scorer theo slug" do
      expect(described_class.for(create(:game))).to be_a(Scoring::BugHunt)
      expect(described_class.for(create(:game, :scenario_based))).to be_a(Scoring::ProdRoulette)
    end
  end
end
