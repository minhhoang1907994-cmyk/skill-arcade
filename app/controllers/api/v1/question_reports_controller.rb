module Api
  module V1
    class QuestionReportsController < BaseController
      # POST /api/v1/questions/:id/reports
      #
      # Bỏ bước admin duyệt câu hỏi nên đây là lưới an toàn chính: người chơi báo,
      # admin xem và ẩn câu sai (BR-18).
      def create
        question = Question.find(params[:id])
        report = QuestionReport.new(
          user: current_user,
          question: question,
          reason: params.require(:reason)
        )

        if report.save
          render json: { id: report.id, status: report.status }, status: :created
        elsif report.errors.of_kind?(:question_id, :taken)
          # BR-17: mỗi người báo mỗi câu tối đa một lần.
          render_error(:conflict, "CONFLICT", "Bạn đã báo câu hỏi này rồi")
        else
          render_error(:bad_request, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ")
        end
      rescue ActiveRecord::RecordNotUnique
        render_error(:conflict, "CONFLICT", "Bạn đã báo câu hỏi này rồi")
      end
    end
  end
end
