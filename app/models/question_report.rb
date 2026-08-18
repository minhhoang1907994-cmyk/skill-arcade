class QuestionReport < ApplicationRecord
  OPEN = "open".freeze
  ACCEPTED = "accepted".freeze
  REJECTED = "rejected".freeze
  STATUSES = [ OPEN, ACCEPTED, REJECTED ].freeze

  belongs_to :user
  belongs_to :question
  belongs_to :handled_by, class_name: "User", optional: true,
             inverse_of: :handled_question_reports

  validates :reason, presence: true
  validates :status, inclusion: { in: STATUSES }
  # Mỗi người báo mỗi câu tối đa một lần (BR-17).
  validates :question_id, uniqueness: { scope: :user_id }

  scope :open, -> { where(status: OPEN) }

  # Chấp nhận báo cáo thì ẩn câu hỏi, không xoá cứng (BR-18).
  def accept!(admin)
    transaction do
      update!(status: ACCEPTED, handled_by: admin, handled_at: Time.current)
      question.update!(hidden: true)
    end
  end

  def reject!(admin)
    update!(status: REJECTED, handled_by: admin, handled_at: Time.current)
  end
end
