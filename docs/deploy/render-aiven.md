# Deploy Skill Arcade — Render (app) + Aiven (MySQL)

Runbook cho lần deploy đầu. Mọi con số và tên biến trong này đã verify từ tài liệu chính thức
hoặc từ chính code của repo; chỗ nào chưa verify được thì ghi rõ.

Chốt ở spec §18: hosting **Render gói Hobby** (Q5), DB **Aiven for MySQL gói free** (Q10).

---

## 0. Thứ tự bắt buộc: Aiven trước, Render sau

`bin/docker-entrypoint` chạy `./bin/rails db:prepare` mỗi khi container khởi động với lệnh mặc
định. Không có DB kết nối được thì web service **fail ngay lúc boot**, không phải fail lúc có
request đầu tiên. Nên phải có thông số Aiven trước khi tạo web service.

Khuyến nghị mạnh: **chuẩn bị schema và seed từ máy local** (mục 2.7) trước khi tạo web service.
Lỗi hiện ngay trên terminal, và kiểm được TLS + CHECK constraint bằng `rake db:preflight` trước
khi tốn một lượt deploy.

Phần Render đã được khai sẵn trong `render.yaml` ở gốc repo, nên bước 3 là apply Blueprint chứ
không phải bấm tay từng service.

## 1. Mật khẩu admin — set `ADMIN_PASSWORD` TRƯỚC lần deploy đầu

`db/seeds.rb` đọc mật khẩu admin từ `ENV["ADMIN_PASSWORD"]` (owner đảo quyết định cũ ngày
2026-08-19, xem spec §12 và §18).

Vì sao phải set trước lần deploy đầu chứ không set sau:

1. Aiven DB mới tạo là trống
2. Container khởi động → `bin/docker-entrypoint` chạy `./bin/rails db:prepare`
3. `ActiveRecord::Tasks::DatabaseTasks.prepare_all` đặt `seed = true if database_initialized &&
   db_config.seeds?`, và `initialize_database` trả `!database_already_initialized` với
   `database_already_initialized` = **bảng `schema_migrations` có tồn tại hay không**. Nên điều
   kiện seed chính xác là **DB chưa có schema**, không phải "DB vừa được tạo" — một DB đã tồn tại
   mà còn trống (đúng trường hợp `defaultdb` của Aiven) vẫn bị seed. Và đây là **lần duy nhất** nó
   tự chạy: lần sau `schema_migrations` đã có nên không seed nữa

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

### 2.4 CA certificate — đã commit trong repo, không phải tải lại

`config/aiven-ca.pem` đã có trong repo. Chỉ phải tải lại nếu bạn dùng project Aiven khác.

**File CA là BẮT BUỘC với Aiven**, không phải tuỳ chọn. Đã test cả hai đường thiếu:

| Thiếu gì | Lỗi thật |
|---|---|
| `sslca` trỏ vào file không tồn tại | `TLS/SSL error: failed to open file` |
| Bỏ hẳn `sslca`, chỉ để `ssl_mode: required` | `Server certificate validation failed … CERT_E_UNTRUSTEDROOT` |

Đường thứ hai fail vì CA riêng của Aiven không nằm trong trust store của OS. Nên bỏ CA **không**
phải là "vẫn chạy nhưng mất xác thực server" — nó là không kết nối được.

Cách `database.yml` xử lý:

- `DB_SSL_CA` có VÀ file tồn tại → `ssl_mode: verify_identity` (mã hoá + xác thực server)
- ngược lại → `ssl_mode: required`, và `production.rb` ghi cảnh báo nêu rõ nguyên nhân. Với Aiven
  thì nhánh này vẫn không kết nối được; nó chỉ biến lỗi cert khó hiểu thành lỗi có nội dung
- `DB_SSL_MODE` ghi đè thủ công nếu cần

Nếu tải lại CA từ console: file tải về tên mặc định là `ca.pem`, đổi thành `config/aiven-ca.pem`.
CA hiện tại là self-signed Project CA, **hạn đến 16/08/2036**.

