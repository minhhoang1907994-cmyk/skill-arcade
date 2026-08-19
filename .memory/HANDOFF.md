# Session Handoff

## Session gần nhất
- Ngày: 2026-08-19
- Tóm tắt: **Phase 3 (AI/Gemini) đã code xong**, spec lên v1.5. Cùng ngày trước đó:
  Bug Hunt phân đề theo ngôn ngữ (BR-35, v1.4). Cuối session: đổi bảng màu nền
  (đồng cỏ + bảng gỗ + header gạch Mario) và thêm item JRPG hai bên. **Toàn bộ chưa commit.**
- CHẶN: chưa có `GEMINI_API_KEY` nên chưa gọi Gemini thật lần nào. Đường lỗi (503)
  đã verify đầy đủ; đường thành công chỉ verify bằng client giả trong rspec.
- CẦN OWNER QUYẾT — Open Question **Q9** (spec §20): điều khoản gói Gemini free cho
  phép Google dùng nội dung gửi lên để cải thiện sản phẩm và cho người thật đọc.
  Spec Detective gửi text người chơi tự gõ. Chưa quyết thì không nên bật Phase 3 thật.
- Session trước (2026-08-18): dựng project từ repo trống, Phase 1 + Phase 2 xong.

## Trạng thái hiện tại

### ✅ Verify đã pass
```
ruby -S rspec           → 133 examples, 0 failures
ruby bin/rubocop        → 87 files, no offenses
bin/rails zeitwerk:check → All is good!
```

Đã chơi thật qua API trên server đang chạy (phần rspec không thay được):
- POST không kèm `X-CSRF-Token` → 422 `INVALID_CSRF_TOKEN`; có token → 201
- Chơi trọn 10 bước Bug Hunt: chấm đúng 10 / 6 / 0 điểm theo từng trường hợp
- PROD Roulette chọn hành động không thu hồi được → 0đ bước đó, kết thúc lượt,
  giữ nguyên điểm bước trước (BR-29 + BR-31)
- Leaderboard tuần trả đúng khoảng `2026-08-17 → 2026-08-23 +07:00`
- Response không bao giờ chứa `answer_key` (BR-03)
- Chọn ngôn ngữ Bug Hunt: `/games/bug_hunt` render đúng 3 radio java/php/ruby;
  POST thiếu `language` → 422 `INVALID_LANGUAGE`; `language=cobol` → 422
  `INVALID_LANGUAGE`; `language=javascript` (chỉ 4 câu) → 422
  `NO_QUESTIONS_AVAILABLE`; `language=java` → chơi trọn 10 bước, cả 10 bước
  `content.language == "java"`. Session test đã xoá khỏi DB dev
- CHƯA verify qua browser thật (owner tự kiểm tra): hiển thị visual của `.chips`
  khi checked/focus, và luồng click "Bắt đầu" gửi `language` từ JS
- Phase 3 trên server thật: nộp đáp án Spec Detective khi không có `GEMINI_API_KEY`
  → 503 `GRADING_UNAVAILABLE`, lượt `abandoned/system_error`, `score = 0`,
  `current_position` giữ 0, `session_answers` 1 dòng score 0 kèm
  `_meta.grading_pending = true`, `ai_gradings` 1 dòng `score = NULL` +
  `error = "Gemini::Client::ConfigurationError: GEMINI_API_KEY chưa được cấu hình"`
- `rake questions:generate` chặn đúng 3 trường hợp: thiếu API key / thiếu language cho
  bug_hunt / game slug không tồn tại
- `rake questions:import` với file YAML tay: nạp 1 câu, loại 1 câu thiếu khoá, chạy lần 2
  ra "0 câu mới, 1 câu cập nhật" (idempotent theo checksum)
- BR-36: câu hiển thị == câu được chấm, `GET current` 2 lần ra cùng `question_id`
- Dữ liệu test đã dọn: xoá session 12/13 và question ai_generated id=59;
  `AiGrading.count = 0`, `Question.where(source: 'ai_generated').count = 0`

