# Deploy Skill Arcade — Render (app) + Aiven (MySQL)

Runbook cho lần deploy đầu. Mọi con số và tên biến trong này đã verify từ tài liệu chính thức
hoặc từ chính code của repo; chỗ nào chưa verify được thì ghi rõ.

Chốt ở spec §18: hosting **Render gói Hobby** (Q5), DB **Aiven for MySQL gói free** (Q10).

---

## 0. Thứ tự bắt buộc: Aiven trước, Render sau

`bin/docker-entrypoint` chạy `./bin/rails db:prepare` mỗi khi container khởi động với lệnh mặc
định. Không có DB kết nối được thì web service **fail ngay lúc boot**, không phải fail lúc có
request đầu tiên. Nên phải có thông số Aiven trước khi tạo web service.

## 1. Mật khẩu admin — set `ADMIN_PASSWORD` TRƯỚC lần deploy đầu

`db/seeds.rb` đọc mật khẩu admin từ `ENV["ADMIN_PASSWORD"]` (owner đảo quyết định cũ ngày
2026-08-19, xem spec §12 và §18).

Vì sao phải set trước lần deploy đầu chứ không set sau:

1. Aiven DB mới tạo là trống
2. Container khởi động → `bin/docker-entrypoint` chạy `./bin/rails db:prepare`
3. `ActiveRecord::Tasks::DatabaseTasks.prepare_all` đặt `seed = true if database_initialized &&
   db_config.seeds?` — DB vừa được tạo nên **nó chạy `db/seeds.rb`**, và đây là **lần duy nhất**
   nó tự chạy. Lần deploy sau DB đã tồn tại nên không seed nữa

Nếu lúc đó chưa có `ADMIN_PASSWORD`, seed sẽ **bỏ qua** việc tạo admin (cố ý không tạo admin với
mật khẩu yếu trên URL public) và in ra:

```
admin: BỎ QUA — ADMIN_PASSWORD chưa được set ở production.
       Set biến đó rồi chạy lại `rails db:seed` để tạo tài khoản admin.
```

5 bản ghi `games` vẫn được tạo nên app chạy bình thường, chỉ là không có admin. Khắc phục: set
biến rồi chạy lại `rails db:seed` một lần (seed dùng `find_or_initialize_by` nên chạy lại an toàn)
— nhưng việc đó cần chỗ chạy lệnh, nên **set trước cho đỡ phiền**.

Development và test không set biến thì vẫn dùng `12345678` như trước, quy trình local không đổi.

## 2. Aiven for MySQL

### 2.1 Tạo service

Chọn service loại **MySQL**, plan **Free**. Chọn region gần region sẽ dùng cho Render để giảm
latency (gói free không cho chọn nhiều nơi, lấy cái gần nhất có sẵn).

### 2.2 Kiểm version MySQL — làm ngay, đừng bỏ qua

Spec §19 yêu cầu **MySQL ≥ 8.0.16**: dưới bản đó MySQL **bỏ qua CHECK constraint âm thầm**,
không báo lỗi. App có validation ở tầng model nên điểm vẫn không vượt 100 được (BR-04), nhưng
lưới an toàn ở tầng DB thì mất. Nếu Aiven cấp bản thấp hơn thì ghi lại vào spec §19 như một hạn
chế đã biết.

### 2.3 Lấy thông số kết nối

Từ trang overview của service, map sang biến môi trường của app:

| Aiven | Biến môi trường | Ghi chú |
|---|---|---|
| Host | `DB_HOST` | |
| Port | `DB_PORT` | Aiven không dùng 3306 |
| User | `DB_USERNAME` | mặc định của Aiven là `avnadmin` |
| Password | `DB_PASSWORD` | |
| Database name | `DB_NAME` | mặc định của Aiven là `defaultdb` |

**KHÔNG dùng Service URI của Aiven làm `DATABASE_URL`.** URI của họ bắt đầu bằng `mysql://`, mà
Rails suy ra tên adapter từ scheme nên sẽ đi tìm adapter `mysql` — không tồn tại, adapter đúng là
`mysql2`. Dùng các biến `DB_*` rời ở trên. Muốn dùng URL thì phải tự sửa scheme thành `mysql2://`.

### 2.4 Tải CA certificate

Aiven đặt SSL ở trạng thái **ENABLED và không tắt được**, nên `config/database.yml` bắt buộc khai
TLS. Tải file CA certificate trong console của service.

Cách `database.yml` xử lý:

- có `DB_SSL_CA` → `ssl_mode: verify_identity` (mã hoá **và** xác thực server, chống MITM)
- không có → tự hạ `ssl_mode: required` (vẫn mã hoá nhưng **không** xác thực server)
- `DB_SSL_MODE` ghi đè thủ công nếu cần

