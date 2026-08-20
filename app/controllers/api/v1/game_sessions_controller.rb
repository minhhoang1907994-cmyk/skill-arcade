module Api
  module V1
    class GameSessionsController < BaseController
      before_action :load_own_session, only: [ :current, :abandon ]

      # POST /api/v1/games/:slug/sessions
      def create
        game = Game.active.find_by!(slug: params[:slug])
        session = ::GameSessions::Creator.new(
          user: current_user, game: game, language: params[:language]
        ).call

        payload = ::GameSessions::StepProvider.new(session).payload
        session.mark_step_served!

        render json: session_payload(session).merge(current: payload), status: :created
      rescue ::GameSessions::Creator::InvalidLanguage => e
        render_error(:unprocessable_entity, "INVALID_LANGUAGE", e.message)
      rescue ::GameSessions::Creator::ConcurrentCreate => e
        render_error(:conflict, "CONFLICT", e.message)
      end

      # GET /api/v1/sessions/:id/current
      # Dùng khi người chơi tải lại trang giữa lượt — server là nguồn sự thật (spec §13) —
      # và khi người chơi bấm "Câu tiếp theo": response của endpoint nộp đáp án KHÔNG kèm
      # bước sau nữa (xem AnswerSubmitter#call), nên đây là chỗ duy nhất phát đề ra.
      #
      # `mark_step_served!` ghi mốc BR-21 và chỉ ghi cho lần phát đầu tiên của mỗi câu, nên
      # đường tải lại trang dùng chung endpoint mà không reset được đồng hồ tốc độ. Ghi SAU
      # khi payload dựng xong: bốc đề lỗi (NO_QUESTIONS_AVAILABLE) thì không tính là đã phát.
      def current
        unless @game_session.in_progress?
          return render_error(:conflict, "SESSION_FINISHED", "Lượt chơi đã kết thúc")
        end

        payload = ::GameSessions::StepProvider.new(@game_session).payload
        @game_session.mark_step_served!

        render json: session_payload(@game_session).merge(current: payload)
      end

      # POST /api/v1/sessions/:id/abandon
      def abandon
        unless @game_session.in_progress?
          return render_error(:conflict, "SESSION_FINISHED", "Lượt chơi đã kết thúc")
        end

        @game_session.abandon!(::GameSession::USER_QUIT)
        head :no_content
      end

      private

      def session_payload(session)
        {
          session_id: session.id,
          game: session.game.slug,
          language: session.language,
          attempt_number: session.attempt_number,
          total_positions: session.game.steps_per_session,
          score: session.score
        }
      end
    end
  end
end
