class GameSession < ApplicationRecord
  IN_PROGRESS = "in_progress".freeze
  FINISHED = "finished".freeze
  ABANDONED = "abandoned".freeze
  STATES = [ IN_PROGRESS, FINISHED, ABANDONED ].freeze

  # Lý do bỏ lượt. Chỉ SYSTEM_ERROR được miễn trừ khỏi bộ đếm rate limit (BR-33).
  USER_QUIT = "user_quit".freeze
  TIMEOUT = "timeout".freeze
  SYSTEM_ERROR = "system_error".freeze
  ABANDONED_REASONS = [ USER_QUIT, TIMEOUT, SYSTEM_ERROR ].freeze

  # Lượt để quá thời gian này mà chưa xong sẽ bị đánh dấu bỏ dở (BR-24).
  STALE_AFTER = 24.hours

  belongs_to :user
  belongs_to :game
  has_many :session_answers, -> { order(:position) }, dependent: :destroy

  validates :state, inclusion: { in: STATES }
  validates :abandoned_reason, inclusion: { in: ABANDONED_REASONS }, allow_nil: true
  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  # MySQL dưới 8.0.16 bỏ qua CHECK constraint, nên validation ở đây là lớp bảo vệ thật.
  validates :score, numericality: {
    only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100
  }
  validates :started_at, presence: true

  scope :finished, -> { where(state: FINISHED).where.not(finished_at: nil) }
  scope :finished_between, ->(from, to) { finished.where(finished_at: from..to) }
  # Lượt hỏng do lỗi hệ thống không bị trừ vào hạn mức của người chơi (BR-33).
  scope :counting_toward_rate_limit, -> {
    where.not(state: ABANDONED, abandoned_reason: SYSTEM_ERROR)
  }
  scope :stale, -> { where(state: IN_PROGRESS).where(started_at: ...STALE_AFTER.ago) }

  def in_progress?
    state == IN_PROGRESS
  end

  def finished?
    state == FINISHED
  end

  # Lượt kết thúc khi đi hết số bước của game, hoặc chạm trần điểm (BR-04, BR-30).
  def completed_all_steps?
    current_position >= game.steps_per_session
  end

  def reached_max_score?
    score >= game.max_score
  end

  # BR-21: ghi mốc câu hỏi đang chờ được phát ra cho client, và CHỈ cho lần phát đầu tiên.
  # Tải lại trang giữa lượt gọi lại `GET current` — ghi lại mốc ở đó thì người chơi reset
  # được đồng hồ tốc độ bằng cách F5 trước khi trả lời.
  def mark_step_served!
    update!(step_served_at: Time.current) if step_served_at.nil?
  end

  def finish!
    update!(state: FINISHED, finished_at: Time.current)
  end

  def abandon!(reason)
    update!(state: ABANDONED, abandoned_reason: reason)
  end
end