Không bao giờ tự tắt TLS. Nên cấp CA để được `verify_identity`.

### 2.5 Hai điều kiện của gói free phải biết

- **Service bị tắt nếu không hoạt động.** Cộng với web service Render gói Hobby cũng tự ngủ khi
  hết traffic, nên request đầu sau một thời gian im ắng có thể chậm hoặc lỗi. Không phải bug.
- `max_connections` = **76**. App dùng pool 5 (`RAILS_MAX_THREADS` mặc định 5) × 1 instance, cộng
  cron job lúc chạy — thoải mái.
- Không có SLA, không có support, một service mỗi loại.

### 2.6 Dung lượng 1GB có đủ không

Đủ nhiều năm. Nguồn phình nhanh nhất là `ai_gradings` (giữ vĩnh viễn theo BR-19), nhưng nó bị hạn
mức Gemini 20 request/ngày chặn sẵn: đo thật một dòng khoảng 2.4KB → ~48KB/ngày → **~17MB/năm**.

---

## 3. Render Key Value (Redis)

Tạo instance **Key Value**, **cùng region** với web service sẽ tạo ở bước 4.

Lấy **Internal URL** trong menu Connect (không dùng External URL — nó cần bật IP allow list và đi
qua đường public).

**Render KHÔNG tự tiêm biến môi trường cho Key Value.** Phải tự đặt Internal URL thành `REDIS_URL`
ở bước 4.

### Vì sao bắt buộc phải có Redis

`config/environments/production.rb` dùng `:redis_cache_store` khi có `REDIS_URL`, không có thì vẫn
boot được bằng file store nhưng ghi cảnh báo vào log. Trên Render, file store là **sai**:
filesystem của Render là ephemeral và riêng từng instance, nên mỗi lần deploy hoặc spin down sẽ
mất:

- bộ đếm rack_attack — gồm throttle **1 lượt/ngày** của Spec Detective (§12). Mất là người chơi
  được lượt mới. Gói Hobby tự ngủ khi hết traffic nên throttle gần như vô hiệu
- trạng thái `Gemini::CircuitBreaker` (§15)

`Gemini::DailyBudget` không bị ảnh hưởng vì đếm bảng `ai_gradings` chứ không dùng cache (BR-37).

---

## 4. Render Web Service

### 4.1 Tạo service

New → **Web Service** → kết nối repo → runtime **Docker** (repo đã có `Dockerfile`). Region phải
**cùng region với Key Value** ở bước 3.

Không cần khai build command hay start command: `Dockerfile` đã có `ENTRYPOINT` và `CMD`.

### 4.2 Secret File cho CA certificate

Environment → Secret Files → thêm file, dán nội dung CA certificate tải ở bước 2.4.

Render mount secret file tại **`/etc/secrets/<tên file>`**. Đặt tên `aiven-ca.pem` thì path là
`/etc/secrets/aiven-ca.pem` — đúng giá trị mẫu trong `.env.example`.

### 4.3 Biến môi trường

| Biến | Giá trị | Lấy ở đâu |
|---|---|---|
| `RAILS_MASTER_KEY` | nội dung file `config/master.key` | Trên máy dev. File này **gitignored và chưa commit** nên Render không tự có. Không dán ra ngoài |
| `DB_HOST` | | Aiven, bước 2.3 |
| `DB_PORT` | | Aiven, bước 2.3 |
| `DB_USERNAME` | thường là `avnadmin` | Aiven, bước 2.3 |
| `DB_PASSWORD` | | Aiven, bước 2.3 |
| `DB_NAME` | thường là `defaultdb` | Aiven, bước 2.3 |
| `DB_SSL_CA` | `/etc/secrets/aiven-ca.pem` | Path của secret file ở bước 4.2 |
| `REDIS_URL` | Internal URL | Render → Key Value → Connect, bước 3 |
| `HTTP_PORT` | `10000` | Xem 4.4 |
| `GEMINI_API_KEY` | | Google AI Studio. Dùng key **mới** nếu key cũ đã từng bị dán ra ngoài |
| `GEMINI_MODEL` | `gemini-3.6-flash` | Cố định. `gemini-2.5-flash` đã bị Google đóng với key mới (§20) |
| `PRIVACY_CONTACT_EMAIL` | `hoangnm.nta@gmail.com` | Chốt ở Q8. Chưa set thì trang `/privacy` ghi "chưa công bố kênh liên hệ" |
| `ADMIN_PASSWORD` | mật khẩu mạnh do bạn chọn | Xem mục 1. **Phải set trước lần deploy đầu**, không thì seed bỏ qua việc tạo admin |

**Không cần set:**

- `SECRET_KEY_BASE` — đã verify `config/credentials.yml.enc` có sẵn `secret_key_base`, nên
  `RAILS_MASTER_KEY` là đủ
