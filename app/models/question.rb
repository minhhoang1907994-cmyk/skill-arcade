require "digest"

class Question < ApplicationRecord
  SOURCES = %w[ai_generated manual].freeze
  DIFFICULTIES = %w[easy medium hard].freeze

  belongs_to :game
  has_many :session_answers, dependent: :restrict_with_error
  has_many :question_reports, dependent: :destroy

  validates :content, :answer_key, presence: true
  validates :checksum, presence: true, uniqueness: true
  validates :source, inclusion: { in: SOURCES }
  validates :difficulty, inclusion: { in: DIFFICULTIES }, allow_nil: true

  before_validation :assign_checksum

  # Câu bị ẩn không được bốc cho lượt mới, nhưng lượt cũ vẫn giữ nguyên điểm đã chấm (BR-16).
  scope :playable, -> { where(hidden: false) }

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
end
