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
        metadata: { "deviation" => deviation.round(4) },
        breakdown: breakdown_for(question.answer_key, actual)
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

    # Bảng "thao tác nào tốn bao nhiêu giờ" hiện kèm giải thích. Trả nil khi đề không có
    # bảng (đề cũ nhập trước khi Validator bắt buộc khoá này) — client tự lùi về chỉ hiện
    # phần chữ.
    #
    # Tổng các dòng phải khớp actual_hours, không thì bỏ luôn bảng: người chơi bị chấm theo
    # actual_hours, hiện một bảng cộng ra số khác là tự mâu thuẫn với chính điểm vừa cho.
    # Validator chặn từ lúc import, đây là lưới cuối cho đề đã nằm sẵn trong DB.
    def breakdown_for(answer_key, actual)
      rows = answer_key["breakdown"]
      return nil unless rows.is_a?(Array) && rows.any?

      rows = rows.filter_map do |row|
        next nil unless row.is_a?(Hash) && row["step"].present? && row["hours"].to_f.positive?

        { "step" => row["step"].to_s, "hours" => row["hours"].to_f }
      end
      return nil if rows.empty?
      return nil if (rows.sum { |row| row["hours"] } - actual).abs > 0.01

      rows
    end
  end
end
