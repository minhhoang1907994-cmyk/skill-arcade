require "rails_helper"

RSpec.describe "Trang chính sách riêng tư (Q7)" do
  # Nội dung trong ERB bị ngắt dòng theo bề rộng file, nên assert trên body thô rất giòn:
  # "Google Gemini" có thể nằm hai dòng khác nhau. Nén khoảng trắng trước khi so.
  def body_text
    response.body.gsub(/\s+/, " ")
  end

  it "guest đọc được — phải đọc được TRƯỚC khi đăng ký" do
    get privacy_path

    expect(response).to have_http_status(:ok)
  end

  it "công bố rõ nội dung người chơi KHÔNG ra khỏi app (1.19)" do
    get privacy_path

    expect(body_text).to include("Nội dung bạn nhập trong game không đi ra khỏi app")
    expect(body_text).to include("Google Gemini")
    expect(body_text).to include("ngoài lúc chơi")
    # Cảnh báo cũ phải biến mất cùng ô gõ text: giữ lại là nói sai về hành vi của app.
    expect(body_text).not_to include("người thật của Google có thể đọc")
    expect(body_text).not_to include("đừng dán nội dung nội bộ của công ty hoặc của khách hàng")
  end

  it "công bố Google Fonts nhận IP của người dùng" do
    get privacy_path

    expect(body_text).to include("fonts.googleapis.com")
  end

  it "nêu đúng số ngày lưu log theo gói Render đang dùng" do
    get privacy_path

    expect(body_text).to include("Log ứng dụng giữ #{PagesController::LOG_RETENTION_DAYS} ngày")
  end

  it "nói rõ bản ghi chấm điểm AI CŨ giữ vĩnh viễn và bảng xếp hạng là công khai" do
    get privacy_path

    expect(body_text).to include("Bản ghi chấm điểm AI cũ giữ vĩnh viễn")
    expect(body_text).to include("xem được không cần đăng nhập")
  end

  describe "kênh liên hệ yêu cầu xoá tài khoản (Q8 chưa chốt)" do
    it "chưa cấu hình thì nói thẳng là chưa có kênh, không bịa địa chỉ" do
      get privacy_path

      expect(body_text).to include("chưa công bố kênh liên hệ")
    end

    it "cấu hình rồi thì hiện địa chỉ đó" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PRIVACY_CONTACT_EMAIL").and_return("privacy@example.com")

      get privacy_path

      expect(body_text).to include("privacy@example.com")
      expect(body_text).not_to include("chưa công bố kênh liên hệ")
    end
  end

  it "mọi trang đều có đường vào trang chính sách" do
    get root_path
    expect(response.body).to include(privacy_path)

    get login_path
    expect(response.body).to include(privacy_path)
  end

  it "trang đăng ký cảnh báo trước khi tạo tài khoản" do
    get signup_path

    expect(body_text).to include("bảng xếp hạng công khai")
    expect(body_text).to include(privacy_path)
  end
end