### 2.5 Hai điều kiện của gói free phải biết

- **Service bị tắt nếu không hoạt động.** Cộng với web service Render gói Hobby cũng tự ngủ khi
  hết traffic, nên request đầu sau một thời gian im ắng có thể chậm hoặc lỗi. Không phải bug.
- `max_connections` = **76**. App dùng pool 5 (`RAILS_MAX_THREADS` mặc định 5) × 1 instance, cộng
  cron job lúc chạy — thoải mái.
- Không có SLA, không có support, một service mỗi loại.

### 2.6 Dung lượng 1GB có đủ không

Đủ nhiều năm. Nguồn phình nhanh nhất là `ai_gradings` (giữ vĩnh viễn theo BR-19), nhưng nó bị hạn
mức Gemini 20 request/ngày chặn sẵn: đo thật một dòng khoảng 2.4KB → ~48KB/ngày → **~17MB/năm**.

### 2.7 Chuẩn bị DB từ máy local TRƯỚC, đừng để Render tự làm

Về nguyên tắc Render tự lo được: entrypoint chạy `db:prepare`. Nhưng làm từ local tốt hơn ở ba
điểm: thấy lỗi ngay trên terminal thay vì phải đọc log deploy, kiểm được TLS và CHECK constraint
trước khi tốn một lượt deploy, và tự chọn thời điểm seed thay vì phụ thuộc vào "DB vừa được tạo"
(mục 1). Sau bước này Render boot lên chỉ thấy DB đã sẵn sàng.

Dùng `script/aiven.ps1` thay vì gõ biến ra dòng lệnh — mật khẩu DB production không nên nằm trong
history của shell, trong log CI, hay trong chat/ticket.

**Bước 1** — copy template rồi điền thông số lấy từ console Aiven:

```powershell
Copy-Item .env.aiven.example .env.aiven
notepad .env.aiven
```

`.env.aiven` nằm trong `.gitignore` (`/.env*`) nên không bị commit. `.env.aiven.example` có ngoại
lệ `!/.env.aiven.example` để template vẫn theo repo.

**Bước 2** — kiểm trước, script này KHÔNG ghi gì lên DB:

```powershell
powershell -File script/aiven.ps1
```

Script in ra đích kết nối và trạng thái CA (cố ý **không** in `DB_PASSWORD`), rồi chạy
`db:preflight`. Trên DB còn trống thì phép kiểm CHECK constraint sẽ ra `SKIP` — bình thường, vì
chưa có bảng nào.

**Bước 3** — tạo schema + seed. Bước này **ghi thật lên DB production**:

```powershell
powershell -File script/aiven.ps1 -Prepare
```

Script bắt buộc có `ADMIN_PASSWORD` trong `.env.aiven` mới cho chạy `-Prepare`, vì `db:prepare`
chỉ tự seed **đúng một lần** lúc DB vừa được tạo — thiếu biến ở đúng lần đó là mất luôn cơ hội tạo
admin tự động.

Chạy xong `-Prepare` script tự chạy lại `db:preflight`, và lần này CHECK constraint phải ra `OK`.

### 2.8 `db:preflight` kiểm những gì

| Kiểm | Ý nghĩa |
|---|---|
| MySQL version | Phải >= 8.0.16 (§19). Đây là cách trả lời câu hỏi ở 2.2 mà không phải tự suy từ số version |
| TLS | Đo bằng `Ssl_cipher` của **chính phiên đang kết nối**, không đọc config. Config khai đúng mà server không bật thì vẫn ra kết nối trần — cách này bắt được |
| CHECK constraint | Thử `update_column(:score, 999)` để bỏ qua validation của model, xem DB có chặn không. Trả lời trực tiếp câu "MySQL bản này có thực thi CHECK không" thay vì suy từ version |
| max_connections | So với pool của app |

Phép kiểm CHECK nằm trong transaction và luôn rollback nên không để lại bản ghi nào. Task **abort**
nếu version thấp hoặc CHECK không được thực thi, nên nó chặn được việc deploy lên một DB không đạt.

