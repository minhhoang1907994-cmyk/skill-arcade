class UsersController < ApplicationController
  def new
    redirect_to games_path and return if logged_in?

    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      # Đăng ký thành công thì đăng nhập luôn (Main Flow bước 1).
      session[:user_id] = @user.id
      respond_to do |format|
        format.html { redirect_to games_path, notice: "Đăng ký thành công" }
        format.json do
          render json: { id: @user.id, email: @user.email, display_name: @user.display_name },
                 status: :created
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render_registration_error }
      end
    end
  end

  private

  def user_params
    params.expect(user: [ :email, :password, :password_confirmation, :display_name ])
  end

  # Email ngoài allowlist trả mã riêng để client hiển thị đúng thông báo (BR-01).
  def render_registration_error
    if @user.errors.of_kind?(:email, :invalid)
      render_error(:unprocessable_entity, "EMAIL_NOT_ALLOWED",
                   "Chỉ chấp nhận email dạng xxx.nta@gmail.com")
    else
      render json: {
        code: "VALIDATION_ERROR",
        message: "Dữ liệu gửi lên không hợp lệ",
        errors: @user.errors.map { |e| { field: e.attribute, message: e.message } }
      }, status: :unprocessable_entity
    end
  end
end
