# Tính bảng xếp hạng từ game_sessions tại thời điểm truy vấn (BR-12).
# Không có bảng ranking denormalized — mọi con số đều suy ra từ lịch sử lượt chơi.
#
# Ba chu kỳ (BR-13, BR-14, BR-15): all-time, tuần (thứ Hai đến Chủ nhật),
# tháng (ngày đầu đến ngày cuối). Không chu kỳ nào bị reset — tuần và tháng chỉ là
# bộ lọc trên dữ liệu lịch sử.
class LeaderboardQuery
  ALL_TIME = "all_time".freeze
  WEEKLY = "weekly".freeze
  MONTHLY = "monthly".freeze
  SCOPES = [ ALL_TIME, WEEKLY, MONTHLY ].freeze

  TOTAL = "total".freeze
  TIME_ZONE = "Asia/Ho_Chi_Minh".freeze
  CACHE_TTL = 60.seconds

  Entry = Struct.new(:rank, :user_id, :display_name, :score, :attempts_to_best,
                     :achieved_at, keyword_init: true)

  class InvalidScope < ArgumentError; end

  # scope: "all_time" | "weekly" | "monthly"
  # game: Game hoặc "total"
  def initialize(scope: ALL_TIME, game: TOTAL, limit: 50, now: Time.current)
    raise InvalidScope, "unknown scope: #{scope}" unless SCOPES.include?(scope.to_s)

    @scope = scope.to_s
    @game = game
    @limit = limit
    @now = now
  end

  def period
    @period ||= case @scope
    when WEEKLY
      local = @now.in_time_zone(TIME_ZONE)
      # Rails tính beginning_of_week từ thứ Hai theo mặc định (BR-13).
      (local.beginning_of_week)..(local.end_of_week)
    when MONTHLY
      local = @now.in_time_zone(TIME_ZONE)
      (local.beginning_of_month)..(local.end_of_month)
    else
      nil
    end
  end

  def call
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      total? ? total_entries : game_entries(@game)
    end
  end

  private

  def total?
    @game == TOTAL || @game.nil?
  end

  def cache_key
    game_key = total? ? TOTAL : @game.slug
    period_key = period ? "#{period.first.to_i}-#{period.last.to_i}" : ALL_TIME
    "leaderboard/#{@scope}/#{game_key}/#{period_key}/#{@limit}"
  end

  def sessions
    base = GameSession.finished
    period ? base.where(finished_at: period) : base
  end

  # Với một game: điểm là personal best trong chu kỳ, kèm số lượt cần để đạt (BR-06, BR-10).
  def game_entries(game)
    rows = best_rows_for(sessions.where(game_id: game.id))
    rank(rows.sort_by { |r| [ -r[:score], r[:attempts_to_best], r[:achieved_at] ] })
  end

  # Bảng tổng: cộng personal best của từng game, tie-break là tổng attempts_to_best (BR-07, BR-11a).
  def total_entries
    rows = best_rows_for(sessions)
      .group_by { |r| r[:user_id] }
      .map do |user_id, per_game|
        {
          user_id: user_id,
          display_name: per_game.first[:display_name],
          score: per_game.sum { |r| r[:score] },
          # Game chưa từng hoàn thành đóng góp 0 vào tổng (BR-11a).
          attempts_to_best: per_game.sum { |r| r[:attempts_to_best] },
          achieved_at: per_game.map { |r| r[:achieved_at] }.max
        }
      end

    rank(rows.sort_by { |r| [ -r[:score], r[:attempts_to_best], r[:achieved_at] ] })
  end

  # Với mỗi cặp (user, game) trong phạm vi đã lọc: tìm lượt đạt điểm cao nhất,
  # và vị trí của lượt đó trong chuỗi lượt của chính chu kỳ này.
  #
  # attempts_to_best đếm theo chu kỳ chứ không dùng attempt_number all-time (BR-10) —
  # nếu dùng attempt_number, người chơi lâu năm luôn thua người mới ở bảng tuần.
  def best_rows_for(relation)
    relation
      .includes(:user)
      .order(:finished_at)
      .group_by { |session| [ session.user_id, session.game_id ] }
      .map do |(_user_id, _game_id), user_sessions|
        best_score = user_sessions.map(&:score).max
        # Lượt sớm nhất đạt điểm cao nhất — quyết định attempts_to_best (BR-10).
        earliest_best = user_sessions.find { |s| s.score == best_score }

        {
          user_id: earliest_best.user_id,
          display_name: earliest_best.user.display_name,
          score: earliest_best.score,
          attempts_to_best: user_sessions.index(earliest_best) + 1,
          achieved_at: earliest_best.finished_at
        }
      end
  end

  def rank(rows)
    rows.first(@limit).each_with_index.map do |row, index|
      Entry.new(rank: index + 1, **row)
    end
  end
end
