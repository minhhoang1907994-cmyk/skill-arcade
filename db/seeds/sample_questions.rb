# Câu hỏi mẫu viết tay để chơi thử được ngay ở Phase 2.
# Ngân hàng câu hỏi thật sẽ do rake questions:generate sinh ở Phase 3 (source: ai_generated).
#
# Chạy: bin/rails runner db/seeds/sample_questions.rb
# Idempotent: checksum unique nên chạy lại không tạo bản ghi trùng.

def upsert_question(game, content, answer_key, difficulty: "medium")
  checksum = Question.checksum_for(content)
  question = Question.find_or_initialize_by(checksum: checksum)
  question.assign_attributes(
    game: game, content: content, answer_key: answer_key,
    difficulty: difficulty, source: "manual"
  )
  question.save!
  question
end

# --- Bug Hunt: 40 snippet, chia theo ngôn ngữ lập trình ---
# Người chơi chọn ngôn ngữ trước khi vào lượt, và Game#playable_languages chỉ hiện
# ngôn ngữ có >= questions_per_session (10) câu. Bốn ngôn ngữ php/ruby/java/javascript
# mỗi loại đúng 10 câu, tức là vừa đủ MỘT lượt và không có câu dư — chơi lại cùng ngôn
# ngữ sẽ gặp lại toàn bộ 10 câu (BR-32 phải fallback). Ngân hàng thật do
# `rake questions:generate` bổ sung.
#
# Khi thêm câu mới: bug_type phải nằm trong Question::BUG_HUNT_TYPES. Danh sách đó đi vào
# content nên thêm/bớt/đổi thứ tự phần tử sẽ đổi checksum của TOÀN BỘ câu Bug Hunt đang có
# — chạy lại seed sẽ tạo bản ghi trùng thay vì cập nhật.
bug_hunt = Game.find_by!(slug: Game::BUG_HUNT)