- `RAILS_ENV` — `Dockerfile` đã đặt `ENV RAILS_ENV="production"`
- `DATABASE_URL` — xem cảnh báo ở 2.3
- `RAILS_MAX_THREADS` — để trống thì mặc định 5, phù hợp với `max_connections` 76 của Aiven

### 4.4 `HTTP_PORT` — chỗ dễ fail nhất ở lần deploy đầu

Render yêu cầu app listen trên `0.0.0.0` tại port trong biến `PORT`, **mặc định 10000**. Nhưng
`Dockerfile` chạy `CMD ["./bin/thrust", "./bin/rails", "server"]`, và theo README của gem
`thruster`:

- `HTTP_PORT` — port Thruster listen, **mặc định 80**
- `TARGET_PORT` — port Puma chạy, mặc định 3000. **Thruster tự ghi đè `PORT` thành giá trị này**
  khi khởi động Puma

Nghĩa là Thruster **không đọc `PORT` của Render** mà còn ghi đè nó. Render nói họ "usually able to
detect" port khác, nhưng không nên phụ thuộc vào chữ "usually".

Cách chắc chắn: set **`HTTP_PORT=10000`** để Thruster listen đúng chỗ Render chờ.

**Chưa verify**: Thruster có bind vào `0.0.0.0` hay chỉ `127.0.0.1` — README không nói. Nếu deploy
vẫn fail vì Render không thấy port, phương án dự phòng là bỏ Thruster và cho Puma bind trực tiếp,
bằng cách khai Docker Command của service:

```
./bin/rails server -b 0.0.0.0 -p 10000
```

Đánh đổi khi bỏ Thruster: mất X-Sendfile và nén cho file tĩnh. Chấp nhận được với app này.

Lưu ý: lệnh dự phòng trên vẫn kết thúc bằng `./bin/rails server` nên entrypoint vẫn chạy
`db:prepare` như bình thường.

---

## 5. Render Cron Job — BR-24

BR-24 yêu cầu lượt để quá 24 giờ phải được đánh dấu `abandoned` với lý do `timeout`. Việc này chạy
bằng rake task, cần một scheduler bên ngoài. Trên Render đó là **Cron Job** — một service riêng,
không đi kèm web service.

- Cùng repo, cùng `Dockerfile`
- Command: `./bin/rails game_sessions:expire_stale`
- Lịch: mỗi giờ là đủ (task chỉ tìm lượt đã quá 24 giờ)
- Env var cần: các biến `DB_*` và `DB_SSL_CA`, cộng `RAILS_MASTER_KEY`. Không cần `GEMINI_*` hay
  `REDIS_URL`

Command này **không** kết thúc bằng `./bin/rails server` nên entrypoint sẽ không chạy `db:prepare`
— đúng như mong muốn, cron job không nên can thiệp schema.

---

## 6. Verify sau khi deploy

Theo thứ tự, dừng lại ở bước đầu tiên fail:

1. **Health check**: `GET /up` trả 200
2. **Redis đã nối chưa**: tìm trong log dòng
   `[cache] REDIS_URL chưa được set`. **Có dòng này nghĩa là Redis CHƯA nối** và throttle sẽ không
   đáng tin
3. **Trang chính sách**: `GET /privacy` trả 200 (không cần đăng nhập), hiện đúng email liên hệ, và
   ghi "Log ứng dụng giữ 7 ngày"
4. **Bảng xếp hạng**: `GET /` trả 200 mà không cần đăng nhập
5. **Đăng nhập admin** được
6. **Throttle Spec Detective**: tạo lượt Spec Detective 2 lần liên tiếp → lần 1 phải 201, lần 2
   phải **429** kèm thông điệp về hạn mức 1 lượt/ngày
7. **Trạng thái sống sót qua deploy**: bấm redeploy, rồi thử tạo lượt Spec Detective lần nữa → vẫn
   phải **429**. Nếu ra 201 thì cache đang là file store, không phải Redis — quay lại bước 2
8. **Hạn mức AI hiển thị**: mở `/games/spec_detective`, phải thấy số lượt còn lại của hệ thống

## 7. Việc sau deploy

- Ngân hàng câu hỏi chưa đạt mức tối thiểu §6. Hạn mức Gemini 20 request/ngày nên cần 3-4 ngày
  chạy `rake questions:generate`. `prod_roulette` hiện chưa có câu nào do AI sinh
- Aiven gói free không có backup dài hạn theo SLA. `ai_gradings` là bằng chứng duy nhất để giải
  trình khi người chơi khiếu nại điểm do AI chấm (BR-19), nên nếu dữ liệu này quan trọng thì cần
  kế hoạch backup riêng
