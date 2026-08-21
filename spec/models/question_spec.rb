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

    # MySQL trả cột JSON về theo thứ tự khoá của nó, không theo thứ tự lúc ghi. Nếu
    # assign_checksum chạy vô điều kiện thì mỗi lần update một cột khác là checksum bị băm
    # lại từ bản đọc-từ-DB và đổi giá trị — seed/import sau đó tạo bản ghi trùng.
    # `task_description` (16 ký tự) và `context` (7) đủ khác độ dài để MySQL đảo thứ tự.
    context "khi update cột khác trên bản ghi nạp từ DB" do
      let(:content) do
        { "task_description" => "Thêm cột deleted_at vào bảng users", "context" => "Dev quen codebase" }
      end

      it "giữ nguyên checksum" do
        created = create(:question, content: content, answer_key: { "actual_hours" => 2 })
        reloaded = described_class.find(created.id)

        expect { reloaded.update!(hidden: true) }.not_to change { reloaded.reload.checksum }
      end

      it "checksum vẫn khớp với content theo thứ tự nguồn, không phải thứ tự MySQL" do
        created = create(:question, content: content, answer_key: { "actual_hours" => 2 })
        described_class.find(created.id).update!(hidden: true)

        expect(created.reload.checksum).to eq(described_class.checksum_for(content))
      end
    end

    it "tính lại khi content thực sự đổi" do
      question = create(:question)

      expect { question.update!(content: { "language" => "go", "code_lines" => [ "x" ] }) }
        .to change { question.checksum }
    end
  end

  describe "cột language" do
    it "nhân ra từ content khi lưu" do
      question = create(:question, content: { "language" => "java", "code_lines" => [ "x" ] })

      expect(question.language).to eq("java")
    end

    it "để nil khi content không có ngôn ngữ" do
      question = create(:question, content: { "statements" => [ "xử lý nhanh" ] })

      expect(question.language).to be_nil
    end
  end

  describe "scope :in_language" do
    it "không lọc gì khi truyền nil" do
      php = create(:question, content: { "language" => "php", "code_lines" => [ "p" ] })
      java = create(:question, content: { "language" => "java", "code_lines" => [ "j" ] })

      expect(described_class.in_language(nil)).to contain_exactly(php, java)
      expect(described_class.in_language("java")).to contain_exactly(java)
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
