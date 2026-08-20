module Questions
  # Kiểm tra một đề (hash `content` + `answer_key`) có dùng được không, TRƯỚC khi vào DB.
  #
  # Tách khỏi Importer vì từ 1.19 có hai đường ghi đề: import file YAML và task chuyển đổi
  # đề Spec Detective format cũ. Hai đường phải áp cùng một luật, không thì đề lọt qua
  # đường này mà đường kia chặn.
  #
  # Kiểm tra ở đây, không phải lúc chơi: đề thiếu khoá mà lọt vào DB thì lỗi chỉ lộ ra khi
  # người chơi đang giữa lượt. Và từ 1.19 mọi game đều chấm từ `answer_key` nên thang điểm
  # sai trong DB là chấm sai người chơi mà không còn tầng nào đứng giữa để đỡ.
  class Validator
    REQUIRED_KEYS = {
      Game::BUG_HUNT => {
        content: %w[language code_lines bug_types], answer_key: %w[buggy_line bug_type]
      },
      Game::SPEC_DETECTIVE => {
        content: %w[statements clarifying_options],
        answer_key: %w[ambiguous_statement_indexes best_option_key]
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

    # nil = dùng được. Chuỗi = lý do bị loại, hiển thị cho người chạy task.
    def self.error_for(game, record)
      new(game: game, record: record).error
    end

    def initialize(game:, record:)
      @game = game
      @record = record
    end

    def error
      return "không phải mapping" unless @record.is_a?(Hash)
      return "thiếu content hoặc answer_key" unless content.is_a?(Hash) &&
                                                   answer_key.is_a?(Hash)

      missing = missing_keys
      return "thiếu khoá: #{missing.join(', ')}" if missing.any?

      case @game.slug
      when Game::BUG_HUNT then bug_hunt_error
      when Game::SPEC_DETECTIVE then spec_detective_error
      end
    end

    private

    def content
      @record["content"]
    end

    def answer_key
      @record["answer_key"]
    end

    def missing_keys
      required = REQUIRED_KEYS.fetch(@game.slug, { content: [], answer_key: [] })

      required[:content].reject { |key| content[key].present? }.map { |key| "content.#{key}" } +
        required[:answer_key].reject { |key| answer_key[key].present? }
                             .map { |key| "answer_key.#{key}" }
    end

    def bug_hunt_error
      lines = content["code_lines"]
      buggy_line = answer_key["buggy_line"].to_i
      bug_type = answer_key["bug_type"].to_s

      return "code_lines phải là mảng chuỗi" unless lines.is_a?(Array) && lines.any?
      unless (1..lines.size).cover?(buggy_line)
        return "buggy_line #{buggy_line} nằm ngoài #{lines.size} dòng code"
      end
      unless Question::BUG_HUNT_TYPES.include?(bug_type)
        return "bug_type không hợp lệ: #{bug_type.inspect}"
      end

      nil
    end

    # Thang điểm phải tự nhất quán: index mơ hồ trỏ đúng câu có thật, phương án tốt nhất có
    # trong danh sách phương án, và phải còn câu KHÔNG mơ hồ — tick hết mà vẫn đủ điểm thì
    # game không phân biệt được ai đọc ai không.
    def spec_detective_error
      statements = content["statements"]
      options = content["clarifying_options"]
      indexes = Array(answer_key["ambiguous_statement_indexes"]).map(&:to_i)
      best = answer_key["best_option_key"].to_s

      return "statements phải là mảng chuỗi" unless statements.is_a?(Array) && statements.any?
      unless options.is_a?(Array) && options.size >= 2 &&
             options.all? { |option| option.is_a?(Hash) && option["key"].present? &&
                                     option["label"].present? }
        return "clarifying_options phải là mảng >= 2 phương án, mỗi phương án có key và label"
      end

      out_of_range = indexes.reject { |index| (1..statements.size).cover?(index) }
      if out_of_range.any?
        return "ambiguous_statement_indexes #{out_of_range.join(', ')} nằm ngoài " \
               "#{statements.size} câu"
      end
      return "không có câu nào được đánh dấu mơ hồ" if indexes.empty?
      if indexes.uniq.size >= statements.size
        return "mọi câu đều bị đánh dấu mơ hồ, đề không phân biệt được người chơi"
      end

      keys = options.map { |option| option["key"].to_s }
      return "best_option_key không có trong clarifying_options: #{best.inspect}" unless
        keys.include?(best)
      return "clarifying_options có key trùng nhau" unless keys.uniq.size == keys.size

      nil
    end
  end
end
