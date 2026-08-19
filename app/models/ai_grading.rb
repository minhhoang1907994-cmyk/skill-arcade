# Log mỗi lần gọi AI chấm điểm, kể cả lần gọi thất bại (BR-19).
# Bản ghi bất biến: không sửa, không xoá. Đây là bằng chứng duy nhất để giải trình
# khi người chơi khiếu nại điểm.
#
# Lưu ý về dữ liệu người dùng: cột prompt chứa nội dung người chơi tự nhập ở
# Spec Detective và được giữ vĩnh viễn. Chỉ admin đọc được (spec section 14).
class AiGrading < ApplicationRecord
  belongs_to :session_answer

  validates :model, presence: true, length: { maximum: 50 }
  validates :prompt, presence: true
  # Lần gọi thất bại (timeout, HTTP lỗi, breaker mở) không có body trả về. Cột response
  # là NOT NULL nên ghi chuỗi rỗng, và cột error là nơi mang thông tin (§8.5).
  validates :response, presence: true, unless: :failed?
  validates :score, numericality: {
    only_integer: true, greater_than_or_equal_to: 0
  }, allow_nil: true

  # Không có updated_at trong bảng này.
  self.record_timestamps = false

  before_validation :assign_created_at, on: :create

  def failed?
    error.present?
  end

  private

  def assign_created_at
    self.created_at ||= Time.current
  end
end
