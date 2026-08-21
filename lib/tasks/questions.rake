namespace :questions do
  desc "Sinh đề bằng Gemini, xuất YAML ra db/question_banks/<game>/<date>.yml " \
       "(vd: rake 'questions:generate[bug_hunt,10,java]')"
  task :generate, [ :game, :count, :language ] => :environment do |_task, args|
    slug = args[:game].to_s
    count = args[:count].to_i
    language = args[:language].to_s.presence

    game = Game.find_by(slug: slug) || abort("Không có game slug=#{slug.inspect}")
    abort("count phải > 0") unless count.positive?
    if game.language_scoped? && language.blank?
      abort("#{slug} phân đề theo ngôn ngữ — truyền thêm tham số language, " \
            "vd: rake 'questions:generate[#{slug},10,java]'")
    end
    unless Gemini::Client.configured?
      abort("GEMINI_API_KEY chưa được cấu hình (xem .env.example)")
    end

    puts "Đang sinh #{count} đề cho #{slug}#{language ? " (#{language})" : ''}..."
    report_request_estimate(game, count)

    batch = Questions::Generator.new(game: game, language: language).call(count: count)

    if batch.records.empty?
      abort("Gemini không trả đề nào dùng được. Chạy lại hoặc giảm count.")
    end

    path = Questions::BankFile.write(game: game, language: language, batch: batch)

    puts "Đã ghi #{batch.records.size}/#{count} đề vào #{path}"
    puts "Model: #{batch.model} — #{batch.prompts.size} request"
    puts ""
    puts "Nạp vào DB bằng:"
    puts "  rake 'questions:import[#{path.relative_path_from(Rails.root)}]'"
  rescue Questions::Generator::UnsupportedGame, Gemini::Error => e
    abort("Sinh đề thất bại: #{e.class}: #{e.message}")
  end

  desc "Nạp file YAML đề đã soát vào DB (vd: rake 'questions:import[db/question_banks/...]')"
  task :import, [ :file ] => :environment do |_task, args|
    abort("Thiếu đường dẫn file") if args[:file].blank?

    report = Questions::Importer.new(path: args[:file]).call

    puts "Đã nạp: #{report.created} câu mới, #{report.updated} câu cập nhật"

    if report.rejected.any?
      puts "Bị loại #{report.rejected.size} câu:"
      report.rejected.each { |line| puts "  - #{line}" }
    end
  rescue Questions::Importer::InvalidFile => e
    abort("File không dùng được: #{e.message}")
  end

  desc "Job hằng ngày: dọn lượt quá hạn rồi sinh + nạp đề cho game đang thiếu (BR-24 + refill)"
  task refill: :environment do
    unless Gemini::Client.configured?
      abort("GEMINI_API_KEY chưa được cấu hình (xem .env.example)")
    end

    # Phải chạy TRƯỚC: Refiller bỏ qua mục tiêu còn lượt in_progress, và lượt treo vĩnh viễn
    # (BR-24 chưa từng có scheduler) sẽ chặn refill mãi mãi nếu không dọn.
    Rake::Task["game_sessions:expire_stale"].invoke

    outcomes = Questions::Refiller.new.call
    outcomes.each { |outcome| puts "[#{outcome.status}] #{outcome.label}: #{outcome.detail}" }

    # Exit code khác 0 để scheduler báo đỏ — im lặng thất bại thì tháng sau mới phát hiện
    # ngân hàng đề không hề lớn lên.
    abort("refill thất bại") if outcomes.any? { |outcome| outcome.status == :failed }

    # Mọi mục tiêu bị chặn cũng phải báo đỏ. Trước đây chỉ :failed làm job đỏ nên nhiều ngày
    # liền job xanh mà KHÔNG nạp được đề nào — đúng cái bẫy mà comment trên đây cảnh báo.
    # :nothing_to_do (mọi game đã đủ đề) vẫn xanh, vì đó là trạng thái đúng.
    if outcomes.none? { |outcome| outcome.status == :done } &&
       outcomes.any? { |outcome| outcome.status == :skipped }
      abort("refill không nạp được đề nào: mọi mục tiêu đang thiếu đều còn lượt đang chơi")
    end
  end

  desc "Ẩn mọi đề không còn hợp lệ theo Questions::Validator (vd: đề Spec Detective format cũ)"
  task hide_invalid: :environment do
    hidden = 0

    Game.find_each do |game|
      Question.playable.where(game: game).find_each do |question|
        record = { "content" => question.content, "answer_key" => question.answer_key }
        error = Questions::Validator.error_for(game, record)
        next if error.nil?

        # hidden thay vì destroy: session_answers trỏ tới câu này (has_many
        # dependent: :restrict_with_error), và BR-16 yêu cầu lượt cũ giữ nguyên điểm.
        question.update!(hidden: true)
        hidden += 1
        puts "  ẩn ##{question.id} (#{game.slug}): #{error}"
      end
    end

    puts "Đã ẩn #{hidden} đề không hợp lệ."
    # next chứ không phải return: trong block của rake task, return ném LocalJumpError.
    next if hidden.zero?

    Game.find_each do |game|
      next if game.language_scoped?

      playable = Question.playable.where(game: game).count
      next if playable >= game.questions_per_session

      puts "CẢNH BÁO: #{game.slug} chỉ còn #{playable} đề, cần #{game.questions_per_session} "            "cho một lượt — người chơi sẽ nhận NO_QUESTIONS_AVAILABLE."
    end
  end

  desc "MỘT LẦN sau 1.19: chuyển đề Spec Detective format cũ sang dạng chọn"
  task convert_spec_detective: :environment do
    unless Gemini::Client.configured?
      abort("GEMINI_API_KEY chưa được cấu hình (xem .env.example)")
    end

    pending = Questions::SpecDetectiveConverter.pending
    if pending.empty?
      puts "Không còn đề Spec Detective format cũ nào."
      next
    end

    puts "Sẽ chuyển #{pending.size} đề. Mỗi đề một request Gemini."
    converter = Questions::SpecDetectiveConverter.new
    counts = { converted: 0, failed: 0 }

    pending.each do |question|
      status, detail = converter.call(question)
      counts[status] += 1
      puts "  ##{question.id}: #{status}#{detail ? " — #{detail}" : ''}"
    end

    puts "Xong: #{counts[:converted]} chuyển được, #{counts[:failed]} thất bại."
    puts "Đề thất bại vẫn ở format cũ và KHÔNG chơi được — chạy lại task này, hoặc ẩn chúng "          "trong trang admin." if counts[:failed].positive?
  end

  # Sinh đề và chấm điểm KHÔNG còn dùng chung hạn mức từ 1.19: Spec Detective chấm từ DB nên
  # Gemini chỉ còn một người dùng duy nhất là việc sinh đề. Ước lượng ở đây để người chạy
  # biết trước lô này tiêu bao nhiêu trong 20 request/ngày (spec §20).
  def report_request_estimate(game, count)
    per_batch = Questions::Generator::BLUEPRINTS.dig(game.slug, :batch_size) ||
                Questions::Generator::BATCH_SIZE
    needed = (count.to_f / per_batch).ceil
    allowance = Questions::Generator::EXTRA_BATCH_ALLOWANCE

    puts "Lô này cần khoảng #{needed} request (#{per_batch} đề/request), tối đa "          "#{needed + allowance} nếu có đề bị loại. Hạn mức đo được: 20 request/ngày mỗi model."
  end
end
