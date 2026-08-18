module GameSessions
  # Tạo một lượt chơi mới ở điểm 0 (BR-05).
  #
  # attempt_number phải liên tục cho mỗi cặp (user, game). Unique index chặn trùng khi
  # hai request đến cùng lúc — gặp trùng thì thử lại một lần với số kế tiếp (§9).
  #
  # Câu hỏi KHÔNG được chốt sẵn cả bộ ở đây mà bốc theo từng bước (xem StepProvider):
  # như vậy không cần lưu trạng thái ngoài DB, và lượt đang chơi không hỏng khi
  # có câu bị ẩn giữa chừng.
  class Creator
    MAX_RETRY = 1

    class ConcurrentCreate < StandardError; end

    def initialize(user:, game:)
      @user = user
      @game = game
    end

    def call
      # Kiểm tra ngân hàng câu hỏi trước khi tạo bản ghi, để không sinh ra lượt rỗng.
      ensure_questions_available!

      attempts = 0
      begin
        create_session
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts <= MAX_RETRY

        raise ConcurrentCreate, "không tạo được lượt chơi, thử lại"
      end
    end

    private

    def ensure_questions_available!
      available = Question.playable.where(game: @game).count
      return if available >= @game.questions_per_session

      raise Questions::Drawer::NotEnoughQuestions, "ngân hàng câu hỏi chưa đủ"
    end

    def create_session
      GameSession.create!(
        user: @user,
        game: @game,
        attempt_number: next_attempt_number,
        score: 0,
        state: GameSession::IN_PROGRESS,
        current_position: 0,
        started_at: Time.current
      )
    end

    def next_attempt_number
      GameSession.where(user: @user, game: @game).maximum(:attempt_number).to_i + 1
    end
  end
end