### Môi trường (đặc thù máy này)
- Ruby 4.0.5, Rails 8.1.3, adapter **mysql2** (trilogy không có trên máy)
- **Docker Desktop phải chạy trước** mọi lệnh chạm DB (migrate/seed/rspec), nếu không
  báo `ActiveRecord::ConnectionNotEstablished ... 127.0.0.1 (10061)`. Container
  `skill_arcade_db` có `restart: unless-stopped` nên tự lên sau khi Docker khởi động
- Sau khi migrate ở development phải chạy thêm
  `RAILS_ENV=test ruby bin/rails db:prepare`, không thì rspec abort vì pending migration
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
- `db/seeds/sample_questions.rb` — câu viết tay (`source: "manual"`).
  Chạy: `ruby bin/rails runner db/seeds/sample_questions.rb`

### Chọn ngôn ngữ lập trình cho Bug Hunt (BR-35, spec v1.4) — chưa commit
- Migration `20260818000008_add_language_to_questions_and_sessions.rb`:
  `questions.language`, index `index_questions_on_game_language_hidden`,
  `game_sessions.language`, kèm backfill nhân `content.language` ra cột riêng
- `Question#assign_language` (before_validation) + scope `in_language(nil = không lọc)`
- `Game#language_scoped?` (chỉ `bug_hunt`), `#available_languages` (có mặt trong bank),
  `#playable_languages` (đủ `questions_per_session` — đây là danh sách hiện cho người chơi)
- `Creator` / `Drawer` / `StepProvider` nhận `language:`; ngôn ngữ chốt ở
  `game_sessions.language` vì đề bốc theo từng bước
- Phân biệt 2 mã lỗi: ngôn ngữ lạ → `INVALID_LANGUAGE`; ngôn ngữ có thật nhưng thiếu
  câu → `NO_QUESTIONS_AVAILABLE`
- `app/views/games/show.html.erb` — radio `.chips` + JS gửi `{language}` khi POST
- Ngân hàng mẫu Bug Hunt: **34 câu** — php 10, ruby 10, java 10, javascript 4.
  javascript chưa đủ 10 nên KHÔNG hiện trong danh sách chọn (4 câu đang là dữ liệu chết)
- Spec `docs/spec/skill-arcade.md` lên **v1.4**: BR-35, 2 cột ở §4.2, param `language`
  + mã lỗi ở §5, §6 sửa "tối thiểu 50 câu" thành tính theo TỪNG ngôn ngữ

### Phase 3 — AI/Gemini (chưa commit)
- `app/services/gemini/` — **thư mục MỚI, phải restart server** (bẫy autoload đã biết)
  - `error.rb` — `Gemini::Error`, gốc của mọi lỗi phía Gemini. Circuit breaker đếm đúng
    lớp này, nên lỗi lập trình (ArgumentError...) không làm breaker mở
  - `client.rb` — `generateContent` REST trên `net/http` stdlib, KHÔNG thêm gem.
    API key đi qua header `x-goog-api-key`, không nằm trong URL (không lọt access log).
    Bắt buộc `response_schema` (structured output), không parse text tự do.
    Chặn cả 200 nhưng vô dụng: `promptFeedback.blockReason`, `finishReason != STOP`,
    text rỗng. read_timeout 10s lúc chơi (§15), 120s khi sinh đề
  - `circuit_breaker.rb` — 5 lỗi liên tiếp → mở 5 phút, state ở `Rails.cache`.
    Lời gọi bị chặn KHÔNG tính là lỗi (không thì mỗi lần retry tự gia hạn trạng thái mở)
  - `spec_detective_grader.rb` — BR-26. **Không raise khi lỗi**, trả `Grading` có
    `failed?` + `attributes` để người gọi còn ghi được `ai_gradings` (BR-19).
    Điểm Gemini trả về bị kẹp 0..10 mỗi thang (BR-02 giữ nguyên: server quyết điểm)