Chạy lại `db:preflight` một lần nữa sau khi deploy lên Render, **từ Render**, để chắc chắn service
ở đó nối đúng DB và đúng TLS — không chỉ đúng ở máy dev.

---

## 2.9 Gemfile.lock phải khai platform Linux

Đã làm fail một lần deploy thật. `Gemfile.lock` sinh trên máy Windows chỉ ghi:

```
PLATFORMS
  x64-mingw-ucrt
```

`Dockerfile` đặt `BUNDLE_DEPLOYMENT="1"` nên bundler ở chế độ frozen và **không được tự thêm
platform**, khiến `bundle install` trong image Linux dừng với **exit code 16**
(`Bundler::ProductionError`):

```
error: failed to solve: process "/bin/sh -c bundle install && ..." did not complete
successfully: exit code: 16
```

Sửa:

```powershell
ruby -S bundle lock --add-platform x86_64-linux
```

**CI không bắt được lỗi này**: `ruby/setup-ruby` với `bundler-cache: true` không bật deployment
mode, nên nó lặng lẽ thêm platform vào lock của runner rồi chạy tiếp — CI xanh mà Docker build vẫn
đỏ. Vì vậy repo có `spec/gemfile_lock_spec.rb` để `rspec` bắt được, và spec đó đã được kiểm là
thật sự đỏ khi thiếu platform.

Mỗi lần chạy `bundle install`/`bundle update` trên Windows đều có thể làm mất dòng đó, nên nếu
Docker build fail ở bước `bundle install` thì kiểm chỗ này trước tiên.

## 2.10 Dockerfile phải có header dev của MySQL client

Lỗi thứ hai gặp ngay sau khi sửa platform, cùng bước `bundle install` nhưng **exit code 5**:

```
checking for -lmysqlclient... no
mysql client is missing. You may need to 'sudo apt-get install libmariadb-dev' ...
extconf failed, exit code 1
```

Build stage của `Dockerfile` do `rails new` sinh ra chỉ cài `build-essential git libvips libyaml-dev
pkg-config` — thiếu header dev để compile gem `mysql2`. Đã thêm **`default-libmysqlclient-dev`**.

Phân biệt hai gói dễ lẫn:

| Gói | Là gì | Ở stage nào |
|---|---|---|
| `default-libmysqlclient-dev` | **header dev**, cần để COMPILE gem mysql2 | build |
| `default-mysql-client` | **CLI** `mysql`, và kéo theo thư viện chia sẻ `libmariadb3` cần lúc CHẠY | base (đã có sẵn) |

Có `default-mysql-client` mà thiếu `default-libmysqlclient-dev` thì build fail — đúng trường hợp đã
gặp.

### Cách kiểm trước khi tốn một lượt deploy

Build VÀ chạy thử image tại máy, nếu có Docker. Đây là cách kiểm gần nhất với những gì Render làm:

```powershell
docker build -t skill-arcade:preflight .

# Chạy với env thật. Tạo file env cho docker từ .env.aiven, nhưng ĐỔI DB_SSL_CA sang đường dẫn
# TRONG image, và thêm HTTP_PORT + RAILS_MASTER_KEY.
docker run -d --name skill-arcade-test -p 3001:10000 --env-file <file env> skill-arcade:preflight
curl http://localhost:3001/up
docker exec skill-arcade-test ./bin/rails db:preflight
docker logs skill-arcade-test
```

Đã chạy đúng quy trình này ngày 2026-08-19 và tất cả xanh, gồm `db:preflight` từ trong container báo
`sslca=/rails/config/aiven-ca.pem` và `verify_identity`.

Hai lỗi ở 2.9 và 2.10 đều lộ ra ở bước này trong khoảng một phút, thay vì phải đợi Render build rồi
đọc log. **Lưu ý đọc đúng exit code của `docker build`**, đừng đọc exit code của lệnh bọc ngoài —
tôi đã một lần tưởng build thành công vì đọc exit code của `tail` đứng sau nó.

---

