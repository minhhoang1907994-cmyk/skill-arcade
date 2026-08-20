# Session Handoff

## Session gần nhất
- Ngày: 2026-08-20
- Tóm tắt: **Bỏ Gemini khỏi đường chơi** (spec v1.19) rồi sửa hai lỗi phát hiện khi chơi
  thật trên Render (spec v1.20). Commit `v2.0` đã push lên `origin/main`.
- **Spec Detective giờ là game CHỌN**: tick câu mơ hồ (10đ, trừ điểm tick sai) + chọn câu
  hỏi làm rõ tốt nhất trong 4 phương án (10đ). Chấm hoàn toàn từ `answer_key`, KHÔNG gọi AI.
- Kéo theo **xoá** `Gemini::SpecDetectiveGrader`, `Gemini::DailyBudget` (BR-37), throttle
  `sessions/spec_detective/user`, đường `503 AI_QUOTA_EXHAUSTED`/`GRADING_UNAVAILABLE`,
  §8.5, `Scoring::Base::GradingUnavailable`, `Game#ai_graded?`. Bảng `ai_gradings` GIỮ LẠI
  (dữ liệu lịch sử, có FK) nhưng không còn gì ghi vào.
- **Hết trần 4 lượt/ngày toàn hệ thống và 1 lượt/người/ngày.** Gemini giờ chỉ còn một người
  dùng duy nhất là việc sinh đề → 20 request/ngày = tối đa 100 đề/ngày, **không cần API key
  thứ hai** như từng tính.
- Thêm job hằng ngày `.github/workflows/questions-refill.yml` → `rake questions:refill`.
  BR-24 lần đầu có scheduler (task gọi `game_sessions:expire_stale` trước tiên), miễn phí.
- Open Question: chỉ còn **Q6** (KPI). Q9 (gửi text người chơi sang Google) **hết hiệu lực**
  — không còn text người chơi nào được gửi đi.


## Trạng thái hiện tại

### ✅ Verify đã pass (2026-08-20, sau v1.22)
```
bundle exec rspec        -> 177 examples, 0 failures
bundle exec rubocop      -> 93 files, no offenses
```
Recheck UI bằng Chrome trên server dev (owner yêu cầu tự động check):
- Spec Detective format mới: 4 ô tick + 4 phương án render đúng, tick [1,3] + chọn "a" →
  **20/20 điểm**, giải thích hiện đúng, KHÔNG có alert nào
- Guard đề format cũ: hiện "Câu hỏi này ở định dạng cũ nên chưa chơi được", disable nút
  Nộp, không màn hình trắng
- Modal: prompt (báo câu sai) focus vào textarea, Esc = huỷ và KHÔNG gửi; confirm (bỏ lượt)
  nút đỏ + Huỷ thì lượt vẫn tiếp tục; alert (hết câu hỏi) hiện message của server, nút Huỷ
  ẩn, không rơi vào màn chơi
- Admin xoá tài khoản: modal hiện đúng email, bấm Huỷ không xoá, bấm "Xoá tài khoản" →
  "Đã xoá tài khoản" (đường `requestSubmit` sau khi chặn hoạt động)


### Số đo thật từ Gemini (không phải từ docs) — chi tiết ở spec §20
| Điều | Kết quả |
|---|---|
| Hạn mức free | **20 request/ngày MỖI MODEL** (HTTP 429 ghi rõ `limit: 20`) |
| `gemini-2.5-flash` | HTTP 404, Google đã đóng với key mới → dùng `gemini-3.6-flash` |
| `gemini-2.5-flash-lite` | HTTP 404 y hệt |
| Tắt thinking | `thinkingBudget: 0` → HTTP 400, KHÔNG tắt được trên flash 3.x |
| Field đúng | `generationConfig.thinkingConfig.thinkingBudget`. `thinkingLevel` đặt trực tiếp dưới `generationConfig` → 400 unknown name |
| Thinking token | tính vào `maxOutputTokens`. Để 256 → `MAX_TOKENS` mà chưa sinh nội dung |
| Độ trễ chấm | `thinkingLevel: low` 10.6s (quá hạn) / budget 128 quá 10s với bài dài / **budget 32 → 2.3-5.2s** |
| Lỗi tạm | HTTP 503 "high demand" xuất hiện ngẫu nhiên giữa lô sinh đề |

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

### v1.19 — Spec Detective đổi sang dạng CHỌN, bỏ AI khỏi đường chơi (2026-08-20)

Format đề mới:
```
content     statements: [...]  +  clarifying_options: [{key, label}]
answer_key  ambiguous_statement_indexes: [...]  +  best_option_key  +  explanation
answer      { statement_indexes: [1,3], option_key: "a" }
```

- `Scoring::SpecDetective` — chấm từ DB. Nửa tick: `floor((đúng − sai)/tổng × 10)` kẹp 0..10.
  **Phải trừ tick sai**, không thì tick hết mọi câu là ăn đủ 10đ mà không cần đọc
- `Questions::Validator` (MỚI) — luật validate đề tách khỏi `Importer` để `Importer` và task
  chuyển đổi dùng CÙNG một luật. Với Spec Detective: index mơ hồ phải trỏ câu có thật, phải
  còn ít nhất một câu KHÔNG mơ hồ, `best_option_key` phải nằm trong `clarifying_options`
- `Questions::BankFile` (MỚI) — tách phần ghi YAML khỏi rake task để `Refiller` dùng lại.
  Nhận `dir:` để test không ghi rác vào `db/question_banks`
- `Questions::Refiller` (MỚI) — job hằng ngày, **ba trần bắt buộc**:
  1. **Bỏ qua game còn lượt `in_progress`** — đề KHÔNG chốt sẵn lúc tạo lượt, mỗi lần hiển
     thị và mỗi lần chấm đều bốc lại từ pool sống. INSERT giữa lượt làm thứ tự MD5 trong
     `Drawer` đổi → chấm theo câu người chơi chưa thấy, phá BR-36
  2. Chỉ sinh khi dưới `3 × questions_per_session` → ngày đủ đề tốn 0 request
  3. Tối đa `MAX_TARGETS_PER_RUN = 1` mục tiêu mỗi lần chạy → bound số request
  KHÔNG tự thêm ngôn ngữ mới cho Bug Hunt — chỉ refill ngôn ngữ đã có trong bank
