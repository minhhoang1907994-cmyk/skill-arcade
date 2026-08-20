module GameSessions
  # Nhận đáp án của một bước, chấm ở server (BR-02), ghi nhận và quyết định lượt
  # đã kết thúc hay chưa.
  #
  # Điểm chỉ cộng thêm, không bao giờ trừ (BR-31). Trần điểm là max_score của game (BR-04).
  class AnswerSubmitter
    class PositionConflict < StandardError; end
    class SessionFinished < StandardError; end

    Outcome = Struct.new(:session_answer, :result, :finished, :next_step, keyword_init: true)

    def initialize(session:, position:, answer:, elapsed_ms: nil)
      @session = session
      @position = position.to_i
      @answer = answer
      @client_elapsed_ms = elapsed_ms
    end

    def call
      raise SessionFinished, "lượt chơi đã kết thúc" unless @session.in_progress?
      raise PositionConflict, "câu này đã được trả lời" unless @position == expected_position

      provider = StepProvider.new(@session)
      question = provider.question
      result = score(question)

      persist(question, result)
      finish_if_needed(result)

      Outcome.new(
        session_answer: @session_answer,
        result: result,
        finished: @session.finished?,
        next_step: @session.finished? ? nil : StepProvider.new(@session.reload).payload
      )
    end

    private

    def expected_position
      @session.current_position + 1
    end

    def score(question)
      Scoring::Base.for(@session.game).call(
        session: @session,
        question: question,
        answer: @answer,
        elapsed_ms: elapsed_ms
      )
    end

    # BR-21: thời gian do server đo là con số có thẩm quyền. Giá trị client gửi lên
    # chỉ được dùng khi nó KHÔNG nhỏ hơn thời gian server đo — nghĩa là client không
    # thể khai thấp đi để ăn hệ số tốc độ cao hơn.
    def elapsed_ms
      server_measured = ((Time.current - last_activity_at) * 1000).to_i
      client_value = @client_elapsed_ms.to_i

      client_value > server_measured ? client_value : server_measured
    end

    def last_activity_at
      @session.session_answers.maximum(:answered_at) || @session.started_at
    end

    def persist(question, result)
      ActiveRecord::Base.transaction do
        @session_answer = SessionAnswer.create!(
          game_session: @session,
          question: question,
          position: @position,
          answer: @answer.merge("_meta" => result.metadata),
          score: result.score,
          elapsed_ms: elapsed_ms,
          answered_at: Time.current
        )

        @session.update!(
          current_position: @position,
          score: capped_score(@session.score + result.score)
        )
      end
    end

    def capped_score(value)
      [ value, @session.game.max_score ].min
    end

    def finish_if_needed(result)
      return unless result.terminal? || @session.completed_all_steps? || @session.reached_max_score?

      apply_time_bonus if bonus_applicable?(result)
      @session.finish!
    end

    # Escape Room cộng thưởng thời gian lúc kết thúc, và chỉ khi chưa quá giờ (BR-27).
    def bonus_applicable?(result)
      return false unless @session.game.slug == Game::INCIDENT_ESCAPE_ROOM
      return false if result.metadata["over_limit"]

      true
    end

    def apply_time_bonus
      total_minutes = Scoring::IncidentEscapeRoom.elapsed_minutes(@session.reload)
      bonus = Scoring::IncidentEscapeRoom.time_bonus(total_minutes)
      return if bonus.zero?

      @session.update!(score: capped_score(@session.score + bonus))
    end
  end
end
