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
    class InvalidLanguage < StandardError; end

    # Hạn mức Gemini còn lại không đủ cho trọn một lượt. Chặn TRƯỚC khi tạo bản ghi để người
    # chơi không vào giữa lượt rồi mới nhận 503 và mất lượt (§8.5 chỉ nói về lỗi bất ngờ; hết
    # hạn mức là chuyện biết trước được).
    class QuotaExhausted < StandardError; end

    def initialize(user:, game:, language: nil)
      @user = user
      @game = game
      # Ngôn ngữ chỉ có ý nghĩa với game phân đề theo ngôn ngữ; game khác bỏ qua.
      @language = game.language_scoped? ? language.presence : nil
    end

    def call
      validate_language!
      ensure_ai_budget!
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

    def validate_language!
      return unless @game.language_scoped?

      raise InvalidLanguage, "cần chọn ngôn ngữ lập trình" if @language.blank?
      return if @game.available_languages.include?(@language)

      # Ngôn ngữ có trong ngân hàng nhưng chưa đủ câu là chuyện khác — để
      # ensure_questions_available! báo NO_QUESTIONS_AVAILABLE.
      raise InvalidLanguage, "ngôn ngữ không hợp lệ"
    end

    # Chỉ game chấm bằng AI mới tiêu hạn mức Gemini. 4 game còn lại chấm từ answer_key nên
    # không bị chặn ở đây (spec §15: Gemini hỏng thì 4/5 game vẫn chơi được).
    def ensure_ai_budget!
      return unless @game.ai_graded?

      budget = Gemini::DailyBudget.new
      return if budget.enough_for_session?(@game)

      raise QuotaExhausted,
            "hạn mức chấm điểm AI hôm nay đã dùng hết (#{budget.used}/" \
            "#{Gemini::DailyBudget::DAILY_REQUEST_LIMIT} lượt gọi trong 24 giờ qua)"
    end

    def ensure_questions_available!
      available = Question.playable.where(game: @game).in_language(@language).count
      return if available >= @game.questions_per_session

      raise Questions::Drawer::NotEnoughQuestions, "ngân hàng câu hỏi chưa đủ"
    end

    def create_session
      GameSession.create!(
        user: @user,
        game: @game,
        language: @language,
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
