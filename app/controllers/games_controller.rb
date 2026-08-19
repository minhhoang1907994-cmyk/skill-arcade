class GamesController < ApplicationController
  before_action :require_login

  def index
    @games = Game.active.order(:id)
    @best_scores = current_user.game_sessions.finished.group(:game_id).maximum(:score)
    @total_score = @best_scores.values.sum
    # Để card của game chấm bằng AI báo trước là hôm nay hết hạn mức, đỡ cho người chơi bấm
    # vào rồi mới biết. Một COUNT thêm cho cả trang.
    @ai_budget = Gemini::DailyBudget.new if @games.any?(&:ai_graded?)
  end

  def show
    @game = Game.active.find_by!(slug: params[:slug])
    # Chỉ hiện ngôn ngữ còn đủ câu cho trọn một lượt.
    @languages = @game.playable_languages
    # Game chấm bằng AI có trần công suất theo ngày — hiện số lượt còn lại ngay trên trang
    # để người chơi không bấm Bắt đầu rồi mới nhận 503.
    @ai_budget = Gemini::DailyBudget.new if @game.ai_graded?
  end
end
