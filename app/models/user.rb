class User < ApplicationRecord
  # Chỉ chấp nhận email dạng xxx.nta@gmail.com (BR-01).
  # Lưu ý: allowlist này không chặn được người cố ý — ai cũng đăng ký được Gmail
  # dạng này. Lớp bảo vệ thật là rate limit (spec section 12).
  EMAIL_FORMAT = /\A[a-z0-9._%+-]+\.nta@gmail\.com\z/i

  # Số lần đăng nhập sai liên tiếp trước khi khoá tài khoản (BR-23).
  MAX_FAILED_LOGINS = 5
  LOCK_DURATION = 15.minutes

  has_secure_password

  has_many :game_sessions, dependent: :destroy
  has_many :question_reports, dependent: :destroy
  has_many :handled_question_reports, class_name: "QuestionReport",
           foreign_key: :handled_by_id, dependent: :nullify, inverse_of: :handled_by

  validates :email, presence: true, uniqueness: { case_sensitive: false },
            format: { with: EMAIL_FORMAT }
  validates :display_name, presence: true, uniqueness: true, length: { in: 2..50 }
  validates :password, length: { minimum: 8 }, allow_nil: true
  # Hình đại diện chỉ được là một trong các sprite app có sẵn (BR-40) — cột lưu tên sprite
  # nên giá trị lạ sẽ làm mọi trang có hiển thị avatar nổ KeyError.
  validates :avatar, inclusion: { in: Avatar::CHOICES }

  normalizes :email, with: ->(email) { email.strip.downcase }

  scope :admins, -> { where(admin: true) }

  def locked?
    locked_until.present? && locked_until > Time.current
  end

  # Gọi sau mỗi lần đăng nhập sai. Chạm ngưỡng thì khoá tạm (BR-23).
  def register_failed_login!
    increment(:failed_login_count)
    self.locked_until = LOCK_DURATION.from_now if failed_login_count >= MAX_FAILED_LOGINS
    save!
  end

  def reset_failed_logins!
    update!(failed_login_count: 0, locked_until: nil)
  end

  # Điểm của một game = điểm cao nhất trong các lượt đã hoàn thành (BR-06, BR-08).
  def best_score_for(game)
    game_sessions.finished.where(game: game).maximum(:score) || 0
  end

  # Tổng điểm = tổng personal best của 5 game, tối đa 500 (BR-07).
  def total_score
    game_sessions.finished.group(:game_id).maximum(:score).values.sum
  end
end
