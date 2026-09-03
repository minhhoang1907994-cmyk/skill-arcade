module Questions
  # Gốc của mọi lỗi phát sinh trong namespace này, theo cùng khuôn với Gemini::Error.
  # Caller rescue được cả namespace bằng một class thay vì liệt kê từng lỗi cụ thể —
  # thêm lỗi mới không phải đi sửa mọi chỗ rescue.
  class Error < StandardError; end
end
