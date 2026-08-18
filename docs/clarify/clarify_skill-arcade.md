# Clarification Report — Skill Arcade

**Ngày**: 2026-08-18
**Người yêu cầu**: HoangNM (owner)
**Trạng thái**: Đã đóng toàn bộ BLOCKER. Sẵn sàng chuyển sang viết spec.
**Số vòng Q&A**: 5

---

## 1. Tổng quan

Web app luyện tập năng lực dev/BA qua 5 mini-game, có tài khoản, tích điểm và bảng
xếp hạng. Repo greenfield — chưa có code, stack đã chốt ở `CLAUDE.md`:
Ruby on Rails + MySQL + Monolith MVC.

### 5 mini-game

| Game | Cơ chế | Mục tiêu rèn luyện |
|---|---|---|
| Bug Hunt | Hiện snippet 10-20 dòng, người chơi click dòng có bug + chọn loại bug | Code review cho junior |
| Spec Detective | Cho đoạn requirement, tìm câu mơ hồ + viết câu hỏi làm rõ, AI chấm | Kỹ năng đặt câu hỏi trước khi họp khách hàng |
| Incident Escape Room | Kịch bản sự cố, chọn hành động theo lượt, mỗi lựa chọn tốn thời gian giả lập | Drill xử lý incident |
| Estimate Poker | Ước tính task, so với "actual" do AI định sẵn | Cảm giác chia nhỏ và ước lượng task |
| PROD Roulette | Mô phỏng thao tác trên PROD, chọn sai thì hiện hậu quả | Onboarding, nhớ rule an toàn PROD |

---

## 2. Quyết định đã chốt

### 2.1 Phạm vi và dữ liệu

| Hạng mục | Quyết định |
|---|---|
| Nguồn nội dung câu hỏi | **KHÔNG** lấy bug thật từ Backlog khách hàng |
| Kịch bản PROD Roulette | Tình huống **hư cấu**, không dùng incident nội bộ thật (con số 60k USD chỉ là ví dụ) |
| Phạm vi truy cập | **Public** trên internet |
| Scope lần này | Làm cả **5 game** |
| Ngôn ngữ | Chỉ **tiếng Việt** |
| Phần thưởng | **Hoãn** — phase 1 leaderboard chỉ mang tính ghi nhận |

> Hai quyết định đầu đã loại bỏ rủi ro lớn nhất của dự án: rò rỉ dữ liệu khách hàng
> ra bên thứ ba và lộ thông tin incident nội bộ.

### 2.2 AI

| Hạng mục | Quyết định |
|---|---|
| Provider | Gemini 2.5 Flash |
| Cách dùng | **Sinh sẵn theo lô** → lưu DB → lúc chơi đọc từ DB (chi phí AI khi chơi ≈ 0) |
| Ngoại lệ | Spec Detective gọi AI **real-time** để chấm câu trả lời tự do |
| Màn hình admin duyệt câu hỏi | **Không làm** |
| Điểm AI chấm không tất định | **Chấp nhận** |
| Log AI | **Có lưu** prompt + response + điểm mỗi lần chấm |

**Chưa verify**: hạn mức và điều khoản gói free của Gemini API — phải đọc trang chính
thức của Google trước khi triển khai.

### 2.3 Tính điểm và xếp hạng

- Mỗi game thang điểm **tối đa 100** → điểm tổng tối đa **500**
- Mỗi lượt chơi bắt đầu từ **0 điểm**
- Điểm của game = **điểm cao nhất từ trước tới nay** (personal best); chơi lại chỉ
  thay thế khi cao hơn
- Đạt 100 điểm → **kết thúc lượt, KHÔNG khoá game** (vẫn chơi lại được, điểm không tăng)
- Leaderboard có đủ **all-time / tuần / tháng**, không reset
- **Tie-break**: ai đạt bằng ít lượt hơn xếp trên; bằng nữa thì ai đạt trước xếp trên
- **Lượt bỏ dở không tính điểm** (session không có `finished_at` bị loại)

#### Ràng buộc schema bắt buộc

