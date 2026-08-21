# Cài đặt tài khoản của chính người đang đăng nhập (BR-40).
# Không có đường nào sửa tài khoản người khác ở đây — mọi thao tác đi qua current_user.
class SettingsController < ApplicationController
  before_action :require_login

  def edit; end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "Đã lưu cài đặt"
    else
      flash.now[:alert] = "Không lưu được — xem lỗi bên dưới"
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.expect(user: [ :display_name, :avatar ])
  end
end
