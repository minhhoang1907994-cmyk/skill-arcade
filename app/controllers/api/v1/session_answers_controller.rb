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

      # Mỗi game một shape answer, nhưng hợp lại là một tập ĐÓNG 6 khoá. Liệt kê tường minh
      # thay vì `permit!`: đúng quy tắc strong parameters của project, và bỏ được cảnh báo
      # Mass Assignment của brakeman (trước đây làm job scan_ruby của CI đỏ với exit 3).
      #
      # Khoá client gửi thêm đều bị loại vì không nằm trong danh sách — gồm cả `score` (server
      # tự chấm, BR-02) và `_meta` (server tự gắn, xem AnswerSubmitter#persist). Trước đây hai
      # khoá đó phải loại bằng `.except`, giờ không cần nữa.
      #
      # THÊM GAME MỚI thì phải bổ sung khoá của nó vào đây, không thì scorer nhận nil và trả
      # 400 VALIDATION_ERROR. Nguồn sự thật là các lời gọi `fetch_answer` trong
      # app/services/scoring/ — hiện đúng 6 khoá dưới đây.
      ANSWER_KEYS = [
        :line, :bug_type,   # Bug Hunt (BR-25)
        :hours,             # Estimate Poker (BR-28)
        :option_key,        # Spec Detective (BR-26) + hai game kịch bản
        :node_key           # Incident Escape Room (BR-27), PROD Roulette (BR-29)
      ].freeze

      def answer_params
        # statement_indexes là MẢNG số (Spec Detective) nên phải khai riêng dạng `key: []`,
        # bọc trong hash vì expect nhận danh sách filter phẳng.
        #
        # expect chứ không phải require(...).permit(...): cùng lọc khoá lạ, nhưng expect còn
        # ném ParameterMissing khi `answer` sai kiểu (vd client gửi string) — chỗ đó trước
        # đây rơi vào NoMethodError trong permit và trả 500 thay vì 400.
        params.expect(answer: [ *ANSWER_KEYS, { statement_indexes: [] } ]).to_h
      end

      def response_payload(outcome)
        payload = {
          position: outcome.session_answer.position,
          awarded_score: outcome.session_answer.score,
          total_score: @game_session.reload.score,
          explanation: outcome.result.explanation,
          finished: outcome.finished
        }

        # Chỉ Estimate Poker có bảng chi tiết giờ; game khác trả nil nên khoá này vắng mặt.
        payload[:breakdown] = outcome.result.breakdown if outcome.result.breakdown.present?
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