Phải lưu **từng lượt chơi**, không chỉ lưu điểm cao nhất:

```
game_sessions: user_id, game_id, score, started_at, finished_at
```

Personal best, cả 3 chu kỳ leaderboard và tie-break đều **suy ra** từ bảng này.
Nếu chỉ lưu một cột `best_score` trên user thì leaderboard tuần/tháng không làm được,
và sửa sau phải migrate lại toàn bộ dữ liệu điểm.

#### Cách quy đổi thang 100 và điều kiện kết thúc lượt

| Game | Một lượt gồm | Quy đổi 100 điểm | Lượt kết thúc khi |
|---|---|---|---|
| Bug Hunt | 10 snippet | Mỗi snippet 10đ: đúng dòng 6đ + đúng loại bug 4đ. Hệ số tốc độ: dưới 30s ×1.0, 30-60s ×0.8, trên 60s ×0.5 | Hết 10 snippet |
| Spec Detective | 5 đoạn spec | Mỗi đoạn 20đ do AI chấm: tìm đủ điểm mơ hồ (10đ) + chất lượng câu hỏi làm rõ (10đ). Không tính tốc độ | Hết 5 đoạn |
| Incident Escape Room | 1 kịch bản | Bắt đầu 100đ. Mỗi phút giả lập vượt mốc 15 phút trừ 2đ. Hành động sai trừ 10đ + tốn thêm thời gian giả lập | Recover xong, hoặc quá 30 phút giả lập (0đ) |
| Estimate Poker | 10 task | Mỗi task 10đ theo sai số: tới 10% được 10đ, tới 25% được 7đ, tới 50% được 4đ, trên 50% được 0đ | Hết 10 task |
| PROD Roulette | 1 kịch bản, 10 bước | Mỗi bước 10đ: an toàn 10đ, rủi ro khôi phục được 3đ, hành động không thể thu hồi 0đ và kết thúc lượt ngay | Hết 10 bước, hoặc chạm hành động không thể thu hồi |

> PROD Roulette dừng ngay khi chọn hành động không thu hồi được — đó chính là bài học
> của game: gửi email thật, tạo giao dịch thật thì không có "dọn dẹp sau".

### 2.4 Tài khoản và quyền

| Hạng mục | Quyết định |
|---|---|
| Auth | Email/password **tự quản lý** (không OAuth) |
| Allowlist đăng ký | Chỉ chấp nhận email dạng `*.nta@gmail.com` |
| Xoá tài khoản | **Chỉ admin** — người dùng không tự xoá được |
| Admin seed | `hoangnm.nta@gmail.com` / mật khẩu `12345678` **hardcode trong `db/seeds.rb`** |
| Quyền admin | Xoá tài khoản, xử lý báo cáo câu hỏi sai (đánh `hidden`, không xoá cứng) |
| Báo câu hỏi sai | **Có** nút cho người chơi |

> **Ghi chú rủi ro (để giải trình sau)**: mật khẩu admin `12345678` hardcode trong
> seed, trên app public. Đã đề xuất phương án thay thế (đọc từ ENV + ép đổi mật khẩu
> lần đầu), owner quyết định giữ hardcode. Rủi ro: tài khoản admin có thể bị chiếm
> nếu seed này chạy trên production.
>
> **Ghi chú rủi ro**: allowlist `*.nta@gmail.com` không chặn được người cố ý — bất kỳ
> ai cũng đăng ký được Gmail dạng này. Rate limit là lớp bảo vệ thật, không phải allowlist.

### 2.5 Rate limit

| Hành động | Giới hạn |
|---|---|
| Đăng ký | 5 lần/giờ/IP |
| Đăng nhập sai | 5 lần thì khoá tài khoản 15 phút; 20 lần/15 phút/IP |
| Bắt đầu lượt chơi | 20 lượt/giờ/user, 60 lượt/ngày/user |
| Lượt Spec Detective (gọi AI) | 5 lượt/giờ/user (khoảng 25 API call/giờ/user) + circuit breaker khi Gemini lỗi/timeout |
| Báo câu hỏi sai | 10 lần/ngày/user |
| Toàn cục | 100 request/phút/IP |

