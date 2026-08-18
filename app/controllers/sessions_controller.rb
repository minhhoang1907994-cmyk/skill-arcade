class SessionsController < ApplicationController
  def new
    redirect_to games_path and return if logged_in?
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    # Tài khoản đang bị khoá thì không cho thử tiếp, kể cả khi mật khẩu đúng (BR-23).
    return render_locked if user&.locked?

    if user&.authenticate(params[:password])
      user.reset_failed_logins!
      reset_session
      session[:user_id] = user.id
      respond_to do |format|
        format.html { redirect_to games_path, notice: "Đăng nhập thành công" }
        format.json do
          render json: { id: user.id, display_name: user.display_name, admin: user.admin }
        end
      end
    else
      user&.register_failed_login!
      respond_to do |format|
        format.html { redirect_to login_path, alert: "Email hoặc mật khẩu không đúng" }
        format.json do
          render_error(:unauthorized, "UNAUTHORIZED", "Email hoặc mật khẩu không đúng")
        end
      end
    end
  end

  def destroy
    reset_session
    respond_to do |format|
      format.html { redirect_to login_path, notice: "Đã đăng xuất" }
      format.json { head :no_content }
    end
  end

  private

  def render_locked
    message = "Tài khoản tạm khoá, thử lại sau #{User::LOCK_DURATION.inspect}"
    respond_to do |format|
      format.html { redirect_to login_path, alert: message }
      format.json { render_error(:forbidden, "ACCOUNT_LOCKED", message) }
    end
  end
end
