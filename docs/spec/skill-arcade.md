# Skill Arcade — Specification

## 1. Tổng quan (Overview)

- **Mục đích**: Web app luyện tập năng lực dev/BA qua 5 mini-game ngắn, có tài khoản, tích điểm và bảng xếp hạng. Thay việc đọc tài liệu/rule bằng luyện tập lặp lại có phản hồi tức thì.
- **Actor**: Người chơi (member), Quản trị viên (admin), System (rake task sinh đề)
- **Priority**: High
- **Phase**: Phase 1 — cả 5 game, chưa có phần thưởng vật chất
- **Ngày soạn**: 2026-08-18
- **Version**: 1.18 (sửa 2 lỗi làm fail Docker build; image đã build và chạy thật với DB Aiven)
- **Input**: `docs/clarify/clarify_skill-arcade.md` (5 vòng clarify, đã đóng toàn bộ BLOCKER)

## 2. User Story

> As a **dev/BA của NTA**, I want to **luyện code review, đặt câu hỏi làm rõ spec, xử lý incident và ước lượng task qua các mini-game ngắn có chấm điểm**, so that **tôi cải thiện được những kỹ năng này mà không cần chờ tình huống thật xảy ra, và thấy được mình đang ở đâu so với đồng nghiệp**.

Phụ:

> As an **admin**, I want to **xoá tài khoản vi phạm và ẩn câu hỏi bị báo sai**, so that **nội dung và bảng xếp hạng giữ được độ tin cậy**.

## 3. Actors & Permissions

| Actor | Quyền | Điều kiện |
|---|---|---|
| Guest | read: trang đăng ký/đăng nhập, xem leaderboard công khai | Không cần đăng nhập |
| Member | create: game_session, session_answer, question_report; read: câu hỏi (không kèm đáp án), điểm và lịch sử của chính mình, leaderboard | Đã đăng nhập, tài khoản không bị khoá |
| Admin | Toàn bộ quyền của Member + delete: user; update: question.hidden; read: question_report, ai_grading | `users.admin = true` |
| System (rake task) | create: question; read: game | Chạy từ CLI, không qua HTTP |

**Ngoài scope**: người dùng **không** tự xoá được tài khoản của mình; không có role trung gian (moderator).

## 4. Entity Schema

### 4.1 Entities bị ảnh hưởng

| Entity | Thao tác | Ghi chú |
|---|---|---|
| `users` | CREATE / READ / UPDATE / DELETE | New table |
| `games` | READ | New table, seed 5 bản ghi cố định |
| `questions` | CREATE (rake) / READ / UPDATE (hidden) | New table |
| `game_sessions` | CREATE / READ / UPDATE | New table — nguồn dữ liệu duy nhất cho mọi bảng xếp hạng |
| `session_answers` | CREATE / READ | New table |
| `ai_gradings` | CREATE / READ | New table — log bắt buộc, không xoá |
| `question_reports` | CREATE / READ / UPDATE | New table |

Toàn bộ là bảng mới — repo greenfield, không có schema hiện hữu để tái sử dụng.

### 4.2 Schema chi tiết

**`users`** (new)

| Column | Type | Nullable | Default | Constraint | Description |
|---|---|---|---|---|---|
| id | bigint unsigned | NO | auto_increment | PK | |
| email | varchar(255) | NO | | UNIQUE | Chỉ chấp nhận pattern allowlist |
| password_digest | varchar(255) | NO | | | bcrypt via `has_secure_password` |
| display_name | varchar(50) | NO | | UNIQUE | Tên hiển thị trên leaderboard — unique để hai người chơi không bị nhầm nhau trên bảng xếp hạng |
| admin | boolean | NO | false | | |
| failed_login_count | int unsigned | NO | 0 | | Reset về 0 khi đăng nhập thành công |
| locked_until | datetime | YES | NULL | | Khoá tạm sau khi sai mật khẩu nhiều lần |
| created_at | datetime | NO | | | |
| updated_at | datetime | NO | | | |

Indexes:
- `index_users_on_email` UNIQUE on `(email)` — tra cứu lúc đăng nhập, chống trùng
- `index_users_on_display_name` UNIQUE on `(display_name)` — chống trùng tên hiển thị

**`games`** (new, seed 5 bản ghi, không cho tạo qua UI)

| Column | Type | Nullable | Default | Constraint | Description |
|---|---|---|---|---|---|
| id | bigint unsigned | NO | auto_increment | PK | |
| slug | varchar(50) | NO | | UNIQUE | `bug_hunt`, `spec_detective`, `incident_escape_room`, `estimate_poker`, `prod_roulette` |
| name | varchar(100) | NO | | | Tên hiển thị tiếng Việt |
| description | text | NO | | | |
| questions_per_session | int unsigned | NO | | | Số câu hỏi bốc từ DB cho một lượt |
| steps_per_session | int unsigned | NO | | | Số position (bước trả lời) trong một lượt — quyết định điều kiện kết thúc |
| max_score | int unsigned | NO | 100 | | Cố định 100 cho cả 5 game |
| active | boolean | NO | true | | Tắt game mà không xoá dữ liệu |
| created_at / updated_at | datetime | NO | | | |

Indexes:
- `index_games_on_slug` UNIQUE on `(slug)`

Giá trị seed:

| slug | questions_per_session | steps_per_session | Giải thích |
|---|---|---|---|
| `bug_hunt` | 10 | 10 | Mỗi câu là một bước |
| `spec_detective` | 5 | 5 | Mỗi đoạn spec là một bước |
| `incident_escape_room` | 1 | 8 | Một kịch bản, 8 bước quyết định |
| `estimate_poker` | 10 | 10 | Mỗi task là một bước |
| `prod_roulette` | 1 | 10 | Một kịch bản, 10 bước quyết định |

**`questions`** (new)

| Column | Type | Nullable | Default | Constraint | Description |
|---|---|---|---|---|---|
| id | bigint unsigned | NO | auto_increment | PK | |
| game_id | bigint unsigned | NO | | FK → games.id | |
| content | json | NO | | | Payload hiển thị cho người chơi — cấu trúc khác nhau theo game, xem 4.3 |
| answer_key | json | NO | | | Đáp án + rubric chấm. **Không bao giờ trả về client** |
| difficulty | varchar(10) | YES | NULL | | `easy` / `medium` / `hard` |
| checksum | varchar(64) | NO | | UNIQUE | SHA-256 của `content` — chống import trùng |
| hidden | boolean | NO | false | | Admin ẩn khi câu bị báo sai |
| source | varchar(20) | NO | `ai_generated` | | `ai_generated` / `manual` |
| generated_at | datetime | YES | NULL | | Thời điểm AI sinh ra |
| language | varchar(20) | YES | NULL | | Ngôn ngữ lập trình của snippet. Chỉ Bug Hunt dùng, game khác để NULL. Nhân ra từ `content.language` để lọc được bằng index |
| created_at / updated_at | datetime | NO | | | |

Indexes:
- `index_questions_on_checksum` UNIQUE on `(checksum)`
- `index_questions_on_game_id_and_hidden` on `(game_id, hidden)` — bốc câu hỏi lúc bắt đầu lượt
- `index_questions_on_game_language_hidden` on `(game_id, language, hidden)` — bốc câu hỏi cho Bug Hunt theo ngôn ngữ đã chọn

Foreign Keys:
- `fk_questions_games`: `game_id` → `games.id` (RESTRICT — không cho xoá game còn câu hỏi)

**`game_sessions`** (new) — bảng trung tâm

| Column | Type | Nullable | Default | Constraint | Description |
|---|---|---|---|---|---|
| id | bigint unsigned | NO | auto_increment | PK | |
| user_id | bigint unsigned | NO | | FK → users.id | |
| game_id | bigint unsigned | NO | | FK → games.id | |
| attempt_number | int unsigned | NO | | | Lượt thứ mấy của user cho game này, bắt đầu từ 1 |
| score | int unsigned | NO | 0 | CHECK 0..100 | Điểm tích luỹ của lượt. CHECK chỉ được MySQL thực thi từ **8.0.16** trở lên — dưới version đó constraint bị bỏ qua âm thầm, nên validation ở tầng model là bắt buộc chứ không phải tuỳ chọn |
| state | varchar(20) | NO | `in_progress` | | `in_progress` / `finished` / `abandoned` |
| abandoned_reason | varchar(20) | YES | NULL | | `user_quit` / `timeout` / `system_error` — chỉ `system_error` được miễn trừ khỏi bộ đếm rate limit (BR-33) |
| current_position | int unsigned | NO | 0 | | Vị trí câu/bước hiện tại |
| language | varchar(20) | YES | NULL | | Ngôn ngữ người chơi chọn cho lượt này (chỉ Bug Hunt). Đề bốc theo từng bước nên phải lưu để mọi bước cùng một ngôn ngữ |
| started_at | datetime | NO | | | |
| finished_at | datetime | YES | NULL | | NULL nghĩa là chưa hoàn thành → **không tính điểm** |
| created_at / updated_at | datetime | NO | | | |

Indexes:
- `index_game_sessions_on_user_game_attempt` UNIQUE on `(user_id, game_id, attempt_number)` — chống tạo trùng số lượt khi request đồng thời
- `index_game_sessions_on_game_finished_score` on `(game_id, finished_at, score)` — truy vấn leaderboard theo chu kỳ
- `index_game_sessions_on_user_started` on `(user_id, started_at)` — đếm lượt cho rate limit

Foreign Keys:
- `fk_game_sessions_users`: `user_id` → `users.id` (CASCADE — xoá user thì xoá sạch dữ liệu chơi)
- `fk_game_sessions_games`: `game_id` → `games.id` (RESTRICT)

**`session_answers`** (new)

| Column | Type | Nullable | Default | Constraint | Description |
|---|---|---|---|---|---|
| id | bigint unsigned | NO | auto_increment | PK | |
| game_session_id | bigint unsigned | NO | | FK | |
| question_id | bigint unsigned | NO | | FK | Với Escape Room / PROD Roulette, nhiều answer cùng trỏ 1 question (mỗi answer là 1 bước) |
| position | int unsigned | NO | | | Thứ tự trong lượt, bắt đầu từ 1 |
| answer | json | NO | | | Dữ liệu người chơi gửi lên |
| score | int unsigned | NO | 0 | | Điểm của riêng câu/bước này, do server tính. Giữ `unsigned` được vì toàn bộ 5 game dùng mô hình cộng dồn, không có bước nào cho điểm âm |
| elapsed_ms | int unsigned | YES | NULL | | Thời gian trả lời — dùng cho hệ số tốc độ Bug Hunt |
| answered_at | datetime | NO | | | |
| created_at / updated_at | datetime | NO | | | |

Indexes:
- `index_session_answers_on_session_position` UNIQUE on `(game_session_id, position)` — chống double-submit cùng một câu

Foreign Keys:
- `fk_session_answers_sessions`: `game_session_id` → `game_sessions.id` (CASCADE)
- `fk_session_answers_questions`: `question_id` → `questions.id` (RESTRICT)

**`ai_gradings`** (new) — log bắt buộc

