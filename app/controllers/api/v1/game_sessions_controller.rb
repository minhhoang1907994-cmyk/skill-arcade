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

        render json: session_payload(session).merge(
          current: ::GameSessions::StepProvider.new(session).payload
        ), status: :created
      rescue ::Questions::Drawer::NotEnoughQuestions
        render_error(:unprocessable_entity, "NO_QUESTIONS_AVAILABLE",
                     "Chưa đủ câu hỏi cho game này")
      rescue ::GameSessions::Creator::InvalidLanguage => e
        render_error(:unprocessable_entity, "INVALID_LANGUAGE", e.message)
      rescue ::GameSessions::Creator::QuotaExhausted
        # 503 chứ không phải 429: đây là trần công suất của hệ thống, không phải lỗi người
        # chơi thao tác quá nhanh. Mã riêng để client phân biệt với GRADING_UNAVAILABLE —
        # cái kia là Gemini hỏng bất ngờ, cái này là biết trước và sẽ hết vào ngày mai.
        render_error(:service_unavailable, "AI_QUOTA_EXHAUSTED",
                     "Hôm nay đã dùng hết hạn mức của dịch vụ chấm điểm AI. " \
                     "Mời bạn quay lại ngày mai, hoặc chơi 4 game còn lại.")
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
          language: session.language,
          attempt_number: session.attempt_number,
          total_positions: session.game.steps_per_session,
          score: session.score
        }
      end
    end
  end
end
