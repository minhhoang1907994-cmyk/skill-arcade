require "rails_helper"

# Modal dialog thay alert/confirm/prompt của trình duyệt (app/views/shared/_dialog.html.erb).
#
# Phần logic là JS nên không test được ở đây. Những gì test được và ĐÁNG test là hợp đồng
# giữa server và JS: dialog có mặt trên mọi trang, và các nút phá huỷ mang đúng thuộc tính
# data mà handler đọc. Trước 1.19 nút xoá tài khoản khai `data-turbo-confirm` mà Turbo
# không hề được nạp, nên bước xác nhận chưa bao giờ chạy — test này chặn việc đó lặp lại.
RSpec.describe "Modal dialog dùng chung" do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  def login(as_user)
    post session_path, params: { email: as_user.email, password: "password123" }
  end

  it "có mặt ở trang guest đọc được" do
    get privacy_path

    expect(response.body).to include('id="app-dialog"')
    expect(response.body).to include("window.appDialog")
  end

  it "có mặt ở trang game" do
    create(:game)
    login(user)

    get game_path(slug: Game::BUG_HUNT)

    expect(response.body).to include('id="app-dialog"')
  end

  describe "nút phá huỷ ở trang admin" do
    it "nút xoá tài khoản mang data-confirm để handler chặn được" do
      victim = create(:user)
      login(admin)

      get admin_users_path

      expect(response.body).to include("data-confirm")
      expect(response.body).to include("Xoá tài khoản #{victim.email}?")
    end

    it "KHÔNG dùng data-turbo-confirm — Turbo không được nạp nên nó là code chết" do
      create(:user)
      login(admin)

      get admin_users_path

      # Khớp dạng THUỘC TÍNH, không phải chuỗi bất kỳ: chữ "data-turbo-confirm" còn
      # xuất hiện trong comment giải thích ở shared/_dialog.html.erb.
      expect(response.body).not_to include('data-turbo-confirm="')
    end

    it "nút ẩn câu hỏi mang data-confirm" do
      QuestionReport.create!(question: create(:question), user: user,
                             reason: "Đáp án sai", status: QuestionReport::OPEN)
      login(admin)

      get admin_question_reports_path

      expect(response.body).to include("Ẩn câu hỏi này khỏi mọi lượt chơi mới?")
    end
  end
end