BUG_HUNT_SAMPLES = [
  {
    language: "php",
    lines: [
      "public function findUser($email) {",
      "    $db = $this->connection;",
      "    $sql = \"SELECT * FROM users WHERE email = '\" . $email . \"'\";",
      "    return $db->query($sql)->fetch();",
      "}"
    ],
    buggy_line: 3,
    bug_type: "sql_injection",
    explanation: "Email được nối thẳng vào câu SQL. Dùng prepared statement với placeholder."
  },
  {
    language: "ruby",
    lines: [
      "def total_price(order)",
      "  order.items.map do |item|",
      "    item.product.price * item.quantity",
      "  end.sum",
      "end"
    ],
    buggy_line: 3,
    bug_type: "n_plus_one",
    explanation: "Mỗi item gọi thêm một query lấy product. Dùng includes(:product) khi load items."
  },
  {
    language: "javascript",
    lines: [
      "function getDisplayName(user) {",
      "  return user.profile.displayName.trim();",
      "}"
    ],
    buggy_line: 2,
    bug_type: "missing_null_check",
    explanation: "profile hoặc displayName có thể null. Dùng optional chaining và giá trị mặc định."
  },
  {
    language: "ruby",
    lines: [
      "def transfer(from, to, amount)",
      "  from.update!(balance: from.balance - amount)",
      "  to.update!(balance: to.balance + amount)",
      "end"
    ],
    buggy_line: 2,
    bug_type: "missing_transaction",
    explanation: "Hai lệnh update không nằm trong transaction. Lỗi ở dòng sau làm mất tiền."
  },
  {
    language: "php",
    lines: [
      "public function deleteAccount($id) {",
      "    $user = User::find($id);",
      "    $user->delete();",
      "    return response()->json(['ok' => true]);",
      "}"
    ],
    buggy_line: 2,
    bug_type: "missing_authorization",
    explanation: "Không kiểm tra người gọi có quyền xoá tài khoản này không (IDOR)."
  },
  {
    language: "javascript",
    lines: [
      "async function saveAll(items) {",
      "  items.forEach(async (item) => {",
      "    await api.save(item);",
      "  });",
      "  console.log('done');",
      "}"
    ],
    buggy_line: 2,
    bug_type: "async_misuse",
    explanation: "forEach không đợi async callback. Dùng for...of hoặc Promise.all."
  },
  {
    language: "ruby",
    lines: [
      "def apply_discount(price, percent)",
      "  price - (price * percent / 100)",
      "end"
    ],
    buggy_line: 2,
    bug_type: "missing_validation",
    explanation: "percent không được kiểm tra khoảng hợp lệ. percent > 100 cho giá âm."
  },
  {
    language: "php",
    lines: [
      "public function login(Request $request) {",
      "    $user = User::where('email', $request->email)->first();",
      "    Log::info('login attempt', ['password' => $request->password]);",
      "    return Auth::attempt($request->only('email', 'password'));",
      "}"
    ],
    buggy_line: 3,
    bug_type: "sensitive_data_logging",
    explanation: "Mật khẩu bị ghi thẳng vào log. Không bao giờ log credential."
  },
  {
    language: "javascript",
    lines: [
      "function renderComment(comment) {",
      "  const el = document.createElement('div');",
      "  el.innerHTML = comment.body;",
      "  return el;",
      "}"
    ],
    buggy_line: 3,
    bug_type: "xss",
    explanation: "innerHTML với nội dung người dùng nhập cho phép chèn script. Dùng textContent."
  },
  {
    language: "ruby",
    lines: [
      "def process_payment(order)",
      "  gateway.charge(order.total)",
      "  order.update!(status: 'paid')",
      "rescue StandardError",
      "  nil",
      "end"
    ],
    buggy_line: 5,
    bug_type: "swallowed_exception",
    explanation: "Nuốt lỗi im lặng: thanh toán hỏng nhưng không ai biết. Ít nhất phải log và raise lại."
  },
  {
    language: "php",
    lines: [
      "public function export(Request $request) {",
      "    $rows = Order::all();",
      "    return Excel::download(new OrdersExport($rows), 'orders.xlsx');",
      "}"
    ],
    buggy_line: 2,
    bug_type: "unbounded_query",
    explanation: "Order::all() nạp toàn bộ bảng vào RAM. Dùng chunk hoặc cursor."
  },
  {
    language: "javascript",
    lines: [
      "const cache = {};",
      "function getConfig(key) {",
      "  if (!cache[key]) {",
      "    cache[key] = fetchConfig(key);",
      "  }",
      "  return cache[key];",
      "}"
    ],
    buggy_line: 3,
    bug_type: "falsy_check",
    explanation: "Giá trị hợp lệ nhưng falsy (0, '', false) làm cache miss mãi. Dùng 'key in cache'."
  },
  # --- php: 6 câu bổ sung cho đủ 10 ---
  {
    language: "php",
    lines: [
      "public function index() {",
      "    $orders = Order::all();",
      "    foreach ($orders as $order) {",
      "        echo $order->customer->name;",
      "    }",
      "}"
    ],
    buggy_line: 4,
    bug_type: "n_plus_one",
    explanation: "Mỗi vòng lặp nạp thêm một customer. Dùng Order::with('customer')."
  },
  {
    language: "php",
    lines: [
      "public function greet(Request $request) {",
      "    $user = User::find($request->id);",
      "    return 'Xin chào ' . $user->name;",
      "}"
    ],
    buggy_line: 3,
    bug_type: "missing_null_check",
    explanation: "find() trả null khi không thấy bản ghi. Dùng findOrFail hoặc kiểm tra null trước."
  },
  {
    language: "php",
    lines: [
      "public function checkout($cart) {",
      "    $order = Order::create(['total' => $cart->total]);",
      "    Inventory::decrease($cart->items);",
      "    $cart->delete();",
      "}"
    ],
    buggy_line: 2,
    bug_type: "missing_transaction",
    explanation: "Ba bước ghi không nằm trong DB::transaction. Lỗi giữa chừng để lại đơn không có hàng."
  },
  {
    language: "php",
    lines: [
      "public function updateQuantity(Request $request, $itemId) {",
      "    $item = CartItem::findOrFail($itemId);",
      "    $item->update(['quantity' => $request->quantity]);",
      "    return response()->json($item);",
      "}"
    ],
    buggy_line: 3,
    bug_type: "missing_validation",
    explanation: "quantity chưa validate. Số âm hoặc chữ đi thẳng vào DB. Dùng $request->validate()."
  },
  {
    language: "php",
    lines: [
      "public function renderComment($comment) {",
      "    $body = $comment->body;",
      "    echo \"<div class='comment'>\" . $body . \"</div>\";",
      "}"
    ],
    buggy_line: 3,
    bug_type: "xss",
    explanation: "Nội dung người dùng in thẳng ra HTML. Dùng htmlspecialchars hoặc in qua Blade {{ }}."
  },
  {
    language: "php",
    lines: [
      "public function sendInvoice($order) {",
      "    try {",
      "        $this->mailer->send(new Invoice($order));",
      "    } catch (Exception $e) {",
      "    }",
      "}"
    ],
    buggy_line: 5,
    bug_type: "swallowed_exception",
    explanation: "catch rỗng: mail hỏng nhưng không ai biết. Ít nhất phải log lại lỗi."
  },
  # --- ruby: 6 câu bổ sung cho đủ 10 ---
  {
    language: "ruby",
    lines: [
      "def search(keyword)",
      "  User.where(\"display_name LIKE '%\#{keyword}%'\").to_a",
      "end"
    ],
    buggy_line: 2,
    bug_type: "sql_injection",
    explanation: "Nội suy chuỗi vào SQL. Dùng placeholder: where('display_name LIKE ?', pattern)."
  },
  {
    language: "ruby",
    lines: [
      "def latest_order_total(user)",
      "  user.orders.last.total.round(2)",
      "end"
    ],
    buggy_line: 2,
    bug_type: "missing_null_check",
    explanation: "Người chưa có đơn thì last trả nil. Kiểm tra nil hoặc dùng &. kèm giá trị mặc định."
  },
  {
    language: "ruby",
    lines: [
      "def destroy",
      "  post = Post.find(params[:id])",
      "  post.destroy!",
      "  head :no_content",
      "end"
    ],
    buggy_line: 2,
    bug_type: "missing_authorization",
    explanation: "Không kiểm tra post thuộc current_user. Lấy qua current_user.posts.find (IDOR)."
  },
  {
    language: "ruby",
    lines: [
      "def create",
      "  Rails.logger.info(\"signup params: \#{params.inspect}\")",
      "  user = User.create!(user_params)",
      "  render json: { id: user.id }",
      "end"
    ],
    buggy_line: 2,
    bug_type: "sensitive_data_logging",
    explanation: "params.inspect chứa cả password. Chỉ log field an toàn, hoặc dùng filter_parameters."
  },
  {
    language: "ruby",
    lines: [
      "def comment_html(comment)",
      "  content_tag(:div, raw(comment.body))",
      "end"
    ],
    buggy_line: 2,
    bug_type: "xss",
    explanation: "raw tắt escape HTML cho nội dung người dùng nhập. Bỏ raw, hoặc sanitize trước."
  },
  {
    language: "ruby",
    lines: [
      "def export_all",
      "  rows = User.all.map { |u| [ u.email, u.display_name ] }",
      "  CSV.generate { |csv| rows.each { |r| csv << r } }",
      "end"
    ],
    buggy_line: 2,
    bug_type: "unbounded_query",
    explanation: "User.all.map nạp cả bảng vào RAM. Dùng find_each hoặc in_batches."
  },
  # --- java: 10 câu (ngôn ngữ mới bổ sung) ---
  {
    language: "java",
    lines: [
      "public User findByEmail(String email) {",
      "    String sql = \"SELECT * FROM users WHERE email = '\" + email + \"'\";",
      "    return jdbcTemplate.queryForObject(sql, userRowMapper);",
      "}"
    ],
    buggy_line: 2,
    bug_type: "sql_injection",
    explanation: "Email nối thẳng vào SQL. Dùng query có tham số: queryForObject(sql, args, mapper)."
  },
  {
    language: "java",
    lines: [
      "public List<String> customerNames() {",
      "    List<Order> orders = orderRepository.findAll();",
      "    return orders.stream()",
      "        .map(order -> order.getCustomer().getName())",
      "        .toList();",
      "}"
    ],
    buggy_line: 4,
    bug_type: "n_plus_one",
    explanation: "getCustomer() lazy load nên mỗi order thêm một query. Dùng JOIN FETCH hoặc EntityGraph."
  },
  {
    language: "java",
    lines: [
      "public String displayName(User user) {",
      "    return user.getProfile().getDisplayName().trim();",
      "}"
    ],
    buggy_line: 2,
    bug_type: "missing_null_check",
    explanation: "getProfile() hoặc getDisplayName() có thể null gây NPE. Dùng Optional hoặc kiểm tra null."
  },
  {
    language: "java",
    lines: [
      "public void transfer(Account from, Account to, BigDecimal amount) {",
      "    from.setBalance(from.getBalance().subtract(amount));",
      "    accountRepository.save(from);",
      "    to.setBalance(to.getBalance().add(amount));",
      "    accountRepository.save(to);",
      "}"
    ],
    buggy_line: 3,
    bug_type: "missing_transaction",
    explanation: "Hai lần save không cùng transaction. Thêm @Transactional để lỗi ở save sau rollback cả hai."
  },
  {
    language: "java",
    lines: [
      "@DeleteMapping(\"/accounts/{id}\")",
      "public ResponseEntity<Void> delete(@PathVariable Long id) {",
      "    accountRepository.deleteById(id);",
      "    return ResponseEntity.noContent().build();",
      "}"
    ],
    buggy_line: 3,
    bug_type: "missing_authorization",
    explanation: "Ai biết id cũng xoá được tài khoản người khác. Phải kiểm tra chủ sở hữu (IDOR)."
  },
  {
    language: "java",
    lines: [
      "public BigDecimal applyDiscount(BigDecimal price, int percent) {",
      "    BigDecimal rate = BigDecimal.valueOf(percent / 100.0);",
      "    return price.subtract(price.multiply(rate));",
      "}"
    ],
    buggy_line: 2,
    bug_type: "missing_validation",
    explanation: "percent không kiểm tra khoảng 0-100. percent > 100 cho ra giá âm."
  },
  {
    language: "java",
    lines: [
      "public boolean login(LoginRequest request) {",
      "    log.info(\"login attempt: {}\", request);",
      "    return authService.authenticate(request.getEmail(), request.getPassword());",
      "}"
    ],
    buggy_line: 2,
    bug_type: "sensitive_data_logging",
    explanation: "toString() của request in cả password vào log. Chỉ log email."
  },
  {
    language: "java",
    lines: [
      "protected void doGet(HttpServletRequest req, HttpServletResponse resp) {",
      "    String keyword = req.getParameter(\"q\");",
      "    resp.getWriter().write(\"<h2>Ket qua cho \" + keyword + \"</h2>\");",
      "}"
    ],
    buggy_line: 3,
    bug_type: "xss",
    explanation: "Tham số query ghi thẳng ra HTML. Phải escape HTML trước khi in."
  },
  {
    language: "java",
    lines: [
      "public Config loadConfig(String path) {",
      "    try {",
      "        return parser.parse(Files.readString(Path.of(path)));",
      "    } catch (IOException e) {",
      "        return null;",
      "    }",
      "}"
    ],
    buggy_line: 5,
    bug_type: "swallowed_exception",
    explanation: "Trả null im lặng: caller ăn NPE mà không biết file cấu hình lỗi. Log và ném lại."
  },
  {
    language: "java",
    lines: [
      "public void exportOrders(OutputStream out) {",
      "    List<Order> orders = orderRepository.findAll();",
      "    for (Order order : orders) {",
      "        writeRow(out, order);",
      "    }",
      "}"
    ],
    buggy_line: 2,
    bug_type: "unbounded_query",
    explanation: "findAll() nạp toàn bộ bảng vào RAM. Dùng Slice/Pageable hoặc Stream có phân trang."
  },
  # --- javascript: 6 câu bổ sung cho đủ 10 ---
  {
    language: "javascript",
    lines: [
      "app.get('/users', async (req, res) => {",
      "  const sql = `SELECT * FROM users WHERE email = '${req.query.email}'`;",
      "  const [rows] = await db.query(sql);",
      "  res.json(rows);",
      "});"
    ],
    buggy_line: 2,
    bug_type: "sql_injection",
    explanation: "Template string nối thẳng query param vào SQL. Dùng placeholder: db.query(sql, [email])."
  },
  {
    language: "javascript",
    lines: [
      "router.delete('/posts/:id', async (req, res) => {",
      "  await Post.destroy({ where: { id: req.params.id } });",
      "  res.status(204).end();",
      "});"
    ],
    buggy_line: 2,
    bug_type: "missing_authorization",
    explanation: "Không kiểm tra post thuộc req.user. Thêm điều kiện userId vào where (IDOR)."
  },
  {
    language: "javascript",
    lines: [
      "async function login(req, res) {",
      "  console.log('login body', req.body);",
      "  const user = await auth.verify(req.body.email, req.body.password);",
      "  res.json({ id: user.id });",
      "}"
    ],
    buggy_line: 2,
    bug_type: "sensitive_data_logging",
    explanation: "req.body chứa cả password. Chỉ log field an toàn, hoặc lọc trước khi log."
  },
  {
    language: "javascript",
    lines: [
      "async function syncOrders() {",
      "  try {",
      "    await api.pushOrders(await Order.pending());",
      "  } catch (e) {",
      "  }",
      "}"
    ],
    buggy_line: 5,
    bug_type: "swallowed_exception",
    explanation: "catch rỗng: đồng bộ hỏng nhưng không ai biết. Ít nhất phải log và báo lỗi lên trên."
  },
  {
    language: "javascript",
    lines: [
      "function setQuantity(cart, itemId, raw) {",
      "  cart.items[itemId].quantity = parseInt(raw, 10);",
      "  return cart;",
      "}"
    ],
    buggy_line: 2,
    bug_type: "missing_validation",
    explanation: "parseInt có thể ra NaN và không kiểm tra khoảng hợp lệ. Validate trước khi gán."
  },
  {
    language: "javascript",
    lines: [
      "async function exportUsers(stream) {",
      "  const users = await User.findAll();",
      "  users.forEach((u) => stream.write(toCsvRow(u)));",
      "}"
    ],
    buggy_line: 2,
    bug_type: "unbounded_query",
    explanation: "findAll() không giới hạn nạp cả bảng vào RAM. Dùng phân trang hoặc cursor stream."
  }
].freeze

