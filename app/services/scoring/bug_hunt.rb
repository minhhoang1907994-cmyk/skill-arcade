module Scoring
  # BR-25: 10 câu × 10 điểm. Đúng dòng 6 điểm, đúng loại bug 4 điểm.
  # BR-21: hệ số tốc độ nhân vào TỔNG điểm của câu rồi mới làm tròn xuống —
  # không nhân riêng từng thành phần.
  class BugHunt < Base
    LINE_POINTS = 6
    TYPE_POINTS = 4

    FAST_THRESHOLD_MS = 30_000
    MEDIUM_THRESHOLD_MS = 60_000

    def call(session:, question:, answer:, elapsed_ms:)
      key = question.answer_key
      line = fetch_answer(answer, :line).to_i
      bug_type = fetch_answer(answer, :bug_type).to_s

      line_correct = line == key["buggy_line"].to_i
      type_correct = bug_type == key["bug_type"].to_s

      raw = (line_correct ? LINE_POINTS : 0) + (type_correct ? TYPE_POINTS : 0)
      multiplier = speed_multiplier(elapsed_ms)
      score = (raw * multiplier).floor

      Result.new(
        score: score,
        explanation: explain(key, line_correct, type_correct, multiplier),
        metadata: { "line_correct" => line_correct, "type_correct" => type_correct,
                    "speed_multiplier" => multiplier }
      )
    end

    private

    def speed_multiplier(elapsed_ms)
      return 1.0 if elapsed_ms.nil? || elapsed_ms < FAST_THRESHOLD_MS
      return 0.8 if elapsed_ms < MEDIUM_THRESHOLD_MS

      0.5
    end

    def explain(key, line_correct, type_correct, multiplier)
      parts = []
      parts << if line_correct
        "Đúng dòng #{key['buggy_line']}."
      else
        "Bug nằm ở dòng #{key['buggy_line']}."
      end
      label = Question.bug_hunt_label(key["bug_type"])
      parts << "Loại bug: #{label['name']}#{type_correct ? ' (bạn chọn đúng)' : ''}."
      parts << key["explanation"] if key["explanation"].present?
      parts << "Hệ số tốc độ: ×#{multiplier}." if multiplier < 1.0
      parts.join(" ")
    end
  end
end
