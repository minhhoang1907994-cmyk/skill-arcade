require "digest"

module GameSessions
  # Trả về bước hiện tại của lượt: vị trí và câu hỏi tương ứng.
  #
  # Hai kiểu game (BR-30):
  # - Thường (Bug Hunt, Spec Detective, Estimate Poker): mỗi bước một câu hỏi mới,
  #   bốc theo BR-32 và không lặp lại câu đã dùng trong chính lượt này.
  # - Kịch bản (Escape Room, PROD Roulette): cả lượt dùng đúng một câu hỏi,
  #   mỗi bước là một node quyết định trong kịch bản đó.
  class StepProvider
    # Bug Hunt hiện bao nhiêu loại bug cho người chơi chọn. Ngân hàng câu hỏi lưu cả 12
    # loại trong `content["bug_types"]`, hiện hết ra thì đoán loại bug khó hơn hẳn tìm
    # đúng dòng. Rút xuống còn 4 lựa chọn (luôn kèm đáp án đúng) để hai phần của câu hỏi
    # cân nhau hơn.
    BUG_HUNT_TYPE_CHOICES = 4

    def initialize(session)
      @session = session
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
        content: display_content
      }
    end

    private

    def next_position
      @session.current_position + 1
    end

    # content đem hiển thị: giống content trong DB, trừ hai chỗ được xử lý ở payload chứ
    # không sửa content trong DB (content đi vào checksum):
    # - Bug Hunt: rút bớt danh sách loại bug.
    # - Spec Detective và game kịch bản: đảo thứ tự phương án.
    def display_content
      content = question.content

      case @session.game.slug
      when Game::BUG_HUNT then bug_hunt_content(content)
      when Game::SPEC_DETECTIVE then shuffled_spec_content(content)
      else @session.game.scenario_based? ? shuffled_scenario_content(content) : content
      end
    end

    def bug_hunt_content(content)
      types = Array(content["bug_types"])
      return content if types.size <= BUG_HUNT_TYPE_CHOICES

      correct = question.answer_key["bug_type"].to_s
      distractors = (types - [ correct ]).sample(BUG_HUNT_TYPE_CHOICES - 1, random: choice_rng)
      content.merge("bug_types" => ([ correct ] + distractors).shuffle(random: choice_rng))
    end

    # Đề trong ngân hàng đặt phương án tốt nhất ở vị trí đầu (khoá "a" ở Spec Detective,
    # "s1a"/"e1a" ở game kịch bản), nên bấm ô đầu tiên là ăn điểm mà không cần đọc. Đảo thứ tự lúc hiển thị
    # thay vì sửa lại từng đề: cách này áp cả cho đề AI sinh sau này.
    #
    # Chấm điểm đi theo `key` của phương án (Scoring::SpecDetective so với
    # best_option_key, hai game kịch bản tra option_effects[key]) nên thứ tự hiển thị đổi
    # mà điểm không đổi. UI cũng không in `key` ra cho người chơi thấy.
    def shuffled_spec_content(content)
      options = Array(content["clarifying_options"])
      return content if options.size < 2

      content.merge("clarifying_options" => options.shuffle(random: option_rng))
    end

    def shuffled_scenario_content(content)
      nodes = Array(content["nodes"])
      return content if nodes.none?

      shuffled = nodes.map do |node|
        options = Array(node["options"])
        next node if options.size < 2

        node.merge("options" => options.shuffle(random: option_rng))
      end

      content.merge("nodes" => shuffled)
    end

    # Cùng khoá seed với việc bốc câu hỏi: tải lại trang giữa bước vẫn thấy đúng danh sách
    # lựa chọn cũ, không phải một tập khác.
    def choice_rng
      @choice_rng ||= rng_for("types")
    end

    # Seed riêng cho thứ tự phương án, tách khỏi choice_rng để việc rút loại bug của Bug
    # Hunt không phụ thuộc vào việc có đảo thứ tự hay không.
    def option_rng
      @option_rng ||= rng_for("options")
    end

    def rng_for(purpose)
      Random.new(
        Digest::SHA256.hexdigest("#{purpose}:#{@session.id}:#{next_position}").to_i(16) % (2**32)
      )
    end

    # Kịch bản đã bốc ở bước đầu thì giữ nguyên cho các bước sau.
    def scenario_question
      first_answer = @session.session_answers.first
      return first_answer.question if first_answer

      draw_one
    end

    def fresh_question
      used_ids = @session.session_answers.pluck(:question_id)
      candidates = drawn_questions.reject { |q| used_ids.include?(q.id) }

      candidates.first || raise(::Questions::NoQuestionsAvailable, "không còn câu hỏi khả dụng")
    end

    def draw_one
      drawn_questions.first ||
        raise(::Questions::NoQuestionsAvailable, "không còn câu hỏi khả dụng")
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
