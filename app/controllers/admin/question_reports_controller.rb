module Admin
  class QuestionReportsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def index
      @reports = QuestionReport.includes(:user, :question).order(status: :asc, created_at: :desc)
    end

    # Chấp nhận báo cáo thì ẩn câu hỏi, không xoá cứng — lượt đã chơi trên câu đó
    # vẫn giữ nguyên điểm (BR-16, BR-18).
    def update
      report = QuestionReport.find(params[:id])

      case params[:decision]
      when "accept"
        report.accept!(current_user)
        log_decision("accepted", report)
        notice = "Đã ẩn câu hỏi"
      when "reject"
        report.reject!(current_user)
        # Cũng ghi log như nhánh accept: bỏ qua một báo cáo cũng là quyết định của admin,
        # và nếu về sau có tranh cãi "sao câu này vẫn còn" thì phải tra được ai đã bỏ qua.
        log_decision("rejected", report)
        notice = "Đã bỏ qua báo cáo"
      else
        return respond_invalid_decision
      end

      respond_handled(notice)
    end

    private

    # info chứ không phải warn: xử lý báo cáo là thao tác thường ngày và đảo ngược được
    # (ẩn/hiện câu hỏi). warn để dành cho thao tác không thu hồi được — xem
    # Admin::UsersController#destroy.
    def log_decision(decision, report)
      Rails.logger.info(
        "[admin] question report #{decision} admin_id=#{current_user.id} " \
        "question_id=#{report.question_id} report_id=#{report.id}"
      )
    end

    # Cùng cặp html/json với Admin::UsersController#destroy: trang admin là HTML, nhưng
    # client JSON gọi vào phải nhận body chuẩn thay vì một cái redirect.
    def respond_handled(notice)
      respond_to do |format|
        format.html { redirect_to admin_question_reports_path, notice: notice }
        format.json { head :no_content }
      end
    end

    def respond_invalid_decision
      message = "Lựa chọn không hợp lệ"

      respond_to do |format|
        format.html { redirect_to admin_question_reports_path, alert: message }
        format.json { render_error(:unprocessable_entity, "VALIDATION_ERROR", message) }
      end
    end
  end
end