- `Questions::SpecDetectiveConverter` (MỚI) + `rake questions:convert_spec_detective` —
  chuyển đề format cũ bằng Gemini, chạy MỘT LẦN sau deploy
- `db/seeds/sample_questions.rb` — 6 đề Spec Detective viết tay theo format mới (verify:
  0 câu không hợp lệ theo Validator). Đủ cho một lượt (`questions_per_session: 5`)
- `.github/workflows/questions-refill.yml` — 19:00 UTC (02:00 VN). **Cố ý KHÔNG set
  `REDIS_URL`** → runner rơi về file store nên circuit breaker của job tách khỏi web service
- Trang `/privacy` §2 viết lại: nội dung người chơi nhập KHÔNG ra khỏi app

### v1.22 — job refill fail exit 126: bin/* thiếu bit thực thi (2026-08-20)

Lần chạy `gh workflow run questions-refill.yml` đầu tiên: bước "Refill question bank" dừng với
**exit code 126** = tìm thấy file nhưng không thực thi được. Không phải lỗi Rails, lỗi file mode.

- Repo tạo trên Windows → **cả 10 file `bin/*` vào git với mode `100644`**, thiếu bit +x
- **Vì sao production vẫn chạy**: `Dockerfile:61` có `RUN chmod +x bin/*` nên image tự sửa lúc
  build. Chỉ runner Actions — chạy thẳng từ checkout — mới gặp
- **Vì sao CI không bắt được**: `ci.yml` cũng gọi `bin/brakeman`, `bin/rubocop`, `bin/rails` nên
  lẽ ra fail y hệt, nhưng trigger là `push: branches: [master]` mà default branch là `main` →
  **CI chưa từng chạy cho commit nào**. Đã sửa thành `[ main ]`
- Sửa mode: `git update-index --chmod=+x bin/<file>` cho cả 10 file
- Guard `spec/bin_executable_spec.rb`, theo đúng pattern `gemfile_lock_spec.rb`. Kiểm mode trong
  **git index**, KHÔNG dùng `File.executable?` — trên Windows filesystem không mang bit +x nên
  hàm đó trả kết quả vô nghĩa. Đã verify guard thật sự đỏ khi bỏ bit của `bin/rails` rồi phục hồi
- Cùng lúc sửa `Questions::Refiller`: lọc mục tiêu bị chặn TRƯỚC khi chọn (xem mục dưới)

**Bẫy chung của cả v1.22 và bẫy Gemfile.lock trước đó**: `Dockerfile` âm thầm sửa hậu quả của
việc phát triển trên Windows (`chmod +x`, `bundle lock --add-platform`), nên mọi đường KHÔNG đi
qua Docker — GitHub Actions, chạy tay trên máy Linux — đều có thể vỡ mà production vẫn xanh.

### Sửa Refiller: mục tiêu bị chặn chiếm suất của mục tiêu nạp được (2026-08-20)

Đo trên production: cả 6 mục tiêu thiếu đề đều có lượt `in_progress`, và `expire_stale` dọn 0
lượt (cũ nhất 17.5 giờ, ngưỡng 24 giờ). Code cũ chọn 1 mục tiêu thiếu nhất RỒI mới kiểm lượt
đang mở → lần chạy sinh 0 đề mà `outcomes.any?(failed)` là false nên **báo xanh**.

Sửa: `partition` mục tiêu bị chặn TRƯỚC khi `sort_by(-shortfall).first(max_targets)`. Mục tiêu
bị chặn vẫn được in ra dạng `:skipped` kèm số lượt đang mở — im lặng thì không phân biệt được
"hôm nay đủ đề rồi" với "lúc nào cũng có người đang chơi nên không bao giờ nạp được".


### v1.21 — vá lỗ 500 khi ngân hàng câu hỏi hụt giữa lượt (2026-08-20)

`Questions::Drawer::NotEnoughQuestions` chỉ được rescue ở endpoint TẠO LƯỢT. `GET current` và
nộp đáp án để nó lọt ra → **500**. Chạm được thật khi admin ẩn câu giữa lúc có người đang chơi
— chính luồng BR-16/BR-18 mà app khuyến khích người chơi dùng.

- Rescue chuyển về **tập trung** ở `Api::V1::BaseController` (`rescue_from`) cho cả
  `NotEnoughQuestions` và `StepProvider::NoQuestionAvailable`. Bỏ 3 rescue inline trùng nhau —
  lý do centralize: 3 endpoint cùng bốc đề, để inline thì endpoint thứ 4 lại quên
- **Tôi đã phân tích sai lúc đầu**: nói exception thoát ra là `NoQuestionAvailable`. Sai.
  `Drawer#call` luôn trả đúng `count` câu hoặc ném `NotEnoughQuestions` trước đó, nên
  `fresh_question` không bao giờ hết ứng viên → `NoQuestionAvailable` hiện KHÔNG chạm được.
  Test viết theo giả định sai đã fail và chỉ đúng chỗ. Bài học: viết test reproduce trước khi
  tin vào suy luận về đường exception
- Lượt cố ý GIỮ `in_progress`, KHÔNG tự chuyển `abandoned`: đó là thay đổi state machine §11 và
  `abandoned_reason` chưa có giá trị nào đúng cho tình huống này. Người chơi thoát bằng nút Bỏ
  lượt sẵn có (`user_quit`)
- 5 test hồi quy, gồm ranh giới `INVALID_LANGUAGE` vs `NO_QUESTIONS_AVAILABLE`: ẩn HẾT câu làm
  ngôn ngữ mất khỏi bank → `INVALID_LANGUAGE` (không phải `NO_QUESTIONS_AVAILABLE`), đúng như
  `creator.rb` đã ghi


### v1.20 — hai lỗi phát hiện khi chơi thật trên Render (2026-08-20)

**Lỗi 1: "Không bắt đầu được lượt chơi" ở Spec Detective.** Thông điệp này SAI hoàn toàn so
với nguyên nhân — server trả 200 và lượt đã được tạo. Đo được trên dev DB dựng giống
production (11 đề format cũ + 6 mới): **6/8 lượt bốc phải đề format cũ**, rồi
`renderSpecDetective` ném `TypeError` ở `c.statements.forEach`. Lỗi đó bị chính `try` của
lời gọi API bắt nên hiện ra như lỗi tạo lượt.

