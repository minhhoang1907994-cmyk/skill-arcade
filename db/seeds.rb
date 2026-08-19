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
# Mật khẩu đọc từ ENV["ADMIN_PASSWORD"]. Owner ĐẢO quyết định cũ ngày 2026-08-19: trước đó chọn
# hardcode (clarify muc 2.4, spec §12), nay đổi vì phát hiện đường lộ cụ thể khi deploy —
# `bin/docker-entrypoint` chạy `db:prepare`, và `DatabaseTasks.prepare_all` seed khi bảng
# `schema_migrations` chưa tồn tại — tức là khi DB chưa có schema, kể cả DB đã tồn tại mà còn
# trống. Nên lần deploy đầu lên DB trống sẽ tự tạo admin trên URL public. Admin xoá được tài khoản
# người khác (BR-22), và app không có chức năng đổi mật khẩu để sửa sau.
#
# Development/test giữ default "12345678" để không đổi quy trình local.
#
# Production KHÔNG có biến thì BỎ QUA việc tạo admin, chứ không abort. Lý do: `db:prepare` chỉ
# seed đúng một lần lúc DB vừa tạo, nên abort giữa seed sẽ để lại DB có schema mà không có bản ghi
# `games` — app hỏng hẳn và lần deploy sau cũng không seed lại. Bỏ qua thì 5 game vẫn được tạo,
# app chạy được, và chỉ cần set biến rồi chạy lại `rails db:seed` (seed này idempotent).
ADMIN_EMAIL = "hoangnm.nta@gmail.com".freeze
ADMIN_PASSWORD = ENV["ADMIN_PASSWORD"].presence || ("12345678" unless Rails.env.production?)

if ADMIN_PASSWORD.nil?
  puts "admin: BỎ QUA — ADMIN_PASSWORD chưa được set ở production."
  puts "       Set biến đó rồi chạy lại `rails db:seed` để tạo tài khoản admin."
else
  admin = User.find_or_initialize_by(email: ADMIN_EMAIL)
  admin.display_name = "HoangNM" if admin.display_name.blank?
  admin.password = ADMIN_PASSWORD
  admin.password_confirmation = ADMIN_PASSWORD
  admin.admin = true
  admin.save!
  puts "admin: #{admin.email}"
end
