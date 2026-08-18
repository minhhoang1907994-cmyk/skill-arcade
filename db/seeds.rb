# Seed 5 game và tài khoản admin.
# Chạy được nhiều lần: dùng find_or_initialize_by nên không tạo bản ghi trùng.

GAMES = [
  {
    slug: Game::BUG_HUNT,
    name: "Bug Hunt",
    description: "Tìm dòng code có bug trong đoạn snippet và chọn đúng loại bug. " \
                 "Rèn kỹ năng code review.",
    questions_per_session: 10,
    steps_per_session: 10
  },
  {
    slug: Game::SPEC_DETECTIVE,
    name: "Spec Detective",
    description: "Tìm câu mơ hồ trong đoạn requirement và viết câu hỏi làm rõ. " \
                 "Rèn kỹ năng đặt câu hỏi trước khi họp khách hàng.",
    questions_per_session: 5,
    steps_per_session: 5
  },
  {
    slug: Game::INCIDENT_ESCAPE_ROOM,
    name: "Incident Escape Room",
    description: "Xử lý sự cố theo lượt, mỗi lựa chọn tốn thời gian giả lập. " \
                 "Mục tiêu khôi phục trong 15 phút giả lập.",
    questions_per_session: 1,
    steps_per_session: 8
  },
  {
    slug: Game::ESTIMATE_POKER,
    name: "Estimate Poker",
    description: "Ước tính effort cho task và so với con số tham chiếu. " \
                 "Rèn cảm giác chia nhỏ và ước lượng công việc.",
    questions_per_session: 10,
    steps_per_session: 10
  },
  {
    slug: Game::PROD_ROULETTE,
    name: "PROD Roulette",
    description: "Mô phỏng thao tác trên môi trường production. Chọn phải hành động " \
                 "không thể thu hồi thì lượt kết thúc ngay.",
    questions_per_session: 1,
    steps_per_session: 10
  }
].freeze

GAMES.each do |attrs|
  game = Game.find_or_initialize_by(slug: attrs[:slug])
  game.assign_attributes(attrs)
  game.save!
  puts "game: #{game.slug} (#{game.questions_per_session} câu / #{game.steps_per_session} bước)"
end

# Tài khoản admin.
#
# CẢNH BÁO ĐÃ ĐƯỢC GHI NHẬN: mật khẩu để hardcode theo quyết định của owner
# (xem docs/clarify/clarify_skill-arcade.md muc 2.4). App này chạy public, nên nếu
# seed chạy trên production thì tài khoản admin có thể bị chiếm. Phương án an toàn
# hơn (đọc từ ENV + ép đổi mật khẩu lần đầu) đã được đề xuất và owner chọn không dùng.
ADMIN_EMAIL = "hoangnm.nta@gmail.com".freeze
ADMIN_PASSWORD = "12345678".freeze

admin = User.find_or_initialize_by(email: ADMIN_EMAIL)
admin.display_name = "HoangNM" if admin.display_name.blank?
admin.password = ADMIN_PASSWORD
admin.password_confirmation = ADMIN_PASSWORD
admin.admin = true
admin.save!
puts "admin: #{admin.email}"