## 3. Render — deploy bằng Blueprint

Repo có `render.yaml` khai sẵn hạ tầng, nên không phải bấm tay từng service. Dashboard → **New**
→ **Blueprint** → chọn repo này.

`render.yaml` tạo hai service:

| Service | Loại | Vì sao |
|---|---|---|
| `skill-arcade` | web, runtime docker | Build từ `Dockerfile` có sẵn, `healthCheckPath: /up` |
| `skill-arcade-cache` | keyvalue (Redis) | **Bắt buộc**, xem 3.3 |

`REDIS_URL` được nối tự động bằng `fromService` nên **không phải copy tay** — đây là chỗ dễ quên
nhất nếu tạo tay, và quên là throttle hỏng trong im lặng.

Không có giá trị bí mật nào nằm trong `render.yaml`. Các biến khai `sync: false` sẽ được Render
**hỏi lúc tạo blueprint**.

### 3.1 Region đã chốt: `oregon`

`render.yaml` đặt `region: oregon` ở **cả hai** service, khớp với service Aiven ở bờ Tây Mỹ
(San Francisco). Hai service phải cùng region, không thì Key Value không dùng được đường nội bộ.

Vì sao khớp Aiven chứ không khớp vị trí người chơi — đo trên chính app này:

| Thao tác | Số query |
|---|---|
| Trang chủ (bảng xếp hạng) | 2 |
| `/games` | 2 |
| Bấm "Bắt đầu lượt" Bug Hunt + ra đề | **11** |

Chặng app↔DB đi **11 lần** mỗi lần bấm nút, còn chặng người dùng↔Render chỉ đi **một lần** mỗi
request. Đo thật từ Việt Nam tới Aiven là ~190ms, nên nếu đặt Render ở `singapore` thì một lần bấm
nút mất ~2,1 giây (11 × 190ms) chỉ để chờ DB — mọi query phải vượt Thái Bình Dương. Đặt ở `oregon`
thì chặng đó nằm trong cùng bờ Tây.

Đánh đổi đã chấp nhận: người chơi ở Việt Nam chịu ~190ms cho chặng tới Render, nhưng chặng đó đi
một lần.

Nếu sau này muốn tối ưu cho người chơi ở Việt Nam thì phải chuyển **cả hai** sang châu Á — chuyển
riêng Render là làm chậm đi, không phải nhanh lên.

**`plan`** — đang là `free` ở cả hai. Render từ chối thì nâng lên `starter`.

### 3.2 Render sẽ hỏi 7 giá trị này

| Biến | Lấy ở đâu |
|---|---|
| `RAILS_MASTER_KEY` | Nội dung file `config/master.key` trên máy dev. File đó gitignored và chưa commit nên Render không tự có. Không dán ra ngoài |
| `DB_HOST` `DB_PORT` `DB_USERNAME` `DB_PASSWORD` `DB_NAME` | Aiven, bước 2.3 |
| `ADMIN_PASSWORD` | Mật khẩu mạnh bạn tự chọn, xem mục 1 |
| `GEMINI_API_KEY` | Google AI Studio. Dùng key **mới** nếu key cũ từng bị dán ra ngoài |

Các biến đã có sẵn giá trị trong `render.yaml`, không phải nhập: `HTTP_PORT` (10000),
`REDIS_URL` (tự nối), `GEMINI_MODEL`, `PRIVACY_CONTACT_EMAIL`, `DB_SSL_CA`.

**Không cần set:**

- `SECRET_KEY_BASE` — đã verify `config/credentials.yml.enc` có sẵn `secret_key_base`, nên
  `RAILS_MASTER_KEY` là đủ
- `RAILS_ENV` — `Dockerfile` đã đặt `ENV RAILS_ENV="production"`
- `DATABASE_URL` — xem cảnh báo ở 2.3
- `RAILS_MAX_THREADS` — để trống thì mặc định 5, phù hợp với `max_connections` 76 của Aiven
- `PORT` — xem 3.4

### 3.3 Không cần Secret File

