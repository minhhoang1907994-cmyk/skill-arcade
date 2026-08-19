namespace :db do
  # Kiểm tra DB đang nối có đáp ứng những gì spec cần, thay vì đọc số version rồi tự suy.
  #
  # Dùng trước khi deploy: trỏ biến DB_* vào Aiven rồi chạy task này từ máy dev. Chạy được cả
  # trên Render sau khi deploy.
  #
  # An toàn để chạy trên production: phép kiểm CHECK constraint nằm trong transaction và luôn
  # rollback, nên không để lại bản ghi nào.
  desc "Kiểm tra DB đáp ứng yêu cầu của spec: version, TLS, CHECK constraint, max_connections"
  task preflight: :environment do
    cfg_for_error = ActiveRecord::Base.connection_db_config.configuration_hash
    # Nối trước, và báo lỗi bằng tiếng người thay vì backtrace: task này thường được chạy đầu tiên
    # khi trỏ vào một DB mới, nên "sai host / sai mật khẩu / chưa có DB" là lỗi hay gặp nhất.
    begin
      conn = ActiveRecord::Base.connection
      conn.select_value("SELECT 1")
    rescue ActiveRecord::NoDatabaseError
      abort("Không thấy database #{cfg_for_error[:database].inspect} trên "             "#{cfg_for_error[:host]}:#{cfg_for_error[:port]}. Kiểm lại DB_NAME, hoặc chạy "             "db:prepare để tạo.")
    rescue ActiveRecord::ConnectionNotEstablished, Mysql2::Error => e
      abort("Không kết nối được #{cfg_for_error[:username]}@#{cfg_for_error[:host]}:"             "#{cfg_for_error[:port]} — #{e.message.lines.first.to_s.strip}")
    end

    failures = []

    def line(status, label, detail)
      puts format("%-4s %-26s %s", status, label, detail)
    end

    puts "=== DB preflight ==="
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    line("--", "kết nối", "#{cfg[:username]}@#{cfg[:host]}:#{cfg[:port]}/#{cfg[:database]}")
    line("--", "adapter", conn.adapter_name)

    # 1. Version. Spec §19: dưới 8.0.16 thì MySQL BỎ QUA CHECK constraint mà không báo lỗi.
    version = conn.select_value("SELECT VERSION()").to_s
    numeric = version[/\A(\d+\.\d+\.\d+)/, 1]
    if numeric && Gem::Version.new(numeric) >= Gem::Version.new("8.0.16")
      line("OK", "MySQL version", version)
    else
      failures << "version"
      line("FAIL", "MySQL version", "#{version} — spec §19 cần >= 8.0.16")
    end

    # 2. TLS. Kiểm bằng cipher của CHÍNH phiên này, không kiểm bằng config — config khai đúng mà
    # server không bật thì vẫn ra kết nối trần.
    cipher = conn.select_rows("SHOW STATUS LIKE 'Ssl_cipher'").dig(0, 1).to_s
    ssl_mode = cfg[:ssl_mode] || "(không khai)"
    if cipher.empty?
      # Không phải lỗi ở local: Docker MySQL của dev không bật TLS. Trên Aiven thì bắt buộc phải có.
      line("WARN", "TLS", "phiên này KHÔNG mã hoá (ssl_mode=#{ssl_mode}) — Aiven bắt buộc TLS")
    else
      line("OK", "TLS", "#{cipher} (ssl_mode=#{ssl_mode}, sslca=#{cfg[:sslca] || 'không có'})")
    end

    # 3. CHECK constraint có thực sự được thực thi hay không (BR-04, trần 100 điểm).
    # update_column bỏ qua validation của model nên chỉ còn DB chặn — đúng cái cần đo.
    #
    # Phải kiểm bảng tồn tại TRƯỚC khi query: task này được thiết kế để chạy trên DB production
    # còn trống (chưa db:prepare), lúc đó Game.first sẽ ném StatementInvalid chứ không trả nil.
    game = if conn.table_exists?("games") && conn.table_exists?("game_sessions")
      Game.first
    end

    if !conn.table_exists?("games")
      line("SKIP", "CHECK constraint", "DB chưa có schema — chạy db:prepare rồi kiểm lại")
    elsif game.nil?
      line("SKIP", "CHECK constraint", "chưa có bản ghi games, chạy db:seed trước")
    else
      enforced = nil
      ActiveRecord::Base.transaction do
        user = User.create!(
          email: "preflight.nta@gmail.com",
          display_name: "preflight-#{SecureRandom.hex(4)}",
          password: SecureRandom.hex(12)
        )
        session = GameSession.create!(
          user: user, game: game, attempt_number: 1, score: 0,
          state: GameSession::IN_PROGRESS, current_position: 0, started_at: Time.current
        )
        begin
          session.update_column(:score, 999)
          enforced = false
        rescue ActiveRecord::StatementInvalid
          enforced = true
        end
        raise ActiveRecord::Rollback
      end

      if enforced
        line("OK", "CHECK constraint", "DB chặn score = 999 (BR-04 có lưới ở tầng DB)")
      else
        failures << "check_constraint"
        line("FAIL", "CHECK constraint", "DB CHO score = 999 — chỉ còn validation ở tầng model")
      end
    end

    # 4. max_connections so với pool. Aiven free giới hạn 76.
    max_conn = conn.select_rows("SHOW VARIABLES LIKE 'max_connections'").dig(0, 1).to_i
    pool = cfg[:pool].to_i
    if max_conn.positive? && max_conn < pool * 2
      failures << "max_connections"
      line("FAIL", "max_connections", "#{max_conn} quá thấp so với pool #{pool}")
    else
      line("OK", "max_connections", "#{max_conn} (pool của app: #{pool})")
    end

    puts
    if failures.empty?
      puts "Tất cả đạt. Xem dòng WARN nếu có."
    else
      abort("KHÔNG đạt: #{failures.join(', ')}. Xem docs/deploy/render-aiven.md.")
    end
  end
end
