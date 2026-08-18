module Api
  module V1
    # Base cho toàn bộ endpoint JSON của gameplay.
    #
    # Vẫn giữ CSRF protection: các endpoint này xác thực bằng session cookie, nên tắt
    # forgery protection sẽ cho phép trang bên thứ ba tạo lượt và nộp đáp án thay người
    # chơi đang đăng nhập (spec §13). Client phải gửi header X-CSRF-Token.
    class BaseController < ApplicationController
      before_action :require_login

      rescue_from ActionController::InvalidAuthenticityToken do
        render_error(:unprocessable_entity, "INVALID_CSRF_TOKEN",
                     "Phiên làm việc không hợp lệ, tải lại trang")
      end

      rescue_from ActionController::ParameterMissing do |e|
        render_error(:bad_request, "VALIDATION_ERROR", "Thiếu tham số: #{e.param}")
      end

      # Prefix :: bắt buộc — không có nó Ruby tìm Api::V1::BaseController::Scoring
      # và ném NameError khi controller được load lazily ở development.
      rescue_from ::Scoring::Base::InvalidAnswer do |e|
        render_error(:bad_request, "VALIDATION_ERROR", e.message)
      end

      private

      # Người chơi chỉ thao tác được trên lượt của chính mình (spec §12).
      def load_own_session
        @game_session = current_user.game_sessions.find(params[:id])
      end
    end
  end
end
