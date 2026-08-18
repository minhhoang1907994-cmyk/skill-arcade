namespace :game_sessions do
  # BR-24: lượt để quá 24 giờ mà chưa xong thì đánh dấu bỏ dở.
  # Phase 1 chạy bằng cron/scheduler bên ngoài, chưa cần queue system (spec section 19).
  desc "Đánh dấu các lượt chơi quá hạn thành abandoned"
  task expire_stale: :environment do
    count = 0

    GameSession.stale.find_each do |session|
      session.abandon!(GameSession::TIMEOUT)
      count += 1
    end

    puts "Đã đánh dấu #{count} lượt quá hạn thành abandoned"
  end
end