# Danh sách lựa chọn hiển thị cho người chơi — nguồn duy nhất là Question::BUG_HUNT_TYPES,
# dùng chung với `rake questions:generate` để đề viết tay và đề AI sinh cùng một danh sách.
BUG_HUNT_TYPES = Question::BUG_HUNT_TYPES

unknown = BUG_HUNT_SAMPLES.map { |s| s[:bug_type] }.uniq - BUG_HUNT_TYPES
raise "bug_type chưa có trong Question::BUG_HUNT_TYPES: #{unknown.join(', ')}" if unknown.any?

BUG_HUNT_SAMPLES.each do |sample|
  upsert_question(
    bug_hunt,
    {
      "language" => sample[:language],
      "code_lines" => sample[:lines],
      "bug_types" => BUG_HUNT_TYPES
    },
    {
      "buggy_line" => sample[:buggy_line],
      "bug_type" => sample[:bug_type],
      "explanation" => sample[:explanation]
    }
  )
end

# --- Estimate Poker: 12 task ---
estimate_poker = Game.find_by!(slug: Game::ESTIMATE_POKER)

# `steps` là bảng thao tác + số giờ hiện cho người chơi sau khi trả lời; `actual_hours`
# cộng ra từ đó chứ không viết tay, nên không thể có chuyện bảng nói một đằng điểm chấm
# một nẻo (Questions::Validator#breakdown_error chặn ở đường import, đây chặn từ nguồn).
#
# Mỗi dòng chỉ tính điều tra + gõ code + tự viết test + sửa sau review, và chỉ tính việc
# CÓ TRONG mô tả task. Thêm dòng cho việc mô tả không nhắc tới là chấm sai người chơi:
# họ ước lượng đúng phạm vi được cho mà vẫn bị trừ điểm.
ESTIMATE_SAMPLES = [
  {
    task: "Thêm cột `deleted_at` vào bảng users và cập nhật model dùng soft delete",
    steps: [
      [ "Viết migration thêm cột và index", 0.5 ],
      [ "Thêm default_scope lọc bản ghi đã xoá vào model", 0.5 ],
      [ "Sửa unique index trên email để bản ghi đã xoá không chặn đăng ký lại", 0.5 ],
      [ "Chỉnh test cũ vỡ vì default_scope", 0.5 ]
    ],
    note: "Rà lại toàn bộ query đang lấy user là việc khác, không nằm trong mô tả task."
  },
  {
    task: "Viết API đăng nhập email/password kèm khoá tài khoản sau 5 lần sai",
    steps: [
      [ "Migration cột đếm lần sai và thời điểm mở khoá", 0.5 ],
      [ "Endpoint xác thực email/password", 1.5 ],
      [ "Logic đếm, reset khi đăng nhập đúng, tự mở khoá sau thời hạn", 1.5 ],
      [ "Test luồng khoá và mở khoá", 2 ],
      [ "Sửa sau review", 0.5 ]
    ],
    note: "Không tính rate limit theo IP — mô tả task chỉ yêu cầu khoá theo tài khoản."
  },
  {
    task: "Đổi màu nút primary trong design system",
    steps: [
      [ "Sửa biến màu trong design token", 0.25 ],
      [ "Rà lại các màn hình chính dùng nút primary", 0.5 ],
      [ "Sửa sau review", 0.25 ]
    ],
    note: "Sửa một biến, phần còn lại là mở vài màn hình xem có chỗ nào lệch tương phản."
  },
  {
    task: "Tích hợp cổng thanh toán mới có webhook và xử lý idempotency",
    steps: [
      [ "Đọc tài liệu và viết module ký/kiểm chữ ký", 3 ],
      [ "Luồng khởi tạo thanh toán và trang trả về", 4 ],
      [ "Webhook cập nhật đơn, chống xử lý trùng bằng unique index mã giao dịch", 4 ],
      [ "Test với sandbox của cổng thanh toán", 3 ],
      [ "Sửa sau review", 2 ]
    ],
    note: "Phần lớn thời gian nằm ở xử lý webhook trùng và test sandbox."
  },
  {
    task: "Sinh báo cáo Excel từ 200k bản ghi, có filter theo khoảng ngày",
    steps: [
      [ "Tối ưu query và thêm index cho filter theo ngày", 2 ],
      [ "Ghi file theo luồng stream để không hết RAM", 2.5 ],
      [ "Endpoint tải file kèm tham số filter", 1 ],
      [ "Test bộ nhớ với 200k bản ghi", 1.5 ],
      [ "Sửa sau review", 1 ]
    ],
    note: "Cần streaming/chunk để không hết RAM, cộng thời gian tối ưu query."
  },
  {
    task: "Thêm trang danh sách có phân trang và sắp xếp cho một bảng đã có sẵn API",
    steps: [
      [ "Thêm tham số sort vào API có sẵn", 0.5 ],
      [ "Dựng bảng và phân trang ở frontend", 2 ],
      [ "Nút sắp xếp theo cột", 0.5 ],
      [ "Test", 0.5 ],
      [ "Sửa sau review", 0.5 ]
    ],
    note: "Frontend là chính, backend chỉ cần bổ sung tham số sort."
  },
  {
    task: "Chuyển toàn bộ upload ảnh từ local disk sang S3",
    steps: [
      [ "Cấu hình SDK, bucket và quyền truy cập", 1.5 ],
      [ "Đổi code upload sang S3", 2 ],
      [ "Script chuyển file cũ từ disk lên S3", 3 ],
      [ "Xử lý URL ảnh trong dữ liệu đã có", 2 ],
      [ "Test", 2 ],
      [ "Sửa sau review", 1.5 ]
    ],
    note: "Gồm migrate file cũ, đổi code upload, và xử lý URL trong dữ liệu đã có."
  },
  {
    task: "Sửa lỗi sai múi giờ khi hiển thị ngày tạo đơn hàng",
    steps: [
      [ "Tái hiện lỗi và xác định lệch ở nơi lưu hay nơi hiển thị", 1.5 ],
      [ "Sửa cấu hình timezone và chỗ format ngày", 1 ],
      [ "Test với vài múi giờ", 1 ],
      [ "Sửa sau review", 0.5 ]
    ],
    note: "Tìm nguyên nhân mất thời gian hơn sửa; phải rà cả nơi lưu và nơi hiển thị."
  },
  {
    task: "Viết unit test cho một service đã có 300 dòng, hiện chưa có test nào",
    steps: [
      [ "Đọc service và tách phụ thuộc để test được", 2 ],
      [ "Viết test cho các nhánh chính", 2.5 ],
      [ "Viết test cho edge case", 1 ],
      [ "Sửa sau review", 0.5 ]
    ],
    note: "Phải tách phụ thuộc trước khi test được, đó mới là phần tốn thời gian."
  },
  {
    task: "Thêm chức năng quên mật khẩu qua email",
    steps: [
      [ "Migration bảng lưu token đặt lại mật khẩu", 0.5 ],
      [ "Sinh token có hạn và gửi mail", 1.5 ],
      [ "Trang đặt lại mật khẩu", 1.5 ],
      [ "Xử lý token hết hạn và token đã dùng", 1 ],
      [ "Test", 1 ],
      [ "Sửa sau review", 0.5 ]
    ],
    note: "Token có hạn, gửi mail, trang đặt lại, và test cho token hết hạn."
  },
  {
    task: "Nâng phiên bản framework từ major cũ lên major mới",
    steps: [
      [ "Đọc release note và liệt kê breaking change", 4 ],
      [ "Nâng version và sửa lỗi không khởi động được", 6 ],
      [ "Sửa code dùng API đã bị bỏ", 10 ],
      [ "Sửa test vỡ", 8 ],
      [ "Chạy lại toàn bộ và sửa lỗi phát sinh", 4 ]
    ],
    note: "Không đoán trước được số breaking change; luôn phát sinh thêm khi chạy test."
  },
  {
    task: "Thêm bộ lọc theo trạng thái vào màn hình danh sách đơn hàng",
    steps: [
      [ "Thêm tham số lọc vào query", 0.5 ],
      [ "Dropdown trạng thái ở màn hình danh sách", 0.75 ],
      [ "Test", 0.5 ],
      [ "Sửa sau review", 0.25 ]
    ],
    note: "Một tham số query, một dropdown, cộng test."
  }
].freeze

