module Scoring
  # BR-26: 5 đoạn spec × 20 điểm do AI chấm — tối đa 10đ cho việc tìm đủ điểm mơ hồ
  # và 10đ cho chất lượng câu hỏi làm rõ. Không có hệ số tốc độ vì người chơi phải gõ text.
  #
  # Đây là game DUY NHẤT gọi AI lúc chơi. Gemini hỏng thì game này trả 503 và lượt
  # chuyển abandoned với lý do system_error — không tính điểm, không trừ quota người
  # chơi (§8.5, BR-33). 4 game còn lại không bị ảnh hưởng vì chấm từ answer_key.
  class SpecDetective < Base
    MAX_SCORE_PER_PASSAGE = Gemini::SpecDetectiveGrader::AMBIGUITY_POINTS +
                            Gemini::SpecDetectiveGrader::QUESTION_POINTS

    def initialize(grader: Gemini::SpecDetectiveGrader.new)
      @grader = grader
    end

    def call(session:, question:, answer:, elapsed_ms:)
      # Validate đầu vào trước, để lỗi định dạng vẫn trả 400 thay vì 503.
      ambiguous_points = fetch_answer(answer, :ambiguous_points)
      questions = fetch_answer(answer, :questions)

      grading = @grader.call(question: question, ambiguous_points: ambiguous_points,
                             questions: questions)

      if grading.failed?
        raise GradingUnavailable.new(
          "Hệ thống chấm điểm tạm thời không khả dụng",
          ai_grading: grading.attributes
        )
      end

      Result.new(
        score: grading.score,
        explanation: grading.explanation,
        metadata: { "graded_by" => grading.attributes[:model] },
        ai_grading: grading.attributes
      )
    end
  end
end
