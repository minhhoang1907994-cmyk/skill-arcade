module Scoring
  # BR-26: 5 đoạn spec × 20 điểm, chấm hoàn toàn từ `answer_key` trong DB — 10đ cho việc
  # tick đúng những câu mơ hồ, 10đ cho việc chọn đúng câu hỏi làm rõ tốt nhất trong 4
  # phương án. Không có hệ số tốc độ: người chơi phải đọc hiểu đoạn spec, thưởng tốc độ
  # ở đây chỉ khuyến khích tick bừa.
  #
  # Trước phiên bản 1.19 game này gọi Gemini lúc chấm và là game DUY NHẤT làm vậy. Đổi
  # sang chọn để bỏ lời gọi AI khỏi request path — xem changelog 1.19 và §20. Hệ quả: cả
  # 5 game giờ đều chấm từ DB nên Gemini hỏng không ảnh hưởng lúc chơi.
  #
  # Nửa điểm tick PHẢI trừ tick sai. Không trừ thì tick toàn bộ câu trong đoạn là ăn đủ
  # 10đ mà không cần đọc, và game mất hết ý nghĩa.
  class SpecDetective < Base
    STATEMENT_POINTS = 10
    QUESTION_POINTS = 10

    def call(session:, question:, answer:, elapsed_ms:)
      key = question.answer_key
      picked = normalize_indexes(fetch_answer(answer, :statement_indexes))
      option_key = fetch_answer(answer, :option_key).to_s
      expected = normalize_indexes(key["ambiguous_statement_indexes"])

      hit = (picked & expected).size
      miss = (picked - expected).size
      statement_score = statement_score_for(hit, miss, expected.size)
      option_correct = option_key.present? && option_key == key["best_option_key"].to_s

      Result.new(
        score: statement_score + (option_correct ? QUESTION_POINTS : 0),
        explanation: explain(question, key, expected, hit, miss, option_correct),
        metadata: { "statement_hit" => hit, "statement_miss" => miss,
                    "option_correct" => option_correct }
      )
    end

    private

    # Người chơi gửi mảng số thứ tự câu, đếm từ 1 theo content["statements"].
    def normalize_indexes(value)
      Array(value).map(&:to_i).select(&:positive?).uniq.sort
    end

    def statement_score_for(hit, miss, expected_size)
      return 0 unless expected_size.positive?

      raw = (hit - miss) * STATEMENT_POINTS / expected_size.to_f
      raw.floor.clamp(0, STATEMENT_POINTS)
    end

    def explain(question, key, expected, hit, miss, option_correct)
      parts = [
        "Câu mơ hồ: #{expected.join(', ')} — bạn tìm đúng #{hit}/#{expected.size}" \
        "#{miss.positive? ? ", tick sai #{miss}" : ''}.",
        option_correct ? "Chọn đúng câu hỏi làm rõ tốt nhất." :
                         "Câu hỏi làm rõ tốt nhất: #{best_option_text(question, key)}"
      ]
      parts << key["explanation"].to_s if key["explanation"].present?
      parts.join(" ")
    end

    # Thứ tự phương án bị đảo lúc hiển thị (GameSessions::StepProvider) nên nói "phương án
    # a" không còn chỉ được vào đâu — phản hồi phải nhắc lại nội dung phương án đúng.
    def best_option_text(question, key)
      best_key = key["best_option_key"].to_s
      label = Array(question.content["clarifying_options"])
              .find { |o| o["key"].to_s == best_key }&.dig("label")

      label.presence || "phương án #{best_key}"
    end
  end
end
