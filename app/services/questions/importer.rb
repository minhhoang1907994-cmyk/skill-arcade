module Questions
  # Nạp file YAML do `rake questions:generate` xuất ra vào bảng questions.
  #
  # Open Question Q4: không có admin panel duyệt đề, nên bước người soạn đề đọc lại file
  # YAML là lưới an toàn duy nhất trước khi câu hỏi đến tay người chơi. Importer vì vậy
  # chỉ nhận file trên đĩa, không tự gọi Gemini.
  #
  # Idempotent theo checksum: chạy lại cùng một file không tạo bản ghi trùng.
  class Importer
    class InvalidFile < StandardError; end

    Report = Struct.new(:created, :updated, :rejected, keyword_init: true) do
      def total
        created + updated
      end
    end

    REQUIRED_KEYS = {
      Game::BUG_HUNT => {
        content: %w[language code_lines bug_types], answer_key: %w[buggy_line bug_type]
      },
      Game::SPEC_DETECTIVE => {
        content: %w[requirement_text], answer_key: %w[ambiguous_points]
      },
      Game::ESTIMATE_POKER => {
        content: %w[task_description], answer_key: %w[actual_hours]
      },
      Game::INCIDENT_ESCAPE_ROOM => {
        content: %w[scenario nodes], answer_key: %w[option_effects recovery_node]
      },
      Game::PROD_ROULETTE => {
        content: %w[scenario nodes], answer_key: %w[option_effects]
      }
    }.freeze

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

    # Kiểm tra ở tầng import, không phải tầng chơi: đề thiếu khoá mà lọt vào DB thì lỗi
    # chỉ lộ ra lúc người chơi đang chơi giữa lượt.
    def validation_error(game, record)
      return "không phải mapping" unless record.is_a?(Hash)
      return "thiếu content hoặc answer_key" unless record["content"].is_a?(Hash) &&
                                                    record["answer_key"].is_a?(Hash)

      required = REQUIRED_KEYS.fetch(game.slug, { content: [], answer_key: [] })
      missing = required[:content].reject { |key| record["content"][key].present? }
                                  .map { |key| "content.#{key}" } +
                required[:answer_key].reject { |key| record["answer_key"][key].present? }
                                     .map { |key| "answer_key.#{key}" }

      return "thiếu khoá: #{missing.join(', ')}" if missing.any?

      bug_hunt_error(game, record)
    end

    def bug_hunt_error(game, record)
      return nil unless game.slug == Game::BUG_HUNT

      lines = record["content"]["code_lines"]
      buggy_line = record["answer_key"]["buggy_line"].to_i
      bug_type = record["answer_key"]["bug_type"].to_s

      return "code_lines phải là mảng chuỗi" unless lines.is_a?(Array) && lines.any?
      unless (1..lines.size).cover?(buggy_line)
        return "buggy_line #{buggy_line} nằm ngoài #{lines.size} dòng code"
      end
      unless Question::BUG_HUNT_TYPES.include?(bug_type)
        return "bug_type không hợp lệ: #{bug_type.inspect}"
      end

      nil
    end

    def parse_time(value)
      return Time.current if value.blank?

      value.is_a?(String) ? Time.zone.parse(value) || Time.current : value.to_time
    end
  end
end
