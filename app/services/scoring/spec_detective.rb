module Scoring
  # BR-26: 5 đoạn spec × 20 điểm do AI chấm — tối đa 10đ cho việc tìm đủ điểm mơ hồ
  # và 10đ cho chất lượng câu hỏi làm rõ. Không có hệ số tốc độ vì người chơi phải gõ text.
  #
  # Đây là game DUY NHẤT gọi AI lúc chơi. Client Gemini thuộc Phase 3, nên hiện tại
  # scorer báo GradingUnavailable — controller sẽ trả 503 và lượt chuyển abandoned với
  # lý do system_error, không tính điểm và không trừ quota của người chơi (§8.5, BR-33).
  class SpecDetective < Base
    MAX_SCORE_PER_PASSAGE = 20

    def call(session:, question:, answer:, elapsed_ms:)
      # Validate đầu vào trước, để lỗi định dạng vẫn trả 400 thay vì 503.
      fetch_answer(answer, :ambiguous_points)
      fetch_answer(answer, :questions)

      raise GradingUnavailable,
            "Chấm điểm Spec Detective cần Gemini API — sẽ có ở Phase 3"
    end
  end
end
