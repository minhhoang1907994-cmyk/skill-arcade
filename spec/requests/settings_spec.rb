require "rails_helper"

RSpec.describe "Settings" do
  let(:user) { create(:user, password: "password123", password_confirmation: "password123") }

  def login
    post session_path, params: { email: user.email, password: "password123" }
  end

  describe "GET /settings" do
    it "guest bị đẩy về trang đăng nhập" do
      get settings_path

      expect(response).to redirect_to(login_path)
    end

    it "hiện lưới chọn với đủ số hình app có" do
      login
      get settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body.scan('name="user[avatar]"').size).to eq(Avatar::CHOICES.size)
    end
  end

  describe "PATCH /settings" do
    it "đổi hình đại diện của chính người đang đăng nhập (BR-40)" do
      login
      patch settings_path, params: { user: { avatar: "mimic" } }

      expect(response).to redirect_to(settings_path)
      expect(user.reload.avatar).to eq("mimic")
    end

    it "từ chối tên hình không có trong app và giữ nguyên hình cũ" do
      login
      patch settings_path, params: { user: { avatar: "../etc/passwd" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.avatar).to eq(Avatar::DEFAULT)
    end

    it "không cho guest đổi" do
      patch settings_path, params: { user: { avatar: "slime" } }

      expect(response).to redirect_to(login_path)
      expect(user.reload.avatar).to eq(Avatar::DEFAULT)
    end
  end
end