`config/aiven-ca.pem` đã nằm trong repo nên có sẵn trong Docker image: `Dockerfile` có
`WORKDIR /rails` và `COPY . .`, còn `.dockerignore` không loại trừ file đó (nó chỉ chặn `/.env*`,
`/config/master.key` và `/config/credentials/*.key`). `render.yaml` khai
`DB_SSL_CA=/rails/config/aiven-ca.pem`.

Vì sao **không** dùng Secret File của Render: Secret File chỉ thêm được **sau khi** service tồn
tại, mà service **không boot được khi thiếu CA** (xem 2.4) — nên lần deploy đầu chắc chắn fail,
rồi mới thêm file được, rồi deploy lại. Ngoài ra Secret File là per-service nên mọi service cần DB
(vd cron job ở mục 5) đều phải thêm lại.

CA certificate là thông tin công khai theo bản chất — server trình nó ra cho mọi client để xác
thực, và nó không chứa private key. Commit được, giống cách AWS ship RDS CA bundle trong code.

### 3.4 `HTTP_PORT` — chỗ dễ fail nhất, và vì sao `render.yaml` đặt nó

Render yêu cầu app listen trên `0.0.0.0` tại port trong biến `PORT`, **mặc định 10000**. Nhưng
`Dockerfile` chạy `CMD ["./bin/thrust", "./bin/rails", "server"]`, và theo README của gem
`thruster` 0.1.25:

- `HTTP_PORT` — port Thruster listen, **mặc định 80**
- `TARGET_PORT` — port Puma chạy, mặc định 3000. **Thruster tự ghi đè `PORT` thành giá trị này**
  khi khởi động Puma

Nghĩa là Thruster **không đọc `PORT` của Render** mà còn ghi đè nó. Render nói họ "usually able to
detect" port khác, nhưng không nên phụ thuộc vào chữ "usually" — nên `render.yaml` đặt thẳng
`HTTP_PORT: 10000`.

**Đã verify 2026-08-19**: Thruster CÓ bind `0.0.0.0`. Chạy image thật với `HTTP_PORT=10000` và port
map `3001:10000`, request từ ngoài container đi tới được (`remote_addr` là `172.17.0.1`), còn Puma
log `Listening on http://0.0.0.0:3000` — đúng như README nói, Thruster ghi đè `PORT` thành
`TARGET_PORT` cho Puma và tự listen ở `HTTP_PORT`. Nên `HTTP_PORT=10000` là đủ.

Phương án dự phòng dưới đây chỉ dùng nếu vì lý do khác mà Render không nhận ra port — bỏ Thruster,
khai thêm vào web service trong `render.yaml`:

```yaml
    dockerCommand: ./bin/rails server -b 0.0.0.0 -p 10000
```

Đánh đổi khi bỏ Thruster: mất X-Sendfile và nén cho file tĩnh. Chấp nhận được với app này. Lệnh
trên vẫn kết thúc bằng `./bin/rails server` nên entrypoint vẫn chạy `db:prepare` như bình thường.

### 3.5 Vì sao Key Value là bắt buộc, không phải tuỳ chọn

`config/environments/production.rb` dùng `:redis_cache_store` khi có `REDIS_URL`, không có thì vẫn
boot được bằng file store nhưng ghi cảnh báo vào log. Trên Render, file store là **sai**:
filesystem của Render là ephemeral và riêng từng instance, nên mỗi lần deploy hoặc spin down sẽ
mất:

- bộ đếm rack_attack — throttle số lượt chơi theo giờ/ngày (§12). Mất là người chơi được lượt mới. Web service gói free tự ngủ khi hết traffic nên throttle gần như vô hiệu
- trạng thái `Gemini::CircuitBreaker` (§15)

Từ 1.19 không có lời gọi Gemini nào lúc chơi, nên mất trạng thái breaker không ảnh hưởng người
chơi — chỉ job sinh đề chạy ngoài app bị ảnh hưởng, và job đó cố ý chạy không có `REDIS_URL`.

---

## 4. Nếu không dùng Blueprint

