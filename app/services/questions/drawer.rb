module Questions
  # BR-32: ưu tiên câu người chơi CHƯA từng trả lời đúng. Chỉ dùng lại câu cũ khi
  # không còn đủ câu mới, và ưu tiên câu đã trả lời lâu nhất.
  #
  # Đây là cơ chế hãm việc cày điểm bằng cách chơi lại để gặp lại câu đã biết đáp án.
  #
  # language: giới hạn theo ngôn ngữ lập trình (chỉ Bug Hunt dùng). nil thì lấy tất cả.
  #
  # seed: chuỗi khoá thứ tự bốc. BẮT BUỘC truyền khi bốc đề để phục vụ một bước cụ thể.
  # Đề không được lưu sẵn cả bộ lúc tạo lượt (xem GameSessions::Creator), nên mỗi lần
  # hiển thị bước và mỗi lần chấm bước đó đều bốc lại. Nếu thứ tự là RAND() thuần thì hai
  # lần bốc cho cùng một bước ra hai câu KHÁC NHAU — người chơi xem câu A mà server chấm
  # theo đáp án câu B. Truyền cùng một seed thì thứ tự lặp lại được, không cần thêm cột DB.
  class Drawer
    class NotEnoughQuestions < NoQuestionsAvailable; end

    def initialize(user:, game:, language: nil, seed: nil)
      @user = user
      @game = game
      @language = language
      @seed = seed
    end

    def call(count = @game.questions_per_session)
      raise NotEnoughQuestions, "ngân hàng câu hỏi chưa đủ" if pool.count < count

      known = answered_correctly_at
      fresh = pool.where.not(id: known.keys).order(shuffle_order).limit(count).to_a
      return fresh if fresh.size >= count

      # Không đủ câu mới thì bù bằng câu đã trả lời đúng, cũ nhất trước.
      needed = count - fresh.size
      reused = pool.where(id: known.keys)
                   .sort_by { |q| known[q.id] }
                   .first(needed)

      fresh + reused
    end

    private

    def pool
      Question.playable.where(game: @game).in_language(@language)
    end

    # Không có seed thì trộn thật (dùng cho thống kê/khảo sát ngân hàng đề). Có seed thì
    # trộn theo hàm băm để cùng seed luôn ra cùng thứ tự.
    def shuffle_order
      return Arel.sql("RAND()") if @seed.blank?

      Arel.sql(Question.sanitize_sql_array([ "MD5(CONCAT(questions.id, ?))", @seed.to_s ]))
    end

    # question_id => lần cuối người này trả lời đúng câu đó.
    # Điểm > 0 coi như đã biết đáp án.
    def answered_correctly_at
      @answered_correctly_at ||= SessionAnswer
        .joins(:game_session)
        .where(game_sessions: { user_id: @user.id, game_id: @game.id })
        .where(SessionAnswer.arel_table[:score].gt(0))
        .group(:question_id)
        .maximum(:answered_at)
    end
  end
end