| Column | Type | Nullable | Default | Constraint | Description |
|---|---|---|---|---|---|
| id | bigint unsigned | NO | auto_increment | PK | |
| session_answer_id | bigint unsigned | NO | | FK | |
| model | varchar(50) | NO | | | `gemini-2.5-flash` |
| prompt | text | NO | | | Prompt gửi đi (đã gồm câu trả lời người chơi) |
| response | text | NO | | | Response thô nhận về |
| score | int unsigned | YES | NULL | | Điểm AI chấm; NULL khi lỗi |
| latency_ms | int unsigned | YES | NULL | | |
| error | text | YES | NULL | | Thông báo lỗi khi gọi API thất bại |
| created_at | datetime | NO | | | Không có `updated_at` — bản ghi bất biến |

Indexes:
- `index_ai_gradings_on_session_answer_id` on `(session_answer_id)`

Foreign Keys:
- `fk_ai_gradings_answers`: `session_answer_id` → `session_answers.id` (CASCADE)

**`question_reports`** (new)

| Column | Type | Nullable | Default | Constraint | Description |
|---|---|---|---|---|---|
| id | bigint unsigned | NO | auto_increment | PK | |
| user_id | bigint unsigned | NO | | FK | Người báo |
| question_id | bigint unsigned | NO | | FK | |
| reason | text | NO | | | Lý do người chơi nhập |
| status | varchar(20) | NO | `open` | | `open` / `accepted` / `rejected` |
| handled_by_id | bigint unsigned | YES | NULL | FK → users.id | Admin xử lý |
| handled_at | datetime | YES | NULL | | |
| created_at / updated_at | datetime | NO | | | |

Indexes:
- `index_question_reports_on_user_and_question` UNIQUE on `(user_id, question_id)` — mỗi người báo mỗi câu tối đa 1 lần
- `index_question_reports_on_status` on `(status)`

Foreign Keys:
- `fk_question_reports_users`: `user_id` → `users.id` (CASCADE)
- `fk_question_reports_questions`: `question_id` → `questions.id` (CASCADE)
- `fk_question_reports_handlers`: `handled_by_id` → `users.id` (SET NULL)

### 4.3 Cấu trúc `content` / `answer_key` theo game

| Game | `content` | `answer_key` |
|---|---|---|
| `bug_hunt` | `{language, code_lines: [...], bug_types: [...]}` | `{buggy_line: N, bug_type: "sql_injection", explanation}` |
| `spec_detective` | `{statements: [...], clarifying_options: [{key, label}]}` | `{ambiguous_statement_indexes: [...], best_option_key, explanation}` |
| `incident_escape_room` | `{scenario, initial_logs, nodes: [{key, prompt, options: [...]}]}` | `{option_effects: {option_key: {points, minutes_cost, next_node}}, recovery_node}` |
| `estimate_poker` | `{task_description, context}` | `{actual_hours: N, reasoning}` — AI tính **một lần lúc sinh đề** |
| `prod_roulette` | `{scenario, nodes: [{key, prompt, options: [...]}]}` | `{option_effects: {option_key: {points, irreversible: bool, consequence_text, next_node}}}` |

Không có bảng leaderboard. Toàn bộ bảng xếp hạng **suy ra** từ `game_sessions` bằng truy vấn — xem BR-12 đến BR-15.

## 5. API Contract

Kiến trúc: Rails monolith, trang server-rendered (ERB) cho điều hướng; JSON endpoints cho gameplay để đảm bảo chấm điểm ở server. Response theo Pattern B của `CLAUDE.md` (HTTP status là signal, body là data).

### 5.1 Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/signup`, `/login` | Guest | Trang HTML |
| POST | `/users` | Guest | Đăng ký |
| POST | `/session` | Guest | Đăng nhập |
| DELETE | `/session` | Member | Đăng xuất |
| GET | `/privacy` | Guest | Trang chính sách riêng tư (Q7) — phải đọc được trước khi đăng ký |
| GET | `/games` | Member | Danh sách 5 game + personal best |
| GET | `/games/:slug` | Member | Trang chơi (HTML shell) |
| POST | `/api/v1/games/:slug/sessions` | Member | Bắt đầu lượt chơi mới |
| GET | `/api/v1/sessions/:id/current` | Member (owner) | Lấy câu/bước hiện tại |
| POST | `/api/v1/sessions/:id/answers` | Member (owner) | Nộp đáp án, server chấm, trả câu tiếp theo |
| POST | `/api/v1/sessions/:id/abandon` | Member (owner) | Bỏ lượt chủ động |
| GET | `/api/v1/leaderboards` | Guest | `?scope=all_time\|weekly\|monthly&game=<slug\|total>` |
| POST | `/api/v1/questions/:id/reports` | Member | Báo câu hỏi sai |
| GET | `/admin/users` | Admin | Danh sách tài khoản |
| DELETE | `/admin/users/:id` | Admin | Xoá tài khoản |
| GET | `/admin/question_reports` | Admin | Danh sách báo cáo |
| PATCH | `/admin/question_reports/:id` | Admin | Xử lý báo cáo (`accepted` → ẩn câu hỏi) |

### 5.2 Request/Response chi tiết

**POST /users** — Đăng ký

Request Body:

| Field | Type | Required | Validation | Description |
|---|---|---|---|---|
| email | string | YES | Match `\A[a-z0-9._%+-]+\.nta@gmail\.com\z` (case-insensitive), unique | Allowlist đăng ký |
| password | string | YES | min 8 ký tự | |
| password_confirmation | string | YES | == password | |
| display_name | string | YES | 2–50 ký tự | |

Response Success (`201`):
```json
{ "id": 12, "email": "abc.nta@gmail.com", "display_name": "ABC" }
```

**POST /session** — Đăng nhập

Request: `{ "email": "...", "password": "..." }`

Response Success (`200`): `{ "id": 12, "display_name": "ABC", "admin": false }` — kèm cookie session httpOnly.

**POST /api/v1/games/:slug/sessions** — Bắt đầu lượt

Request Headers:
```
Cookie: _skill_arcade_session=<SESSION_COOKIE>
Content-Type: application/json
```

Request Body:

| Field | Type | Required | Validation | Description |
|---|---|---|---|---|
| language | string | Chỉ với `bug_hunt` | Phải là ngôn ngữ có mặt trong ngân hàng câu hỏi của game | Ngôn ngữ lập trình cho cả lượt (BR-35). Game khác gửi kèm thì bị bỏ qua |

Response Success (`201`):
```json
{
  "session_id": 981,
  "game": "bug_hunt",
  "language": "php",
  "attempt_number": 4,
  "total_positions": 10,
  "current": {
    "position": 1,
    "question_id": 552,
    "content": { "language": "php", "code_lines": ["..."], "bug_types": ["sql_injection", "n_plus_one", "missing_null_check"] }
  }
}
```

`total_positions` lấy từ `games.steps_per_session` (BR-30), không phải `questions_per_session` — với Escape Room giá trị này là 8 dù chỉ bốc 1 kịch bản.

`answer_key` không bao giờ xuất hiện trong response.

**POST /api/v1/sessions/:id/answers** — Nộp đáp án

Request Body:

| Field | Type | Required | Validation | Description |
|---|---|---|---|---|
| position | integer | YES | == `current_position + 1` của session | Chống double-submit và chống nộp lệch thứ tự |
| answer | object | YES | Cấu trúc theo game | Ví dụ Bug Hunt: `{"line": 7, "bug_type": "sql_injection"}` |
| elapsed_ms | integer | NO | 0..600000 | Client báo, server **kẹp trần** theo thời gian thực đo được phía server |

Response Success (`200`):
```json
{
  "position": 1,
  "awarded_score": 10,
  "total_score": 10,
  "explanation": "Dòng 7 nối chuỗi trực tiếp vào câu SQL.",
  "finished": false,
  "next": { "position": 2, "question_id": 553, "content": {} }
}
```

Khi lượt kết thúc (`finished: true`):
```json
{
  "position": 10,
  "awarded_score": 8,
  "total_score": 96,
  "finished": true,
  "next": null,
  "summary": {
    "score": 96,
    "personal_best": 96,
    "is_new_best": true,
    "attempt_number": 4
  }
}
```

**GET /api/v1/leaderboards**

Response Success (`200`):
```json
{
  "scope": "weekly",
  "game": "bug_hunt",
  "period": { "from": "2026-08-17T00:00:00+07:00", "to": "2026-08-23T23:59:59+07:00" },
  "entries": [
    { "rank": 1, "display_name": "ABC", "score": 100, "attempts_to_best": 2, "achieved_at": "2026-08-18T09:14:22+07:00" }
  ]
}
```

Response Errors (áp dụng cho toàn bộ endpoint):

| HTTP Code | Error Code | Condition | Message |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | Body sai định dạng, thiếu field bắt buộc | "Dữ liệu gửi lên không hợp lệ" |
| 401 | `UNAUTHORIZED` | Chưa đăng nhập hoặc session hết hạn | "Vui lòng đăng nhập" |
| 403 | `FORBIDDEN` | Thao tác trên session của người khác, hoặc không phải admin | "Bạn không có quyền thực hiện" |
| 403 | `ACCOUNT_LOCKED` | `locked_until` còn hiệu lực | "Tài khoản tạm khoá, thử lại sau 15 phút" |
| 404 | `NOT_FOUND` | Game slug / session / question không tồn tại | "Không tìm thấy" |
| 409 | `POSITION_CONFLICT` | `position` gửi lên không khớp `current_position + 1` | "Câu này đã được trả lời" |
| 409 | `SESSION_FINISHED` | Nộp đáp án cho lượt đã kết thúc | "Lượt chơi đã kết thúc" |
| 422 | `NO_QUESTIONS_AVAILABLE` | Ngân hàng câu hỏi không đủ câu chưa ẩn | "Chưa đủ câu hỏi cho game này" |
| 422 | `EMAIL_NOT_ALLOWED` | Email không khớp allowlist | "Chỉ chấp nhận email dạng xxx.nta@gmail.com" |
| 422 | `INVALID_LANGUAGE` | Bug Hunt không gửi `language`, hoặc gửi ngôn ngữ không có trong ngân hàng câu hỏi | "Cần chọn ngôn ngữ lập trình" |
| 422 | `INVALID_CSRF_TOKEN` | Non-GET JSON call thiếu hoặc sai header `X-CSRF-Token` (xem §13) | "Phiên làm việc không hợp lệ, tải lại trang" |
| 429 | `TOO_MANY_REQUESTS` | Vượt rate limit | Thông điệp theo rule bị chạm, không dùng chung một câu: hạn mức tính theo phút/giờ → "Bạn thao tác quá nhanh, thử lại sau"; hạn mức tính theo ngày → nói rõ đã hết lượt của ngày, vì câu "quá nhanh" làm người chơi retry cả ngày vô ích |

## 6. Điều kiện tiên quyết (Preconditions)