Ba thay đổi:
- `renderStep` chuyển ra NGOÀI `try` của API. Lượt đã tạo ở server thì lỗi dựng giao diện
  không phải lỗi tạo lượt — gộp hai thứ vào một `catch` là cách bug này ẩn được lâu
- Guard trong `renderSpecDetective`: thiếu `statements`/`clarifying_options` → báo "câu hỏi ở
  định dạng cũ", disable nút Nộp, mời báo câu sai. Không còn màn hình trắng
- `rake questions:hide_invalid` (MỚI) — ẩn mọi đề không qua `Questions::Validator`. **Ẩn chứ
  không xoá**: `session_answers` trỏ tới câu đó (`restrict_with_error`) và BR-16 yêu cầu lượt
  cũ giữ nguyên điểm. Chạy trên dev: ẩn 11 đề, còn 6 đề hợp lệ

**Lỗi 2: nút xoá tài khoản ở trang admin CHƯA BAO GIỜ hỏi xác nhận.** Nó khai
`data-turbo-confirm`, nhưng **Turbo không hề được nạp ở app này** — không có
`config/importmap.rb`, không có `app/javascript`, layout không gọi
`javascript_importmap_tags`. Nút xoá tài khoản (kèm CASCADE toàn bộ lượt chơi) chạy ngay khi
bấm.

- `app/views/shared/_dialog.html.erb` (MỚI) — modal dùng chung, nạp ở layout.
  `window.appDialog.alert/confirm/prompt`, cả ba trả Promise. Dựng trên thẻ `<dialog>` +
  `showModal()` để có focus trap + Esc + inert phần còn lại của trang mà không tự cài
- Nút đồng ý của hành động phá huỷ dùng `.btn--danger` và đứng **SAU** nút huỷ trong DOM
  (CSS `flex-direction: row-reverse` đưa nó sang phải), nên Enter trong form không kích hoạt
  hành động phá huỷ
- Handler `submit` đọc `data-confirm` trên form → dùng cho nút phá huỷ dạng `button_to`
  (xoá tài khoản, ẩn câu hỏi). `spec/requests/dialog_spec.rb` chặn việc `data-turbo-confirm`
  quay lại
- Thay hết `alert`/`confirm`/`prompt` của trình duyệt trong `games/show.html.erb`


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

### Chọn ngôn ngữ lập trình cho Bug Hunt (BR-35)
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

### Phase 3 — AI/Gemini
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

### Giao diện — đổi bảng màu nền + item JRPG
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

### Cấu hình môi trường Gemini (đã xong)
- `dotenv-rails` đã duyệt và thêm, **chỉ ở group `:development`**. Cố ý không có ở test:
  nếu test env nạp `.env` thì rspec gọi Gemini THẬT, đốt hạn mức và làm test phụ thuộc
  mạng. Đã gặp thật — 1 test fail vì lý do đó, phải sửa sang stub `Gemini::Client`
- `.env` (gitignored qua `/.env*`) chứa `GEMINI_API_KEY` + `GEMINI_MODEL`
- **Key hiện tại đã bị dán vào chat log → nên rotate ở AI Studio**

### Ngân hàng đề hiện có (số liệu TRƯỚC v1.19 — Spec Detective đã đổi format)

> Từ v1.19, đề Spec Detective format cũ đã bị `rake questions:hide_invalid` ẩn. Số câu khả
> dụng thật của game đó = số đề format mới. Các game khác không đổi.
| Game | Tổng | manual | ai_generated |
|---|---|---|---|
| bug_hunt | 45 | 40 | 5 (java) |
| spec_detective | 11 | 6 | 5 |
| estimate_poker | 17 | 12 | 5 |
| incident_escape_room | 7 | 3 | 4 |
| prod_roulette | 3 | 3 | 0 |

Bug Hunt theo ngôn ngữ: java 15 / javascript 10 / php 10 / ruby 10 — cả 4 đều playable.
File YAML đã sinh nằm ở `db/question_banks/<game>/2026-08-19*.yml`, import lại được
(idempotent theo checksum).

Chất lượng đề AI đã soát: bug_hunt 4/5 câu `buggy_line` chỉ đúng chỗ; câu thiếu
`@Transactional` chỉ vào dòng signature trong khi bộ đề tay đánh dòng `save` đầu tiên —
người chơi dễ click lệch. escape_room đủ 8 node đúng `steps_per_session`, không option_key
nào thiếu effect.

### Hạ tầng đã chốt: Render Hobby + cache Redis (spec v1.10)
- **Q5 đóng**: app chạy trên **Render, gói Hobby** → log giữ **7 ngày**
  (`PagesController::LOG_RETENTION_DAYS`, đổi gói thì sửa hằng số đó). Render retention theo
  gói: Hobby 7 / Pro 14 / Scale-Enterprise 30 ngày; quá hạn là mất hẳn, nâng gói không lấy lại
- **Render KHÔNG có managed MySQL** — chỉ Postgres và Key Value (Redis). DB buộc phải dùng dịch
  vụ ngoài
- Gem `redis` đã duyệt. `production.rb` dùng `:redis_cache_store` khi có `REDIS_URL`, không có
  thì vẫn boot bằng file store nhưng log cảnh báo. **BẮT BUỘC phải có Redis trên Render**:
  filesystem của Render là ephemeral + per-instance nên file store làm rack_attack (throttle
  1 lượt/ngày Spec Detective) và `Gemini::CircuitBreaker` mất trạng thái mỗi lần deploy, mà gói
  Hobby còn tự ngủ khi hết traffic → throttle gần như vô hiệu
- Verify: có `REDIS_URL` → `cache_store = :redis_cache_store` và
  `Rack::Attack.cache.store = RedisCacheStoreProxy`; không có → file store + cảnh báo
- **BẪY đã gặp**: bản đầu tôi gọi `Rails.logger.warn` ngay trong `production.rb` → `Rails.logger`
  lúc đó còn `nil` nên **production không boot được**. Phải hoãn vào `config.after_initialize`.
  Lỗi này chỉ lộ ở lần deploy đầu nếu không test bằng `RAILS_ENV=production`
