# skill-arcade

## Tech Stack
- Language: Ruby
- Framework: Ruby on Rails
- Database: MySQL
- Architecture: Monolith MVC

> Version Ruby/Rails/MySQL: điền sau khi chạy `rails new` (đọc từ `.ruby-version`, `Gemfile.lock`).

## Project Conventions

### Naming
- Classes, Modules: PascalCase (`User`, `OrdersController`, `OrderCreator`)
- Methods, variables: snake_case (`find_by_email`, `total_price`)
- Predicate methods: hậu tố `?` (`active?`, `paid?`)
- Destructive/raising methods: hậu tố `!` (`save!`, `update!`)
- Constants: SCREAMING_SNAKE_CASE (`MAX_RETRY_COUNT`)
- File name: snake_case khớp tên class (`orders_controller.rb` → `OrdersController`)
- Model: danh từ số ít (`User`); table: số nhiều snake_case (`users`)
- Controller: số nhiều + hậu tố `Controller` (`OrdersController`)
- Route path: số nhiều snake_case theo mặc định Rails (`/order_items`)

### Architecture
Monolith MVC theo cấu trúc chuẩn Rails:

- `app/controllers/` — nhận request, xác thực/phân quyền, gọi model hoặc service, render response. Không chứa business logic phức tạp
- `app/models/` — ActiveRecord model: association, validation, scope, business rule gắn với entity
- `app/views/` — ERB template
- `app/services/` — business logic nhiều bước hoặc liên quan nhiều model (quy ước bổ sung, không phải mặc định Rails). Mỗi class 1 việc, entry point là `call`
- `app/jobs/` — background job (ActiveJob)
- `app/mailers/` — gửi email
- `app/helpers/` — helper cho view, không chứa business logic
- `config/routes.rb` — định nghĩa route, ưu tiên `resources` thay vì khai báo từng route thủ công
- `db/migrate/` — migration

### DB Conventions
- Table naming: snake_case số nhiều (`users`, `order_items`)
- PK: `id` (BIGINT AUTO_INCREMENT — mặc định Rails 5.1+)
- FK columns: `{table_số_ít}_id` (`user_id`, `order_id`), luôn kèm index
- Timestamp: `created_at`, `updated_at` (DATETIME) — dùng `t.timestamps`
- Soft delete: `deleted_at` (DATETIME, nullable)
- Boolean: `is_{name}` hoặc tính từ (`active`, `published`) — NOT NULL kèm default
- Index: đặt tên mặc định Rails, hoặc `index_{table}_on_{column}` khi cần chỉ định
- Charset: `utf8mb4` / collation `utf8mb4_unicode_ci`
- Mọi thay đổi schema đi qua migration; KHÔNG sửa tay `db/schema.rb`

### API Response Format
HTTP status là signal, body là data:

```json
200: { "id": 1, "name": "..." }
404: { "code": "NOT_FOUND", "message": "User not found" }
422: { "errors": [{ "field": "email", "message": "Invalid email" }] }
```

### Error Handling
- Custom exception kế thừa `StandardError`, gom trong `app/errors/` hoặc namespace riêng
- Xử lý tập trung bằng `rescue_from` trong `ApplicationController`
- `rescue StandardError` hoặc class cụ thể — KHÔNG `rescue Exception`
- Trong service: raise exception hoặc trả về result object, nhất quán 1 kiểu trong toàn project
- Dùng `save!` / `update!` khi lỗi là bất thường; dùng `save` / `update` khi cần xử lý nhánh false

### Test Conventions
- Framework: RSpec (`rspec-rails`) — nếu project dùng Minitest, cập nhật lại section này
- Location: `spec/models/`, `spec/requests/`, `spec/services/`, `spec/jobs/`
- Naming: `describe ClassName` > `context 'khi ...'` > `it 'trả về ...'`
- Test data: FactoryBot, không dùng fixture
- Test behavior, không test implementation

## Lệnh thường dùng
```bash
bundle install
bin/rails server
bin/rails console
bin/rails db:create db:migrate
bin/rails db:seed
bin/rails generate migration AddStatusToOrders status:string
bundle exec rspec
bundle exec rubocop
```

## Quy tắc của project
- Thay đổi schema chỉ qua migration — không sửa `db/schema.rb` bằng tay
- Strong parameters bắt buộc ở controller (`params.require(...).permit(...)`) — không truyền `params` trực tiếp vào model
- Không nội suy chuỗi vào SQL — dùng placeholder (`where('name = ?', name)`) hoặc hash condition
- Phòng N+1: dùng `includes` / `preload` khi lặp qua association
- Business logic nhiều bước đặt ở `app/services/`, không viết trong controller
- Secrets qua `Rails.credentials` hoặc ENV, không hardcode
