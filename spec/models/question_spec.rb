require "rails_helper"

RSpec.describe Question do
  describe "answer_key không được lộ ra ngoài (BR-03)" do
    let(:question) { create(:question) }

    it "as_json không chứa answer_key" do
      expect(question.as_json.keys).not_to include("answer_key")
    end

    it "serializable_hash không chứa answer_key" do
      expect(question.serializable_hash.keys).not_to include("answer_key")
    end

    it "to_json không chứa answer_key" do
      expect(question.to_json).not_to include("answer_key")
    end

    it "vẫn giữ content để hiển thị cho người chơi" do
      expect(question.as_json.keys).to include("content")
    end
  end

  describe "checksum" do
    it "tự sinh từ content" do
      question = create(:question)
      expect(question.checksum).to eq(described_class.checksum_for(question.content))
    end

    it "chặn import trùng nội dung" do
      first = create(:question)
      duplicate = build(:question, game: first.game, content: first.content)
      expect(duplicate).not_to be_valid
    end
  end

  describe "scope :playable (BR-16)" do
    it "loại câu đã bị ẩn" do
      visible = create(:question)
      create(:question, hidden: true)

      expect(described_class.playable).to contain_exactly(visible)
    end
  end
end