- `Gemini::DailyBudget` không bị ảnh hưởng vì đếm `ai_gradings` từ DB, không dùng cache

### DB production: Aiven for MySQL free (Q10 đã đóng, spec v1.11)
- **Giữ MySQL, KHÔNG chuyển Postgres.** Neon bị loại vì là PostgreSQL only. Tiêu chí chọn là
  phải **thực thi FK thật** — 7 bảng dựa vào FK `CASCADE`/`RESTRICT`, và BR-38 đã hứa với người
  dùng là xoá tài khoản sẽ xoá luôn dữ liệu chấm AI; lời hứa đó thực thi bằng FK cascade chứ
  không bằng code. TiDB Cloud bị loại vì FK chỉ GA từ TiDB v8.5.0 và chưa xác nhận được TiDB
  Cloud Serverless có thực thi FK. PlanetScale bỏ free tier từ 04/2024
- Gói free Aiven: 1GB RAM / 1GB disk / 1 CPU, `max_connections` 76, có backup, không cần thẻ.
  Đủ rộng vì `ai_gradings` (nguồn phình nhanh nhất) bị hạn mức Gemini 20 request/ngày chặn sẵn —
  ~2.4KB/dòng, tức ~17MB/năm
- **Hai bẫy của gói free**: service bị tắt nếu không hoạt động (cộng Render Hobby cũng tự ngủ →
  request đầu sau khi ngủ có thể chậm/lỗi), và không có SLA/support
- `config/database.yml` production đã khai TLS: có `DB_SSL_CA` → `ssl_mode: verify_identity`,
  không có → tự hạ `required` (vẫn mã hoá, KHÔNG xác thực server). Aiven đặt SSL ENABLED và
  không tắt được. `DB_SSL_MODE` ghi đè thủ công được
- **BẪY: KHÔNG dùng service URI của Aiven làm `DATABASE_URL`.** URI của họ bắt đầu bằng
  `mysql://`, Rails suy ra adapter từ scheme nên sẽ tìm adapter `mysql` (không tồn tại) thay vì
  `mysql2`. Dùng các biến `DB_*` rời, hoặc tự đổi scheme thành `mysql2://`
- **CHƯA verify**: version MySQL của Aiven. Kiểm trong console khi tạo service — §19 cần
  ≥ 8.0.16 để CHECK constraint được thực thi. Validation tầng model vẫn chặn nên không vỡ
- Trong `database.yml` cố ý dùng Ruby thuần (`.to_s.empty?`) chứ không dùng `present?` của
  ActiveSupport: file này còn bị công cụ không nạp Rails đọc, và bản đầu dùng `present?` đã nổ
  ngay khi test bằng ERB thuần

### Kênh liên hệ xoá tài khoản (Q8 đã đóng)
`PRIVACY_CONTACT_EMAIL=hoangnm.nta@gmail.com`. Owner đã được nêu rõ và chấp nhận rủi ro: đây là
email cá nhân trên trang guest đọc được nên bot quét email sẽ thấy. Đổi sang mailbox dùng chung
thì chỉ cần đổi biến môi trường.

### Trang chính sách riêng tư — BR-38 (spec v1.9)
- `GET /privacy` → `PagesController#privacy`, **guest đọc được** (phải đọc được trước khi
  đăng ký). Link ở footer mọi trang + ở trang đăng ký
- Nội dung viết theo THỰC TẾ CODE, không theo spec. Quá trình viết bắt được 1 chỗ spec sai:
  §14 ghi "logs rotate at 30 days" nhưng `production.rb` log ra **STDOUT** và app không có
  cấu hình rotation nào → thời gian lưu do nền tảng vận hành quyết định (Q5 chưa chốt).
  Đã sửa §14 và trang chính sách KHÔNG nêu con số
- Bắt được thêm 1 điểm chưa có ở đâu trong spec: CSS `@import` font từ **Google Fonts**
  (`application.css:11`) nên mỗi lần tải trang là Google nhận IP + User-Agent người dùng.
  Đã công bố trên trang
- Cảnh báo "không dán nội dung nội bộ/khách hàng" ở **hai chỗ**: panel intro của Spec
  Detective và ngay trên ô textarea (người chơi đã cuộn qua panel intro rồi)
- Kênh liên hệ xoá tài khoản đọc từ `PRIVACY_CONTACT_EMAIL` (Q8 chưa chốt). Chưa set thì
  trang nói thẳng "chưa công bố kênh liên hệ" — **không bịa địa chỉ**. Đã thêm vào
  `.env.example`
- Spec `privacy_spec.rb` dùng `body_text` (nén khoảng trắng) vì ERB ngắt dòng làm chuỗi bị
  tách — assert trên `response.body` thô rất giòn, đã gặp thật

### ⛔ ĐÃ XOÁ Ở v1.19 — Trần hạn mức Gemini toàn hệ thống, BR-37 (spec v1.8)

> `Gemini::DailyBudget`, BR-37, `503 AI_QUOTA_EXHAUSTED` và cổng chặn trong `Creator` đều đã
> bị xoá: Spec Detective không còn gọi AI lúc chơi nên không còn gì để bound. Giữ mục dưới
> đây làm lịch sử quyết định — **đừng hồi sinh** trừ khi đưa AI trở lại đường chơi.
- `app/services/gemini/daily_budget.rb`: giới hạn 20 request trong **cửa sổ TRƯỢT 24 giờ**,
  đếm số dòng `ai_gradings` (BR-19 bảo đảm mọi lời gọi có 1 dòng, **kể cả lời gọi thất bại** —
  mà lần thất bại vẫn tiêu hạn mức Google). Một lượt tiêu `steps_per_session` request, làm
  tròn XUỐNG nên không ai vào lượt rồi giữa đường hết hạn mức
- Vì sao cửa sổ trượt: không biết Google chốt ngày theo múi giờ nào; cửa sổ trượt luôn chặt
  hơn hoặc bằng mọi cửa sổ ngày cố định
