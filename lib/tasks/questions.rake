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
    puts "Lưu ý: mỗi lô #{Questions::Generator::BATCH_SIZE} đề tiêu 1 request Gemini — " \
         "gói free có hạn mức theo ngày, xem AI Studio của project."

    batch = Questions::Generator.new(game: game, language: language).call(count: count)

    if batch.records.empty?
      abort("Gemini không trả đề nào dùng được. Chạy lại hoặc giảm count.")
    end

    path = write_bank_file(game, language, batch)

    puts "Đã ghi #{batch.records.size}/#{count} đề vào #{path}"
    puts "Model: #{batch.model} — #{batch.prompts.size} request"
    puts ""
    puts "BƯỚC BẮT BUỘC TIẾP THEO: đọc lại file trên trước khi import (Open Question Q4)."
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

  # Không ghi đè file đã tồn tại: file cũ có thể đã được người soạn đề soát và sửa tay.
  def write_bank_file(game, language, batch)
    dir = Rails.root.join("db", "question_banks", game.slug)
    dir.mkpath

    base = [ Date.current.iso8601, language ].compact.join("-")
    path = dir.join("#{base}.yml")
    suffix = 2
    while path.exist?
      path = dir.join("#{base}-#{suffix}.yml")
      suffix += 1
    end

    payload = { "game" => game.slug, "model" => batch.model,
                "generated_at" => Time.current.iso8601 }
    payload["language"] = language if language
    payload["questions"] = batch.records

    # deep_dup trước khi dump: nhiều câu dùng chung object Question::BUG_HUNT_TYPES, và
    # Psych sẽ sinh anchor/alias (*id001) cho object trùng — đọc rất khó khi soát tay.
    path.write(<<~HEADER + payload.deep_dup.to_yaml)
      # Đề do Gemini sinh — CHƯA vào DB.
      #
      # Soát tay trước khi import (Open Question Q4): kiểm tra đáp án có đúng không,
      # nội dung có phù hợp không, và với Bug Hunt là buggy_line có trỏ đúng dòng không.
      # Sửa trực tiếp trong file này rồi mới chạy:
      #   rake 'questions:import[#{path.relative_path_from(Rails.root)}]'
    HEADER

    path
  end
end