ESTIMATE_SAMPLES.each do |sample|
  breakdown = sample[:steps].map { |step, hours| { "step" => step, "hours" => hours } }

  upsert_question(
    estimate_poker,
    { "task_description" => sample[:task], "context" => "Dev có kinh nghiệm trung bình, đã quen codebase" },
    {
      "actual_hours" => breakdown.sum { |row| row["hours"] },
      "breakdown" => breakdown,
      "reasoning" => sample[:note]
    }
  )
end

# --- Spec Detective: 6 đoạn requirement (chấm bằng AI ở Phase 3) ---
spec_detective = Game.find_by!(slug: Game::SPEC_DETECTIVE)

# Từ 1.19 Spec Detective chấm từ answer_key thay vì gọi Gemini, nên đề phải mang sẵn thang
# điểm: câu nào mơ hồ (số thứ tự, đếm từ 1 theo statements) và phương án nào là tốt nhất.
# Mỗi đề phải còn ít nhất một câu KHÔNG mơ hồ, không thì tick hết là đủ điểm.
SPEC_SAMPLES = [
  {
    statements: [
      "Hệ thống phải xử lý đơn hàng nhanh chóng sau khi khách bấm đặt hàng.",
      "Đơn hàng được lưu vào bảng orders với trạng thái pending.",
      "Khi có đơn mới, gửi thông báo cho bộ phận liên quan nếu cần thiết.",
      "Thông báo gửi qua email tới địa chỉ đã cấu hình trong phần cài đặt."
    ],
    ambiguous: [ 1, 3 ],
    options: [
      { key: "a", label: "\"Nhanh chóng\" là trong bao nhiêu giây, và đo từ lúc nào tới lúc nào?" },
      { key: "b", label: "Đơn hàng được lưu vào bảng nào?" },
      { key: "c", label: "Hệ thống có cần chạy nhanh hơn đối thủ không?" },
      { key: "d", label: "Email gửi bằng SMTP hay dịch vụ bên thứ ba?" }
    ],
    best: "a",
    explanation: "Phương án a đóng được điểm mơ hồ nặng nhất và trả lời được bằng một con số. "                  "b hỏi thứ câu 2 đã nói rõ, c ngoài phạm vi yêu cầu, d là chuyện kỹ thuật "                  "chưa cần chốt ở bước làm rõ nghiệp vụ."
  },
  {
    statements: [
      "Người dùng có thể tải file lên trong phần hồ sơ cá nhân.",
      "File quá lớn sẽ bị từ chối với thông báo phù hợp.",
      "Chỉ chấp nhận file định dạng PDF và PNG.",
      "File tải lên được lưu 90 ngày rồi tự xoá."
    ],
    ambiguous: [ 2 ],
    options: [
      { key: "a", label: "Ngưỡng \"quá lớn\" là bao nhiêu MB, và thông báo hiển thị đúng câu gì?" },
      { key: "b", label: "Những định dạng file nào được phép tải lên?" },
      { key: "c", label: "File lưu trên server hay trên dịch vụ lưu trữ ngoài?" },
      { key: "d", label: "Người dùng có thích tính năng này không?" }
    ],
    best: "a",
    explanation: "Chỉ câu 2 còn mơ hồ và phương án a đóng đúng nó. b đã có ở câu 3, c là "                  "quyết định kỹ thuật, d không phải câu hỏi làm rõ yêu cầu."
  },
  {
    statements: [
      "Báo cáo doanh thu hiển thị dữ liệu của kỳ hiện tại.",
      "Người dùng có thể xuất báo cáo ra file.",
      "Báo cáo chỉ hiện dữ liệu của chi nhánh mà người dùng được phân quyền.",
      "Trang báo cáo có bộ lọc theo ngày bắt đầu và ngày kết thúc."
    ],
    ambiguous: [ 1, 2 ],
    options: [
      { key: "a", label: "\"Kỳ hiện tại\" là tháng, quý hay năm, và file xuất ở định dạng nào?" },
      { key: "b", label: "Người dùng thấy được dữ liệu của chi nhánh nào?" },
      { key: "c", label: "Báo cáo có cần đẹp không?" },
      { key: "d", label: "Có nên thêm biểu đồ vào báo cáo không?" }
    ],
    best: "a",
    explanation: "a đóng cả hai điểm mơ hồ còn lại bằng câu trả lời cụ thể được. b đã rõ ở "                  "câu 3, c không đo được, d là đề xuất tính năng mới chứ không làm rõ yêu cầu."
  },
  {
    statements: [
      "Khi khách hàng huỷ đơn, hệ thống hoàn tiền theo chính sách của công ty.",
      "Đơn đã giao thành công thì không cho huỷ.",
      "Yêu cầu huỷ được ghi log kèm thời điểm và người thực hiện.",
      "Tiền hoàn về đúng phương thức thanh toán ban đầu."
    ],
    ambiguous: [ 1 ],
    options: [
      { key: "a", label: "Chính sách hoàn tiền cụ thể là gì: hoàn toàn bộ hay trừ phí, "                          "và trong bao nhiêu ngày kể từ khi huỷ?" },
      { key: "b", label: "Đơn ở trạng thái nào thì không cho huỷ?" },
      { key: "c", label: "Tiền hoàn về đâu?" },
      { key: "d", label: "Khách hàng có hay huỷ đơn không?" }
    ],
    best: "a",
    explanation: "Chỉ câu 1 mơ hồ. b và c đã được câu 2 và câu 4 trả lời, d là câu hỏi "                  "thống kê chứ không làm rõ quy tắc."
  },
  {
    statements: [
      "Admin có thể chỉnh sửa thông tin người dùng trong trang quản trị.",
      "Một số trường không được phép sửa.",
      "Mọi thay đổi được ghi vào bảng audit_logs.",
      "Chỉ admin có quyền user_manage mới vào được trang này."
    ],
    ambiguous: [ 2 ],
    options: [
      { key: "a", label: "\"Một số trường\" là những trường nào, và ai được sửa ngoại lệ?" },
      { key: "b", label: "Thay đổi có được ghi log không?" },
      { key: "c", label: "Admin cấp nào vào được trang quản trị?" },
      { key: "d", label: "Trang quản trị dùng framework gì?" }
    ],
    best: "a",
    explanation: "a đóng đúng điểm mơ hồ duy nhất bằng một danh sách cụ thể. b và c đã rõ ở "                  "câu 3 và câu 4, d là chuyện kỹ thuật."
  },
  {
    statements: [
      "Hệ thống tự động đồng bộ dữ liệu với hệ thống kế toán định kỳ.",
      "Đồng bộ chỉ đẩy dữ liệu hoá đơn đã được duyệt.",
      "Khi đồng bộ thất bại, hệ thống xử lý phù hợp.",
      "Kết quả mỗi lần đồng bộ được ghi vào bảng sync_logs."
    ],
    ambiguous: [ 1, 3 ],
    options: [
      { key: "a", label: "\"Định kỳ\" là mỗi bao lâu, và khi thất bại thì retry mấy lần "                          "rồi báo cho ai?" },
      { key: "b", label: "Dữ liệu nào được đồng bộ sang hệ thống kế toán?" },
      { key: "c", label: "Hệ thống kế toán đang dùng là phần mềm nào?" },
      { key: "d", label: "Đồng bộ có nhanh không?" }
    ],
    best: "a",
    explanation: "a đóng cả hai điểm mơ hồ bằng con số và quy tắc. b đã rõ ở câu 2, c hữu "                  "ích nhưng không đóng điểm mơ hồ nào, d không đo được."
  }
].freeze