- Vì sao đếm `ai_gradings` chứ không dùng `Rails.cache` như circuit breaker: cache là
  per-host, DB thì mọi host cùng thấy một con số
- `GameSessions::Creator#ensure_ai_budget!` chặn **TRƯỚC** khi tạo bản ghi → `503`
  `AI_QUOTA_EXHAUSTED`, không tạo `game_sessions` row nên người chơi không mất lượt vì trần
  của hệ thống
- UI: trang game hiện "hôm nay còn N lượt", hết thì disable nút + thông báo; card ở `/games`
  có badge "Hết hạn mức hôm nay". Đã xoá đoạn text cũ nói "Phase 3 chưa chơi được"
- **Thứ tự 2 lớp chặn**: rack_attack là middleware nên chạy TRƯỚC controller. Người đã dùng
  lượt của mình → `429`; người chưa dùng mà hệ thống hết hạn mức → `503 AI_QUOTA_EXHAUSTED`.
  Verify thật cả hai đường bằng 2 user khác nhau
- **HẠN CHẾ đã biết**: `rake questions:generate` không ghi `ai_gradings` nên request sinh đề
  KHÔNG được tính vào budget. Task tự in phần đã dùng cho chấm điểm và cảnh báo nếu lô sắp
  vượt, nhưng không trừ được. Cố ý không abort

### ⛔ ĐÃ XOÁ Ở v1.19 — Rate limit Spec Detective 1 lượt/ngày/user (spec v1.7)

> Throttle `sessions/spec_detective/user` đã bị xoá khỏi `rack_attack.rb`. Con số 1 lượt/ngày
> do hạn mức Gemini quyết định, không do thiết kế gameplay — hết lời gọi AI thì hết lý do.
> Giữ mục dưới đây làm lịch sử quyết định.
- `config/initializers/rack_attack.rb`: `sessions/spec_detective/user` từ 5 lượt/giờ →
  **1 lượt/ngày**. Verify thật: lần 1 → 201, lần 2 và 3 → 429, bug_hunt không bị ảnh hưởng
- Thông điệp 429 giờ tra theo `rack.attack.matched` (hằng `THROTTLE_MESSAGES`) thay vì dùng
  chung một câu. Lý do: "Bạn thao tác quá nhanh" đúng với hạn mức theo phút/giờ nhưng SAI với
  hạn mức theo ngày — người chơi sẽ retry cả ngày vô ích
- **Sửa initializer phải RESTART server**, `config/initializers/*` không reload theo code

### `render.yaml` — hạ tầng Render khai trong repo
Web service (runtime docker, `healthCheckPath: /up`) + Key Value gói free, cùng region.
`REDIS_URL` nối tự động bằng `fromService: {type: keyvalue, property: connectionString}` — bỏ được
bước copy tay dễ quên nhất. Không có bí mật nào trong file: 7 biến `sync: false` để Render hỏi lúc
tạo blueprint.

`region: oregon` ở cả hai service — khớp service Aiven ở **bờ Tây Mỹ (San Francisco)**, owner xác
nhận 2026-08-19. Region phải khớp Aiven chứ KHÔNG khớp vị trí người chơi: đã đo bấm "Bắt đầu lượt"
Bug Hunt sinh **11 query** (trang chủ và /games chỉ 2), còn latency VN→Aiven đo được ~190ms. Đặt
Render ở singapore thì một lần bấm nút mất ~2,1 giây chỉ để chờ DB. Muốn tối ưu cho người chơi VN
thì phải chuyển CẢ HAI sang châu Á, chuyển riêng Render là chậm đi.

Không xác định được region Aiven từ ngoài: hostname là `skill-arcade-1`, IP `134.199.233.131`
(DigitalOcean) không có PTR, `@@hostname`/timezone không mang thông tin region. Chỉ suy được "không
ở châu Á" từ latency 190ms — phải đọc trên console.

`plan: free` ở cả hai; Render từ chối thì nâng `starter`.

**Cron job cho BR-24 cố ý KHÔNG nằm trong file**: Render tính phí cron theo phút, không có gói
free, đưa vào là apply blueprint phát sinh tiền. Đã rà tác động của việc thiếu scheduler — nhỏ hơn
tưởng: leaderboard chỉ đếm lượt `finished` (BR-08) nên không ảnh hưởng; rack_attack đếm request
chứ không đếm bản ghi lượt; `GameSessions::Creator` không kiểm lượt `in_progress` đang mở nên lượt
treo không chặn ai chơi. Mất thật sự chỉ là độ chính xác `abandoned_reason` cho thống kê.

### ✅ Docker image đã build và chạy thật với DB Aiven (2026-08-19)
`docker build` xanh (`DOCKER_BUILD_EXIT=0`, image 934MB), rồi `docker run` với env Aiven:
```
/up      -> 200
/privacy -> 200, hiện "Log ứng dụng giữ 7 ngày"
/        -> 200 (guest)
db:preflight TỪ TRONG container:
  OK MySQL version    8.4.8
  OK TLS              verify_identity, sslca=/rails/config/aiven-ca.pem
  OK CHECK constraint DB chặn score = 999
  OK max_connections  76
0 dòng cảnh báo về DB_SSL_CA  → CA commit trong repo hoạt động đúng trong image
```
Đã xoá container, image và file env tạm sau khi verify.

**Hai điểm "chưa verify" trước đây giờ đã xác nhận:**
- **Thruster CÓ bind `0.0.0.0`**: request từ ngoài container vào qua port map `3001:10000` đi tới
  được, `remote_addr` là `172.17.0.1`. Nên `HTTP_PORT=10000` trong `render.yaml` là đủ, không cần
  phương án dự phòng bỏ Thruster
- Puma log `Listening on http://0.0.0.0:3000` — đúng như README thruster nói, nó ghi đè `PORT`
  thành `TARGET_PORT` (3000) cho Puma còn tự listen ở `HTTP_PORT`

Ghi chú không phải lỗi: log build có
`Bundler 4.0.10 is running, but your lockfile was generated with 4.0.14. Installing Bundler
4.0.14 and restarting` — bundler tự cài đúng version, chỉ tốn thêm thời gian build.