- `app/services/questions/generator.rb` — sinh đề cho **cả 5 game** qua BLUEPRINTS
  (item_schema + instructions + build). Hai chỗ Ruby phải tự dựng:
  `bug_types` lấy từ `Question::BUG_HUNT_TYPES`, và `option_effects` của 2 game kịch bản
  (responseSchema không diễn đạt được hash khoá động → AI trả array, Ruby gom lại)
- `app/services/questions/importer.rb` — đọc YAML, validate theo `REQUIRED_KEYS` từng
  game, upsert theo checksum, `source: ai_generated`
- `lib/tasks/questions.rake` — `questions:generate[game,count,language]` và
  `questions:import[file]`
- Sửa kèm: `Scoring::Result` thêm field `ai_grading`; `GradingUnavailable` mang theo
  attributes để ghi log; `AnswerSubmitter` ghi `ai_gradings` cả đường thành công và
  đường lỗi; `AiGrading` cho `response` rỗng khi `failed?` (cột NOT NULL)
- `Question::BUG_HUNT_TYPES` — danh sách chuẩn 12 loại bug, seed dùng chung với generator

### Giao diện — đổi bảng màu nền + item JRPG (chưa commit)
- **Token đã XOÁ**: `--sky-1/2/3` (và override dark mode của chúng). Không còn chỗ nào
  tham chiếu. Thay bằng:
  - `--field` / `--field-tuft` / `--field-bloom` — đồng cỏ hai bên trang.
    `--field: var(--grass)` ở light mode theo đúng yêu cầu
  - `--board` / `--board-dark` / `--board-line` — khối `main`, tông gỗ `#6b4527`
  - `--header` / `--header-dark` / `--header-deep` — thân gạch header, cam-nâu `#b8500e`
- Lý do chọn màu (đừng đổi lại mà không tính tương phản): chữ trắng trên `--grass` cũ
  chỉ đạt **2.2:1**, trên `--header` `#b8500e` đạt **5.0:1** (WCAG AA). Cam sáng NES
  `#e45c10` chỉ được 3.6:1 nên KHÔNG dùng. h1 chữ trắng trên `--brick` cũ **2.6:1**,
  trên `--board` nâu **8.4:1**
- **Header là khối gạch kiểu Mario**: tile SVG 32x32 data URI trong `.site-header`,
  2 hàng gạch xếp lệch nửa viên. Tile CHỈ vẽ vữa + bevel bằng đen/trắng có
  `fill-opacity`, thân gạch trong suốt → màu gạch là `background-color: var(--header)`,
  nên dark mode chỉ đổi token, không cần tile thứ hai. Không làm được bằng gradient CSS
  vì kiểu xếp lệch hàng cần biến thiên theo 2 trục
- `.site-header__inner` có `min-height: 64px` = đúng 2 tile 32px để hàng gạch cuối không
  bị cắt giữa viên. Đổi số này thì chọn bội số của 32
- Token `--text-outline` (8 bóng đổ cứng 1px màu `--ink`) cho chữ nằm trên hoạ tiết gạch:
  brand, nav, tên user. Cần nó vì hoạ tiết có vạch bevel TRẮNG chạy dưới nét chữ nên
  contrast CỤC BỘ sụp, dù contrast trung bình vẫn đạt AA — bóng đổ 1 hướng không cứu được.
  Đã hạ thêm `fill-opacity` của 2 rect bevel trắng trong data URI xuống `.18` để bớt
  va chạm trắng-trên-trắng ngay tại nguồn. Đòn còn lại nếu vẫn khó đọc: thêm nền tối mờ
  sau hàng nội dung header (đánh đổi: che một phần mặt gạch)
- `--sea` / `--sea-dark` / `--flame` là slot màu trong palette, hiện KHÔNG chỗ nào dùng
- `--brick` giờ chỉ còn đúng vai trò màu cảnh báo (`.errors`, `.flash--alert`,
  `.btn--danger`, `.feedback--bad`)
- Nền không dùng ảnh: `body` và `main` đều là nhiều lớp gradient (búi cỏ, hoa, dải cỏ
  đã cắt / đường ghép ván gỗ, vân gỗ). Số lớp trong `background-image` phải khớp thứ tự
  với `background-size` và `background-repeat`
