# Session Handoff

## Session gần nhất
- Ngày: 2026-08-18
- Tóm tắt: Dựng project skill-arcade từ repo trống — CLAUDE.md, clarify (5 vòng),
  spec (v1.3), **Phase 1 (nền tảng) và Phase 2 (gameplay) đã chạy được và verify đầy đủ**.
  Còn Phase 3 (AI/Gemini).

## Trạng thái hiện tại

### ✅ Verify đã pass
```
ruby -S rspec           → 81 examples, 0 failures
ruby bin/rubocop        → 73 files, no offenses
bin/rails zeitwerk:check → All is good!
```

Đã chơi thật qua API trên server đang chạy (phần rspec không thay được):
- POST không kèm `X-CSRF-Token` → 422 `INVALID_CSRF_TOKEN`; có token → 201
- Chơi trọn 10 bước Bug Hunt: chấm đúng 10 / 6 / 0 điểm theo từng trường hợp
- PROD Roulette chọn hành động không thu hồi được → 0đ bước đó, kết thúc lượt,
  giữ nguyên điểm bước trước (BR-29 + BR-31)
- Leaderboard tuần trả đúng khoảng `2026-08-17 → 2026-08-23 +07:00`
- Response không bao giờ chứa `answer_key` (BR-03)

### Môi trường (đặc thù máy này)
- Ruby 4.0.5, Rails 8.1.3, adapter **mysql2** (trilogy không có trên máy)
- MySQL container map ra **host port 3307** — máy có `mysqld.exe` Windows Service
  chiếm sẵn 3306 của project khác, KHÔNG được tắt
- **Lệnh phải gọi qua `ruby`**: `ruby bin/rails server`, `ruby bin/rubocop`,
  `ruby -S rspec`. Gõ thẳng `bin/rails ...` trong PowerShell chỉ mở file bằng editor;
  `bundle exec rspec` bị wrapper rtk chặn ("program not found")
- DB development hiện có vài lượt chơi test trên leaderboard. Xoá:
  `ruby bin/rails runner "GameSession.destroy_all"`

## Đã thực hiện

### Tài liệu
- `CLAUDE.md`, `docs/clarify/clarify_skill-arcade.md`
- `docs/spec/skill-arcade.md` — **v1.3**
  (v1.0 → v1.1 xử lý 4 blocker + 7 warning → v1.2 xử lý 4 suggestion →
   v1.3 bổ sung CSRF vào §13, mã lỗi `INVALID_CSRF_TOKEN` §5.2, test scenario §17)
- `docs/spec/assets/skill-arcade-img1.mmd`

### Phase 1 — nền tảng
7 migration, 7 model, `LeaderboardQuery`, auth controllers, admin users,
rack_attack, seeds (5 game + admin), docker-compose, rake `game_sessions:expire_stale`.

### Phase 2 — gameplay
- `app/services/scoring/` — base + result + 5 scorer (BR-25→29)
- `app/services/game_sessions/` — creator, step_provider, answer_submitter
- `app/services/questions/drawer.rb` — BR-32
- `app/controllers/api/v1/` — base, game_sessions, session_answers, question_reports
- `app/controllers/admin/question_reports_controller.rb` + view
- `app/views/games/show.html.erb` — giao diện chơi cho cả 5 game
- `db/seeds/sample_questions.rb` — 36 câu viết tay (`source: "manual"`).
  Chạy: `ruby bin/rails runner db/seeds/sample_questions.rb`

## Việc tiếp theo — Phase 3 (AI)
1. Verify Open Question Q2: hạn mức + điều khoản gói free Gemini API
2. Gemini client + `rake questions:generate[game,count]` xuất YAML ra
   `db/question_banks/<game>/<date>.yml`, người xem qua rồi `rake questions:import[file]`
3. Chấm Spec Detective real-time (hiện scorer raise `GradingUnavailable` → 503),
   ghi `ai_gradings` cho mọi lần gọi kể cả lần lỗi (BR-19)
4. Circuit breaker: mở sau 5 lần lỗi liên tiếp, giữ 5 phút (spec §15)

## Ghi chú quan trọng

### Bẫy môi trường đã gặp — nhớ để khỏi mất thời gian lại
- **Tạo thư mục mới dưới `app/` phải RESTART server.** Rails chốt autoload paths lúc
  boot; code reload không nạp thư mục mới. Đã mất thời gian debug vì `app/services`
  tạo sau khi server đã chạy → `uninitialized constant Scoring`
- **Trong `Api::V1::*` phải prefix `::` cho hằng service** (`::Scoring::Base`,
  `::GameSessions::Creator`, `::GameSession::USER_QUIT`). Không có `::` thì Ruby tìm
  `Api::V1::BaseController::Scoring` và ném NameError khi lazy-load ở development —
  **test env eager-load nên spec vẫn xanh**, lỗi chỉ lộ khi chạy server
- **Test env tắt CSRF protection** nên request spec không chứng minh được client gửi
  token đúng. Phải kiểm tra bằng curl trên server thật
- `ENV.fetch` không default trong `database.yml` làm hỏng MỌI môi trường vì ERB render cả file

### Quyết định thiết kế đã chốt — KHÔNG hồi sinh phương án cũ
- **`game_sessions` lưu từng lượt**, KHÔNG chỉ `best_score`
- **Cả 5 game cộng dồn** (BR-31), bắt đầu 0, không bao giờ trừ. Escape Room từng thiết kế
  "bắt đầu 100 rồi trừ dần" ở spec v1.0 nhưng đã bị loại
- **`games` tách `questions_per_session` và `steps_per_session`** (BR-30):
  Escape Room 1/8, PROD Roulette 1/10
- **`attempts_to_best` tính theo chu kỳ đang xem** (BR-10), không dùng `attempt_number` all-time
- **Chấm điểm ở server** (BR-02); `answer_key` chặn ở cả `as_json` và `serializable_hash` (BR-03)
- **Câu hỏi bốc theo từng bước**, không chốt sẵn cả bộ vào cache — cache mất là hỏng lượt
- **MySQL tối thiểu 8.0.16** — dưới đó CHECK constraint bị bỏ qua âm thầm
- **Giữ CSRF protection cho JSON API** — endpoint dùng cookie session, tắt là mở lỗ hổng thật

### Ràng buộc nghiệp vụ đã chốt
- **KHÔNG dùng dữ liệu Backlog khách hàng** làm nội dung câu hỏi (rủi ro NDA)
- **PROD Roulette / Escape Room dùng kịch bản hư cấu**, bám bài học trong
  `~/.claude/rules/nta-prod-safety.md` nhưng không dùng incident thật
- **Estimate Poker**: `actual` do AI sinh — không đo được velocity thật của team
- Chỉ tiếng Việt. Estimate Poker solo. Không có màn hình admin duyệt câu hỏi
  (thay bằng soát file YAML lúc import + nút báo câu hỏi sai)

### Quyết định rủi ro owner đã chấp nhận (không tự ý đổi)
- **Mật khẩu admin `12345678` hardcode** trong `db/seeds.rb`. Đã đề xuất ENV + ép đổi
  mật khẩu lần đầu, owner giữ hardcode. Security review flag CRITICAL — đã acknowledge.
  Giá trị nằm trong git history: nếu push GitHub public thì phải đổi mật khẩu sau deploy
- **Allowlist `*.nta@gmail.com`** không chặn người cố ý — rate limit mới là lớp bảo vệ thật
- **Điểm AI chấm không tất định** — chấp nhận, bù bằng log `ai_gradings`
