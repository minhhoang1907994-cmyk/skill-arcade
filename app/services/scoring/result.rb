module Scoring
  # Kết quả chấm một bước.
  #
  # score       — điểm của riêng bước này, luôn >= 0 (BR-31: mô hình cộng dồn)
  # explanation — giải thích hiển thị cho người chơi sau khi trả lời
  # terminal    — true thì lượt kết thúc ngay tại bước này, không phục vụ bước tiếp
  #               (PROD Roulette chọn hành động không thể thu hồi, Escape Room quá giờ)
  # metadata    — dữ liệu phụ lưu kèm câu trả lời, ví dụ minutes_cost của Escape Room
  Result = Struct.new(:score, :explanation, :terminal, :metadata, keyword_init: true) do
    def initialize(score:, explanation: nil, terminal: false, metadata: {})
      super
    end

    def terminal?
      terminal
    end
  end
end