- `PixelArtHelper`: thêm 6 sprite 16x16 (`bush`, `flower`, `coin`, `potion`, `sword`,
  `mushroom`) + hằng `SCENERY` + method `scenery_sprites`. Layout render
  `<div class="scenery" aria-hidden="true">`
- **Ràng buộc dễ vỡ**: bề rộng sprite trong `PixelArtHelper::SCENERY` gắn với khoảng lệch
  `calc(50% - Npx)` của đúng slot đó trong `application.css`. Điều kiện: `N - W >= 506`
  và `N <= 560`. Đổi `size` mà không tính lại N thì sprite đè lên `main` hoặc bị cắt ở
  mép màn hình. Công thức đã ghi comment ở cả hai file
- Lớp trang trí tự ẩn dưới 1140px (lề không còn đủ chỗ), `pointer-events: none`
- `prefers-reduced-motion` trước đây chỉ tắt `transition`; đã bổ sung tắt `animation`
  cho `.sprite--bounce` và `.scenery__item`
- CHƯA verify bằng mắt — owner tự mở xem (đã hỏi và owner chọn tự kiểm tra)

### Bug Phase 2 đã sửa trong session này — BR-36
`StepProvider` bốc đề theo từng bước bằng `ORDER BY RAND()`, nên **câu hiển thị cho người
chơi và câu server chấm là hai câu khác nhau**. Verify thật bắt được: client thấy
`question_id=27`, server chấm `question_id=29`. Với Bug Hunt thì người chơi bị chấm sai
oan; với Spec Detective thì AI chấm bài của đoạn A theo đáp án đoạn B.
Sửa: `Questions::Drawer` nhận `seed:`, thứ tự bốc là `MD5(CONCAT(questions.id, seed))`;
`StepProvider` truyền `seed: "#{session.id}:#{next_position}"`. Không thêm cột DB.

## Việc tiếp theo
1. **Owner quyết Q9** (spec §20) trước khi bật Phase 3 thật — rủi ro dữ liệu, không phải
   quyết định kỹ thuật
2. Export `GEMINI_API_KEY` rồi verify đường thành công thật: sinh 1 lô đề nhỏ
   (`rake "questions:generate[bug_hunt,5,java]"`) và chấm thật 1 lượt Spec Detective
3. Mở AI Studio đọc hạn mức thật của project, cập nhật §20 (con số 10 RPM / 250 RPD
   hiện chỉ từ nguồn thứ ba, CHƯA verify từ Google)
4. Sinh ngân hàng đề đạt mức tối thiểu §6: Bug Hunt 50 câu **mỗi ngôn ngữ**,
   Spec Detective 25, Estimate Poker 50, Escape Room 20, PROD Roulette 20
5. Cân nhắc `dotenv-rails` (CẦN DUYỆT theo CLAUDE.md) — hiện `.env` không được nạp,
   phải export biến bằng tay

## Ghi chú quan trọng

### Bẫy khi thêm câu Bug Hunt vào `db/seeds/sample_questions.rb`
`bug_types` trong `content` sinh từ chính `BUG_HUNT_SAMPLES.map { bug_type }.uniq`, và
checksum = SHA-256 của `content`. Nên thêm **một bug_type mới** sẽ đổi checksum của TOÀN
BỘ câu cũ → `upsert_question` không tìm thấy bản ghi cũ và tạo bản ghi TRÙNG thay vì cập
nhật. Thêm câu mới thì dùng lại 12 bug_type đã có, hoặc phải xử lý câu cũ trước.

### Ngân hàng Bug Hunt hiện chỉ đủ mức tối thiểu
Mỗi ngôn ngữ đúng 10 câu = `questions_per_session`. Chơi lại cùng ngôn ngữ sẽ gặp lại
toàn bộ 10 câu (BR-32 buộc phải fallback sang câu đã trả lời đúng). Muốn có câu mới ở
lượt sau thì cần thêm ít nhất 2-3 câu mỗi ngôn ngữ.

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
