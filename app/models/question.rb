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
