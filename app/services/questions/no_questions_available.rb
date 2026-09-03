module Questions
  # Không đủ đề để phục vụ bước đang cần.
  #
  # Cha chung của Questions::Drawer::NotEnoughQuestions, và cũng là lỗi mà
  # GameSessions::StepProvider ném thẳng khi không còn câu khả dụng — hai chỗ đó là CÙNG một
  # tình huống nghiệp vụ và phải ra cùng một mã lỗi cho client, nên Api::V1::BaseController
  # rescue đúng một class ở đây thay vì đuổi theo từng lớp con.
  #
  # StepProvider ném lỗi của namespace Questions chứ không tự khai lớp con riêng: cùng cách
  # GameSessions::Creator đã ném Questions::Drawer::NotEnoughQuestions từ trước.
  class NoQuestionsAvailable < Error; end
end
