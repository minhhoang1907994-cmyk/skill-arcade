class LeaderboardsController < ApplicationController
  # Leaderboard xem được không cần đăng nhập (spec section 3).
  def show
    scope = params[:scope].presence || LeaderboardQuery::ALL_TIME
    @game = resolve_game

    @query = LeaderboardQuery.new(scope: scope, game: @game)
    @entries = @query.call

    respond_to do |format|
      format.html
      format.json { render json: serialized(scope) }
    end
  rescue LeaderboardQuery::InvalidScope
    render_error(:bad_request, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ")
  end

  private

  def resolve_game
    slug = params[:game].presence || LeaderboardQuery::TOTAL
    return LeaderboardQuery::TOTAL if slug == LeaderboardQuery::TOTAL

    Game.find_by!(slug: slug)
  end

  def serialized(scope)
    {
      scope: scope,
      game: @game == LeaderboardQuery::TOTAL ? LeaderboardQuery::TOTAL : @game.slug,
      period: period_payload,
      entries: @entries.map do |entry|
        {
          rank: entry.rank,
          display_name: entry.display_name,
          score: entry.score,
          attempts_to_best: entry.attempts_to_best,
          achieved_at: entry.achieved_at
        }
      end
    }
  end

  def period_payload
    range = @query.period
    return nil if range.nil?

    { from: range.first, to: range.last }
  end
end