- [ ] Đã chạy `rails new` với MySQL adapter, Ruby/Rails version chốt và ghi vào `CLAUDE.md`
- [ ] `bcrypt` được bật trong `Gemfile` (cho `has_secure_password`)
- [ ] Gem `rack-attack` được duyệt và thêm vào `Gemfile` *(chờ owner duyệt — xem Open Questions)*
- [ ] `GEMINI_API_KEY` có trong biến môi trường, không commit vào repo. Project **không dùng gem dotenv** nên file `.env` không được nạp tự động — phải export biến ở shell/systemd/Docker env. `GEMINI_MODEL` không bắt buộc, mặc định `gemini-2.5-flash`
- [ ] Đã chạy `rake questions:generate` + `rake questions:import` để ngân hàng câu hỏi có tối thiểu: Bug Hunt 50 câu **cho mỗi ngôn ngữ được mở** (BR-35 giới hạn cả lượt trong một ngôn ngữ, nên mức tối thiểu tính theo từng ngôn ngữ chứ không tính tổng — hiện mở 4 ngôn ngữ php/ruby/java/javascript nên là 200 câu), Spec Detective 25 câu, Estimate Poker 50 câu, Escape Room 20 kịch bản, PROD Roulette 20 kịch bản
  > Ở hạn mức free 20 request/ngày (§20), khối lượng này cần khoảng 60-70 request tức **3-4 ngày**. Từ 1.19 việc sinh đề là người dùng Gemini DUY NHẤT (Spec Detective chấm từ DB), nên cả 20 request/ngày đều dùng được cho sinh đề và không đụng gì tới người chơi.
  > Mức tối thiểu này được tính để người chơi có ít nhất 5 lượt liên tiếp không gặp lại nội dung cũ (BR-32). Escape Room và PROD Roulette mỗi lượt tiêu thụ trọn 1 kịch bản nên cần nhiều kịch bản hơn tỷ lệ thuận với số lượt kỳ vọng
- [ ] `PRIVACY_CONTACT_EMAIL` đã được set — chưa set thì trang `/privacy` nói thẳng là app chưa công bố kênh liên hệ để yêu cầu xoá tài khoản (Q8)
- [ ] Đã seed 5 bản ghi `games` và tài khoản admin

## 7. Luồng chính (Main Flow)

| # | Actor | Hành động | System Response |
|---|---|---|---|
| 1 | Guest | Đăng ký bằng email `xxx.nta@gmail.com` | Kiểm tra allowlist + trùng email, tạo user, đăng nhập luôn |
| 2 | Member | Vào `/games` | Hiển thị 5 game kèm personal best và điểm tổng hiện tại |
| 3 | Member | Chọn game, bấm "Bắt đầu" | Kiểm tra rate limit; tạo `game_sessions` với `attempt_number = số lượt trước + 1`, `score = 0`, `state = in_progress`; bốc `questions_per_session` câu chưa `hidden` theo chính sách ưu tiên câu chưa trả lời đúng (BR-32); trả bước đầu tiên (không kèm đáp án) |
| 4 | Member | Trả lời câu hiện tại | Server đối chiếu `answer_key`, tính điểm câu đó, ghi `session_answers`, cộng vào `game_sessions.score`, trả điểm + giải thích + câu tiếp theo |
| 5 | System | Lặp bước 4 cho tới khi `current_position == steps_per_session`, hoặc chạm điều kiện kết thúc sớm của game | Đặt `state = finished`, `finished_at = now` |
| 6 | System | So sánh điểm lượt này với personal best | Nếu cao hơn thì personal best mới là điểm lượt này; nếu không, giữ nguyên. Không ghi đè dữ liệu lượt cũ |
| 7 | Member | Xem `/leaderboards` | Tính bảng xếp hạng từ `game_sessions` theo chu kỳ đang chọn |

## 7b. Flow Diagram

```
([Member]) → [Đăng nhập] → [Chọn game] → <Còn lượt trong hạn mức?>
                                                ↓ Có                    ↓ Không
                                   [Tạo game_session, score=0]     [429 Rate limited]
                                                ↓
                                   [Bốc N câu chưa hidden]
                                                ↓
                                   [Hiển thị câu hiện tại] ←──────────┐
                                                ↓                     │
                                   ([Member]) → [Nộp đáp án]          │
                                                ↓                     │
                                        <Game cần AI chấm?>           │
                                          ↓ Có          ↓ Không       │
                                   [Gọi Gemini]    [Chấm theo         │
                                   [Ghi ai_grading] answer_key]       │
                                          ↓             ↓             │
                                        [Cộng điểm vào session]       │
                                                ↓                     │
                                        <Hết câu / chạm điều kiện     │
                                         kết thúc sớm?>               │
                                          ↓ Không ────────────────────┘
                                          ↓ Có
                                   [state=finished, finished_at=now]
                                                ↓
                                   <Điểm > personal best?>
                                     ↓ Có              ↓ Không
                              [Best mới]         [Giữ best cũ]
                                     ↓                 ↓
                                   [Hiển thị kết quả lượt]
```

> SVG chưa sinh được (Playwright MCP không khả dụng trong môi trường hiện tại).
> Xem file [docs/spec/assets/skill-arcade-img1.mmd](assets/skill-arcade-img1.mmd) và render tại https://mermaid.live

## 8. Luồng thay thế (Alternative Flows)

### 8.1 Đạt 100 điểm trước khi hết bước
- Điều kiện: tại bước 4, sau khi cộng điểm mà `score == 100` trong khi `current_position < steps_per_session`
- Luồng: server đặt `state = finished` ngay, không trả bước tiếp theo
- Kết quả: lượt kết thúc, người chơi **vẫn chơi lại được** game đó (điểm không tăng thêm được nữa vì đã chạm trần)
- **Ghi chú**: với công thức điểm hiện tại (BR-25 đến BR-29), cả 5 game chỉ có thể chạm 100 ở bước cuối cùng, nên nhánh này thực tế không xảy ra. Giữ lại làm lưới an toàn phòng khi công thức điểm thay đổi — implement vẫn phải có, test vẫn phải cover

### 8.2 PROD Roulette — chọn hành động không thể thu hồi
- Điều kiện: tại bước 4, `answer_key.option_effects[choice].irreversible == true`
- Luồng: bước đó được 0 điểm, `state = finished`, trả về `consequence_text` mô tả hậu quả
- Kết quả: lượt kết thúc ngay giữa chừng — đây là chủ đích thiết kế, không phải lỗi

### 8.3 Incident Escape Room — quá 30 phút giả lập
- Điều kiện: tổng `minutes_cost` tích luỹ vượt 30
- Luồng: `state = finished`; giữ nguyên điểm đã tích luỹ từ các bước xử lý đúng, **không** cộng điểm thưởng thời gian (BR-27)
- Kết quả: hiển thị post-mortem tự động (chuỗi hành động đã chọn + thời gian tiêu tốn từng bước)

### 8.4 Người chơi bỏ lượt giữa chừng
- Điều kiện: gọi `/abandon` (`abandoned_reason = user_quit`), hoặc lượt `in_progress` quá 24 giờ (`abandoned_reason = timeout`)
- Luồng: `state = abandoned`, `finished_at` giữ NULL
- Kết quả: **không** tính vào personal best và không tính vào leaderboard. Vẫn tính vào hạn mức rate limit để tránh lách luật bằng cách bỏ lượt liên tục (BR-33)

## 9. Luồng lỗi (Exception Flows)

Phần lớn đã cover ở 5.2. Ba luồng cần nêu riêng:

- **Nộp trùng đáp án (double-submit)**: unique index `(game_session_id, position)` chặn ở tầng DB; server trả `409 POSITION_CONFLICT`, không cộng điểm lần hai
- **Hai request tạo lượt đồng thời**: unique index `(user_id, game_id, attempt_number)` chặn; server retry một lần với `attempt_number` mới, thất bại tiếp thì trả `409`
- **Admin xoá tài khoản đang có lượt `in_progress`**: FK CASCADE xoá toàn bộ `game_sessions`, `session_answers`, `ai_gradings` của user đó; leaderboard tự cập nhật ở lần truy vấn kế tiếp

## 10. Business Rules

- **BR-01**: Registration is restricted to emails matching `\A[a-z0-9._%+-]+\.nta@gmail\.com\z` (case-insensitive). Any other address is rejected with `EMAIL_NOT_ALLOWED`.
- **BR-02**: Every score is computed **server-side only**. Any score value present in a client request is ignored.
- **BR-03**: `answer_key` is never serialized into any HTTP response, including admin endpoints.
- **BR-04**: Each game has a hard maximum of 100 points per session. A session ends immediately when its score reaches 100.
- **BR-05**: A session starts at 0 points. Scores from different sessions are never accumulated.
- **BR-06**: A user's score for a game is `MAX(score)` over their `finished` sessions of that game. Replaying only replaces it when the new score is strictly higher.
- **BR-07**: A user's total score is the sum of their per-game scores across all 5 games. Maximum possible total is 500.
- **BR-08**: Sessions with `state != 'finished'` are excluded from every score and ranking calculation.
- **BR-09**: Reaching 100 points does **not** lock the game. The user may replay it indefinitely; the score simply cannot increase further.
- **BR-10**: `attempts_to_best` is scoped to the leaderboard period being queried. It is the 1-based ordinal position — among the user's `finished` sessions for that game whose `finished_at` falls inside the period, ordered by `finished_at` ascending — of the earliest session that achieved their best score within that period. For the all-time leaderboard this equals the session's `attempt_number`; for weekly and monthly leaderboards it is recomputed within the period so that a long-time player is not penalised against a newcomer.
- **BR-11**: Ranking order is: score descending, then `attempts_to_best` ascending, then earliest `finished_at` ascending.
- **BR-11a**: For the combined leaderboard, `attempts_to_best` is the sum of the per-game `attempts_to_best` across all 5 games, where a game the user has never finished contributes 0.
- **BR-12**: Leaderboards are computed from `game_sessions` at query time. No denormalized ranking table exists.
- **BR-13**: The weekly leaderboard covers Monday 00:00:00 to Sunday 23:59:59 in `Asia/Ho_Chi_Minh`.
- **BR-14**: The monthly leaderboard covers the first to the last day of the calendar month in `Asia/Ho_Chi_Minh`.
- **BR-15**: No leaderboard is ever reset. Weekly and monthly views are filters over historical data, not counters.
- **BR-16**: Questions with `hidden = true` are excluded when drawing questions for a new session. Sessions already played on a now-hidden question keep their recorded scores.
- **BR-17**: Each user may report a given question at most once (`UNIQUE (user_id, question_id)`).
- **BR-18**: When an admin sets a report to `accepted`, the referenced question is set to `hidden = true`. Questions are never hard-deleted.
- **BR-19** *(lịch sử — không còn sinh bản ghi mới từ 1.19)*: Khi Spec Detective còn chấm bằng Gemini, mọi lời gọi ghi đúng một dòng `ai_gradings`, kể cả lời gọi thất bại. Từ 1.19 không game nào gọi AI lúc chơi nên không có dòng mới; bảng và các dòng cũ được giữ để giải trình điểm đã chấm trước đó.
- **BR-20**: For Estimate Poker, `actual_hours` is fixed in `answer_key` at question generation time. It is never recomputed at play time, so all players are graded against the same value.
- **BR-21**: Bug Hunt speed multiplier is applied on `elapsed_ms` measured server-side (time between the question being served and the answer arriving): below 30s ×1.0, 30–60s ×0.8, above 60s ×0.5. The multiplier is applied **once, to the question's total raw points**, and the result is then floored — not applied to each component separately. Example: correct line and correct type at 45s gives `floor((6 + 4) × 0.8) = 8`, not `floor(6×0.8) + floor(4×0.8) = 7`.
- **BR-22**: Only accounts with `admin = true` may delete users. A user cannot delete their own account, and an admin cannot delete their own account.
- **BR-23**: After 5 consecutive failed logins, the account is locked for 15 minutes (`locked_until`). A successful login resets `failed_login_count` to 0.
- **BR-24**: A session left `in_progress` for more than 24 hours is marked `abandoned` with `abandoned_reason = 'timeout'` by a scheduled task.
- **BR-30**: A session ends when `current_position` reaches the game's `steps_per_session`. `questions_per_session` only governs how many question records are drawn from the bank; for scenario-based games (Escape Room, PROD Roulette) one question supplies many steps, so the two values differ.
- **BR-31**: All five games use an **additive** scoring model: a session starts at 0 and only ever gains points. No rule may subtract from an already-awarded score.
- **BR-32**: When drawing questions for a new session, unhidden questions the user has never answered correctly are preferred. Previously-answered questions are only reused when there are not enough fresh ones, and the oldest-answered are reused first.
- **BR-33** *(lịch sử — không còn phát sinh từ 1.19)*: Lượt có `abandoned_reason = system_error` không tính vào personal best, leaderboard, và không trừ vào hạn mức rate limit. Trạng thái này chỉ do đường chấm bằng Gemini sinh ra; đường đó đã bỏ nên không có lượt mới nào nhận lý do này. Giá trị enum và cách loại trừ được giữ nguyên cho dữ liệu cũ.
- **BR-34**: Rate-limit rules are evaluated independently. A per-game rule and the global per-user rule both apply; whichever threshold is reached first blocks the request. From 1.19 there is no per-game rule left — the Spec Detective daily cap existed only to fit the Gemini free-tier quota and went away with the runtime AI call. All current caps are per user or per IP.
- **BR-38**: Every page links to `/privacy`, and `/privacy` is readable without logging in so it can be read before registering. The page states only what the code actually does, and where a fact is not yet decided it says so instead of naming a figure: from 1.19 it discloses that **no game sends player input outside the app** and that Gemini is used offline only to author questions, that Google Fonts receives the player's IP on every page load, that pre-1.19 `ai_gradings` rows (which do contain player-typed text) are kept forever, that the leaderboard is public, and log retention for the hosting platform. The account-deletion contact comes from `PRIVACY_CONTACT_EMAIL`; while unset the page says no channel has been published rather than inventing one (Q8).
- **BR-36**: The question served for a given step must be stable. A step is drawn on demand rather than fixed at session creation, so the draw is keyed on `(session_id, position)` and is deterministic: displaying a step, reloading it via `GET /sessions/:id/current`, and grading the submitted answer all resolve to the same question record. A non-deterministic draw would grade the player against a question they never saw.
- **BR-35**: Bug Hunt is scoped to one programming language per session. The player picks the language before the session starts, it is stored on `game_sessions.language`, and every question drawn for that session must have the same `questions.language`. The picker only offers languages whose unhidden question count reaches `questions_per_session`; a language present in the bank but short of that count is still accepted by the API and answered with `NO_QUESTIONS_AVAILABLE`, while an unknown language gives `INVALID_LANGUAGE`. The other four games ignore the field.

