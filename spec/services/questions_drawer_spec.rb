require "rails_helper"

RSpec.describe Questions::Drawer do
  let(:user) { create(:user) }
  let(:game) { create(:game, questions_per_session: 3) }

  def answer_correctly(question, at: Time.current)
    session = create(:game_session, :finished, user: user, game: game,
                     attempt_number: GameSession.where(user: user, game: game).count + 1)
    create(:session_answer_record, session: session, question: question, score: 10, at: at)
  end

  before do
    5.times { create(:question, game: game) }
  end

  it "báo lỗi khi ngân hàng câu hỏi không đủ" do
    Question.where(game: game).limit(3).update_all(hidden: true)

    expect { described_class.new(user: user, game: game).call }
      .to raise_error(described_class::NotEnoughQuestions)
  end

  describe "seed" do
    it "cùng seed thì bốc ra đúng cùng thứ tự" do
      first = described_class.new(user: user, game: game, seed: "s1:1").call
      second = described_class.new(user: user, game: game, seed: "s1:1").call

      expect(second.map(&:id)).to eq(first.map(&:id))
    end

    it "seed khác nhau thì thứ tự khác nhau" do
      orders = (1..10).map do |i|
        described_class.new(user: user, game: game, seed: "s:#{i}").call.map(&:id)
      end

      expect(orders.uniq.size).to be > 1
    end
  end

  it "chỉ bốc câu thuộc ngôn ngữ được chỉ định" do
    java = Array.new(3) do |i|
      create(:question, game: game,
             content: { "language" => "java", "code_lines" => [ "j#{i}" ] })
    end

    drawn = described_class.new(user: user, game: game, language: "java").call

    expect(drawn.map(&:id)).to match_array(java.map(&:id))
  end

  it "báo lỗi khi ngôn ngữ được chỉ định không đủ câu, dù ngôn ngữ khác còn dư" do
    create(:question, game: game, content: { "language" => "java", "code_lines" => [ "j" ] })

    expect { described_class.new(user: user, game: game, language: "java").call }
      .to raise_error(described_class::NotEnoughQuestions)
  end

  it "không bốc câu đã bị ẩn (BR-16)" do
    hidden = Question.where(game: game).first
    hidden.update!(hidden: true)

    drawn = described_class.new(user: user, game: game).call

    expect(drawn.map(&:id)).not_to include(hidden.id)
  end

  it "ưu tiên câu người chơi chưa từng trả lời đúng (BR-32)" do
    known = Question.where(game: game).first(2)
    known.each { |q| answer_correctly(q) }

    drawn = described_class.new(user: user, game: game).call

    # Còn 3 câu chưa trả lời đúng, vừa đủ một lượt — không được lấy lại câu đã biết.
    expect(drawn.size).to eq(3)
    expect(drawn.map(&:id) & known.map(&:id)).to be_empty
  end

  it "dùng lại câu cũ nhất khi không còn đủ câu mới" do
    all = Question.where(game: game).order(:id).to_a
    answer_correctly(all[0], at: 10.days.ago)
    answer_correctly(all[1], at: 1.day.ago)
    answer_correctly(all[2], at: 5.days.ago)
    answer_correctly(all[3], at: 2.days.ago)

    drawn = described_class.new(user: user, game: game).call

    expect(drawn.size).to eq(3)
    # Câu duy nhất chưa trả lời đúng phải có mặt.
    expect(drawn.map(&:id)).to include(all[4].id)
    # Hai câu bù thêm là hai câu trả lời lâu nhất.
    expect(drawn.map(&:id)).to include(all[0].id, all[2].id)
  end
end
