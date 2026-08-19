module Gemini
  # Gốc của mọi lỗi phía Gemini. Circuit breaker đếm đúng lớp lỗi này, nên bất kỳ
  # thất bại nào đáng để ngừng gọi API tạm thời đều phải kế thừa từ đây.
  class Error < StandardError; end
end