SPEC_SAMPLES.each do |sample|
  upsert_question(
    spec_detective,
    {
      "statements" => sample[:statements],
      "clarifying_options" => sample[:options].map { |o| { "key" => o[:key], "label" => o[:label] } }
    },
    {
      "ambiguous_statement_indexes" => sample[:ambiguous],
      "best_option_key" => sample[:best],
      "explanation" => sample[:explanation]
    }
  )
end

# --- PROD Roulette: 3 kịch bản, mỗi kịch bản 10 bước ---
prod_roulette = Game.find_by!(slug: Game::PROD_ROULETTE)

def roulette_scenario(title, steps)
  nodes = steps.each_with_index.map do |step, i|
    {
      "key" => "n#{i + 1}",
      "prompt" => step[:prompt],
      "options" => step[:options].map { |o| { "key" => o[:key], "label" => o[:label] } }
    }
  end

  effects = {}
  steps.each_with_index do |step, i|
    step[:options].each do |o|
      effects[o[:key]] = {
        "points" => o[:points],
        "irreversible" => o.fetch(:irreversible, false),
        "consequence_text" => o[:consequence],
        "next_node" => (i + 2 <= steps.size ? "n#{i + 2}" : nil)
      }
    end
  end

  [ { "scenario" => title, "nodes" => nodes }, { "option_effects" => effects } ]
