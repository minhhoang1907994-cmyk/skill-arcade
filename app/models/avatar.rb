# Danh sách hình đại diện người chơi được phép chọn (BR-40).
#
# Đây là nguồn DUY NHẤT cho cả validation ở User và lưới chọn ở trang cài đặt. Pixel art
# của từng tên nằm ở PixelArtHelper::SPRITES; spec/models/avatar_spec.rb chốt hai bên không
# lệch nhau, vì thêm sprite mà quên khai ở đây thì người chơi không chọn được, còn khai ở
# đây mà chưa vẽ sprite thì trang cài đặt nổ KeyError.
module Avatar
  DEFAULT = "hero".freeze

  # Nhóm chỉ để xếp lưới cho dễ tìm, không mang ý nghĩa nghiệp vụ — mọi hình đều chọn được
  # như nhau. Khoá là nhãn hiển thị luôn.
  GROUPS = {
    "Nhân vật" => %w[hero knight mage archer].freeze,
    "Quái vật" => %w[slime dragon skull eye mimic bat ghost].freeze,
    "Vật phẩm" => %w[chest coin potion sword mushroom flower bush].freeze
  }.freeze

  CHOICES = GROUPS.values.flatten.freeze

  def self.valid?(name)
    CHOICES.include?(name.to_s)
  end

  # Tên lấy từ DB có thể trỏ sprite đã đổi tên ở lần deploy sau, nên mọi chỗ hiển thị
  # đi qua đây thay vì tin thẳng vào giá trị trong cột.
  def self.resolve(name)
    valid?(name) ? name.to_s : DEFAULT
  end
end