### BẪY đã làm fail deploy thật: Gemfile.lock thiếu platform Linux
`Gemfile.lock` sinh trên Windows chỉ có `PLATFORMS: x64-mingw-ucrt`. `Dockerfile` đặt
`BUNDLE_DEPLOYMENT="1"` nên bundler frozen, không tự thêm platform được → `bundle install` trong
image Linux dừng với **exit code 16** = `Bundler::ProductionError`.

Sửa: `ruby -S bundle lock --add-platform x86_64-linux`

**CI KHÔNG bắt được**: `ruby/setup-ruby` với `bundler-cache: true` không bật deployment mode nên nó
lặng lẽ thêm platform vào lock của runner rồi chạy tiếp — CI xanh mà Docker build đỏ. Đã thêm
`spec/gemfile_lock_spec.rb` làm guard, và đã kiểm guard đó thật sự đỏ khi bỏ dòng platform.

**Mỗi lần `bundle install`/`bundle update` trên Windows đều có thể làm mất dòng đó.** Docker build
fail ở bước `bundle install` thì kiểm chỗ này trước tiên.

### BẪY 3: Missing secret_key_base — RAILS_MASTER_KEY chưa set trên Render
```
ArgumentError: Missing `secret_key_base` for 'production' environment
Tasks: TOP => db:prepare => db:load_config => environment
```
Rails không giải mã được `credentials.yml.enc` nên không lấy được `secret_key_base`, dừng ngay lúc
nạp environment — TRƯỚC cả khi thử nối DB, nên lỗi này **che mất mọi biến thiếu khác**.

Nguyên nhân hệ thống, đã verify từ docs Render: **Render chỉ hỏi biến `sync: false` ở LẦN TẠO
BLUEPRINT ĐẦU TIÊN**; khi cập nhật blueprint sau đó nó BỎ QUA những biến đó. Bỏ qua prompt nào ở
lần đầu thì phải set tay trong dashboard, không bao giờ được hỏi lại.

`render.yaml` không sai: `sync: false` KHÔNG cần kèm `value` (đã verify docs).

Đã kiểm: `credentials.yml.enc` chỉ chứa duy nhất `secret_key_base` (128 ký tự), và
`config/master.key` là 32 hex sạch, không newline. Nên có 2 cách sửa tương đương:
`RAILS_MASTER_KEY` (Rails-native, giữ credentials dùng được cho secret sau này) hoặc
`SECRET_KEY_BASE` (Rails đọc ENV này TRƯỚC credentials, bỏ qua hẳn chuỗi master-key).

Lời khuyên cho lần sau: sửa thì kiểm **cả 7 biến `sync: false`** trong một lần, đừng sửa từng cái
rồi deploy lại — vì lỗi environment che mất các biến thiếu phía sau.

### BẪY 2: Dockerfile thiếu header dev của MySQL client
Ngay sau khi sửa platform thì build fail tiếp, cùng bước `bundle install` nhưng **exit code 5**:
`checking for -lmysqlclient... no` → gem `mysql2` không compile được.

`Dockerfile` do `rails new` sinh chỉ cài `build-essential git libvips libyaml-dev pkg-config` ở
build stage. Đã thêm **`default-libmysqlclient-dev`**.

Đừng lẫn hai gói: `default-libmysqlclient-dev` là **header dev** để COMPILE (build stage), còn
`default-mysql-client` ở base stage là **CLI** và kéo theo `libmariadb3` cần lúc CHẠY. Có cái sau
mà thiếu cái trước thì build fail.

**Cách kiểm rẻ**: `docker build -t skill-arcade:preflight .` tại máy — cả hai bẫy lộ ra trong ~1
phút thay vì phải đợi Render build. NHỚ đọc exit code của chính `docker build`, không phải của lệnh
bọc ngoài: tôi đã một lần tưởng build xong vì đọc exit code của `tail` đứng sau nó.

### CA của Aiven commit trong repo — KHÔNG dùng Render Secret File
`config/aiven-ca.pem`, `render.yaml` khai `DB_SSL_CA=/rails/config/aiven-ca.pem`. File có trong
image vì `Dockerfile` có `WORKDIR /rails` + `COPY . .` và `.dockerignore` không loại trừ nó
(chỉ chặn `/.env*`, `/config/master.key`, `/config/credentials/*.key`).

**Tôi đã ghi sai ở mấy lượt trước rằng thiếu file CA thì tự hạ xuống `required`.** Test thật cả
hai đường thiếu, cả hai đều KHÔNG kết nối được:
- `sslca` trỏ file không tồn tại → `TLS/SSL error: failed to open file`
- bỏ hẳn `sslca`, chỉ `ssl_mode: required` → `Server certificate validation failed …
  CERT_E_UNTRUSTEDROOT`, vì CA riêng của Aiven không nằm trong trust store của OS

Nên file CA là BẮT BUỘC. Kéo theo: Render Secret File không dùng được thuận lợi vì nó chỉ thêm
được SAU khi service tồn tại, mà service không boot nổi khi thiếu CA → lần deploy đầu chắc chắn
fail. Secret File cũng là per-service nên cron job sau này phải thêm lại.

CA là self-signed Project CA, không chứa private key, **hạn 16/08/2036** — commit an toàn.
Tải lại từ console thì file tên mặc định `ca.pem`, phải đổi thành `config/aiven-ca.pem`.

### ✅ DB production Aiven ĐÃ provision xong (2026-08-19)
`avnadmin@skill-arcade-skill-arcade.k.aivencloud.com:11695/defaultdb`

Số đo thật từ `db:preflight` trên Aiven:
```
OK   MySQL version     8.4.8                    → đạt yêu cầu >= 8.0.16 của §19
OK   TLS               TLS_AES_256_GCM_SHA384   → ssl_mode=verify_identity, CÓ xác thực server
OK   CHECK constraint  DB chặn score = 999      → BR-04 có lưới ở tầng DB
OK   max_connections   76                        → khớp đúng tài liệu gói free Aiven
```

Đã nạp: 9 bảng, 5 game, admin (`admin? true`, mật khẩu từ `.env.aiven` authenticate được),
**83 câu hỏi** (64 manual + 19 ai_generated). Cả 5 game đều đủ câu để chơi; Bug Hunt có đủ 4 ngôn
ngữ `["java","javascript","php","ruby"]`.

