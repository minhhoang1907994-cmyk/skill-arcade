module Questions
  # Nạp file YAML do `rake questions:generate` xuất ra vào bảng questions.
  #
  # Open Question Q4 (owner chốt 2026-08-19): KHÔNG cần người soát tay, đề do AI sinh được
  # import trực tiếp. Lưới an toàn còn lại là luật cấu trúc trong Questions::Validator cộng
  # luồng người chơi báo câu sai rồi admin ẩn (BR-16, BR-18).
  #
  # Idempotent theo checksum: chạy lại cùng một file không tạo bản ghi trùng.
  class Importer
    class InvalidFile < StandardError; end

    Report = Struct.new(:created, :updated, :rejected, keyword_init: true) do
      def total
        created + updated
      end
    end

    def initialize(path:)
      @path = Pathname.new(path)
    end

    def call
      data = load_file
      game = Game.find_by(slug: data["game"]) ||
             raise(InvalidFile, "game không tồn tại: #{data['game'].inspect}")
      generated_at = parse_time(data["generated_at"])

      report = Report.new(created: 0, updated: 0, rejected: [])

      Array(data["questions"]).each_with_index do |record, index|
        import_one(game, record, generated_at, report, index)
      end

      report
    end

    private

    def load_file
      raise InvalidFile, "không thấy file #{@path}" unless @path.file?

      # aliases: true — người soát đề có thể tự dùng anchor/alias cho phần lặp lại, và
      # Psych cũng tự sinh alias khi hai câu dùng chung một object. safe_load vẫn chặn
      # việc khởi tạo class tuỳ ý, đó mới là phần nguy hiểm.
      data = YAML.safe_load(@path.read, permitted_classes: [ Date, Time ], aliases: true)
      raise InvalidFile, "file YAML phải là một mapping ở mức trên cùng" unless data.is_a?(Hash)
      raise InvalidFile, "thiếu khoá 'questions'" unless data["questions"].is_a?(Array)

      data
    end

    def import_one(game, record, generated_at, report, index)
      error = validation_error(game, record)
      if error
        report.rejected << "câu ##{index + 1}: #{error}"
        return
      end

      content = record["content"]
      question = Question.find_or_initialize_by(checksum: Question.checksum_for(content))
      existed = question.persisted?

      question.assign_attributes(
        game: game, content: content, answer_key: record["answer_key"],
        difficulty: record["difficulty"].presence, source: "ai_generated",
        generated_at: generated_at
      )
      question.save!

      existed ? report.updated += 1 : report.created += 1
    rescue ActiveRecord::RecordInvalid => e
      report.rejected << "câu ##{index + 1}: #{e.record.errors.full_messages.join(', ')}"
    end

    def validation_error(game, record)
      Validator.error_for(game, record)
    end

    def parse_time(value)
      return Time.current if value.blank?

      value.is_a?(String) ? Time.zone.parse(value) || Time.current : value.to_time
    end
  end
end
