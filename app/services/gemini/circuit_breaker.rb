module Gemini
  # Spec §15: mở sau 5 lần lỗi Gemini liên tiếp và giữ mở 5 phút. Mục đích là ngừng
  # nện API khi nó đang hỏng — 4/5 game vẫn chơi được bình thường vì chấm từ answer_key.
  #
  # Trạng thái nằm ở Rails.cache, KHÔNG ở biến class, để nhiều worker Puma cùng thấy.
  # Kéo theo một giới hạn phải biết: cache store hiện tại là per-host
  # (`:memory_store` ở development, mặc định `:file_store` ở production). Chạy nhiều
  # host thì mỗi host có breaker riêng — muốn dùng chung phải chuyển sang
  # `:mem_cache_store` / Redis. Ghi rõ ở đây vì đây là điểm dễ hiểu sai khi scale.
  #
  # Bộ đếm lỗi cũng có TTL bằng OPEN_DURATION: "liên tiếp" chỉ có nghĩa trong một
  # khoảng thời gian, không thì 5 lần lỗi rải rác cả tháng cũng mở breaker.
  class CircuitBreaker
    class OpenError < Error; end

    FAILURE_THRESHOLD = 5
    OPEN_DURATION = 5.minutes

    def initialize(name: "gemini", cache: Rails.cache)
      @name = name
      @cache = cache
    end

    def open?
      @cache.read(open_key).present?
    end

    # Chạy block qua breaker. Chỉ lỗi Gemini::Error mới tính vào bộ đếm — lỗi lập trình
    # (ArgumentError, NoMethodError...) không phải dấu hiệu API đang hỏng.
    def run(&block)
      # OpenError phải được raise NGOÀI phạm vi rescue của attempt: lần gọi bị breaker
      # chặn không phải một lần API lỗi, không được tính vào bộ đếm.
      raise OpenError, "Gemini circuit breaker đang mở" if open?

      attempt(&block)
    end

    def reset
      @cache.delete(failure_key)
      @cache.delete(open_key)
    end

    private

    def attempt
      result = yield
      reset
      result
    rescue Error
      record_failure
      raise
    end

    def record_failure
      count = @cache.read(failure_key).to_i + 1

      if count >= FAILURE_THRESHOLD
        @cache.write(open_key, Time.current.to_i, expires_in: OPEN_DURATION)
        @cache.delete(failure_key)
        Rails.logger.warn("[gemini] circuit breaker mở sau #{count} lỗi liên tiếp")
      else
        @cache.write(failure_key, count, expires_in: OPEN_DURATION)
      end
    end

    def failure_key
      "#{@name}/circuit/failures"
    end

    def open_key
      "#{@name}/circuit/open_at"
    end
  end
end
