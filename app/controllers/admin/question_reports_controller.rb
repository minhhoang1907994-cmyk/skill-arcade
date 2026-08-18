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
        Rails.logger.info(
          "[admin] question hidden admin_id=#{current_user.id} " \
          "question_id=#{report.question_id} report_id=#{report.id}"
        )
        notice = "Đã ẩn câu hỏi"
      when "reject"
        report.reject!(current_user)
        notice = "Đã bỏ qua báo cáo"
      else
        return redirect_to admin_question_reports_path, alert: "Lựa chọn không hợp lệ"
      end

      redirect_to admin_question_reports_path, notice: notice
    end
  end
end
