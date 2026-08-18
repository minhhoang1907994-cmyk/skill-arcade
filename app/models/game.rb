class Game < ApplicationRecord
  BUG_HUNT = "bug_hunt".freeze
  SPEC_DETECTIVE = "spec_detective".freeze
  INCIDENT_ESCAPE_ROOM = "incident_escape_room".freeze
  ESTIMATE_POKER = "estimate_poker".freeze
  PROD_ROULETTE = "prod_roulette".freeze

  SLUGS = [ BUG_HUNT, SPEC_DETECTIVE, INCIDENT_ESCAPE_ROOM, ESTIMATE_POKER, PROD_ROULETTE ].freeze

  # Game duy nhất gọi AI lúc chơi. 4 game còn lại chấm từ answer_key trong DB,
  # nên vẫn chơi được khi Gemini không khả dụng (spec section 15).
  AI_GRADED_SLUGS = [ SPEC_DETECTIVE ].freeze

  has_many :questions, dependent: :restrict_with_error
  has_many :game_sessions, dependent: :restrict_with_error

  validates :slug, presence: true, uniqueness: true, inclusion: { in: SLUGS }
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, presence: true
  validates :questions_per_session, :steps_per_session, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :max_score, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(active: true) }

  def ai_graded?
    AI_GRADED_SLUGS.include?(slug)
  end

  # Kịch bản nhiều bước: một câu hỏi cung cấp nhiều position (BR-30).
  def scenario_based?
    questions_per_session < steps_per_session
  end
end