**Dependency đề xuất**: gem `rack-attack` — **chưa được duyệt**, cần owner xác nhận
trước khi đưa vào `Gemfile`.

### 2.6 Quy trình nạp câu hỏi

```bash
rake questions:generate[bug_hunt,50]   # gọi Gemini, xuất db/question_banks/bug_hunt/20260818.yml
# người xem qua file YAML, sửa/xoá câu không đạt
rake questions:import[db/question_banks/bug_hunt/20260818.yml]
```

- File YAML là bước "người nhìn qua" thay cho admin panel — giữ lưới an toàn mà không tốn công làm UI
- Import validate schema trước khi insert, dùng checksum nội dung để tránh nhập trùng
- Câu bị báo sai thì admin đánh `hidden`, không xoá cứng (để truy được lịch sử điểm đã chấm)

---

## 3. Impact Scan

Repo greenfield — không có module nội bộ nào bị ảnh hưởng. Các phụ thuộc bên ngoài:

| Hệ thống ngoài | Liên quan | Rủi ro |
|---|---|---|
| Gemini 2.5 Flash API | Sinh đề theo lô + chấm điểm Spec Detective real-time | MEDIUM — quota gói free chưa verify; cần circuit breaker |
| Hạ tầng hosting public | App mở ra internet | MEDIUM — cần HTTPS, rate limit, backup DB |
| Backlog | **Đã loại khỏi scope** | — |
| Quy trình khen thưởng | Hoãn sang sau | LOW — nhưng cần audit log điểm ngay từ đầu để sau này truy ngược được |

---

## 4. Ước lượng tiến độ

**Giả định: 1 dev full-time, chưa tính thời gian sinh và soát nội dung câu hỏi.**
Đây là ước lượng, không phải cam kết — cần đối chiếu với nguồn lực thật.

| Giai đoạn | Nội dung | Ước lượng |
|---|---|---|
| Nền tảng | Auth, user, admin tối thiểu, `game_sessions`, leaderboard 3 chu kỳ, rake task sinh/import đề, log AI | 2 tuần |
| Bug Hunt | Không cần AI lúc chơi | 1 tuần |
| PROD Roulette | Cây quyết định tĩnh | 1 tuần |
| Estimate Poker | Solo, actual định sẵn | 0.5-1 tuần |
| Spec Detective | AI chấm real-time + xử lý lỗi/timeout | 1 tuần |
| Incident Escape Room | State machine + thời gian giả lập + sinh post-mortem | 1.5 tuần |
| Hoàn thiện | Deploy, rate limit, privacy, sửa lỗi | 1 tuần |
| **Tổng** | | **khoảng 8 tuần** |

Thứ tự có chủ đích: 3 game đầu không phụ thuộc AI lúc chơi, chạy thật được sau tuần 4
để lấy phản hồi, trước khi đầu tư vào 2 game phức tạp.

---

## 5. Rủi ro còn lại

| Rủi ro | Trạng thái | Ghi chú |
|---|---|---|
| Rò rỉ dữ liệu khách hàng | **Đã loại** | Không dùng dữ liệu Backlog |
| Lộ thông tin incident nội bộ | **Đã loại** | Kịch bản hư cấu |
| Cháy quota AI do public | **Đã giảm mạnh** | Sinh đề theo lô, chỉ Spec Detective gọi real-time |
| Chất lượng câu hỏi do AI sinh | **Còn** | Bỏ bước duyệt; chỉ còn lần xem qua file YAML + nút báo câu sai |
| Chống gian lận leaderboard | **Còn** | Chấm điểm **bắt buộc ở server**, không tin dữ liệu từ client |
| Tài khoản admin mật khẩu yếu | **Còn (đã chấp nhận)** | Owner quyết giữ hardcode `12345678` |
| Allowlist Gmail không chặn được người cố ý | **Còn (đã chấp nhận)** | Bù bằng rate limit |
| Tiến độ 5 game song song | **Còn** | Owner đã quyết làm cả 5 |
| Chưa có KPI đo thành công | **Còn** | Chưa định nghĩa "app thành công" nghĩa là gì |

