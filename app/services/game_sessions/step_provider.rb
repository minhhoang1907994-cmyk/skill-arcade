module GameSessions
  # Trả về bước hiện tại của lượt: vị trí và câu hỏi tương ứng.
  #
  # Hai kiểu game (BR-30):
  # - Thường (Bug Hunt, Spec Detective, Estimate Poker): mỗi bước một câu hỏi mới,
  #   bốc theo BR-32 và không lặp lại câu đã dùng trong chính lượt này.
  # - Kịch bản (Escape Room, PROD Roulette): cả lượt dùng đúng một câu hỏi,
  #   mỗi bước là một node quyết định trong kịch bản đó.
  class StepProvider
    class NoQuestionAvailable < StandardError; end

    def initialize(session)
      @session = session
    end

    def next_position
      @session.current_position + 1
    end

    # Câu hỏi phục vụ bước kế tiếp.
    def question
      @question ||= @session.game.scenario_based? ? scenario_question : fresh_question
    end

    # Payload an toàn gửi cho client — không bao giờ kèm answer_key (BR-03).
    def payload
      {
        position: next_position,
        question_id: question.id,
        content: question.content
      }
    end

    private

    # Kịch bản đã bốc ở bước đầu thì giữ nguyên cho các bước sau.
    def scenario_question
      first_answer = @session.session_answers.first
      return first_answer.question if first_answer

      draw_one
    end

    def fresh_question
      used_ids = @session.session_answers.pluck(:question_id)
      candidates = drawn_questions.reject { |q| used_ids.include?(q.id) }

      candidates.first || raise(NoQuestionAvailable, "không còn câu hỏi khả dụng")
    end

    def draw_one
      drawn_questions.first || raise(NoQuestionAvailable, "không còn câu hỏi khả dụng")
    end

    # Bốc theo đúng ngôn ngữ đã chốt lúc tạo lượt, để mọi bước trong lượt cùng ngôn ngữ.
    #
    # seed khoá theo (lượt, bước): cùng một bước được hiển thị và được chấm bằng cùng một
    # câu hỏi, và người chơi tải lại trang giữa bước vẫn thấy đúng câu đó. Không có seed
    # thì mỗi lần bốc ra một câu khác và server chấm câu mà người chơi chưa từng thấy.
    def drawn_questions
      @drawn_questions ||= Questions::Drawer
        .new(user: @session.user, game: @session.game, language: @session.language,
             seed: "#{@session.id}:#{next_position}")
        .call(@session.game.questions_per_session)
    end
  end
end
