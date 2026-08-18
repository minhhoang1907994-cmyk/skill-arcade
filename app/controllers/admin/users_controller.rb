module Admin
  class UsersController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def index
      @users = User.order(:id)
    end

    # Người dùng không tự xoá được tài khoản, và admin cũng không xoá được
    # chính mình (BR-22). Xoá user kéo theo CASCADE toàn bộ lượt chơi,
    # câu trả lời và log chấm điểm của họ.
    def destroy
      user = User.find(params[:id])

      if user == current_user
        return respond_to do |format|
          format.html { redirect_to admin_users_path, alert: "Không thể tự xoá tài khoản của mình" }
          format.json do
            render_error(:forbidden, "FORBIDDEN", "Không thể tự xoá tài khoản của mình")
          end
        end
      end

      Rails.logger.warn(
        "[admin] user deleted admin_id=#{current_user.id} " \
        "deleted_user_id=#{user.id} deleted_user_email=#{user.email}"
      )
      user.destroy!

      respond_to do |format|
        format.html { redirect_to admin_users_path, notice: "Đã xoá tài khoản" }
        format.json { head :no_content }
      end
    end
  end
end
