require "rails_helper"

RSpec.describe Game do
  describe "#language_scoped?" do
    it "chỉ đúng với Bug Hunt" do
      expect(create(:game).language_scoped?).to be true
      expect(create(:game, :scenario_based).language_scoped?).to be false
    end
  end

  describe "danh sách ngôn ngữ" do
    let(:game) { create(:game, questions_per_session: 3) }

    before do
      3.times { |i| create_question("php", i) }
      2.times { |i| create_question("java", i) }
    end

    def create_question(language, index)
      create(:question, game: game,
             content: { "language" => language, "code_lines" => [ "#{language}#{index}" ] })
    end

    it "chỉ hiện cho người chơi ngôn ngữ đủ câu cho trọn một lượt" do
      expect(game.playable_languages).to eq([ "php" ])
    end

    it "vẫn coi ngôn ngữ chưa đủ câu là hợp lệ" do
      expect(game.available_languages).to eq([ "java", "php" ])
    end

    it "không tính câu đã bị ẩn (BR-16)" do
      Question.where(game: game, language: "php").limit(1).update_all(hidden: true)

      expect(game.playable_languages).to be_empty
      expect(game.available_languages).to eq([ "java", "php" ])
    end

    it "trả rỗng với game không phân đề theo ngôn ngữ" do
      roulette = create(:game, :scenario_based)

      expect(roulette.playable_languages).to be_empty
      expect(roulette.available_languages).to be_empty
    end
  end
end