### Scoring rules per game

- **BR-25** (Bug Hunt): 10 questions × 10 points. Correct line = 6 points, correct bug type = 4 points, then multiplied by the BR-21 speed factor and rounded down.
- **BR-26** (Spec Detective): 5 đoạn × 20 điểm, chấm hoàn toàn từ `answer_key` trong DB — 10 điểm cho việc tick đúng các câu còn mơ hồ, 10 điểm cho việc chọn đúng câu hỏi làm rõ tốt nhất trong 4 phương án. Không có hệ số tốc độ. Nửa điểm tick tính bằng `floor((số tick đúng − số tick sai) / tổng số câu mơ hồ × 10)`, kẹp trong `0..10`: **phải trừ tick sai**, không thì tick toàn bộ câu trong đoạn là ăn đủ 10 điểm mà không cần đọc. Nửa điểm phương án là tất-cả-hoặc-không. Đề bắt buộc còn ít nhất một câu KHÔNG mơ hồ, `Questions::Validator` chặn đề vi phạm ngay lúc import.
- **BR-27** (Incident Escape Room): 8 decision steps × 10 points, plus a time bonus of up to 20 points — total 100. Per step: the correct diagnostic or recovery action scores 10, a harmless but time-wasting action scores 5, a wrong action scores 0 and adds its own `minutes_cost`. Time bonus on completion: recovery within 15 simulated minutes adds 20, within 30 adds 10, beyond 30 adds 0 and ends the session immediately (§8.3). Points already awarded for individual steps are always kept (BR-31).
- **BR-28** (Estimate Poker): 10 tasks × 10 points based on deviation from `actual_hours` — within 10% scores 10, within 25% scores 7, within 50% scores 4, beyond 50% scores 0.
- **BR-29** (PROD Roulette): 10 decision steps × 10 points — a safe choice scores 10, a recoverable-risk choice scores 3, an irreversible choice scores 0 and ends the session immediately.

## 11. State Machine

`game_sessions.state`:

| Trạng thái hiện tại | Event | Trạng thái tiếp theo | Điều kiện |
|---|---|---|---|
| — | Tạo lượt | `in_progress` | Qua rate limit và có đủ câu hỏi |
| `in_progress` | Nộp đáp án bước cuối | `finished` | `current_position == steps_per_session` (BR-30) |
| `in_progress` | Điểm chạm 100 | `finished` | BR-04 — lưới an toàn, xem ghi chú §8.1 |
| `in_progress` | Chọn hành động không thể thu hồi | `finished` | PROD Roulette, BR-29 |
| `in_progress` | Quá 30 phút giả lập | `finished` (giữ điểm đã có, không cộng bonus) | Escape Room, BR-27 |
| `in_progress` | Gọi `/abandon` | `abandoned` (`user_quit`) | Người chơi chủ động bỏ |
| `in_progress` | Quá 24 giờ | `abandoned` (`timeout`) | BR-24, scheduled task |
| `in_progress` | AI chấm lỗi | `abandoned` (`system_error`) | *Chỉ dữ liệu cũ* — đường chấm bằng AI đã bỏ ở 1.19, không có lượt mới nào đi vào trạng thái này (BR-33) |
| `finished` | (bất kỳ) | `finished` | Trạng thái cuối, bất biến |
| `abandoned` | (bất kỳ) | `abandoned` | Trạng thái cuối, bất biến |

`question_reports.status`: `open` → `accepted` (ẩn câu hỏi) hoặc `open` → `rejected`. Không quay lại `open`.

## 12. Security & Authorization

- **Authentication**: required for all gameplay endpoints. Cookie-based session (`httpOnly`, `secure`, `SameSite=Lax`), managed by Rails. No JWT, no API token in Phase 1.
- **Authorization**: session ownership is enforced on every `/api/v1/sessions/:id/*` call — a member may only act on sessions where `user_id == current_user.id`. Admin endpoints require `current_user.admin`.
- **Rate limiting** (via `rack-attack`):

| Scope | Limit |
|---|---|
| `POST /users` | 5 per hour per IP |
| `POST /session` (failed) | 20 per 15 min per IP; plus per-account lockout at 5 failures (BR-23) |
| `POST /api/v1/games/:slug/sessions` | 20 per hour and 60 per day per user |
| `POST /api/v1/questions/:id/reports` | 10 per day per user |
| Global | 100 requests per minute per IP |

Rules are evaluated independently (BR-34): a session counts toward both the per-hour and the per-day session cap, and whichever is hit first returns `429`. Until 1.19 there was an extra `1 per day per user` cap on Spec Detective, dictated by the Gemini free-tier quota rather than by gameplay design; it was removed together with the runtime AI call because nothing about the game needs it any more.

rack_attack keeps its counters in `Rails.cache`, so on Render these caps only hold if `REDIS_URL` is set (§15): with the default file store on Render's ephemeral, per-instance filesystem, every deploy or spin-down resets the counters, and a Hobby web service sleeps whenever traffic stops — which would make the per-day caps effectively meaningless.

- **Input validation**: strong parameters on every controller; `answer` JSON validated against a per-game schema before grading; all ActiveRecord queries use placeholders or hash conditions — no string interpolation into SQL.
- **Sensitive data**: `password_digest` is never serialized. `answer_key` is excluded from all serializers (BR-03). `GEMINI_API_KEY` is read from ENV and never logged. The `ai_gradings.prompt` column stores prompt content only, never the API key; from 1.19 nothing writes to that table any more, so no player-authored text reaches it.
- **Anti-cheat**: scoring is server-side (BR-02); `elapsed_ms` from the client is capped by server-measured elapsed time; `position` must match `current_position + 1`; unique indexes block replay and double-submit.
- **Known accepted risks** (owner decision, recorded in the clarify report):
  - ~~Admin seed password `12345678` is hardcoded in `db/seeds.rb`~~ — **reversed 2026-08-19.** The owner originally chose to hardcode it; the decision was revisited when preparing the Render deploy because the exposure turned out to be concrete rather than hypothetical: `bin/docker-entrypoint` runs `db:prepare`, and `DatabaseTasks.prepare_all` seeds whenever the `schema_migrations` table is absent — that is, whenever the database has no schema, including a database that already exists but is still empty, so the very first boot against an empty database would publish an admin account with a known password on a public URL — and the app has no password-change feature to fix it afterwards. `db/seeds.rb` now reads `ENV["ADMIN_PASSWORD"]`; development and test keep `12345678` as the default, and production without the variable **skips creating the admin** (the five `games` rows are still seeded so the app works) instead of aborting — aborting mid-seed would leave a schema with no games and `db:prepare` never seeds a second time.
  - The `*.nta@gmail.com` allowlist does not stop a determined outsider — anyone can register such a Gmail address. Rate limiting is the actual protection layer.
- **Not in scope**: 2FA, OAuth, email verification, CAPTCHA, password reset flow.

## 13. Integration Contract (Frontend)

Frontend is server-rendered ERB with vanilla JS calling the JSON endpoints. No SPA framework.

- **Session storage**: session lives in an httpOnly cookie set by Rails. JS never reads or stores credentials.
- **CSRF token (required on every non-GET JSON call)**: because these endpoints authenticate with the session cookie, Rails' forgery protection applies to them exactly as it does to HTML forms. A JSON `POST` without a token is rejected with **422**, not 401 — this is the single most likely reason a correctly-authenticated call fails. The client reads the token from the `<meta name="csrf-token">` tag rendered by the layout and sends it as the `X-CSRF-Token` header:

```js
const csrf = document.querySelector('meta[name="csrf-token"]').content;
fetch(url, {
  method: "POST",
  headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
  body: JSON.stringify(payload)
});
```

  **Do not disable forgery protection** on these endpoints (`skip_forgery_protection`, `protect_from_forgery with: :null_session`). They are cookie-authenticated, so turning CSRF off would let any third-party page start sessions and submit answers on behalf of a logged-in player — a real vulnerability, not a formality. Token-based auth would remove the need for CSRF tokens, but Phase 1 deliberately uses cookie sessions (section 12).

  **Testing note**: Rails disables forgery protection in the test environment, so request specs pass whether or not the client sends a token. This gap must be covered by a manual check against a running server, or by enabling `allow_forgery_protection` in a dedicated spec.
- **Session lifetime**: 24 hours of inactivity. On `401`, redirect to `/login` — there is no silent refresh in Phase 1.
- **Gameplay state**: the server is the single source of truth. On page reload mid-session, the client calls `GET /api/v1/sessions/:id/current` and resumes from `current_position`.
- **Concurrent requests**: the client must disable the submit control until the previous `POST /answers` resolves. A `409 POSITION_CONFLICT` means the answer was already recorded — the client re-fetches `/current` instead of retrying.
- **Retry strategy**: no response is auto-retried. `4xx` responses are never retried automatically, and from 1.19 there is no AI-dependent `503` on the gameplay path to retry.
- **Loading states**: every answer submission disables the submit button until the response arrives. Grading is a local DB comparison for all five games from 1.19, so no step needs a long-wait spinner.
- **Optimistic update**: not allowed. The score shown always comes from the server response, never computed client-side.
- **Timer display**: the client may show a countdown for Bug Hunt, but the authoritative `elapsed_ms` is measured server-side (BR-21).

