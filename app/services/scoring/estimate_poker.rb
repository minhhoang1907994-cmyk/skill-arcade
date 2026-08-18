module Scoring
  # BR-28: 10 task × 10 điểm theo sai số so với actual_hours.
  # BR-20: actual_hours cố định trong answer_key từ lúc sinh đề, không tính lại lúc chơi —
  # nhờ vậy mọi người chơi cùng một task đều được chấm theo cùng một đáp án.
  class EstimatePoker < Base
    THRESHOLDS = [
      [ 0.10, 10 ],
      [ 0.25, 7 ],
      [ 0.50, 4 ]
    ].freeze

    def call(session:, question:, answer:, elapsed_ms:)
      actual = question.answer_key["actual_hours"].to_f
      estimate = fetch_answer(answer, :hours).to_f

      raise InvalidAnswer, "ước lượng phải lớn hơn 0" if estimate <= 0
      raise InvalidAnswer, "đáp án của câu hỏi không hợp lệ" if actual <= 0

      deviation = ((estimate - actual).abs / actual)
      score = THRESHOLDS.find { |limit, _| deviation <= limit }&.last || 0

      Result.new(
        score: score,
        explanation: explain(actual, estimate, deviation, question.answer_key["reasoning"]),
        metadata: { "deviation" => deviation.round(4) }
      )
    end

    private

    def explain(actual, estimate, deviation, reasoning)
      parts = [
        "Bạn ước tính #{format('%g', estimate)}h, con số tham chiếu là #{format('%g', actual)}h " \
        "(lệch #{(deviation * 100).round}%)."
      ]
      parts << reasoning if reasoning.present?
      parts.join(" ")
    end
  end
end
