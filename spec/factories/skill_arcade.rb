FactoryBot.define do
  sequence(:allowed_email) { |n| "player#{n}.nta@gmail.com" }
  sequence(:display_name) { |n| "Player #{n}" }

  factory :user do
    email { generate(:allowed_email) }
    display_name { generate(:display_name) }
    password { "password123" }
    password_confirmation { "password123" }

    trait :admin do
      admin { true }
    end
  end

  factory :game do
    # games là bảng tra cứu với 5 slug cố định — tái sử dụng bản ghi cùng slug
    # thay vì tạo mới, để test tạo nhiều game không đụng unique index.
    initialize_with { Game.find_or_initialize_by(slug: slug) }

    slug { Game::BUG_HUNT }
    name { "Bug Hunt" }
    description { "Tìm bug trong đoạn code" }
    questions_per_session { 10 }
    steps_per_session { 10 }

    trait :scenario_based do
      slug { Game::PROD_ROULETTE }
      name { "PROD Roulette" }
      questions_per_session { 1 }
      steps_per_session { 10 }
    end
  end

  factory :question do
    game
    sequence(:content) { |n| { "language" => "php", "code_lines" => [ "line #{n}" ] } }
    answer_key { { "buggy_line" => 1, "bug_type" => "sql_injection" } }
    source { "ai_generated" }
  end

  factory :game_session do
    user
    game
    # Tự tính số lượt kế tiếp để tạo nhiều session cho cùng cặp (user, game)
    # không đụng unique index. Test nào cần số cụ thể thì truyền tường minh.
    attempt_number do
      GameSession.where(user: user, game: game).maximum(:attempt_number).to_i + 1
    end
    score { 0 }
    state { GameSession::IN_PROGRESS }
    started_at { Time.current }

    trait :finished do
      state { GameSession::FINISHED }
      finished_at { Time.current }
    end

    trait :abandoned_by_system do
      state { GameSession::ABANDONED }
      abandoned_reason { GameSession::SYSTEM_ERROR }
    end
  end

  # Ghi một câu trả lời đã chấm vào lượt — dùng để dựng lịch sử chơi trong test.
  factory :session_answer_record, class: "SessionAnswer" do
    transient do
      session { nil }
      at { Time.current }
    end

    game_session { session }
    question { nil }
    position { (session&.session_answers&.count || 0) + 1 }
    answer { { "choice" => "x" } }
    score { 10 }
    answered_at { at }
  end
end