end

ROULETTE_STEPS = [
  { prompt: "Khách báo tính năng gửi voucher chưa chạy đúng. Project chưa có Staging. Bạn làm gì trước?",
    options: [
      { key: "s1a", label: "Xin approval bằng văn bản trước khi đụng vào PROD", points: 10,
        consequence: "Đúng. Có approval là điều kiện đầu tiên khi buộc phải test trên PROD." },
      { key: "s1b", label: "Vào PROD thử luôn cho nhanh, sếp đang giục", points: 0, irreversible: false,
        consequence: "Rủi ro: không ai biết bạn đang thao tác gì trên PROD." },
      { key: "s1c", label: "Đề xuất dựng Staging trước đã", points: 3,
        consequence: "Đúng về lâu dài nhưng không giải quyết được việc cần làm hôm nay." }
    ] },
  { prompt: "Bạn cần tài khoản để test. Chọn cách nào?",
    options: [
      { key: "s2a", label: "Tạo tài khoản test riêng, đánh dấu rõ [TEST-DO-NOT-USE]", points: 10,
        consequence: "Đúng. Dữ liệu test phải nhận diện được để còn dọn." },
      { key: "s2b", label: "Dùng tài khoản của một khách hàng thật cho giống thực tế", points: 0,
        irreversible: true,
        consequence: "DỪNG LƯỢT. Bạn vừa thao tác trên dữ liệu của khách hàng thật. Mọi thông báo, giao dịch phát sinh đều đã xảy ra thật và không thu hồi được." },
      { key: "s2c", label: "Dùng tài khoản cá nhân của mình", points: 3,
        consequence: "Đỡ hơn dùng của khách, nhưng vẫn khó phân biệt khi rà soát sau này." }
    ] },
  { prompt: "Trước khi chạy, bạn rà soát side-effect của tính năng. Bước nào quan trọng nhất?",
    options: [
      { key: "s3a", label: "Liệt kê mọi kênh gửi ra ngoài: email, SMS, push, webhook bên thứ 3", points: 10,
        consequence: "Đúng. Đây là bước quyết định giữa 'dọn được' và 'không thu hồi được'." },
      { key: "s3b", label: "Đọc lướt code xem có gì lạ không", points: 3,
        consequence: "Chưa đủ. Side-effect thường nằm ở event listener hoặc job chạy nền." },
      { key: "s3c", label: "Bỏ qua, tính năng này chắc không gửi gì đâu", points: 0,
        consequence: "\"Chắc không sao đâu\" là câu mở đầu của phần lớn incident." }
    ] },
  { prompt: "Bạn phát hiện tính năng có gửi email thật cho người nhận voucher. Làm gì?",
    options: [
      { key: "s4a", label: "Bật feature flag chặn gửi thật, hoặc trỏ sang sandbox của provider", points: 10,
        consequence: "Đúng. Chặn kênh gửi thật TRƯỚC khi chạy, không phải sau." },
      { key: "s4b", label: "Cứ chạy, email gửi nhầm thì gửi email xin lỗi sau", points: 0,
        irreversible: true,
        consequence: "DỪNG LƯỢT. Email đã đến hộp thư người dùng thật. Đây chính là kịch bản dẫn tới thiệt hại hàng chục nghìn USD trong bài học có thật của công ty." },
      { key: "s4c", label: "Giới hạn allowlist chỉ gửi tới email nội bộ", points: 10,
        consequence: "Đúng. Allowlist là cách chặn hiệu quả khi provider không có sandbox." }
    ] },
  { prompt: "Rollback plan của bạn hiện đang ở đâu?",
    options: [
      { key: "s5a", label: "Đã viết ra cụ thể: xoá bản ghi nào, ở bảng nào, bằng query nào", points: 10,
        consequence: "Đúng. Rollback plan phải có TRƯỚC khi bắt đầu, không phải nghĩ sau." },
      { key: "s5b", label: "Trong đầu rồi, xong việc tính sau", points: 0,
        consequence: "Đây là lý do dữ liệu test bị bỏ quên trên PROD." },
      { key: "s5c", label: "Sẽ nhờ DBA nếu có chuyện", points: 3,
        consequence: "Phụ thuộc người khác lúc khẩn cấp làm chậm thời gian khôi phục." }
    ] },
  { prompt: "Chạy test xong, kết quả đúng như mong đợi. Việc tiếp theo?",
    options: [
      { key: "s6a", label: "Dọn dữ liệu test ngay trong cùng phiên làm việc", points: 10,
        consequence: "Đúng. \"Để mai dọn\" là cách dữ liệu test đến tay khách hàng." },
      { key: "s6b", label: "Ghi chú vào TODO, mai dọn", points: 0,
        consequence: "Rủi ro cao: mai bạn bận việc khác, dữ liệu ở lại PROD." },
      { key: "s6c", label: "Để lại vài bản ghi phòng khi cần test tiếp", points: 0,
        consequence: "Dữ liệu \"để tạm\" là dữ liệu bị quên." }
    ] },
  { prompt: "Bạn dọn xong. Làm sao chắc chắn đã sạch?",
    options: [
      { key: "s7a", label: "Chạy lại đúng filter đã dùng để tạo dữ liệu, xác nhận trả về rỗng", points: 10,
        consequence: "Đúng. Xác minh bằng chính tiêu chí đã tạo ra dữ liệu." },
      { key: "s7b", label: "Nhìn qua màn hình danh sách thấy không còn là được", points: 3,
        consequence: "Màn hình có phân trang và bộ lọc mặc định, dễ bỏ sót." },
      { key: "s7c", label: "Tin là đã xoá hết vì query báo thành công", points: 0,
        consequence: "Query thành công không có nghĩa là đã xoá đúng phạm vi." }
    ] },
  { prompt: "Ai xác nhận việc dọn dẹp đã hoàn tất?",
    options: [
      { key: "s8a", label: "Nhờ người thứ hai kiểm tra lại (4-eyes)", points: 10,
        consequence: "Đúng. Người tạo ra dữ liệu là người dễ bỏ sót nó nhất." },
      { key: "s8b", label: "Tự mình xác nhận là đủ", points: 3,
        consequence: "Chấp nhận được với việc nhỏ, rủi ro với thao tác trên PROD." },
      { key: "s8c", label: "Không cần ai xác nhận", points: 0,
        consequence: "Không có lớp kiểm tra nào thì sai sót đi thẳng tới khách hàng." }
    ] },
  { prompt: "Báo cáo lại kết quả thế nào?",
    options: [
      { key: "s9a", label: "Ghi vào ticket: đã test gì, tạo gì, dọn gì, ai xác nhận", points: 10,
        consequence: "Đúng. Có ghi chép thì lần sau còn truy được." },
      { key: "s9b", label: "Nhắn miệng cho leader là xong rồi", points: 3,
        consequence: "Không tra lại được khi có vấn đề phát sinh sau này." },
      { key: "s9c", label: "Không báo, mọi thứ đều ổn mà", points: 0,
        consequence: "Không ai biết đã có thao tác trên PROD." }
    ] },
  { prompt: "Rút kinh nghiệm cho lần sau, đề xuất nào có giá trị nhất?",
    options: [
      { key: "s10a", label: "Đề xuất dựng môi trường Staging/UAT", points: 10,
        consequence: "Đúng. Checklist con người chỉ là băng dán; thiếu Staging mới là nguyên nhân gốc." },
      { key: "s10b", label: "Viết thêm checklist cho mọi người tự nhớ", points: 3,
        consequence: "Có ích, nhưng vẫn phụ thuộc việc người ta nhớ mở checklist ra." },
      { key: "s10c", label: "Nhắc nhau cẩn thận hơn", points: 0,
        consequence: "Không phải giải pháp mang tính hệ thống." }
    ] }
].freeze