---

## 6. Các mục bắt buộc

### TOP 3 điểm dễ bị bỏ sót nguy hiểm nhất

1. **Schema chỉ lưu điểm cao nhất thay vì lưu từng lượt chơi** — leaderboard tuần/tháng
   và tie-break sẽ không làm được, phát hiện muộn thì phải migrate lại toàn bộ dữ liệu điểm.
2. **Chấm điểm ở client** — người chơi gọi thẳng API chấm điểm hoặc sửa payload để tự cho
   mình 100 điểm. Bắt buộc chấm ở server.
3. **Không lưu log mỗi lần AI chấm** — mất khả năng giải trình khi người chơi khiếu nại
   điểm, đặc biệt khi sau này gắn phần thưởng vào leaderboard.

### TOP 3 điều cần xác nhận (nội bộ, không phải với khách hàng)

1. Duyệt dependency mới: gem `rack-attack`.
2. Verify hạn mức và điều khoản gói free của Gemini API trước khi triển khai.
3. Xác nhận ai chịu trách nhiệm soát nội dung câu hỏi trước khi import (hiện chưa có owner
   cho việc này).

### File cần đọc trước khi implement

- `D:\skill-arcade\CLAUDE.md` — conventions đã chốt (Rails, MySQL, naming, error handling, test)
- `~/.claude/rules/nta-prod-safety.md` — nội dung gốc cho kịch bản PROD Roulette; đọc để
  kịch bản bám sát bài học thật thay vì bịa
- Trang chính thức của Google về hạn mức/điều khoản Gemini API — chưa verify

### Luận điểm cần trao đổi với PM

- Nguồn lực thật so với ước lượng 8 tuần (1 dev full-time)
- Ai chịu trách nhiệm sinh và soát nội dung câu hỏi — đây là công việc người, không tự động hoá được
- Hosting và chi phí vận hành app public
- Khi nào gắn phần thưởng thật vào leaderboard (ảnh hưởng yêu cầu chống gian lận)

### Điểm nguy hiểm nếu tiến hành với yêu cầu hiện tại

- Assumption chưa verify: gói free Gemini đủ cho lượng dùng thực tế
- Estimate Poker đã đổi bản chất so với ý tưởng gốc: actual do AI tính là **ý kiến của model,
  không phải dữ liệu thật**, nên không thể dùng kết quả game để kết luận ai estimate chuẩn trong
  công việc thật. Owner đã biết và chấp nhận trade-off này
- Chưa có KPI: sau 3 tháng không có cơ sở đánh giá app có đáng duy trì không

### Điểm còn thiếu theo tiêu chuẩn chất lượng NTA

- **Tuân thủ deadline**: chưa có deadline từ phía tổ chức; ước lượng 8 tuần chưa được đối chiếu nguồn lực thật
- **Giảm sai sót**: bỏ bước duyệt câu hỏi nên có rủi ro phát hành câu sai, dạy sai kiến thức. Lưới an
  toàn còn lại: xem file YAML khi import + nút báo câu hỏi sai
- **Không gây khó khăn cho công đoạn sau**: `game_sessions` và log AI phải có ngay từ migration
  đầu tiên, thêm sau sẽ mất dữ liệu lịch sử
- **Ngăn ngừa tái phát**: PROD Roulette dùng tình huống hư cấu vẫn giữ được giá trị bài học,
  miễn kịch bản bám sát rule trong `nta-prod-safety.md`
- **Có thể giải trình trách nhiệm**: các quyết định rủi ro (mật khẩu admin hardcode, allowlist
  Gmail yếu, chấp nhận điểm AI không tất định) đã được ghi lại kèm người quyết định trong file này

---

## 7. Bước tiếp theo

- Hết BLOCKER, chạy `/nta-spec:nta-spec-write` để soạn spec chi tiết
- Cần duyệt gem `rack-attack` trước khi implement
- Cần verify hạn mức Gemini API trước khi chốt kiến trúc gọi AI real-time cho Spec Detective
