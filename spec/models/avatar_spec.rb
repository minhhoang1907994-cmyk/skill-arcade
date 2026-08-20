require "rails_helper"

RSpec.describe Avatar do
  it "mọi hình cho chọn đều có sprite vẽ sẵn" do
    expect(described_class::CHOICES.map(&:to_sym) - PixelArtHelper::SPRITES.keys).to be_empty
  end

  it "phủ hết sprite app đang có — thêm sprite mới thì phải khai vào đây (BR-40)" do
    expect(PixelArtHelper::SPRITES.keys - described_class::CHOICES.map(&:to_sym)).to be_empty
  end

  it "không khai trùng tên giữa các nhóm" do
    expect(described_class::CHOICES.uniq).to eq(described_class::CHOICES)
  end

  it "hình mặc định nằm trong danh sách cho chọn" do
    expect(described_class).to be_valid(described_class::DEFAULT)
  end

  describe ".resolve" do
    it "giữ nguyên tên hợp lệ" do
      expect(described_class.resolve("slime")).to eq("slime")
    end

    it "rơi về hình mặc định với tên lạ, không ném lỗi" do
      expect(described_class.resolve("sprite_da_xoa")).to eq(described_class::DEFAULT)
      expect(described_class.resolve(nil)).to eq(described_class::DEFAULT)
    end
  end
end