3.times do |i|
  content, answer_key = roulette_scenario(
    "Kịch bản #{i + 1}: test tính năng gửi voucher trên môi trường PRODUCTION",
    ROULETTE_STEPS
  )
  # Mỗi kịch bản khác nhau ở tiêu đề nên checksum khác nhau.
  upsert_question(prod_roulette, content, answer_key)
end

# --- Incident Escape Room: 3 kịch bản, mỗi kịch bản 8 bước ---
escape_room = Game.find_by!(slug: Game::INCIDENT_ESCAPE_ROOM)

ESCAPE_STEPS = [
  { prompt: "03:10 — Cảnh báo: API trả 500 hàng loạt. Việc đầu tiên?",
    options: [
      { key: "e1a", label: "Mở dashboard xem phạm vi ảnh hưởng", points: 10, minutes: 2,
        explanation: "Đúng: xác định phạm vi trước khi đụng vào bất cứ thứ gì." },
      { key: "e1b", label: "Restart toàn bộ service ngay", points: 0, minutes: 8,
        explanation: "Restart mù xoá mất dấu vết và có thể không giải quyết nguyên nhân." },
      { key: "e1c", label: "Nhắn hỏi cả team xem ai vừa deploy", points: 5, minutes: 5,
        explanation: "Có ích, nhưng chờ người trả lời lúc 3 giờ sáng rất tốn thời gian." }
    ] },
  { prompt: "03:12 — 100% request tới /orders lỗi, các endpoint khác bình thường. Tiếp theo?",
    options: [
      { key: "e2a", label: "Đọc log của service orders quanh thời điểm bắt đầu lỗi", points: 10, minutes: 3,
        explanation: "Đúng: khoanh vùng đã hẹp, đọc log là bước rẻ nhất." },
      { key: "e2b", label: "Scale thêm instance cho orders", points: 0, minutes: 6,
        explanation: "Chưa biết nguyên nhân mà scale thì chỉ nhân bản lỗi." },
      { key: "e2c", label: "Kiểm tra dashboard database", points: 5, minutes: 3,
        explanation: "Hợp lý nhưng log service cho manh mối trực tiếp hơn." }
    ] },
  { prompt: "03:15 — Log đầy `ActiveRecord::ConnectionTimeoutError`. Nghĩ gì?",
    options: [
      { key: "e3a", label: "Kiểm tra số connection đang mở tới DB", points: 10, minutes: 3,
        explanation: "Đúng: timeout khi lấy connection thường do pool cạn." },
      { key: "e3b", label: "Tăng pool size rồi deploy ngay", points: 0, minutes: 10,
        explanation: "Sửa triệu chứng khi chưa biết vì sao pool cạn, dễ tái phát." },
      { key: "e3c", label: "Khởi động lại database", points: 0, minutes: 12,
        explanation: "Rủi ro rất cao, làm đứt cả những phần đang hoạt động bình thường." }
    ] },
  { prompt: "03:18 — DB đang có 200 connection, chạm giới hạn max_connections. Ai giữ?",
    options: [
      { key: "e4a", label: "Xem danh sách process đang chạy trên DB", points: 10, minutes: 3,
        explanation: "Đúng: nhìn thẳng vào query đang giữ connection." },
      { key: "e4b", label: "Kill hết connection cho nhanh", points: 0, minutes: 5,
        explanation: "Giết cả giao dịch đang chạy dở của người dùng thật." },
      { key: "e4c", label: "Tăng max_connections", points: 5, minutes: 4,
        explanation: "Câu giờ được, nhưng chưa chạm nguyên nhân." }
    ] },
  { prompt: "03:21 — Một query report chạy 40 phút chưa xong, giữ phần lớn connection. Làm gì?",
    options: [
      { key: "e5a", label: "Kill riêng query đó và ghi lại query id", points: 10, minutes: 2,
        explanation: "Đúng: xử lý đúng thủ phạm, giữ bằng chứng để điều tra sau." },
      { key: "e5b", label: "Chờ nó tự xong", points: 0, minutes: 15,
        explanation: "Dịch vụ tiếp tục chết trong lúc chờ." },
      { key: "e5c", label: "Kill query và không ghi lại gì", points: 5, minutes: 2,
        explanation: "Khôi phục được nhưng mất manh mối cho post-mortem." }
    ] },
  { prompt: "03:23 — API bắt đầu trả 200 trở lại. Bước tiếp theo?",
    options: [
      { key: "e6a", label: "Theo dõi 5 phút xác nhận ổn định rồi báo team", points: 10, minutes: 5,
        explanation: "Đúng: xác nhận đã khôi phục thật trước khi tuyên bố hết sự cố." },
      { key: "e6b", label: "Tuyên bố xong việc và đi ngủ", points: 0, minutes: 1,
        explanation: "Chưa xác nhận ổn định, sự cố có thể quay lại ngay." },
      { key: "e6c", label: "Bắt tay sửa code report luôn", points: 3, minutes: 10,
        explanation: "Sửa code lúc 3 giờ sáng chưa qua review là rủi ro mới." }
    ] },
  { prompt: "03:28 — Hệ thống ổn định. Ngăn tái phát ngay đêm nay bằng cách nào?",
    options: [
      { key: "e7a", label: "Tạm tắt job report định kỳ cho tới khi sửa xong", points: 10, minutes: 3,
        explanation: "Đúng: chặn nguồn gây sự cố bằng biện pháp đảo ngược được." },
      { key: "e7b", label: "Không làm gì, mai tính", points: 0, minutes: 1,
        explanation: "Job chạy lại lúc 4 giờ sáng thì sự cố lặp lại." },
      { key: "e7c", label: "Thêm statement timeout cho DB ngay lập tức", points: 5, minutes: 6,
        explanation: "Đúng hướng nhưng đổi cấu hình DB lúc đang mệt cần thận trọng." }
    ] },
  { prompt: "03:32 — Kết thúc ca xử lý. Việc cuối cùng?",
    options: [
      { key: "e8a", label: "Ghi timeline: mốc thời gian, hành động, kết quả", points: 10, minutes: 5,
        explanation: "Đúng: timeline là nguyên liệu chính cho post-mortem." },
      { key: "e8b", label: "Nhắn ngắn gọn \"đã fix\" vào nhóm", points: 3, minutes: 1,
        explanation: "Không đủ để người khác hiểu chuyện gì đã xảy ra." },
      { key: "e8c", label: "Không ghi gì, mai kể lại", points: 0, minutes: 1,
        explanation: "Chi tiết sẽ quên mất sau vài giờ ngủ." }
    ] }
].freeze

