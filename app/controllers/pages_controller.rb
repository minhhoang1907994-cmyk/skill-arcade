# Trang tĩnh xem được không cần đăng nhập. Trang chính sách riêng tư phải đọc được TRƯỚC khi
# đăng ký, nên không có require_login ở đây.
class PagesController < ApplicationController
  # Ngày trang này được viết ra. Sửa nội dung thì phải sửa mốc này.
  PRIVACY_EFFECTIVE_ON = Date.new(2026, 8, 19)

  def privacy
    @effective_on = PRIVACY_EFFECTIVE_ON
    # Q8 chưa chốt kênh liên hệ để yêu cầu xoá tài khoản. Đọc từ ENV để owner cấu hình được
    # mà không cần sửa code; chưa cấu hình thì trang nói thẳng là chưa có kênh, không bịa ra.
    @contact = ENV["PRIVACY_CONTACT_EMAIL"].presence
  end
end
