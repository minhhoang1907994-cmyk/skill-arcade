require "rails_helper"

# Trang Hướng dẫn nói luật chơi, nên rủi ro của nó là nói SAI luật. Test giữ hai thứ:
# đường vào trang có ở mọi header, và các con số lấy từ DB thay vì viết cứng trong văn bản.
RSpec.describe "Trang hướng dẫn" do
  # Nội dung ERB bị ngắt dòng theo bề rộng file nên assert trên body thô rất giòn.
  # Nén khoảng trắng trước khi so (giống privacy_spec).
  def body_text
    response.body.gsub(/\s+/, " ")
  end

  let!(:bug_hunt) do
    create(:game, slug: Game::BUG_HUNT, name: "Bug Hunt",
           questions_per_session: 10, steps_per_session: 10)
  end

  it "guest đọc được — luật phải đọc được trước khi đăng ký" do
    get guide_path

    expect(response).to have_http_status(:ok)
    expect(body_text).to include("Bug Hunt")
  end

  it "có nút Hướng dẫn ở header cả khi chưa đăng nhập và khi đã đăng nhập" do
    get login_path
    expect(response.body).to include(guide_path)

    post session_path, params: { email: create(:user).email, password: "password123" }
    get games_path
    expect(response.body).to include(guide_path)
  end

  it "lấy số bước và trần điểm từ DB, không viết cứng trong văn bản" do
    bug_hunt.update!(steps_per_session: 7, max_score: 70)

    get guide_path

    expect(body_text).to include("7 bước · tối đa 70 điểm")
  end

  it "không nói về game đã bị tắt" do
    create(:game, slug: Game::PROD_ROULETTE, name: "PROD Roulette",
           questions_per_session: 1, steps_per_session: 10, active: false)

    get guide_path

    expect(body_text).not_to include("PROD Roulette")
  end

  it "nêu đúng hệ số tốc độ của Bug Hunt — màn duy nhất tính thời gian" do
    get guide_path

    expect(body_text).to include("Dưới 30 giây")
    expect(body_text).to include("×0.8")
    expect(body_text).to include("×0.5")
  end
end
