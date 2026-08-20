Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth (spec section 5.1)
  get "signup", to: "users#new", as: :signup
  post "users", to: "users#create", as: :users
  get "login", to: "sessions#new", as: :login
  # Singular resource: cả POST và DELETE dùng chung helper session_path.
  resource :session, only: [ :create, :destroy ]

  # Gameplay pages
  get "games", to: "games#index", as: :games
  get "games/:slug", to: "games#show", as: :game

  # Cài đặt tài khoản: hiện chỉ có chọn hình đại diện (BR-40). Route số nhiều, không dùng
  # `resource :setting` vì URL /setting số ít đọc lạ mà trang này còn nhận thêm mục sau này.
  get "settings", to: "settings#edit", as: :settings
  patch "settings", to: "settings#update"

  # Leaderboard (guest xem được)
  get "leaderboards", to: "leaderboards#show", as: :leaderboards

  # Hướng dẫn cách chơi — guest xem được để đọc luật trước khi đăng ký.
  get "guide", to: "pages#guide", as: :guide

  # Chính sách riêng tư — phải đọc được trước khi đăng ký nên để guest xem (Q7, spec §14).
  get "privacy", to: "pages#privacy", as: :privacy

  # Admin (spec section 3 — chỉ users.admin = true)
  namespace :admin do
    resources :users, only: [ :index, :destroy ]
    resources :question_reports, only: [ :index, :update ]
  end

  # JSON API cho gameplay (spec §5.1). Xác thực bằng session cookie, nên mọi lời gọi
  # không phải GET đều cần header X-CSRF-Token (spec §13).
  namespace :api do
    namespace :v1 do
      post "games/:slug/sessions", to: "game_sessions#create", as: :game_sessions
      get "sessions/:id/current", to: "game_sessions#current", as: :session_current
      post "sessions/:id/abandon", to: "game_sessions#abandon", as: :session_abandon
      post "sessions/:id/answers", to: "session_answers#create", as: :session_answers
      post "questions/:id/reports", to: "question_reports#create", as: :question_reports
    end
  end

  root "leaderboards#show"
end
