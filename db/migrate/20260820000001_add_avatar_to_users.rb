class AddAvatarToUsers < ActiveRecord::Migration[8.1]
  def change
    # Hình đại diện người chơi (BR-40). Lưu TÊN sprite, không lưu file: pixel art nằm trong
    # code (PixelArtHelper) nên cột chỉ cần đủ rộng cho tên dài nhất trong Avatar::CHOICES.
    # NOT NULL kèm default để tài khoản tạo trước cột này vẫn có hình hiển thị được ngay.
    # Default viết thẳng "hero" chứ không tham chiếu Avatar::DEFAULT: migration đã chạy rồi
    # thì không được đổi hành vi theo code hiện tại.
    add_column :users, :avatar, :string, limit: 20, null: false, default: "hero"
  end
end