## 14. Audit & Logging

| Event | Log level | Destination | Fields |
|---|---|---|---|
| Registration success | INFO | Rails log | user_id, email, ip |
| Login success | INFO | Rails log | user_id, ip, user_agent |
| Login failed | WARN | Rails log | email, ip, reason, failed_count |
| Account locked | WARN | Rails log | user_id, ip, locked_until |
| Session created | INFO | Rails log | user_id, game_id, attempt_number |
| Session finished | INFO | Rails log | session_id, user_id, game_id, score, is_new_best |
| AI grading call | — | `ai_gradings` table | session_answer_id, model, prompt, response, score, latency_ms, error |
| Rate limit hit | WARN | Rails log | ip, user_id, matched rule |
| Question hidden by admin | INFO | Rails log | admin_id, question_id, report_id |
| User deleted by admin | WARN | Rails log | admin_id, deleted_user_id, deleted_user_email |

Retention: **corrected 2026-08-19** — the app does not rotate logs. `config/environments/production.rb` sends the logger to `STDOUT`, so retention is decided by whatever collects that stream. Hosting is now Render (Q5), whose retention is per plan: Hobby 7 days, Pro 14 days, Scale/Enterprise 30 days. The app runs on **Hobby, so 7 days**. Render's docs note that logs past the window are gone for good — upgrading the plan does not bring them back — and that longer retention requires streaming to a third-party log provider. The figure lives in one place, `PagesController::LOG_RETENTION_DAYS`; changing plan means changing that constant. The earlier "30 days" in this spec was an assumption, not an implemented setting. `ai_gradings` rows are retained indefinitely and never deleted — they are the only evidence available if a player disputes an AI-assigned score (BR-19).

**User-generated content in logs**: no longer applicable from 1.19. Until then `ai_gradings.prompt` embedded the free-text a player typed in Spec Detective, and that column is the reason the table is kept forever (see /privacy). With the runtime AI call gone, nothing the player types leaves the app or reaches an append-only store; answers live in `session_answers` and are deleted with the account.

## 15. Non-functional Requirements

- **Performance**: page render and grading endpoints target under 300ms at p95 — from 1.19 every game grades from a local DB comparison, so no endpoint on the gameplay path depends on an external call. The offline generation path (`rake questions:generate`, `rake questions:refill`) has no latency target; it runs with a 120s read timeout because a batch of questions takes far longer than a grading call did.
- **Leaderboard cost**: computed by query with a 60-second cache. At the expected scale (tens of users, thousands of sessions) no materialized ranking table is needed. Revisit if `game_sessions` exceeds 1 million rows.
- **Scalability**: the app is stateless apart from the session cookie, so it scales horizontally. MySQL is the only stateful component.
- **Availability**: Gemini is no longer on the gameplay path from 1.19 — all five games grade from `answer_key` in the local DB, so Gemini being unavailable does not affect playing at all. It is only called offline by `rake questions:generate` and `rake questions:refill`; a failure there means the question bank does not grow that day and the scheduled job exits non-zero. The circuit breaker (`Gemini::CircuitBreaker`) is kept for those offline calls: it opens after 5 consecutive failures and stays open 5 minutes, and a call rejected by an open breaker is not itself counted as a failure, otherwise every retry would extend the open window indefinitely. Breaker state lives in `Rails.cache`; the scheduled job deliberately runs without `REDIS_URL` so its breaker state stays separate from the web service.
- **Accessibility**: WCAG 2.1 AA for the non-game pages. Bug Hunt's click-a-line interaction is desktop-first; a keyboard alternative (arrow keys + Enter to select a line) is required.
- **Backward compatibility**: N/A — first release, no existing clients.
- **Localization**: Vietnamese only. No i18n framework in Phase 1; strings may be inline.

## 16. Edge Cases

### Security
- [x] Brute force login → BR-23 lockout + rack-attack per-IP limit
- [x] Score tampering via client payload → BR-02, server-side only
- [x] Answer key leakage → BR-03, excluded from all serializers
- [x] Replay/double-submit for extra points → unique `(game_session_id, position)`
- [x] Acting on another user's session → ownership check, `403`
- [ ] Mass registration of `*.nta@gmail.com` addresses → mitigated but not prevented (accepted risk)

### Timing & State
- [x] Session expires mid-game → `401`, session row stays `in_progress`, later marked `abandoned` (BR-24)
- [x] Browser closed mid-game → `abandoned`, no score counted (BR-08)
- [x] Score hits 100 before the last step → session ends immediately (BR-04). Unreachable with the current formulas, kept as a safeguard (§8.1)
- [x] Two tabs playing the same game → each creates its own `game_sessions` row with a distinct `attempt_number`; both count toward the rate limit

### Data Integrity
- [x] Question bank runs out of unhidden questions → `422 NO_QUESTIONS_AVAILABLE`, no session created
- [x] Question hidden while a session using it is still in progress → the running session finishes normally (BR-16)
- [x] Admin deletes a user → CASCADE removes their sessions, answers and gradings; leaderboard reflects it on next query
- [x] Duplicate question import → blocked by `UNIQUE (checksum)`

### Concurrency
- [x] Two simultaneous "start session" requests → unique `(user_id, game_id, attempt_number)`, retry once then `409`
- [x] Two simultaneous answer submissions for the same position → unique `(game_session_id, position)`, second gets `409`
- [x] Rake import running while players are drawing questions → import is additive; in-flight sessions are unaffected

### External Dependencies
- [x] Gemini timeout during grading → 8.5, session `abandoned`, error logged, player not penalized
- [x] Gemini returns malformed/unparseable output → treated as a failed call, same as timeout
- [x] Gemini không khả dụng → không ảnh hưởng lúc chơi, cả 5 game vẫn chấm được từ `answer_key`. Chỉ `rake questions:refill` thất bại và job theo lịch báo đỏ
- [ ] Gemini free tier limits unknown → see Open Questions Q2

## 17. Test Scenarios

### Happy Path
1. Register with `test.nta@gmail.com` → account created, logged in, `/games` shows 5 games with 0 points each
2. Play Bug Hunt, answer all 10 correctly and quickly → score 100, session `finished`, personal best 100, total 100
3. Play Bug Hunt again scoring 60 → personal best stays 100, total stays 100, a second `game_sessions` row exists
4. Play all 5 games → total equals the sum of the 5 per-game bests
5. Weekly, monthly and all-time leaderboards all list the player with consistent scores

### Edge Cases
1. Register with `test@gmail.com` → `422 EMAIL_NOT_ALLOWED`
2. Submit an answer with a `score` field in the payload → field ignored, server-computed score applied
3. Submit the same `position` twice → second call returns `409 POSITION_CONFLICT`, score unchanged
4. Submit `position: 5` when `current_position` is 2 → `409`
5. Start a session, close the browser, wait past the cutoff → session becomes `abandoned` with reason `timeout`, absent from leaderboards, still counted against the rate limit
6. Bug Hunt answered perfectly and fast on all 10 questions → exactly 100; answering 8 perfectly then 2 wrong → 80, session runs to question 10 (100 is unreachable before the final step, per §8.1 note)
7. PROD Roulette: pick the "send real email" option → 0 points for that step, session ends, consequence text shown, points from earlier steps are kept (BR-31)
8. Escape Room: exceed 30 simulated minutes after scoring 40 across steps → final score 40, no time bonus, post-mortem shown
9. Hide every Bug Hunt question, then start a session → `422 NO_QUESTIONS_AVAILABLE`
10. Two users tie at 500 points → the one with the smaller sum of per-game `attempts_to_best` ranks higher (BR-11a)
11. A player with 40 prior all-time attempts and a newcomer both reach 100 on their 2nd attempt this week → they tie on `attempts_to_best` in the weekly board, broken only by `finished_at` (BR-10)
12. Escape Room session: `steps_per_session = 8` while `questions_per_session = 1` → the session serves 8 steps from one scenario and ends at step 8 (BR-30)
13. Spec Detective: tick đúng 2/3 câu mơ hồ và tick sai 1 câu → nửa điểm tick = `floor((2-1)/3*10)` = 3; chọn đúng phương án → +10; tổng 13/20 cho đoạn đó (BR-26)
14. Play Bug Hunt twice in a row → the second session draws questions the player has not yet answered correctly, as long as fresh ones remain (BR-32)

### Security Tests
1. Call `POST /api/v1/sessions/:id/answers` for another user's session → `403`
2. Inspect any API response for `answer_key` → must be absent everywhere
3. 6 consecutive failed logins → account locked, `403 ACCOUNT_LOCKED` for 15 minutes
4. Non-admin calls `DELETE /admin/users/:id` → `403`
5. Send `elapsed_ms: 0` after actually taking 90 seconds → server-measured time wins, ×0.5 multiplier applied
6. Exceed 60 sessions in a day → `429`
7. Send a JSON `POST` to any gameplay endpoint without the `X-CSRF-Token` header → `422`, no session created and no answer recorded. Must be checked against a running server: the test environment disables forgery protection, so a request spec alone cannot catch a missing token (§13)

### Accessibility Tests
1. Play a full Bug Hunt session using only the keyboard → arrow keys move the line selection, Enter selects, the bug-type control is reachable by Tab, and the session can be completed without a mouse (§15)
2. Every interactive control has an accessible name, and the current selection is announced by a screen reader

### Performance Tests
1. 30 concurrent users starting sessions → all succeed, p95 under 300ms
2. Leaderboard query against 100,000 `game_sessions` rows → under 300ms with the cache cold

## 18. Open Questions

