require "rails_helper"

RSpec.describe GameSession do
  let(:user) { create(:user) }
  let(:game) { create(:game) }

  describe "validations" do
    it "không cho điểm vượt 100 (BR-04)" do
      session = build(:game_session, user: user, game: game, score: 101)
      expect(session).not_to be_valid
    end

    it "không cho hai lượt cùng attempt_number cho cùng user và game" do
      create(:game_session, user: user, game: game, attempt_number: 1)
      duplicate = build(:game_session, user: user, game: game, attempt_number: 1)
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#completed_all_steps? (BR-30)" do
    it "dùng steps_per_session chứ không phải questions_per_session" do
      scenario_game = create(:game, :scenario_based)
      session = build(:game_session, user: user, game: scenario_game, current_position: 1)

      expect(scenario_game.questions_per_session).to eq(1)
      expect(session.completed_all_steps?).to be false

      session.current_position = 10
      expect(session.completed_all_steps?).to be true
    end
  end

  describe "scope :finished (BR-08)" do
    it "chỉ lấy lượt có state finished và finished_at" do
      finished = create(:game_session, :finished, user: user, game: game, attempt_number: 1)
      create(:game_session, user: user, game: game, attempt_number: 2)
      create(:game_session, :abandoned_by_system, user: user, game: game, attempt_number: 3)

      expect(described_class.finished).to contain_exactly(finished)
    end
  end

  describe "scope :counting_toward_rate_limit (BR-33)" do
    it "loại lượt hỏng do lỗi hệ thống, giữ lượt người chơi tự bỏ" do
      finished = create(:game_session, :finished, user: user, game: game, attempt_number: 1)
      create(:game_session, :abandoned_by_system, user: user, game: game, attempt_number: 2)
      user_quit = create(:game_session, user: user, game: game, attempt_number: 3,
                         state: GameSession::ABANDONED,
                         abandoned_reason: GameSession::USER_QUIT)

      expect(described_class.counting_toward_rate_limit).to contain_exactly(finished, user_quit)
    end
  end

  describe "scope :stale (BR-24)" do
    it "chỉ lấy lượt in_progress quá 24 giờ" do
      old = create(:game_session, user: user, game: game, attempt_number: 1,
                   started_at: 25.hours.ago)
      create(:game_session, user: user, game: game, attempt_number: 2,
             started_at: 1.hour.ago)

      expect(described_class.stale).to contain_exactly(old)
    end
  end

  describe "#abandon!" do
    it "ghi lại lý do bỏ lượt" do
      session = create(:game_session, user: user, game: game)
      session.abandon!(GameSession::SYSTEM_ERROR)

      expect(session.state).to eq(GameSession::ABANDONED)
      expect(session.abandoned_reason).to eq(GameSession::SYSTEM_ERROR)
      expect(session.finished_at).to be_nil
    end
  end
end
