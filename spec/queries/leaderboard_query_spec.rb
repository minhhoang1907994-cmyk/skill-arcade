require "rails_helper"

RSpec.describe LeaderboardQuery do
  let(:game) { create(:game) }
  let(:alice) { create(:user, display_name: "Alice") }
  let(:bob) { create(:user, display_name: "Bob") }

  def finished_session(user, score:, attempt:, at:, on_game: game)
    create(:game_session, :finished, user: user, game: on_game, score: score,
           attempt_number: attempt, started_at: at, finished_at: at)
  end

  before { Rails.cache.clear }

  describe "xếp hạng theo personal best (BR-06, BR-11)" do
    it "lấy điểm cao nhất của mỗi người, xếp giảm dần" do
      finished_session(alice, score: 60, attempt: 1, at: 3.days.ago)
      finished_session(alice, score: 90, attempt: 2, at: 2.days.ago)
      finished_session(bob, score: 80, attempt: 1, at: 2.days.ago)

      entries = described_class.new(scope: "all_time", game: game).call

      expect(entries.map(&:display_name)).to eq([ "Alice", "Bob" ])
      expect(entries.first.score).to eq(90)
      expect(entries.first.rank).to eq(1)
    end
  end

  describe "cache" do
    # Cache giữ chính object Entry: khi thêm thành viên `avatar` vào Struct, code mới đọc
    # payload cũ đã ném `TypeError: struct size differs` và trang xếp hạng 500. Khoá cache
    # giờ mang chữ ký của Entry nên payload của bản cũ (khoá không có chữ ký) không đọc tới.
    it "không đọc payload nằm ở khoá của phiên bản Entry cũ" do
      finished_session(alice, score: 60, attempt: 1, at: 1.day.ago)
      Rails.cache.write("leaderboard/all_time/#{game.slug}/all_time/50", [ :payload_cu ])

      entries = described_class.new(scope: "all_time", game: game).call

      expect(entries.map(&:display_name)).to eq([ "Alice" ])
    end

    it "khoá cache đổi khi cấu trúc Entry đổi" do
      key = described_class.new(scope: "all_time", game: game).send(:cache_key)

      expect(key).to include(described_class::ENTRY_VERSION)
    end
  end

  describe "hình đại diện (BR-40)" do
    it "mang avatar của người chơi ra Entry ở bảng một game" do
      alice.update!(avatar: "mimic")
      finished_session(alice, score: 60, attempt: 1, at: 1.day.ago)

      entries = described_class.new(scope: "all_time", game: game).call

      expect(entries.first.avatar).to eq("mimic")
    end

    it "mang cả ở bảng tổng, nơi mỗi người gộp nhiều game" do
      other = create(:game, :scenario_based)
      alice.update!(avatar: "dragon")
      finished_session(alice, score: 60, attempt: 1, at: 2.days.ago)
      finished_session(alice, score: 30, attempt: 1, at: 1.day.ago, on_game: other)

      entries = described_class.new(scope: "all_time", game: LeaderboardQuery::TOTAL).call

      expect(entries.first.score).to eq(90)
      expect(entries.first.avatar).to eq("dragon")
    end
  end

  describe "tie-break theo số lượt (BR-10, BR-11)" do
    it "người đạt bằng ít lượt hơn xếp trên khi bằng điểm" do
      finished_session(alice, score: 50, attempt: 1, at: 5.days.ago)
      finished_session(alice, score: 100, attempt: 2, at: 4.days.ago)

      finished_session(bob, score: 100, attempt: 1, at: 3.days.ago)

      entries = described_class.new(scope: "all_time", game: game).call

      expect(entries.map(&:display_name)).to eq([ "Bob", "Alice" ])
      expect(entries.first.attempts_to_best).to eq(1)
      expect(entries.second.attempts_to_best).to eq(2)
    end
  end

  describe "attempts_to_best tính theo chu kỳ (BR-10)" do
    it "không dùng attempt_number all-time cho bảng tuần" do
      # Alice đã chơi nhiều từ tháng trước, tuần này mới đạt 100 ở lượt thứ 2 trong tuần.
      # Neo mốc theo đầu tuần thay vì "N ngày trước" để test không phụ thuộc hôm nay là thứ mấy.
      week_start = Time.current.in_time_zone(LeaderboardQuery::TIME_ZONE).beginning_of_week

      finished_session(alice, score: 30, attempt: 1, at: 40.days.ago)
      finished_session(alice, score: 40, attempt: 2, at: 39.days.ago)
      finished_session(alice, score: 50, attempt: 3, at: week_start + 1.hour)
      finished_session(alice, score: 100, attempt: 4, at: week_start + 2.hours)

      entries = described_class.new(scope: "weekly", game: game).call
      alice_entry = entries.find { |e| e.display_name == "Alice" }

      # Trong tuần này Alice chơi 2 lượt, đạt best ở lượt thứ 2 — không phải lượt thứ 4.
      expect(alice_entry.attempts_to_best).to eq(2)
    end
  end

  describe "bảng tổng (BR-07, BR-11a)" do
    it "cộng personal best của các game và cộng cả attempts_to_best" do
      other_game = create(:game, :scenario_based)

      finished_session(alice, score: 90, attempt: 1, at: 2.days.ago)
      finished_session(alice, score: 40, attempt: 1, at: 2.days.ago, on_game: other_game)

      entries = described_class.new(scope: "all_time", game: LeaderboardQuery::TOTAL).call
      alice_entry = entries.find { |e| e.display_name == "Alice" }

      expect(alice_entry.score).to eq(130)
      expect(alice_entry.attempts_to_best).to eq(2)
    end
  end

  describe "loại lượt chưa hoàn thành (BR-08)" do
    it "không tính lượt in_progress và abandoned" do
      create(:game_session, user: alice, game: game, score: 100, attempt_number: 1)
      create(:game_session, :abandoned_by_system, user: bob, game: game, score: 100,
             attempt_number: 1)

      entries = described_class.new(scope: "all_time", game: game).call

      expect(entries).to be_empty
    end
  end

  describe "chu kỳ (BR-13, BR-14, BR-15)" do
    it "tuần bắt đầu từ thứ Hai theo giờ Việt Nam" do
      query = described_class.new(scope: "weekly", game: game)
      expect(query.period.first.strftime("%A")).to eq("Monday")
      expect(query.period.first.time_zone.name).to eq(LeaderboardQuery::TIME_ZONE)
    end

    it "all_time không giới hạn khoảng thời gian" do
      expect(described_class.new(scope: "all_time", game: game).period).to be_nil
    end

    it "từ chối scope không hợp lệ" do
      expect { described_class.new(scope: "daily", game: game) }
        .to raise_error(LeaderboardQuery::InvalidScope)
    end
  end
end