- [x] **Q1**: Duyệt gem `rack-attack` để làm rate limit? → **Owner xác nhận 2026-08-19: duyệt.** Đã có trong `Gemfile` và đang chạy ở `config/initializers/rack_attack.rb`.
- [x] **Q2**: Hạn mức và điều khoản gói free Gemini API hiện hành là gì? → **Đã verify 2026-08-19 từ trang chính thức của Google**, chi tiết ở §20. Tóm tắt: Google KHÔNG còn công bố bảng hạn mức cố định (phải xem trong AI Studio của từng project), và điều khoản Unpaid Services nói rõ Google dùng nội dung gửi lên để cải thiện sản phẩm, có người thật đọc/annotate, kèm câu "Do not submit sensitive, confidential, or personal information to the Unpaid Services". Từng cần owner quyết định (Q9) vì Spec Detective gửi text người chơi tự gõ; từ 1.19 không còn gửi nữa.
- [x] **Q3**: Ruby version và Rails version chốt là bao nhiêu? → **Owner xác nhận 2026-08-19**: Ruby 4.0.5, Rails 8.1.3.1, MySQL 8.4, adapter `mysql2`. Đã điền vào `CLAUDE.md`.
- [x] **Q4**: Ai chịu trách nhiệm soát file YAML trước khi `rake questions:import`? → **Owner quyết 2026-08-19: KHÔNG cần người soát tay.** Đề do AI sinh được import trực tiếp. Hệ quả phải biết: lưới an toàn duy nhất còn lại là luồng người chơi báo câu sai (`POST /api/v1/questions/:id/reports`) rồi admin ẩn câu đó (BR-16, BR-18) — tức là sai sót chỉ được phát hiện SAU khi đã có người chơi bị chấm sai. Bù lại, `Questions::Importer` validate cấu trúc từng đề theo game và riêng Bug Hunt còn kiểm `buggy_line` có nằm trong phạm vi `code_lines` và `bug_type` có thuộc `Question::BUG_HUNT_TYPES`, nên lỗi cấu trúc không lọt vào DB. Cái không kiểm được là đáp án có ĐÚNG về nghiệp vụ hay không.
- [x] **Q5**: Hosting ở đâu, có HTTPS và backup DB chưa? → **Owner chốt 2026-08-19: Render, gói Hobby.** Ba phần của câu hỏi này: (1) HTTPS — đã xong từ trước bằng `force_ssl` + `assume_ssl` trong `production.rb`, không phụ thuộc nền tảng; (2) thời gian lưu log — Render Hobby là 7 ngày, đã điền vào §14 và trang chính sách; (3) backup DB — phụ thuộc nhà cung cấp DB, tách thành Q10. Render không có managed MySQL nên DB bắt buộc dùng dịch vụ ngoài.
- [ ] **Q6**: KPI đo thành công của app là gì (số người chơi/tuần? số lượt/người?) → **Owner/PM**. Chưa có thì sau 3 tháng không có cơ sở đánh giá có nên duy trì không.
- [x] **Q7**: Có cần trang chính sách riêng tư không, khi app public và lưu email người dùng? → **Đã làm 2026-08-19** (BR-38): `GET /privacy`, guest đọc được, có link ở footer mọi trang và ở trang đăng ký. Q9 chọn gói Gemini free nên trang này là bắt buộc chứ không còn tuỳ chọn. Còn phụ thuộc Q8 (kênh liên hệ xoá tài khoản) và Q5 (thời gian lưu log) — hai chỗ đó trang nói rõ là chưa chốt.
- [x] **Q8**: Người dùng muốn xoá tài khoản thì liên hệ admin bằng đường nào? → **Owner chốt 2026-08-19: `hoangnm.nta@gmail.com`.** Set qua biến `PRIVACY_CONTACT_EMAIL`, hiện trên `/privacy`. Ghi nhận rủi ro owner đã chấp nhận: đây là email cá nhân trên một trang guest đọc được, nên bot quét email sẽ thấy. Muốn đổi sang mailbox dùng chung thì chỉ cần đổi biến môi trường, không sửa code.
- [x] **Q9**: Có chấp nhận gửi text người chơi tự gõ ở Spec Detective sang gói Gemini **free** không? → **Owner chốt 2026-08-19: phương án (a) — chấp nhận.** **Hết hiệu lực từ 1.19**: BR-26 đổi game sang dạng chọn nên không còn text người chơi nào được gửi đi. Chi tiết ở §20.
- [x] **Q10**: Dùng nhà cung cấp MySQL nào? → **Owner chốt 2026-08-19: Aiven for MySQL, gói free.** Chọn được vì là MySQL thật nên thực thi foreign key đầy đủ — điều kiện bắt buộc vì 7 bảng dựa vào FK `CASCADE`/`RESTRICT` và BR-38 đã hứa với người dùng là xoá tài khoản sẽ xoá luôn dữ liệu chấm AI. Neon bị loại vì là PostgreSQL only. TiDB Cloud bị loại vì FK chỉ GA từ TiDB v8.5.0 và chưa xác nhận được TiDB Cloud Serverless có thực thi FK; dung lượng 25GiB của họ cũng không cần thiết. PlanetScale bị loại vì đã bỏ free tier (thấp nhất 39 USD/tháng).
  > Hạn mức gói free: 1GB RAM / 1GB disk / 1 CPU, `max_connections` 76, có backup, không cần thẻ, dùng vĩnh viễn. Đủ rộng: nguồn phình nhanh nhất là `ai_gradings` mà nó bị hạn mức Gemini 20 request/ngày chặn sẵn — khoảng 2.4KB mỗi dòng, tức ~17MB/năm.
  > Hai điều kiện của gói free phải biết: **service bị tắt nếu không hoạt động** (cộng với web service Render gói Hobby cũng tự ngủ, nên request đầu sau khi ngủ có thể chậm hoặc lỗi), và không có SLA/support, chỉ một service mỗi loại.
  > **CHƯA verify**: version MySQL cụ thể của Aiven. Cần kiểm trong console khi tạo service vì §19 yêu cầu ≥ 8.0.16 để CHECK constraint được thực thi (dưới bản đó MySQL bỏ qua âm thầm). Validation ở tầng model vẫn chặn nên không vỡ, nhưng cần biết.

Giả định tạm khi chưa có câu trả lời (ghi rõ để sau này truy được):
- Q3 → dùng Rails và Ruby bản ổn định mới nhất tại thời điểm `rails new`
- Q7 → chưa làm trang chính sách ở Phase 1

## 19. Dependencies & Impact

- **Phụ thuộc vào**:
  - MySQL **8.0.16 trở lên** — JSON column cho `content` / `answer_key`, và CHECK constraint chỉ được thực thi từ version này. Chạy trên bản thấp hơn thì CHECK bị bỏ qua mà không báo lỗi. Đừng suy từ số version: `rake db:preflight` đo trực tiếp bằng cách thử ghi `score = 999` qua `update_column` (bỏ qua validation của model) và xem DB có chặn không, đồng thời kiểm TLS bằng `Ssl_cipher` của chính phiên đang kết nối. Task này an toàn để chạy trên production — phép thử nằm trong transaction và luôn rollback
  - Gemini **3.6 Flash** API — **chỉ dùng offline** để sinh đề (`rake questions:generate`, `rake questions:refill`). Từ 1.19 không có lời gọi nào lúc chơi: cả 5 game chấm từ `answer_key` trong DB, nên Gemini hỏng không ảnh hưởng người chơi. Spec ban đầu chốt 2.5 Flash nhưng model đó đã bị Google đóng với API key mới (§20). Model đổi được qua biến `GEMINI_MODEL`. Hạn mức free tier đo được là **20 request/ngày cho mỗi model** — từ 1.19 toàn bộ hạn mức đó dành cho sinh đề, xem §20
  - `bcrypt` gem (`has_secure_password`)
  - `rack-attack` gem — **owner đã duyệt** 2026-08-19 (Q1)
  - `dotenv-rails` gem (chỉ development) và `redis` gem — **owner đã duyệt** 2026-08-19
  - **Render** — nơi chạy app, gói Hobby. Hạ tầng khai trong `render.yaml` ở gốc repo (web service runtime docker + Key Value), `REDIS_URL` nối tự động bằng `fromService` nên không phải copy tay. Kéo theo: Render **không có managed MySQL** (chỉ Postgres và Key Value) nên DB phải dùng dịch vụ ngoài; filesystem ephemeral nên cache phải là Render Key Value; **BR-24 hiện KHÔNG có scheduler** — Render tính phí cron theo phút, không có gói free, nên cron job cố ý không nằm trong `render.yaml`. Tác động của việc thiếu nó đã rà: leaderboard không ảnh hưởng (chỉ đếm lượt `finished`, BR-08), rate limit không ảnh hưởng (rack_attack đếm request), và `GameSessions::Creator` không kiểm lượt `in_progress` đang mở nên lượt treo không chặn người chơi — mất thật sự chỉ là độ chính xác của `abandoned_reason` cho thống kê **Từ 1.19 BR-24 đã có scheduler**: `.github/workflows/questions-refill.yml` chạy `rake questions:refill`, mà task đó gọi `game_sessions:expire_stale` trước tiên — GitHub Actions theo lịch là miễn phí nên không phát sinh chi phí Render
  - **Aiven for MySQL** gói free — DB production (Q10). Đã provision và đo: MySQL 8.4.8, TLS `verify_identity`, CHECK constraint được thực thi, `max_connections` 76. Aiven đặt SSL ENABLED và không tắt được, **và CA riêng của họ không nằm trong trust store của OS**, nên **file CA là bắt buộc**: đã test thật, bỏ `sslca` mà chỉ để `ssl_mode: required` vẫn báo `CERT_E_UNTRUSTEDROOT`. Vì vậy CA được **commit trong repo** tại `config/aiven-ca.pem` (self-signed Project CA, không chứa private key, hạn 2036) thay vì dùng Render Secret File — Secret File chỉ thêm được sau khi service tồn tại, mà service không boot được khi thiếu CA, nên lần deploy đầu chắc chắn fail. Không dùng service URI của Aiven làm `DATABASE_URL` vì scheme `mysql://` làm Rails đi tìm adapter `mysql` thay vì `mysql2`
- **Ảnh hưởng đến**: không có module hiện hữu nào — repo greenfield
- **Migration cần thiết**: YES — 7 bảng mới, tạo theo thứ tự `users` → `games` → `questions` → `game_sessions` → `session_answers` → `ai_gradings` → `question_reports`
- **Breaking change**: NO — bản phát hành đầu tiên
- **Scheduled task**: `.github/workflows/questions-refill.yml` chạy 19:00 UTC (02:00 giờ VN) mỗi ngày, gọi `rake questions:refill` → task này chạy `game_sessions:expire_stale` (BR-24) rồi sinh + nạp đề cho game đang thiếu. Chạy ngoài app nên chưa cần queue system. **Điều kiện tiên quyết chưa verify**: IP của GitHub runner là động nên service Aiven phải cho phép mọi IP; nếu Aiven bật Allowed IP addresses thì phải chuyển sang Render Cron Job (`type: cron`, ~1 USD/tháng)

## 20. Gemini API — hạn mức, model và điều khoản (verify 2026-08-19)

Đây là kết quả trả lời Open Question Q2. Ghi rõ nguồn để sau này verify lại được, và tách rõ
phần đo được bằng lời gọi thật với phần chỉ đọc từ tài liệu.

### Đã verify bằng LỜI GỌI THẬT (bằng chứng mạnh nhất — chính API trả về)

| Điểm | Kết luận đo được |
|---|---|
| Hạn mức ngày | **20 request/NGÀY cho mỗi model** ở free tier. Nguyên văn HTTP 429: `Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20, model: gemini-3.6-flash`. Đây là con số phải dùng để thiết kế, KHÔNG dùng số từ nguồn thứ ba |
| `gemini-2.5-flash` | **Không dùng được với API key mới.** HTTP 404: `This model models/gemini-2.5-flash is no longer available to new users. Please update your code to use models/gemini-3.6-flash`. `gemini-2.5-flash-lite` cũng trả 404 y hệt |
| Model đang dùng | `gemini-3.6-flash` (đổi bằng biến `GEMINI_MODEL`, không cần sửa code) |
| Thinking không tắt được | `generationConfig.thinkingConfig.thinkingBudget = 0` bị trả HTTP 400 `Request contains an invalid argument` |
| Field điều khiển thinking | Trên endpoint `v1beta:generateContent` là `generationConfig.thinkingConfig.thinkingBudget` (số token). `thinkingLevel` đặt ngay dưới `generationConfig` bị trả 400 `Unknown name "thinkingLevel"` — trang docs `/gemini-api/docs/thinking` mô tả API shape khác, không áp dụng cho endpoint này |
| Thinking token tính vào `maxOutputTokens` | Có. Đặt `maxOutputTokens: 256` làm model tiêu hết budget vào thinking rồi dừng với `finishReason: MAX_TOKENS` mà chưa sinh nội dung nào |
| Độ trễ theo thinking budget | Cùng một prompt chấm Spec Detective: `thinkingLevel: "low"` → **10.6s** (vượt hard timeout 10s của §15); `thinkingBudget: 128` → vượt 10s với bài trả lời dài; `thinkingBudget: 32` → **2.3 / 2.9 / 3.6 / 5.2s** qua 4 lần đo. Nên chốt 32 cho đường chấm lúc chơi |
| Lỗi tạm thời cần chịu được | HTTP 503 `This model is currently experiencing high demand` xuất hiện ngẫu nhiên giữa lô sinh đề. Circuit breaker (§15) đếm nó như một lần lỗi Gemini |