Lưu ý: `db:prepare` KHÔNG chạy `db/seeds/sample_questions.rb` — phải nạp riêng, đã làm.

CA cert của Aiven tải về tên mặc định `ca.pem`, đã đổi thành `tmp/aiven-ca.pem` cho khớp
`.env.aiven` và tên Secret File khai trong `render.yaml`.

### Sửa lại mô tả điều kiện seed — trước đó tôi ghi chưa chính xác
`prepare_all` seed khi `initialize_database` trả true, mà hàm đó trả
`!database_already_initialized` với `database_already_initialized` = **bảng `schema_migrations` có
tồn tại hay không**. Nên điều kiện đúng là **DB chưa có schema**, KHÔNG phải "DB vừa được tạo" —
một DB đã tồn tại mà còn trống (đúng trường hợp `defaultdb` Aiven tạo sẵn) vẫn bị seed. Đã sửa ở
`db/seeds.rb`, runbook và spec §12.

### `script/aiven.ps1` — chạy preflight/prepare lên Aiven không cần gõ mật khẩu
Đọc `.env.aiven` (gitignored qua `/.env*`), set biến, rồi chạy task. `.env.aiven.example` là
template — phải thêm ngoại lệ `!/.env.aiven.example` vào `.gitignore` vì `/.env*` chặn cả nó.
- không cờ → chỉ `db:preflight`, KHÔNG ghi gì lên DB
- `-Prepare` → `db:prepare` (GHI lên production) rồi tự `db:preflight` lại. Bắt buộc có
  `ADMIN_PASSWORD` mới cho chạy, vì `db:prepare` chỉ tự seed đúng một lần
- `-Command "<lệnh rails>"` → chạy lệnh rails tuỳ ý lên Aiven, vd
  `-Command "runner db/seeds/sample_questions.rb"` hoặc `-Command "questions:import[file]"`.
  Dùng cái này thay vì tự export biến ở shell để mật khẩu không vào history
- Cố ý KHÔNG in `DB_PASSWORD` ra output

Đã test end-to-end bằng một DB nháp trên máy (không dùng Aiven, không dùng DB dev): tạo DB → seed
5 game + admin → preflight all OK. Đã xoá DB nháp và file `.env.aiven` test.

**BẪY MÔI TRƯỜNG — Windows PowerShell 5.1 đọc `.ps1` theo ANSI nếu file không có BOM UTF-8.**
Bản đầu tôi ghi file không BOM → tiếng Việt bị mangle thành ký tự `'` làm vỡ cú pháp string,
PowerShell báo `TerminatorExpectedAtEndOfString`. Phải ghi bằng `utf-8-sig`. Ghi chú này đã để ở
dòng đầu chính file `.ps1`. Ngoài ra cần
`[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` để output tiếng Việt không ra ký tự lạ.

### `rake db:preflight` — đo DB thật thay vì suy từ số version
`lib/tasks/db_checks.rake`. Chạy được cả từ máy local (trỏ biến `DB_*` vào Aiven) và từ Render.
Kiểm 4 thứ: MySQL version >= 8.0.16, **TLS bằng `Ssl_cipher` của chính phiên đang kết nối** (config
khai đúng mà server không bật thì vẫn ra kết nối trần — cách này bắt được), **CHECK constraint bằng
cách thử `update_column(:score, 999)`** để bỏ qua validation model, và `max_connections` so với pool.
Abort nếu không đạt.

An toàn trên production: phép thử CHECK nằm trong transaction và luôn `raise ActiveRecord::Rollback`.
Đã verify không để lại bản ghi (chỉ tốn vài giá trị auto-increment, MySQL không trả lại).

Chạy trên DB dev: MySQL 8.4.11 / TLS `TLS_AES_256_GCM_SHA384` / CHECK chặn được / max_conn 151.

Đã bổ sung 2 đường lỗi cho đúng mục đích dùng (task này thường chạy đầu tiên lên một DB mới):
- DB chưa có schema → CHECK constraint ra `SKIP` chứ không ném `StatementInvalid`. Bản đầu tôi
  viết `Game.first` trực tiếp nên nó nổ trên DB trống — đúng tình huống Aiven mới tạo
- Không nối được / sai mật khẩu / DB không tồn tại → thông báo tiếng người kèm host, thay vì
  backtrace Ruby

### Runbook deploy: `docs/deploy/render-aiven.md`
Đã viết đầy đủ, mọi con số verify từ docs chính thức hoặc từ code. Ba điểm quan trọng nhất:
- **Thứ tự bắt buộc: Aiven TRƯỚC, Render sau.** `bin/docker-entrypoint` chạy `db:prepare` lúc
  container boot nên không có DB là fail ngay lúc boot
- **`HTTP_PORT=10000`** là chỗ dễ fail nhất. Render cần app listen `0.0.0.0` tại `PORT`
  (mặc định 10000), nhưng `thruster` listen ở `HTTP_PORT` (mặc định 80) và còn **tự ghi đè
  `PORT`** thành `TARGET_PORT` (3000) cho Puma. Verify từ README gem thruster 0.1.25
- **Render KHÔNG tự tiêm biến cho Key Value** (docs xác nhận) — phải tự copy Internal URL đặt
  thành `REDIS_URL`. Trước đó tôi nói sai là "tự có khi link"
- Secret File của Render mount tại `/etc/secrets/<tên file>` → khớp default `DB_SSL_CA` trong
  `.env.example`

### Mật khẩu admin chuyển sang ENV — ĐẢO quyết định cũ (spec v1.12)
Owner trước đây chọn hardcode `12345678` (clarify muc 2.4, spec §12). **Đảo ngày 2026-08-19** sau
khi phát hiện đường lộ cụ thể: `bin/docker-entrypoint` chạy `db:prepare`, và
`DatabaseTasks.prepare_all` có `seed = true if database_initialized && db_config.seeds?` → lần
boot đầu trên DB trống sẽ tự chạy `db/seeds.rb`, tạo admin với mật khẩu đã biết trên URL public.
App không có chức năng đổi mật khẩu nên không sửa được sau.

