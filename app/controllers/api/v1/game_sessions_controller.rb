module Api
  module V1
    class GameSessionsController < BaseController
      before_action :load_own_session, only: [ :current, :abandon ]

      # POST /api/v1/games/:slug/sessions
      def create
        game = Game.active.find_by!(slug: params[:slug])
        session = ::GameSessions::Creator.new(user: current_user, game: game).call

        render json: session_payload(session).merge(
          current: ::GameSessions::StepProvider.new(session).payload
        ), status: :created
      rescue ::Questions::Drawer::NotEnoughQuestions
        render_error(:unprocessable_entity, "NO_QUESTIONS_AVAILABLE",
                     "Chưa đủ câu hỏi cho game này")
      rescue ::GameSessions::Creator::ConcurrentCreate => e
        render_error(:conflict, "CONFLICT", e.message)
      end

      # GET /api/v1/sessions/:id/current
      # Dùng khi người chơi tải lại trang giữa lượt — server là nguồn sự thật (spec §13).
      def current
        unless @game_session.in_progress?
          return render_error(:conflict, "SESSION_FINISHED", "Lượt chơi đã kết thúc")
        end

        render json: session_payload(@game_session).merge(
          current: ::GameSessions::StepProvider.new(@game_session).payload
        )
      rescue ::GameSessions::StepProvider::NoQuestionAvailable
        render_error(:unprocessable_entity, "NO_QUESTIONS_AVAILABLE",
                     "Chưa đủ câu hỏi cho game này")
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
          attempt_number: session.attempt_number,
          total_positions: session.game.steps_per_session,
          score: session.score
        }
      end
    end
  end
end
