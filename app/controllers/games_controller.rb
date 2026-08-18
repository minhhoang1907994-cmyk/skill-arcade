class GamesController < ApplicationController
  before_action :require_login

  def index
    @games = Game.active.order(:id)
    @best_scores = current_user.game_sessions.finished.group(:game_id).maximum(:score)
    @total_score = @best_scores.values.sum
  end

  def show
    @game = Game.active.find_by!(slug: params[:slug])
  end
end
