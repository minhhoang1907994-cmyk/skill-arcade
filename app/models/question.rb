require "digest"

class Question < ApplicationRecord
  SOURCES = %w[ai_generated manual].freeze
  DIFFICULTIES = %w[easy medium hard].freeze

  # Danh sách loại bug của Bug Hunt — đây là các lựa chọn hiển thị cho người chơi, nằm
  # trong `content["bug_types"]` của từng câu.
  #
  # THỨ TỰ LÀ MỘT PHẦN CỦA HỢP ĐỒNG: checksum = SHA-256 của content, nên đổi thứ tự hoặc
  # thêm/bớt phần tử sẽ đổi checksum của TOÀN BỘ câu Bug Hunt đang có. Chạy lại seed hay
  # import sau đó sẽ tạo bản ghi trùng thay vì cập nhật. Chỉ sửa danh sách này khi đã có
  # kế hoạch xử lý câu cũ.
  BUG_HUNT_TYPES = %w[
    sql_injection
    n_plus_one
    missing_null_check
    missing_transaction
    missing_authorization
    async_misuse
    missing_validation
    sensitive_data_logging
    xss
    swallowed_exception
    unbounded_query
    falsy_check
  ].freeze

  # Nhãn hiển thị cho từng loại bug: tên ngắn tiếng Việt + một dòng gợi ý dấu hiệu nhận
  # biết. Người chơi trước đây chỉ thấy slug tiếng Anh (`sensitive_data_logging`) nên khó
  # đoán loại nào là loại nào.
  #
  # Hash này KHÔNG đi vào checksum (chỉ `BUG_HUNT_TYPES` ở trên mới đi vào `content`),
  # nên sửa nhãn tự do, không ảnh hưởng câu hỏi đã import.
  BUG_HUNT_TYPE_LABELS = {
    "sql_injection" => {
      "name" => "SQL Injection",
      "hint" => "Nối input của người dùng vào câu SQL thay vì dùng placeholder"
    },
    "n_plus_one" => {
      "name" => "Query N+1",
      "hint" => "Lặp qua danh sách rồi query DB lại trong mỗi vòng lặp"
    },
    "missing_null_check" => {
      "name" => "Thiếu kiểm tra null",
      "hint" => "Dùng giá trị có thể null/undefined mà không kiểm tra trước"
    },
    "missing_transaction" => {
      "name" => "Thiếu transaction",
      "hint" => "Nhiều thao tác ghi phải cùng thành công hoặc cùng rollback"
    },
    "missing_authorization" => {
      "name" => "Thiếu kiểm tra quyền",
      "hint" => "Không kiểm tra người gọi có quyền với dữ liệu đang truy cập"
    },
    "async_misuse" => {
      "name" => "Dùng sai async/await",
      "hint" => "Thiếu await, hoặc chạy song song việc phải làm tuần tự"
    },
    "missing_validation" => {
      "name" => "Thiếu validate input",
      "hint" => "Nhận dữ liệu từ ngoài mà không kiểm tra định dạng, giới hạn"
    },
    "sensitive_data_logging" => {
      "name" => "Log dữ liệu nhạy cảm",
      "hint" => "Ghi mật khẩu, token, thông tin cá nhân ra log"
    },
    "xss" => {
      "name" => "XSS",
      "hint" => "Đưa dữ liệu người dùng vào HTML mà không escape"
    },
    "swallowed_exception" => {
      "name" => "Nuốt exception",
      "hint" => "Bắt lỗi rồi bỏ qua, không log cũng không xử lý"
    },
    "unbounded_query" => {
      "name" => "Query không giới hạn",
      "hint" => "Lấy toàn bộ bảng, thiếu LIMIT hoặc phân trang"
    },
    "falsy_check" => {
      "name" => "Nhầm falsy với rỗng",
      "hint" => "Kiểu `if (!x)` khiến 0 hay chuỗi rỗng bị coi là thiếu giá trị"
    }
  }.freeze

  belongs_to :game
  has_many :session_answers, dependent: :restrict_with_error
  has_many :question_reports, dependent: :destroy

  validates :content, :answer_key, presence: true
  validates :checksum, presence: true, uniqueness: true
  validates :source, inclusion: { in: SOURCES }
  validates :difficulty, inclusion: { in: DIFFICULTIES }, allow_nil: true

  before_validation :assign_checksum
  before_validation :assign_language

  # Câu bị ẩn không được bốc cho lượt mới, nhưng lượt cũ vẫn giữ nguyên điểm đã chấm (BR-16).
  scope :playable, -> { where(hidden: false) }
  # Lọc theo ngôn ngữ lập trình; truyền nil thì không lọc (game không phân ngôn ngữ).
  scope :in_language, ->(language) { language.present? ? where(language: language) : all }

  # Nhãn của một loại bug; slug lạ (đề cũ, dữ liệu sai) thì trả về chính slug đó thay vì
  # nil để chỗ hiển thị không phải tự xử lý.
  def self.bug_hunt_label(type)
    BUG_HUNT_TYPE_LABELS[type.to_s] || { "name" => type.to_s, "hint" => "" }
  end

  def self.checksum_for(content)
    Digest::SHA256.hexdigest(content.to_json)
  end

  # answer_key không bao giờ được serialize ra response (BR-03).
  # Override cả as_json và serializable_hash để không lọt qua đường nào.
  def as_json(options = {})
    super(options.merge(except: Array(options[:except]) + [ :answer_key ]))
  end

  def serializable_hash(options = nil)
    options = (options || {}).dup
    options[:except] = Array(options[:except]) + [ :answer_key ]
    super(options)
  end

  # Payload an toàn để gửi cho client.
  def playable_content
    { position: nil, question_id: id, content: content }
  end

  private

  def assign_checksum
    self.checksum = self.class.checksum_for(content) if content.present?
  end

  # Ngôn ngữ nằm trong content khi sinh đề; nhân ra cột riêng để lọc bằng index.
  def assign_language
    self.language = content["language"].presence if content.is_a?(Hash)
  end
end
