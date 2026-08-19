# Rate limit theo bảng ở spec section 12.
#
# Hai điểm quan trọng:
# - Các rule được đánh giá độc lập; chạm ngưỡng nào trước thì rule đó chặn (BR-34).
#   Một lượt Spec Detective tính vào cả hạn mức riêng của game lẫn hạn mức lượt chung.
# - Lượt hỏng do lỗi hệ thống không được tính vào hạn mức (BR-33) — phần đó xử lý ở
#   tầng ứng dụng khi đếm game_sessions, không phải ở đây.
#
# Lưu ý: allowlist email *.nta@gmail.com KHÔNG chặn được người cố ý (ai cũng đăng ký
# được Gmail dạng đó). Rate limit mới là lớp bảo vệ thật của app public này.
class Rack::Attack
  ### Đăng ký: 5 lần/giờ/IP
  throttle("signup/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/users"
  end

  ### Đăng nhập: 20 lần/15 phút/IP.
  # Khoá theo tài khoản sau 5 lần sai là rule riêng ở tầng model (BR-23).
  throttle("login/ip", limit: 20, period: 15.minutes) do |req|
    req.ip if req.post? && req.path == "/session"
  end

  ### Bắt đầu lượt chơi: 20 lượt/giờ và 60 lượt/ngày cho mỗi user.
  throttle("sessions/user/hourly", limit: 20, period: 1.hour) do |req|
    game_session_user_id(req)
  end

  throttle("sessions/user/daily", limit: 60, period: 1.day) do |req|
    game_session_user_id(req)
  end

  ### Spec Detective gọi Gemini real-time: 1 lượt/NGÀY/user (5 API call/ngày/user).
  #
  # Con số này bị hạn mức Gemini quyết định, không phải bởi thiết kế gameplay: gói free
  # đo được 20 request/ngày cho mỗi model (spec §20), mỗi lượt 5 đoạn = 5 request, nên cả
  # hệ thống chỉ đủ 4 lượt/ngày. Mức cũ 5 lượt/GIỜ/user cho một người tiêu 25 request
  # trong một giờ — vượt hạn mức cả ngày và đẩy mọi người còn lại vào 503.
  #
  # CHÚ Ý: đây là hạn mức THEO USER nên vẫn không chặn được tổng hệ thống — 20 user khác
  # nhau mỗi người 1 lượt vẫn là 100 request. Muốn chặn cứng phải thêm một throttle dùng
  # discriminator hằng số (xem spec §20).
  throttle("sessions/spec_detective/user", limit: 1, period: 1.day) do |req|
    user_id = game_session_user_id(req)
    "#{user_id}/spec_detective" if user_id && req.path.include?("/games/spec_detective/")
  end

  ### Báo câu hỏi sai: 10 lần/ngày/user
  throttle("reports/user", limit: 10, period: 1.day) do |req|
    if req.post? && req.path.match?(%r{\A/api/v1/questions/\d+/reports\z})
      req.env["rack.session"]&.dig("user_id")
    end
  end

  ### Lưới chung: 100 request/phút/IP
  throttle("req/ip", limit: 100, period: 1.minute, &:ip)

  # Thông điệp phải khớp loại hạn mức. "Thao tác quá nhanh" đúng với các rule tính theo
  # phút/giờ, nhưng SAI với hạn mức 1 lượt/ngày của Spec Detective: người chơi đâu có nhanh,
  # họ đã dùng hết lượt của ngày. Không phân biệt thì họ retry cả ngày vô ích.
  THROTTLE_MESSAGES = {
    "sessions/spec_detective/user" =>
      "Spec Detective giới hạn 1 lượt mỗi ngày cho mỗi người, do hạn mức của dịch vụ chấm "       "điểm AI. Mời bạn quay lại ngày mai, hoặc chơi 4 game còn lại.",
    "sessions/user/daily" => "Bạn đã dùng hết số lượt chơi trong ngày, thử lại ngày mai.",
    "reports/user" => "Bạn đã gửi hết số lượt báo lỗi trong ngày, thử lại ngày mai."
  }.freeze

  DEFAULT_THROTTLE_MESSAGE = "Bạn thao tác quá nhanh, thử lại sau".freeze

  self.throttled_responder = lambda do |request|
    rule = request.env["rack.attack.matched"]
    message = THROTTLE_MESSAGES.fetch(rule, DEFAULT_THROTTLE_MESSAGE)
    body = { code: "TOO_MANY_REQUESTS", message: message }.to_json
    [ 429, { "content-type" => "application/json" }, [ body ] ]
  end

  def self.game_session_user_id(req)
    return nil unless req.post?
    return nil unless req.path.match?(%r{\A/api/v1/games/[a-z_]+/sessions\z})

    req.env["rack.session"]&.dig("user_id")
  end
end

ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn(
    "[rack-attack] throttled rule=#{req.env['rack.attack.matched']} ip=#{req.ip} path=#{req.path}"
  )
end
