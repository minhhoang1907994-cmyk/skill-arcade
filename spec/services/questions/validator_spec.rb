require "rails_helper"

RSpec.describe Questions::Validator do
  def error_for(game, content:, answer_key:)
    described_class.error_for(game, { "content" => content, "answer_key" => answer_key })
  end

  describe "spec_detective (BR-26 — thang điểm phải tự nhất quán)" do
    let(:game) { create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective") }
    let(:content) do
      { "statements" => [ "A.", "B.", "C." ],
        "clarifying_options" => [ { "key" => "a", "label" => "hỏi a" },
                                  { "key" => "b", "label" => "hỏi b" } ] }
    end
    let(:answer_key) do
      { "ambiguous_statement_indexes" => [ 1, 3 ], "best_option_key" => "a" }
    end

    it "nhận đề hợp lệ" do
      expect(error_for(game, content: content, answer_key: answer_key)).to be_nil
    end

    it "loại đề có index trỏ ra ngoài danh sách câu" do
      key = answer_key.merge("ambiguous_statement_indexes" => [ 1, 9 ])

      expect(error_for(game, content: content, answer_key: key)).to include("9 nằm ngoài 3 câu")
    end

    it "loại đề đánh dấu MỌI câu là mơ hồ — tick hết là đủ điểm thì game vô nghĩa" do
      key = answer_key.merge("ambiguous_statement_indexes" => [ 1, 2, 3 ])

      expect(error_for(game, content: content, answer_key: key))
        .to include("mọi câu đều bị đánh dấu mơ hồ")
    end

    it "loại đề có best_option_key không nằm trong clarifying_options" do
      key = answer_key.merge("best_option_key" => "z")

      expect(error_for(game, content: content, answer_key: key))
        .to include("best_option_key không có trong clarifying_options")
    end

    it "loại đề có phương án trùng key" do
      dup = content.merge("clarifying_options" => [ { "key" => "a", "label" => "x" },
                                                    { "key" => "a", "label" => "y" } ])

      expect(error_for(game, content: dup, answer_key: answer_key))
        .to include("key trùng nhau")
    end

    it "loại đề có phương án thiếu label" do
      bad = content.merge("clarifying_options" => [ { "key" => "a" }, { "key" => "b" } ])

      expect(error_for(game, content: bad, answer_key: answer_key))
        .to include("mỗi phương án có key và label")
    end

    it "loại đề thiếu khoá bắt buộc" do
      expect(error_for(game, content: { "statements" => [ "A." ] }, answer_key: answer_key))
        .to include("content.clarifying_options")
    end
  end

  describe "estimate_poker (BR-28 — actual_hours phải cùng thang với người chơi)" do
    let(:game) { create(:game, slug: Game::ESTIMATE_POKER, name: "Estimate Poker") }
    let(:content) { { "task_description" => "Thêm một field vào API sẵn có" } }

    # Mọi đề hợp lệ đều phải có breakdown cộng đúng bằng actual_hours (BR-20b), nên helper
    # này dựng sẵn một bảng khớp — test nào muốn kiểm chính breakdown thì truyền đè.
    def answer_key_for(hours, breakdown: [ { "step" => "Làm việc đó", "hours" => hours } ])
      { "actual_hours" => hours, "breakdown" => breakdown }
    end

    it "nhận đề có actual_hours trong khoảng hợp lệ" do
      expect(error_for(game, content: content, answer_key: answer_key_for(4.0))).to be_nil
    end

    it "loại đề vượt trần — task quá lớn phải chẻ nhỏ trước khi đem ước lượng" do
      expect(error_for(game, content: content, answer_key: answer_key_for(120)))
        .to include("nằm ngoài khoảng")
    end

    it "loại đề dưới sàn" do
      expect(error_for(game, content: content, answer_key: answer_key_for(0.25)))
        .to include("nằm ngoài khoảng")
    end

    it "loại đề có actual_hours không phải số" do
      expect(error_for(game, content: content, answer_key: answer_key_for("8 giờ")))
        .to include("phải là số")
    end

    it "loại đề thiếu breakdown — người chơi cần thấy giờ đi đâu (BR-20b)" do
      expect(error_for(game, content: content, answer_key: { "actual_hours" => 4.0 }))
        .to include("breakdown")
    end

    it "loại đề có tổng breakdown lệch actual_hours" do
      answer_key = answer_key_for(8.0, breakdown: [
        { "step" => "Viết migration", "hours" => 3 },
        { "step" => "Viết test", "hours" => 2 }
      ])

      expect(error_for(game, content: content, answer_key: answer_key))
        .to include("không khớp actual_hours")
    end

    it "loại đề có dòng breakdown thiếu step" do
      answer_key = answer_key_for(4.0, breakdown: [ { "hours" => 4 } ])

      expect(error_for(game, content: content, answer_key: answer_key)).to include("thiếu step")
    end

    it "loại đề có dòng breakdown hours không phải số dương" do
      answer_key = answer_key_for(4.0, breakdown: [
        { "step" => "Làm việc đó", "hours" => 4 },
        { "step" => "Việc không tốn giờ", "hours" => 0 }
      ])

      expect(error_for(game, content: content, answer_key: answer_key))
        .to include("không phải số dương")
    end
  end

  describe "bug_hunt" do
    let(:game) { create(:game) }
    let(:content) do
      { "language" => "java", "code_lines" => [ "a", "b" ],
        "bug_types" => Question::BUG_HUNT_TYPES }
    end

    it "loại buggy_line ngoài phạm vi" do
      key = { "buggy_line" => 5, "bug_type" => "n_plus_one" }

      expect(error_for(game, content: content, answer_key: key))
        .to include("buggy_line 5 nằm ngoài 2 dòng code")
    end

    it "loại bug_type ngoài danh sách chuẩn" do
      key = { "buggy_line" => 1, "bug_type" => "typo" }

      expect(error_for(game, content: content, answer_key: key)).to include("bug_type không hợp lệ")
    end
  end
end
