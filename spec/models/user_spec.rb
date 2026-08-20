require "rails_helper"

RSpec.describe User do
  describe "email allowlist (BR-01)" do
    it "chấp nhận email dạng xxx.nta@gmail.com" do
      user = build(:user, email: "hoang.nta@gmail.com")
      expect(user).to be_valid
    end

    it "từ chối email gmail thường" do
      user = build(:user, email: "hoang@gmail.com")
      expect(user).not_to be_valid
      expect(user.errors.of_kind?(:email, :invalid)).to be true
    end

    it "từ chối domain khác" do
      user = build(:user, email: "hoang.nta@example.com")
      expect(user).not_to be_valid
    end

    it "chuẩn hoá email về chữ thường" do
      user = create(:user, email: "Hoang.NTA@Gmail.com")
      expect(user.email).to eq("hoang.nta@gmail.com")
    end
  end

  describe "display_name" do
    it "không cho trùng" do
      create(:user, display_name: "Hoang")
      duplicate = build(:user, display_name: "Hoang")
      expect(duplicate).not_to be_valid
    end
  end

  describe "avatar (BR-40)" do
    it "mặc định là hình hero" do
      expect(create(:user).avatar).to eq(Avatar::DEFAULT)
    end

    it "chấp nhận mọi hình trong Avatar::CHOICES" do
      Avatar::CHOICES.each do |name|
        expect(build(:user, avatar: name)).to be_valid, "#{name} phải chọn được"
      end
    end

    it "từ chối tên hình không có trong app" do
      user = build(:user, avatar: "khong_ton_tai")

      expect(user).not_to be_valid
      expect(user.errors.of_kind?(:avatar, :inclusion)).to be true
    end
  end

  describe "password" do
    it "yêu cầu tối thiểu 8 ký tự" do
      user = build(:user, password: "1234567", password_confirmation: "1234567")
      expect(user).not_to be_valid
    end
  end

  describe "khoá tài khoản khi đăng nhập sai (BR-23)" do
    let(:user) { create(:user) }

    it "chưa khoá khi chưa chạm ngưỡng" do
      (User::MAX_FAILED_LOGINS - 1).times { user.register_failed_login! }
      expect(user).not_to be_locked
    end

    it "khoá khi chạm ngưỡng" do
      User::MAX_FAILED_LOGINS.times { user.register_failed_login! }
      expect(user).to be_locked
      expect(user.locked_until).to be > Time.current
    end

    it "đăng nhập thành công thì reset bộ đếm" do
      User::MAX_FAILED_LOGINS.times { user.register_failed_login! }
      user.reset_failed_logins!
      expect(user).not_to be_locked
      expect(user.failed_login_count).to eq(0)
    end
  end

  describe "#best_score_for (BR-06, BR-08)" do
    let(:user) { create(:user) }
    let(:game) { create(:game) }

    it "lấy điểm cao nhất trong các lượt đã hoàn thành" do
      create(:game_session, :finished, user: user, game: game, score: 40, attempt_number: 1)
      create(:game_session, :finished, user: user, game: game, score: 70, attempt_number: 2)
      create(:game_session, :finished, user: user, game: game, score: 55, attempt_number: 3)

      expect(user.best_score_for(game)).to eq(70)
    end

    it "bỏ qua lượt chưa hoàn thành" do
      create(:game_session, user: user, game: game, score: 90, attempt_number: 1)
      expect(user.best_score_for(game)).to eq(0)
    end
  end

  describe "#total_score (BR-07)" do
    it "cộng personal best của từng game" do
      user = create(:user)
      bug_hunt = create(:game)
      roulette = create(:game, :scenario_based)

      create(:game_session, :finished, user: user, game: bug_hunt, score: 80, attempt_number: 1)
      create(:game_session, :finished, user: user, game: bug_hunt, score: 60, attempt_number: 2)
      create(:game_session, :finished, user: user, game: roulette, score: 30, attempt_number: 1)

      expect(user.total_score).to eq(110)
    end
  end
end
