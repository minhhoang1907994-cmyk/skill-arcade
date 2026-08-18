module Scoring
  # BR-27: 8 bước × 10 điểm + thưởng thời gian tối đa 20 điểm = 100.
  # Mỗi bước: hành động đúng 10đ, hành động vô hại nhưng tốn thời gian 5đ,
  # hành động sai 0đ và cộng thêm minutes_cost của nó.
  #
  # Thưởng thời gian được cộng lúc kết thúc lượt, xử lý ở GameSessions::AnswerSubmitter.
  # Quá 30 phút giả lập thì lượt dừng ngay và không có thưởng (§8.3).
  class IncidentEscapeRoom < Base
    TIME_LIMIT_MINUTES = 30
    BONUS_TIERS = [
      [ 15, 20 ],
      [ 30, 10 ]
    ].freeze

    def call(session:, question:, answer:, elapsed_ms:)
      node_key = fetch_answer(answer, :node_key).to_s
      option_key = fetch_answer(answer, :option_key).to_s

      effect = question.answer_key.dig("option_effects", option_key)
      raise InvalidAnswer, "lựa chọn không hợp lệ" if effect.nil?

      minutes_cost = effect["minutes_cost"].to_i
      total_minutes = self.class.elapsed_minutes(session) + minutes_cost
      over_limit = total_minutes > TIME_LIMIT_MINUTES

      Result.new(
        score: effect["points"].to_i,
        explanation: explain(effect, minutes_cost, total_minutes, over_limit),
        # Quá giờ thì dừng; đến node khôi phục cũng dừng vì sự cố đã xử lý xong.
        terminal: over_limit || reached_recovery?(question, effect),
        metadata: { "node_key" => node_key, "option_key" => option_key,
                    "minutes_cost" => minutes_cost, "total_minutes" => total_minutes,
                    "over_limit" => over_limit, "next_node" => effect["next_node"] }
      )
    end

    # Tổng thời gian giả lập đã tiêu của lượt, cộng từ metadata các bước trước.
    def self.elapsed_minutes(session)
      session.session_answers.sum { |sa| sa.answer.dig("_meta", "minutes_cost").to_i }
    end

    # Thưởng thời gian lúc kết thúc: <=15 phút được 20đ, <=30 phút được 10đ, quá thì 0đ.
    def self.time_bonus(total_minutes)
      BONUS_TIERS.find { |limit, _| total_minutes <= limit }&.last || 0
    end

    private

    def reached_recovery?(question, effect)
      recovery = question.answer_key["recovery_node"]
      recovery.present? && effect["next_node"].to_s == recovery.to_s
    end

    def explain(effect, minutes_cost, total_minutes, over_limit)
      parts = [ effect["explanation"].presence || "Đã ghi nhận lựa chọn." ]
      parts << "Tốn #{minutes_cost} phút giả lập (tổng #{total_minutes} phút)."
      parts << "Quá #{TIME_LIMIT_MINUTES} phút — sự cố không được khắc phục kịp, không có điểm thưởng thời gian." if over_limit
      parts.join(" ")
    end
  end
end
