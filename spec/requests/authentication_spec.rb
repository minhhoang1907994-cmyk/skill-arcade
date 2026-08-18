require "rails_helper"

RSpec.describe "Authentication" do
  describe "POST /users" do
    let(:valid_params) do
      {
        user: {
          email: "newplayer.nta@gmail.com",
          display_name: "New Player",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    it "tạo tài khoản và đăng nhập luôn" do
      post users_path, params: valid_params, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["email"]).to eq("newplayer.nta@gmail.com")
      expect(session[:user_id]).to eq(User.last.id)
    end

    it "từ chối email ngoài allowlist với mã EMAIL_NOT_ALLOWED (BR-01)" do
      params = valid_params.deep_merge(user: { email: "outsider@gmail.com" })

      post users_path, params: params, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("EMAIL_NOT_ALLOWED")
    end
  end

  describe "POST /session" do
    let!(:user) { create(:user, password: "password123", password_confirmation: "password123") }

    it "đăng nhập thành công" do
      post session_path, params: { email: user.email, password: "password123" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(session[:user_id]).to eq(user.id)
    end

    it "trả 401 khi sai mật khẩu" do
      post session_path, params: { email: user.email, password: "wrong" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("UNAUTHORIZED")
      expect(user.reload.failed_login_count).to eq(1)
    end

    it "khoá tài khoản sau 5 lần sai và trả ACCOUNT_LOCKED (BR-23)" do
      User::MAX_FAILED_LOGINS.times do
        post session_path, params: { email: user.email, password: "wrong" }, as: :json
      end

      post session_path, params: { email: user.email, password: "password123" }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("ACCOUNT_LOCKED")
      expect(session[:user_id]).to be_nil
    end
  end

  describe "quyền truy cập" do
    it "chưa đăng nhập thì không vào được danh sách game" do
      get games_path

      expect(response).to redirect_to(login_path)
    end

    it "member thường không vào được trang admin" do
      user = create(:user)
      post session_path, params: { email: user.email, password: "password123" }

      get admin_users_path

      expect(response).to redirect_to(root_path)
    end

    it "admin vào được trang admin" do
      admin = create(:user, :admin)
      post session_path, params: { email: admin.email, password: "password123" }

      get admin_users_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /admin/users/:id (BR-22)" do
    let(:admin) { create(:user, :admin) }

    before { post session_path, params: { email: admin.email, password: "password123" } }

    it "admin xoá được tài khoản khác" do
      victim = create(:user)

      expect { delete admin_user_path(victim) }.to change(User, :count).by(-1)
    end

    it "admin không tự xoá được chính mình" do
      expect { delete admin_user_path(admin), as: :json }.not_to change(User, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