Tạo tay theo đúng thứ tự, dùng `render.yaml` làm bảng tra giá trị:

1. **Key Value** trước — cần connection string của nó ở bước sau. Chọn `ipAllowList` rỗng để chỉ
   truy cập nội bộ, `maxmemoryPolicy` = `noeviction`
2. **Web Service** — New → Web Service → chọn repo → runtime **Docker**, cùng region với Key Value
3. Copy **Internal URL** của Key Value trong menu Connect, đặt thành `REDIS_URL`. **Render KHÔNG
   tự tiêm biến này** khi tạo tay — đây là chỗ dễ quên nhất, và quên thì throttle hỏng mà không
   báo gì ngoài một dòng cảnh báo trong log
4. Set toàn bộ biến ở mục 3.2 cộng các biến có giá trị sẵn trong `render.yaml`, gồm
   `DB_SSL_CA=/rails/config/aiven-ca.pem`

Không cần thêm Secret File — CA đã nằm trong repo (mục 3.3).

---

## 5. Scheduler cho BR-24 và việc sinh đề — MIỄN PHÍ qua GitHub Actions

Từ 1.19 cả hai việc chạy trong cùng một job theo lịch: `.github/workflows/questions-refill.yml`
gọi `rake questions:refill`, và task đó chạy `game_sessions:expire_stale` (BR-24) trước tiên rồi
mới sinh + nạp đề cho game đang thiếu.

**Vì sao không dùng Render Cron Job:** Render tính phí cron theo phút, không có gói free (từ
khoảng 1 USD/tháng ở gói starter). Actions theo lịch miễn phí, nên cron job vẫn **không** nằm
trong `render.yaml`.

### Cần set gì

Secrets của repo (Settings → Secrets and variables → Actions):

| Secret | Giá trị |
|---|---|
| `RAILS_MASTER_KEY` | nội dung `config/master.key` |
| `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME` | thông số Aiven, giống hệt biến trên Render |
| `GEMINI_API_KEY` | key Gemini |

`DB_SSL_CA` và `GEMINI_MODEL` đã ghi thẳng trong workflow — CA nằm trong repo nên có ngay sau
checkout, không cần secret.

**KHÔNG set `REDIS_URL`.** Thiếu biến đó thì runner rơi về file store, nhờ vậy circuit breaker và
rack_attack của job tách hoàn toàn khỏi web service: job lỗi liên tiếp không mở breaker của
production.

### Điều kiện tiên quyết chưa verify

IP của GitHub runner là **động**. Nếu service Aiven đang bật **Allowed IP addresses** thì job
không kết nối được DB. Kiểm tra ở Aiven console → service → Allowed IP addresses:

- Cho phép mọi IP → dùng được Actions
- Có allowlist → phải chuyển sang **Render Cron Job** (`type: cron`, `plan: starter`, ~1 USD/tháng,
  command `./bin/rails questions:refill`). Cron job không kết thúc bằng `./bin/rails server` nên
  entrypoint sẽ KHÔNG chạy `db:prepare` — đúng ý, cron không nên đụng schema. Cần các biến `DB_*`
  + `DB_SSL_CA` + `RAILS_MASTER_KEY` + `GEMINI_API_KEY`; CA đã có trong image

### Chạy tay khi cần

Từ máy dev, với biến `DB_*` trỏ vào Aiven:

```bash
bin/rails questions:refill                     # dọn lượt quá hạn + sinh đề cho game đang thiếu
bin/rails questions:convert_spec_detective     # MỘT LẦN sau khi deploy 1.19
```

Task `refill` in ra từng mục tiêu kèm trạng thái, và exit code khác 0 khi có mục tiêu thất bại —
để scheduler báo đỏ thay vì im lặng.

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
9. **`rake db:preflight` từ chính Render** (one-off job hoặc shell nếu gói có) — xác nhận service ở đó
   nối đúng DB và đúng TLS, không chỉ đúng ở máy dev

## 7. Gỡ lỗi — những lần fail đã gặp thật