def escape_scenario(title, steps)
  nodes = steps.each_with_index.map do |step, i|
    {
      "key" => "n#{i + 1}",
      "prompt" => step[:prompt],
      "options" => step[:options].map { |o| { "key" => o[:key], "label" => o[:label] } }
    }
  end

  effects = {}
  steps.each_with_index do |step, i|
    step[:options].each do |o|
      effects[o[:key]] = {
        "points" => o[:points],
        "minutes_cost" => o[:minutes],
        "explanation" => o[:explanation],
        "next_node" => (i + 2 <= steps.size ? "n#{i + 2}" : "recovered")
      }
    end
  end

  [
    { "scenario" => title,
      "initial_logs" => "03:10:02 ERROR ActiveRecord::ConnectionTimeoutError: could not obtain a connection from the pool within 5.000 seconds",
      "nodes" => nodes },
    { "option_effects" => effects, "recovery_node" => "recovered" }
  ]
end

3.times do |i|
  content, answer_key = escape_scenario(
    "Kịch bản #{i + 1}: API trả 500 hàng loạt lúc 3 giờ sáng",
    ESCAPE_STEPS
  )
  upsert_question(escape_room, content, answer_key)
end

Game.order(:id).each do |game|
  puts "#{game.slug}: #{game.questions.playable.count} câu khả dụng " \
       "(cần #{game.questions_per_session} mỗi lượt)"
end