### Đã verify từ trang chính thức của Google

| Điểm | Kết luận | Nguồn |
|---|---|---|
| Bảng hạn mức free tier | Google **không còn công bố** bảng số cố định trong docs, chỉ ghi phải xem trong AI Studio của từng project. Con số thật ở bảng trên lấy từ chính response 429 | `ai.google.dev/gemini-api/docs/rate-limits` |
| Điều khoản Unpaid Services | Google "uses the content you submit to the Services and any generated responses to provide, improve, and develop Google products and services". Có **người thật** đọc: "human reviewers may read, annotate, and process your API input and output" — được ngắt khỏi Google Account / API key / Cloud project trước khi reviewer xem | `ai.google.dev/gemini-api/terms` |
| Cảnh báo dữ liệu | Nguyên văn: "Do not submit sensitive, confidential, or personal information to the Unpaid Services" | `ai.google.dev/gemini-api/terms` |
| Người dùng EEA / Thuỵ Sĩ / UK | Phải dùng Paid Services, điều khoản dữ liệu khác | `ai.google.dev/gemini-api/terms` |

### Hệ quả: 20 request/ngày chỉ còn chi phối việc SINH ĐỀ (viết lại ở 1.19)

**Cho tới 1.18, hạn mức này gần như làm Spec Detective không chơi được.** Mỗi lượt 5 đoạn = 5 lời
gọi Gemini, nên 20 request/ngày = **4 lượt Spec Detective mỗi ngày cho TOÀN HỆ THỐNG**. Ba lớp
chặn từng được dựng lên chỉ để sống với con số đó: throttle `sessions/spec_detective/user` 1
lượt/ngày/user, `Gemini::DailyBudget` bound tổng (BR-37), và đường `503 AI_QUOTA_EXHAUSTED`.

**1.19 bỏ nguyên nhân thay vì tiếp tục vá triệu chứng.** Spec Detective đổi sang dạng chọn (BR-26)
nên chấm từ `answer_key` như 4 game còn lại, và cả ba lớp chặn trên được xoá cùng lúc: không còn
trần 4 lượt/ngày, không còn 1 lượt/ngày/user, không còn 503 nào trên đường chơi.

Kéo theo hai điều về hạn mức:

- **Sinh đề là người dùng Gemini DUY NHẤT.** Cả 20 request/ngày đều dùng được cho việc sinh đề, và
  một request sinh tối đa 5 đề (2 đề với hai game kịch bản) → tối đa **100 đề/ngày**. Không còn
  chuyện "sinh đề tranh hạn mức với người chơi", nên cũng không cần API key thứ hai.
- **`Gemini::DailyBudget` đã bị xoá.** Lớp đó đếm `ai_gradings` trong 24h trượt, mà từ 1.19 không
  có dòng `ai_gradings` mới nào nên con số luôn bằng 0 — giữ lại chỉ là code chết báo tin sai.
  Trần request của job hằng ngày được bound theo cách khác: `Questions::Refiller` xử lý tối đa
  `MAX_TARGETS_PER_RUN` mục tiêu mỗi lần chạy, và `Questions::Generator` gọi tối đa
  `ceil(count / batch_size) + EXTRA_BATCH_ALLOWANCE` request cho một mục tiêu.

Lưới an toàn ở tầng dưới vẫn là circuit breaker: 429 là `Gemini::Error` nên sau 5 lần liên tiếp
breaker mở 5 phút, hạn chế việc nện API vô ích. Job hằng ngày cố ý chạy KHÔNG có `REDIS_URL` nên
breaker của nó tách khỏi web service.


### Rủi ro dữ liệu người dùng — Q9 đã hết hiệu lực từ 1.19

Owner từng chốt phương án (a): chấp nhận gửi text người chơi tự gõ ở Spec Detective sang gói free,
biết rằng nội dung đó có thể được người thật của Google đọc và dùng để cải thiện sản phẩm của
Google.

**Rủi ro này không còn tồn tại.** BR-26 đổi Spec Detective sang dạng chọn nên người chơi không gõ
text nào nữa, và không có game nào gọi Gemini lúc chơi. Nội dung duy nhất còn gửi sang Google là
prompt sinh đề, do app tự dựng và không chứa dữ liệu người dùng.

Hai hạng mục từng bắt buộc vì Q9, và hiện trạng của chúng:

- Trang chính sách riêng tư (Q7) **vẫn giữ** nhưng §2 được viết lại: nói rõ nội dung người chơi
  nhập không đi ra khỏi app, và Gemini chỉ được dùng ngoài lúc chơi để soạn đề.
- Cảnh báo "không dán nội dung nội bộ/bí mật" trên màn Spec Detective **đã xoá** — không còn ô gõ
  để dán vào.

Điều còn lại: bảng `ai_gradings` giữ nguyên các dòng cũ (có chứa text người chơi đã gõ trước 1.19)
và trang `/privacy` vẫn công bố việc đó, vì xoá tài khoản vẫn là cách duy nhất xoá dữ liệu đó.


