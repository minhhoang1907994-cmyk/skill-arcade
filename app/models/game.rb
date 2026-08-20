class Game < ApplicationRecord
  BUG_HUNT = "bug_hunt".freeze
  SPEC_DETECTIVE = "spec_detective".freeze
  INCIDENT_ESCAPE_ROOM = "incident_escape_room".freeze
  ESTIMATE_POKER = "estimate_poker".freeze
  PROD_ROULETTE = "prod_roulette".freeze

  SLUGS = [ BUG_HUNT, SPEC_DETECTIVE, INCIDENT_ESCAPE_ROOM, ESTIMATE_POKER, PROD_ROULETTE ].freeze

  has_many :questions, dependent: :restrict_with_error
  has_many :game_sessions, dependent: :restrict_with_error

  validates :slug, presence: true, uniqueness: true, inclusion: { in: SLUGS }
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, presence: true
  validates :questions_per_session, :steps_per_session, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :max_score, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(active: true) }

  # Kịch bản nhiều bước: một câu hỏi cung cấp nhiều position (BR-30).
  def scenario_based?
    questions_per_session < steps_per_session
  end

  # Game phân đề theo ngôn ngữ lập trình — người chơi chọn trước khi vào lượt.
  def language_scoped?
    slug == BUG_HUNT
  end

  # Ngôn ngữ nhận là hợp lệ khi tạo lượt: có mặt trong ngân hàng câu hỏi, kể cả khi
  # chưa đủ câu cho trọn một lượt (trường hợp đó trả NO_QUESTIONS_AVAILABLE).
  def available_languages
    return [] unless language_scoped?

    questions.playable.where.not(language: nil).distinct.pluck(:language).sort
  end

  # Danh sách hiện cho người chơi chọn: chỉ ngôn ngữ còn đủ câu cho trọn một lượt,
  # để không chọn xong mới nhận lỗi không đủ câu hỏi.
  def playable_languages
    return [] unless language_scoped?

    questions.playable.where.not(language: nil)
             .group(:language).count
             .select { |_lang, count| count >= questions_per_session }
             .keys.sort
  end
end
