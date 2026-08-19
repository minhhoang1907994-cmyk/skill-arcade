module Gemini
  # Hạn mức gọi Gemini còn lại, dùng để CHẶN TRƯỚC thay vì để người chơi vào giữa lượt mới
  # nhận 503.
  #
  # Vì sao cần: hạn mức free tier đo được là 20 request/ngày cho mỗi model (spec §20), mỗi
  # lượt Spec Detective tiêu `steps_per_session` request. Throttle 1 lượt/ngày/user ở
  # rack_attack chỉ chặn theo TỪNG NGƯỜI nên không bound được tổng — 20 người khác nhau vẫn
  # vượt hạn mức. Lớp này bound tổng.
  #
  # Vì sao đếm bằng bảng `ai_gradings` chứ không phải Rails.cache như circuit breaker:
  # - BR-19 bảo đảm MỌI lời gọi chấm điểm ghi đúng một dòng, kể cả lời gọi THẤT BẠI — mà lời
  #   gọi thất bại vẫn tiêu hạn mức của Google. Đếm số lượt chơi thì sẽ đếm thiếu.
  # - Ở DB nên nhiều process/host cùng thấy một con số. Cache thì mỗi host một bản.
  #
  # Vì sao cửa sổ TRƯỢT 24 giờ chứ không phải "từ 0h hôm nay": không xác định được Google chốt
  # ngày theo múi giờ nào. Cửa sổ trượt luôn chặt hơn hoặc bằng mọi cửa sổ ngày cố định, nên
  # không bao giờ cho vượt 20 request trong bất kỳ khoảng 24 giờ nào — kể cả khi mốc reset của
  # Google lệch với mốc của app.
  #
  # HẠN CHẾ phải biết: `rake questions:generate` KHÔNG ghi `ai_gradings` (cột
  # `session_answer_id` là NOT NULL, đề sinh ra chưa gắn với câu trả lời nào), nên request sinh
  # đề không được tính vào đây. Con số ở đây là hạn mức còn lại VỚI GIẢ ĐỊNH hôm nay không chạy
  # sinh đề. Rake task dùng lại lớp này để cảnh báo, xem lib/tasks/questions.rake.
  class DailyBudget
    # Đo được từ HTTP 429 của Google: `limit: 20, model: gemini-3.6-flash` (spec §20).
    DAILY_REQUEST_LIMIT = 20
    WINDOW = 24.hours

    def initialize(now: Time.current)
      @now = now
    end

    def used
      @used ||= AiGrading.where(created_at: (@now - WINDOW)..@now).count
    end

    def remaining
      [ DAILY_REQUEST_LIMIT - used, 0 ].max
    end

    # Mỗi bước của lượt là một lời gọi chấm, nên giá của một lượt là số bước.
    def requests_per_session(game)
      game.steps_per_session.to_i
    end

    def sessions_left(game)
      cost = requests_per_session(game)
      return 0 unless cost.positive?

      remaining / cost
    end

    def enough_for_session?(game)
      sessions_left(game).positive?
    end
  end
end
