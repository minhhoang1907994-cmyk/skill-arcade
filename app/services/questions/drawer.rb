module Questions
  # BR-32: ưu tiên câu người chơi CHƯA từng trả lời đúng. Chỉ dùng lại câu cũ khi
  # không còn đủ câu mới, và ưu tiên câu đã trả lời lâu nhất.
  #
  # Đây là cơ chế hãm việc cày điểm bằng cách chơi lại để gặp lại câu đã biết đáp án.
  class Drawer
    class NotEnoughQuestions < StandardError; end

    def initialize(user:, game:)
      @user = user
      @game = game
    end

    def call(count = @game.questions_per_session)
      pool = Question.playable.where(game: @game)
      raise NotEnoughQuestions, "ngân hàng câu hỏi chưa đủ" if pool.count < count

      known = answered_correctly_at
      fresh = pool.where.not(id: known.keys).order(Arel.sql("RAND()")).limit(count).to_a
      return fresh if fresh.size >= count

      # Không đủ câu mới thì bù bằng câu đã trả lời đúng, cũ nhất trước.
      needed = count - fresh.size
      reused = pool.where(id: known.keys)
                   .sort_by { |q| known[q.id] }
                   .first(needed)

      fresh + reused
    end

    private

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
