class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :logged_in?

  # Bảng mã lỗi dùng chung cho toàn bộ endpoint (spec section 5.2).
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    respond_to do |format|
      format.html { redirect_to login_path, alert: "Vui lòng đăng nhập" }
      format.json { render_error(:unauthorized, "UNAUTHORIZED", "Vui lòng đăng nhập") }
    end
  end

  def require_admin
    return if current_user&.admin?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Bạn không có quyền thực hiện" }
      format.json { render_error(:forbidden, "FORBIDDEN", "Bạn không có quyền thực hiện") }
    end
  end

  def render_error(status, code, message)
    render json: { code: code, message: message }, status: status
  end

  def render_not_found
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Không tìm thấy" }
      format.json { render_error(:not_found, "NOT_FOUND", "Không tìm thấy") }
    end
  end
end