## 21. Change Log

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.19 | 2026-08-20 | HoangNM | **Bỏ Gemini khỏi đường chơi.** BR-26 viết lại: Spec Detective đổi từ gõ text tự do sang dạng CHỌN — tick những câu còn mơ hồ trong đoạn spec (10đ, trừ điểm tick sai) và chọn câu hỏi làm rõ tốt nhất trong 4 phương án (10đ) — nên chấm hoàn toàn từ `answer_key` như 4 game còn lại. Lý do: hạn mức free 20 request/ngày × 5 bước/lượt = **4 lượt/ngày cho toàn hệ thống**, và ba lớp chặn dựng lên để sống với con số đó (throttle 1 lượt/ngày/user, `Gemini::DailyBudget`/BR-37, đường `503 AI_QUOTA_EXHAUSTED`/`GRADING_UNAVAILABLE`) đều là vá triệu chứng. Cả ba đã xoá cùng `Gemini::SpecDetectiveGrader`, §8.5 và `Scoring::Base::GradingUnavailable`. Hệ quả tích cực: không còn giới hạn lượt chơi, không cần API key thứ hai, và người chơi không gõ gì nên **không có dữ liệu người dùng nào ra khỏi app** — §20/Q9 và trang `/privacy` viết lại theo. Thêm job hằng ngày `.github/workflows/questions-refill.yml` → `rake questions:refill`: chạy `game_sessions:expire_stale` trước (BR-24 lần đầu có scheduler, miễn phí qua GitHub Actions), rồi sinh + nạp đề cho game đang thiếu. Ba trần bắt buộc trong `Questions::Refiller`: **bỏ qua game còn lượt in_progress** (nạp đề giữa lượt làm pool đổi → `Questions::Drawer` bốc câu khác → chấm theo câu người chơi chưa thấy, phá BR-36), chỉ sinh khi dưới ngưỡng 3× `questions_per_session`, và tối đa 1 mục tiêu mỗi lần chạy. Luật validate đề tách ra `Questions::Validator` để import file và task chuyển đổi dùng cùng một luật. `rake questions:convert_spec_detective` chuyển 5 đề format cũ bằng Gemini, chạy một lần sau deploy |
| 1.18 | 2026-08-19 | HoangNM | Sửa hai lỗi làm fail Docker build trên Render, cả hai ở bước `bundle install`: (1) `Gemfile.lock` sinh trên Windows chỉ có `PLATFORMS: x64-mingw-ucrt` trong khi Dockerfile đặt `BUNDLE_DEPLOYMENT=1` → exit code 16 `Bundler::ProductionError`; sửa bằng `bundle lock --add-platform x86_64-linux` và thêm `spec/gemfile_lock_spec.rb` làm guard vì CI không bắt được. (2) Build stage thiếu `default-libmysqlclient-dev` nên gem `mysql2` không compile → exit code 5. Đã build và CHẠY image thật với DB Aiven: `/up`, `/privacy`, `/` đều 200, `db:preflight` từ trong container báo `verify_identity` với `sslca=/rails/config/aiven-ca.pem`. Xác nhận luôn Thruster bind `0.0.0.0` nên `HTTP_PORT=10000` là đủ |
| 1.17 | 2026-08-19 | HoangNM | Chốt `region: oregon` cho cả hai service Render, khớp service Aiven ở bờ Tây Mỹ — region phải khớp Aiven chứ không khớp vị trí người chơi vì đo được một lần bấm "Bắt đầu lượt" sinh 11 query, còn chặng người dùng↔Render chỉ đi một lần. **Sửa một điều tôi ghi sai**: thiếu file CA KHÔNG phải là hạ cấp âm thầm xuống `required` — test thật cho thấy Aiven vẫn báo `CERT_E_UNTRUSTEDROOT` vì CA riêng của họ không có trong trust store OS, tức là không kết nối được. Do đó CA được commit tại `config/aiven-ca.pem` thay vì dùng Render Secret File (Secret File chỉ thêm được sau khi service tồn tại → lần deploy đầu chắc chắn fail, và phải lặp lại cho từng service cần DB) |
| 1.16 | 2026-08-19 | HoangNM | Provision DB production trên Aiven for MySQL và đo bằng `db:preflight`: **MySQL 8.4.8** (đạt yêu cầu >= 8.0.16 của §19), TLS `TLS_AES_256_GCM_SHA384` với `verify_identity`, **CHECK constraint được thực thi thật**, `max_connections` 76 đúng như tài liệu gói free. Nạp 5 game, admin, và 83 câu hỏi. **Sửa lại mô tả điều kiện seed** ở §12: `prepare_all` seed khi bảng `schema_migrations` chưa tồn tại (tức DB chưa có schema, kể cả DB đã tồn tại mà còn trống), không phải "DB vừa được tạo" như ghi trước đó — `defaultdb` của Aiven tồn tại sẵn nên phân biệt này quan trọng |
| 1.15 | 2026-08-19 | HoangNM | Thêm `script/aiven.ps1` + `.env.aiven.example`: chạy `db:preflight` và `db:prepare` lên DB production mà mật khẩu chỉ nằm trong file gitignored, không vào history của shell hay chat/ticket. `-Prepare` là cờ riêng vì bước đó ghi thật lên production. `db:preflight` bổ sung hai đường lỗi cho đúng mục đích dùng: DB chưa có schema thì SKIP phép kiểm CHECK thay vì nổ `StatementInvalid`, và lỗi kết nối/sai mật khẩu/thiếu DB thì báo bằng thông báo có host thay vì backtrace |
| 1.14 | 2026-08-19 | HoangNM | Thêm `render.yaml` khai hạ tầng Render (web service runtime docker + Key Value gói free), thay cho việc bấm tay trong dashboard. `REDIS_URL` nối tự động bằng `fromService` — bỏ được bước copy tay dễ quên nhất, mà quên thì throttle hỏng chỉ với một dòng cảnh báo trong log. Không có giá trị bí mật nào trong file: 7 biến khai `sync: false` để Render hỏi lúc tạo. Cron job cho BR-24 **cố ý không** nằm trong file vì Render tính phí cron theo phút, không có gói free; §19 ghi rõ tác động của việc thiếu nó sau khi rà code |
| 1.13 | 2026-08-19 | HoangNM | Thêm `rake db:preflight` (`lib/tasks/db_checks.rake`): đo MySQL version, TLS bằng `Ssl_cipher` của phiên đang kết nối, CHECK constraint bằng cách thử `update_column(:score, 999)`, và `max_connections` so với pool. Thay hai chỗ "chưa verify" ở §19 và runbook bằng một lệnh đo được. An toàn trên production: phép thử CHECK nằm trong transaction và luôn rollback. Runbook thêm mục 2.7 — chuẩn bị schema và seed từ máy local trước khi tạo web service, để lỗi hiện trên terminal và không phụ thuộc vào việc `db:prepare` chỉ seed đúng một lần |
| 1.12 | 2026-08-19 | HoangNM | Thêm runbook `docs/deploy/render-aiven.md`. **Đảo quyết định cũ về mật khẩu admin** (§12): `db/seeds.rb` đọc `ENV["ADMIN_PASSWORD"]` thay vì hardcode, vì phát hiện đường lộ cụ thể — `db:prepare` tự seed ở lần boot đầu nên admin với mật khẩu đã biết sẽ có mặt trên URL public, mà app không có chức năng đổi mật khẩu. Production thiếu biến thì BỎ QUA tạo admin chứ không abort, để không để lại DB có schema mà không có `games`. Runbook ghi 3 điểm dễ fail đã verify: thứ tự Aiven trước Render (entrypoint chạy `db:prepare` lúc boot), `HTTP_PORT=10000` (thruster listen `HTTP_PORT` mặc định 80 và tự ghi đè `PORT`), và Render KHÔNG tự tiêm biến cho Key Value nên `REDIS_URL` phải set tay |
| 1.11 | 2026-08-19 | HoangNM | Đóng Q10 (**Aiven for MySQL** gói free — chọn theo tiêu chí phải thực thi FK thật vì BR-38 hứa xoá tài khoản là xoá dữ liệu chấm AI) và Q8 (`hoangnm.nta@gmail.com`, set qua `PRIVACY_CONTACT_EMAIL`). `config/database.yml` thêm cấu hình TLS cho production vì Aiven bắt buộc SSL; ghi rõ bẫy scheme `mysql://` của service URI Aiven. Chỉ còn Q6 (KPI) mở |
| 1.10 | 2026-08-19 | HoangNM | Chốt Q5: hosting là **Render gói Hobby** → log giữ **7 ngày**, điền vào §14 và trang chính sách qua `PagesController::LOG_RETENTION_DAYS`. Thêm gem `redis` và chuyển cache store production sang Redis khi có `REDIS_URL`: bắt buộc vì filesystem Render là ephemeral/per-instance nên file store làm rack_attack (throttle 1 lượt/ngày) và circuit breaker mất trạng thái mỗi lần deploy — gói Hobby còn tự ngủ khi hết traffic. Mở **Q10**: Neon là PostgreSQL only nên không dùng được, cần chọn nhà cung cấp MySQL có thực thi FK; ghi rõ hiện trạng Aiven / PlanetScale / TiDB đã verify. §19 ghi nhận Render không có managed MySQL và BR-24 cần Render Cron Job riêng |
| 1.9 | 2026-08-19 | HoangNM | BR-38: trang `/privacy` (guest đọc được, link ở footer mọi trang + trang đăng ký), cảnh báo không dán nội dung nội bộ ở cả panel intro và ngay trên ô gõ của Spec Detective. Đóng Q7. **Sửa sai §14**: spec ghi "logs rotate at 30 days" nhưng production log ra STDOUT và app không có cấu hình rotation nào — thời gian lưu do nền tảng vận hành quyết định (Q5), nên trang chính sách không nêu con số. Bổ sung công bố Google Fonts nhận IP người dùng — trước đây không có ở đâu trong spec |
| 1.8 | 2026-08-19 | HoangNM | BR-37: bound tổng hạn mức Gemini ở tầng ứng dụng bằng `Gemini::DailyBudget` — đếm `ai_gradings` trong 24h trượt thay vì thêm throttle rack_attack, vì cần đếm cả lời gọi thất bại và cần trạng thái dùng chung nhiều host. Chặn TRƯỚC khi tạo lượt nên người chơi không mất lượt vì trần hệ thống; mã lỗi mới `AI_QUOTA_EXHAUSTED` ở §5.2. Trang game và card ở /games hiện số lượt còn lại và disable nút khi hết. Xoá đoạn cảnh báo cũ ở màn Spec Detective (nói Phase 3 chưa chơi được) vì đã lỗi thời |
| 1.7 | 2026-08-19 | HoangNM | Owner chốt hạ throttle `sessions/spec_detective/user` từ 5 lượt/giờ xuống **1 lượt/ngày** cho khớp hạn mức Gemini free 20 request/ngày. Cập nhật bảng rate limit §12 và BR-34. Ghi rõ phần CHƯA xử lý: hạn mức theo user không bound được tổng hệ thống, cần thêm throttle discriminator hằng số — kèm đánh đổi về trải nghiệm nên chưa tự làm |
| 1.6 | 2026-08-19 | HoangNM | Gọi Gemini thật lần đầu, §20 viết lại bằng số đo từ chính API thay vì nguồn thứ ba: hạn mức free là **20 request/ngày mỗi model** (không phải 250), `gemini-2.5-flash` đã bị đóng với key mới nên chuyển sang `gemini-3.6-flash`, thinking không tắt được và phải chốt `thinkingBudget: 32` mới kịp hard timeout 10s của §15. Nêu rõ xung đột giữa hạn mức 20/ngày và BR-34 (5 lượt Spec Detective/giờ/user) — chưa xử lý trong code, cần quyết định. Đóng Q1, Q2, Q3, Q4, Q9; Q7 (trang chính sách) chuyển từ known gap thành hạng mục bắt buộc do Q9 chọn gói free |
| 1.5 | 2026-08-19 | HoangNM | Phase 3: trả lời Open Question Q2 và bổ sung §20 (hạn mức + điều khoản Gemini, kèm phần chưa verify được); mở Q9 xin owner quyết việc gửi text người chơi sang gói free; chi tiết hoá circuit breaker ở §15; BR-36 (câu hỏi của một bước phải ổn định) — phát hiện khi verify Phase 3 rằng câu server chấm không phải câu đã hiển thị; ghi rõ ở §6 là project không có dotenv |
| 1.4 | 2026-08-19 | HoangNM | Bug Hunt phân đề theo ngôn ngữ lập trình: BR-35, cột `questions.language` + `game_sessions.language` và index `index_questions_on_game_language_hidden` ở §4.2, tham số `language` cho `POST /api/v1/games/:slug/sessions` và mã lỗi `INVALID_LANGUAGE` ở §5. Ngân hàng câu hỏi mẫu hiện có php/ruby/java, mỗi ngôn ngữ 10 câu |
| 1.0 | 2026-08-18 | HoangNM | Initial draft, tổng hợp từ `docs/clarify/clarify_skill-arcade.md` (5 vòng clarify) |
| 1.3 | 2026-08-18 | HoangNM | Bổ sung yêu cầu CSRF token cho JSON endpoint vào §13, kèm mã lỗi `INVALID_CSRF_TOKEN` ở §5.2 và test scenario ở §17. Phát hiện khi chạy server thật ở Phase 1: JSON POST không kèm `X-CSRF-Token` bị trả 422, trong khi request spec vẫn xanh vì môi trường test tắt forgery protection |
| 1.2 | 2026-08-18 | HoangNM | Xử lý 4 suggestion từ `/nta-spec-review`: `display_name` UNIQUE; ghi rõ MySQL tối thiểu 8.0.16 cho CHECK constraint; nêu retention và phạm vi truy cập của nội dung người dùng trong `ai_gradings.prompt`; thêm nhóm Accessibility Tests cho điều hướng Bug Hunt bằng bàn phím |
| 1.1 | 2026-08-18 | HoangNM | Xử lý 4 blocker + 7 warning từ `/nta-spec-review`: Escape Room chuyển sang mô hình cộng dồn (BR-27, BR-31); tách `steps_per_session` khỏi `questions_per_session` (BR-30); định nghĩa `attempts_to_best` theo chu kỳ (BR-10) và cho bảng tổng (BR-11a); chính sách bốc câu chưa trả lời đúng (BR-32); thêm `abandoned_reason` và miễn trừ rate limit khi lỗi hệ thống (BR-33); làm rõ thứ tự áp dụng rate limit (BR-34); chốt cách làm tròn Bug Hunt (BR-21); nâng số câu hỏi tối thiểu; bổ sung 5 test scenario |

---

## 22. Tóm tắt xác nhận *(dành cho team review — xoá trước khi gửi ra ngoài)*

**Tính năng**: Skill Arcade — web app luyện năng lực dev/BA qua 5 mini-game có chấm điểm và bảng xếp hạng.

**Mục đích**: Biến việc học rule và luyện kỹ năng (code review, đặt câu hỏi làm rõ spec, xử lý incident, ước lượng task, an toàn PROD) thành hoạt động ngắn có phản hồi tức thì, thay cho đọc tài liệu.

**Những điểm cần team xác nhận**:
- [ ] Business rule: BR-06 (personal best), BR-09 (đạt 100 không khoá game), BR-10/11/11a (tie-break theo số lượt, tính riêng cho từng chu kỳ và cho bảng tổng), BR-13/14 (tuần bắt đầu thứ Hai, múi giờ `Asia/Ho_Chi_Minh`), BR-25→29 (công thức điểm 5 game), BR-31 (mọi game đều cộng dồn, không trừ điểm), BR-32 (ưu tiên câu chưa trả lời đúng)
- [ ] Data: 7 bảng mới; đặc biệt `game_sessions` phải lưu **từng lượt** chứ không chỉ điểm cao nhất — đây là điều kiện để có leaderboard tuần/tháng và tie-break. `games` tách `questions_per_session` và `steps_per_session` (BR-30)
- [ ] Luồng ngoại lệ: 8.2 (PROD Roulette kết thúc ngay khi chọn hành động không thu hồi được), 8.5 (Gemini lỗi thì lượt không tính điểm, không phạt người chơi)
- [ ] Open Questions: chỉ còn **Q6** (KPI đo thành công của app). Q1–Q5 và Q7–Q10 đã đóng, xem §18

**Ảnh hưởng đến phần khác**: không có module hiện hữu. Phụ thuộc ngoài: Gemini API, MySQL 8, 2 gem cần duyệt.

**Không nằm trong scope lần này**:
- Phần thưởng vật chất gắn với leaderboard
- Xác thực email khi đăng ký, 2FA, OAuth, quên mật khẩu
- Người dùng tự xoá tài khoản
- Đa ngôn ngữ (chỉ tiếng Việt)
- Estimate Poker nhiều người vote cùng lúc (chỉ solo)
- Màn hình admin duyệt câu hỏi (thay bằng soát file YAML lúc import)
- Đo velocity thật của team qua Estimate Poker — `actual` là số do AI sinh, không phải dữ liệu công việc thật