`db/seeds.rb` giờ đọc `ENV["ADMIN_PASSWORD"]`:
- development/test không set → vẫn `12345678`, quy trình local không đổi
- **production không set → BỎ QUA tạo admin**, KHÔNG abort. Lý do quan trọng: `db:prepare` chỉ
  seed đúng một lần lúc DB vừa tạo, nên abort giữa seed sẽ để lại DB có schema mà **không có bản
  ghi `games`** → app hỏng hẳn và lần deploy sau cũng không seed lại. Bỏ qua thì 5 game vẫn có,
  app chạy được, chỉ cần set biến rồi `rails db:seed` lại (seed idempotent)

Verify thật bằng `RAILS_ENV=production` trên một DB nháp rồi xoá đi:
```
khong co bien -> 5 game duoc tao + "admin: BỎ QUA — ADMIN_PASSWORD chưa được set ở production."
co bien       -> admin tao voi mat khau do; authenticate('12345678') = false
dev           -> van dung 12345678 (da tra lai sau khi test)
```

## Việc tiếp theo
**Chỉ còn Q6 (KPI) là Open Question. Phần còn lại là việc thao tác.**

### 🔴 Gấp — production đang lỗi sau khi deploy v2.0
`render.yaml` không khai `autoDeploy` nên Render mặc định tự deploy khi push `main`. Code mới
đã lên nhưng đề Spec Detective trong DB Aiven vẫn format cũ → người chơi nhận "Không bắt đầu
được lượt chơi" (đã reproduce trên dev: 6/8 lượt).

Chạy từ máy dev với biến `DB_*` trỏ Aiven (dùng `script/aiven.ps1`), theo thứ tự:
```
bin/rails questions:hide_invalid              # ẩn ngay đề format cũ — production hết lỗi
bin/rails questions:convert_spec_detective    # chuyển đề cũ sang format mới (cần GEMINI_API_KEY)
bin/rails runner db/seeds/sample_questions.rb # nếu sau khi ẩn còn < 5 đề khả dụng
```
`hide_invalid` in cảnh báo nếu game nào còn dưới `questions_per_session` đề.

### 🟡 Job hằng ngày chưa chạy được
1. **Kiểm Aiven allowlist TRƯỚC** — Aiven console → service → Allowed IP addresses. IP của
   GitHub runner là động: có allowlist thì workflow không nối được DB, phải chuyển sang Render
   Cron Job (cách làm ở `docs/deploy/render-aiven.md` mục 5)
2. Set 7 secrets ở GitHub → Settings → Secrets and variables → Actions:
   `RAILS_MASTER_KEY`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`,
   `GEMINI_API_KEY`
3. Chạy thử bằng `workflow_dispatch` trước, đừng để lần chạy đầu là lần theo lịch lúc 2h sáng
4. Quyết định về bước cuối của workflow: nó `git push` file YAML về `main` (cần
   `permissions: contents: write`). Không muốn job tự push thì xoá step đó và hạ xuống
   `contents: read` — chỉ mất git history của đề

### 🟡 CI không chạy cho commit nào trên `main`
`.github/workflows/ci.yml` trigger `push: branches: [master]` nhưng default branch là `main`.
Commit `v2.0` **không có CI gate nào**. Sửa 1 dòng thành `[ main ]`. Lỗi có sẵn từ trước, nhưng
giờ nó che mất đúng lúc cần nhất.

### Việc còn lại từ session trước
- **Rotate `GEMINI_API_KEY`** — key hiện tại nằm trong chat log của session 2026-08-19
- Sinh tiếp ngân hàng đề cho đủ §6. Từ v1.19 cả 20 request/ngày dùng được cho sinh đề (không
  còn tranh với người chơi), và `questions:refill` tự làm dần mỗi ngày khi job chạy được
- Cân nhắc sửa prompt Bug Hunt: nói rõ với bug "thiếu transaction" thì `buggy_line` trỏ vào
  dòng ghi DB đầu tiên, để khớp quy ước của bộ đề viết tay


## Ghi chú quan trọng

### Bẫy khi thêm câu Bug Hunt vào `db/seeds/sample_questions.rb`
`bug_types` trong `content` sinh từ chính `BUG_HUNT_SAMPLES.map { bug_type }.uniq`, và
checksum = SHA-256 của `content`. Nên thêm **một bug_type mới** sẽ đổi checksum của TOÀN
BỘ câu cũ → `upsert_question` không tìm thấy bản ghi cũ và tạo bản ghi TRÙNG thay vì cập
nhật. Thêm câu mới thì dùng lại 12 bug_type đã có, hoặc phải xử lý câu cũ trước.

### Ngân hàng Bug Hunt hiện chỉ đủ mức tối thiểu
php/ruby/javascript đúng 10 câu = `questions_per_session` (java 15 sau khi import đề AI). Chơi lại cùng ngôn ngữ sẽ gặp lại
toàn bộ 10 câu (BR-32 buộc phải fallback sang câu đã trả lời đúng). Muốn có câu mới ở
lượt sau thì cần thêm ít nhất 2-3 câu mỗi ngôn ngữ.

### Bẫy môi trường đã gặp — nhớ để khỏi mất thời gian lại
- **Turbo/Stimulus KHÔNG được nạp** dù có gem trong `Gemfile`: không có `config/importmap.rb`,
  không có `app/javascript`, layout không gọi `javascript_importmap_tags`. Nên MỌI thứ dựa vào
  Turbo là code chết — `data-turbo-confirm`, `data-turbo-method`, turbo frame/stream. Đã làm nút
  xoá tài khoản không hỏi xác nhận suốt nhiều version mà không ai thấy, vì nó "trông đúng"
- **Đừng gộp lời gọi API và việc dựng giao diện vào cùng một `try`.** Lỗi render sẽ hiện ra dưới
  thông điệp lỗi API và che mất nguyên nhân thật — mất khá lâu mới tìm ra vì mọi dấu hiệu đều
  trỏ về server, trong khi server trả 200
- **Script verify chạy bằng `bin/rails runner` với `RAILS_ENV=test` làm BẨN test DB.** Bản ghi
  không nằm trong transaction của rspec nên còn lại và làm fail các test đếm bản ghi
  (`Question.count` ra 65). Dọn bằng `RAILS_ENV=test bin/rails db:test:prepare`

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
