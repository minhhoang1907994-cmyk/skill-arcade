module Api
  module V1
    class SessionAnswersController < BaseController
      before_action :load_own_session

      # POST /api/v1/sessions/:id/answers
      def create
        outcome = ::GameSessions::AnswerSubmitter.new(
          session: @game_session,
          position: params.require(:position),
          answer: answer_params,
          elapsed_ms: params[:elapsed_ms]
        ).call

        render json: response_payload(outcome)
      rescue ::GameSessions::AnswerSubmitter::PositionConflict => e
        render_error(:conflict, "POSITION_CONFLICT", e.message)
      rescue ::GameSessions::AnswerSubmitter::SessionFinished => e
        render_error(:conflict, "SESSION_FINISHED", e.message)
      rescue ActiveRecord::RecordNotUnique
        # Hai request cùng nộp một position — unique index chặn ở tầng DB (§9).
        render_error(:conflict, "POSITION_CONFLICT", "Câu này đã được trả lời")
      end

      private

      # Cấu trúc answer khác nhau theo game nên nhận nguyên hash, nhưng vẫn qua
      # permit! có kiểm soát: chỉ lấy nhánh :answer, và mọi giá trị điểm client
      # gửi kèm đều bị bỏ qua vì server tự chấm (BR-02).
      def answer_params
        params.require(:answer).permit!.to_h.except("score", "_meta")
      end

      def response_payload(outcome)
        payload = {
          position: outcome.session_answer.position,
          awarded_score: outcome.session_answer.score,
          total_score: @game_session.reload.score,
          explanation: outcome.result.explanation,
          finished: outcome.finished,
          next: outcome.next_step
        }

        payload[:summary] = summary if outcome.finished
        payload
      end

      def summary
        best = current_user.best_score_for(@game_session.game)

        {
          score: @game_session.score,
          personal_best: best,
          is_new_best: @game_session.score >= best,
          attempt_number: @game_session.attempt_number
        }
      end
    end
  end
end
