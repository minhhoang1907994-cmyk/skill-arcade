module Scoring
  # BR-29: 10 bước × 10 điểm. Chọn an toàn 10đ, rủi ro nhưng khôi phục được 3đ,
  # hành động KHÔNG THỂ THU HỒI thì 0đ và lượt kết thúc ngay tại đó.
  #
  # Điểm đã cộng ở các bước trước được giữ nguyên (BR-31) — dừng lượt là bài học,
  # không phải hình phạt xoá sạch.
  class ProdRoulette < Base
    def call(session:, question:, answer:, elapsed_ms:)
      node_key = fetch_answer(answer, :node_key).to_s
      option_key = fetch_answer(answer, :option_key).to_s

      effect = question.answer_key.dig("option_effects", option_key)
      raise InvalidAnswer, "lựa chọn không hợp lệ" if effect.nil?

      irreversible = effect["irreversible"] == true

      Result.new(
        score: irreversible ? 0 : effect["points"].to_i,
        explanation: effect["consequence_text"].to_s,
        terminal: irreversible,
        metadata: { "node_key" => node_key, "option_key" => option_key,
                    "irreversible" => irreversible, "next_node" => effect["next_node"] }
      )
    end
  end
end