Ba lỗi dưới đây đều đã gặp trong lần deploy đầu ngày 2026-08-19, theo đúng thứ tự này. Sửa lỗi
trước mới lộ ra lỗi sau, và cả ba đều đã sửa trong repo.

### `bundle install` exit code 16

```
error: failed to solve: process "/bin/sh -c bundle install && ..." exit code: 16
```

`Bundler::ProductionError` — `Gemfile.lock` thiếu platform Linux. Xem mục 2.9.

### `bundle install` exit code 5

```
checking for -lmysqlclient... no
extconf failed, exit code 1
```

Thiếu `default-libmysqlclient-dev` ở build stage. Xem mục 2.10.

### `Missing secret_key_base for 'production' environment`

```
bin/rails aborted!
ArgumentError: Missing `secret_key_base` for 'production' environment
Tasks: TOP => db:prepare => db:load_config => environment
```

**`RAILS_MASTER_KEY` chưa được set trên service.** Rails không giải mã được `credentials.yml.enc`
nên không lấy được `secret_key_base` và dừng ngay lúc nạp environment — trước cả khi thử nối DB.

Nguyên nhân thường gặp: Render **chỉ hỏi các biến `sync: false` ở lần tạo blueprint đầu tiên**;
khi cập nhật blueprint sau đó nó BỎ QUA những biến này. Bỏ qua prompt nào ở lần đầu thì biến đó
không bao giờ được hỏi lại, phải set tay trong dashboard.

Vì lỗi này dừng ở bước nạp environment, nó **che mất** mọi biến thiếu khác. Nên khi sửa, hãy kiểm
**cả 7 biến `sync: false`** trong một lần thay vì sửa từng cái rồi deploy lại:

| Biến | Lấy ở đâu |
|---|---|
| `RAILS_MASTER_KEY` | `Get-Content config\master.key -Raw \| Set-Clipboard` — 32 ký tự hex, không có newline |
| `DB_HOST` `DB_PORT` `DB_USERNAME` `DB_PASSWORD` `DB_NAME` | `.env.aiven` trên máy dev |
| `ADMIN_PASSWORD` | mật khẩu mạnh bạn chọn |
| `GEMINI_API_KEY` | Google AI Studio |

Cách khác cho `secret_key_base`: set thẳng biến **`SECRET_KEY_BASE`**. Rails đọc
`ENV["SECRET_KEY_BASE"]` trước khi tìm trong credentials, nên nó bỏ qua hẳn chuỗi
credentials/master-key. `credentials.yml.enc` của repo này hiện **chỉ chứa `secret_key_base`** nên
làm vậy không mất gì. Chọn `RAILS_MASTER_KEY` nếu sau này muốn để thêm secret vào credentials.

### Lỗi kết nối DB

| Log | Nguyên nhân |
|---|---|
| `TLS/SSL error: failed to open file` | `DB_SSL_CA` trỏ vào đường dẫn không có file. Trên Render phải là `/rails/config/aiven-ca.pem` |
| `CERT_E_UNTRUSTEDROOT` | Không có CA. Xem mục 2.4 — với Aiven thì CA là bắt buộc |
| `Unknown database` | Sai `DB_NAME`. Aiven mặc định là `defaultdb` |
| `issue connecting ... username/password` | Sai `DB_USERNAME` / `DB_PASSWORD` |

Chạy `./bin/rails db:preflight` từ chính service (one-off job hoặc shell) để đọc được thông báo có
nội dung thay vì backtrace.

---

## 8. Việc sau deploy

- Ngân hàng câu hỏi chưa đạt mức tối thiểu §6. Hạn mức Gemini 20 request/ngày nên cần 3-4 ngày
  chạy `rake questions:generate`. `prod_roulette` hiện chưa có câu nào do AI sinh
- Aiven gói free không có backup dài hạn theo SLA. `ai_gradings` là bằng chứng duy nhất để giải
  trình khi người chơi khiếu nại điểm do AI chấm (BR-19), nên nếu dữ liệu này quan trọng thì cần
  kế hoạch backup riêng
