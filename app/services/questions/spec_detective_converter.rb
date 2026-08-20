module Questions
  # Chuyển đề Spec Detective format TRƯỚC 1.19 sang format chọn.
  #
  # Format cũ: content = { requirement_text }, answer_key = { ambiguous_points, sample_questions }
  # — đủ để Gemini chấm text tự do, KHÔNG đủ để chấm từ DB.
  # Format mới: content = { statements, clarifying_options },
  #             answer_key = { ambiguous_statement_indexes, best_option_key, explanation }
  #
  # Dùng ĐÚNG MỘT LẦN sau khi deploy 1.19, qua `rake questions:convert_spec_detective`.
  # Giữ nguyên nội dung nghiệp vụ của đề cũ (requirement_text + các điểm mơ hồ đã soạn),
  # chỉ nhờ Gemini tách câu và dựng 4 phương án câu hỏi làm rõ.
  #
  # Ghi đè content nên checksum được tính lại (Question#assign_checksum). Lượt cũ vẫn trỏ
  # đúng bản ghi đó qua question_id nên điểm đã chấm không đổi.
  class SpecDetectiveConverter
    Report = Struct.new(:converted, :skipped, :failed, keyword_init: true)

    RESPONSE_SCHEMA = {
      type: "object",
      properties: {
        statements: { type: "array", items: { type: "string" } },
        ambiguous_statement_indexes: { type: "array", items: { type: "integer" } },
        clarifying_options: {
          type: "array",
          items: {
            type: "object",
            properties: { key: { type: "string" }, label: { type: "string" } },
            required: [ "key", "label" ]
          }
        },
        best_option_key: { type: "string" },
        explanation: { type: "string" }
      },
      required: [ "statements", "ambiguous_statement_indexes", "clarifying_options",
                  "best_option_key", "explanation" ]
    }.freeze

    TIMEOUT_SECONDS = 120
    THINKING_BUDGET = 1024
    MAX_OUTPUT_TOKENS = 4096

    def initialize(client: nil, breaker: Gemini::CircuitBreaker.new)
      @client = client || Gemini::Client.new(read_timeout: TIMEOUT_SECONDS)
      @breaker = breaker
    end

    # Chỉ nhận đề CÒN format cũ. Nhận diện bằng sự có mặt của requirement_text, không bằng
    # sự thiếu statements — đề nửa vời (có cả hai) cũng phải được chuyển cho hết.
    def self.pending
      game = Game.find_by(slug: Game::SPEC_DETECTIVE)
      return Question.none unless game

      Question.where(game: game).select { |q| q.content["requirement_text"].present? }
    end

    def call(question)
      item = generate(question)
      record = build_record(item)
      error = Validator.error_for(question.game, record)
      return [ :failed, error ] if error

      question.update!(content: record["content"], answer_key: record["answer_key"])
      [ :converted, nil ]
    rescue Gemini::Error, JSON::ParserError => e
      [ :failed, "#{e.class}: #{e.message}" ]
    rescue ActiveRecord::RecordInvalid => e
      [ :failed, e.record.errors.full_messages.join(", ") ]
    end

    private

    def generate(question)
      raw = @breaker.run do
        @client.generate(prompt_for(question), response_schema: RESPONSE_SCHEMA,
                         temperature: 0.4, max_output_tokens: MAX_OUTPUT_TOKENS,
                         thinking_budget: THINKING_BUDGET)
      end

      JSON.parse(raw.text)
    end

    def prompt_for(question)
      old_points = Array(question.answer_key["ambiguous_points"]).map { |p| "- #{p}" }.join("\n")

      <<~TEXT
        Chuyển đề luyện tập sau sang dạng câu hỏi CHỌN, giữ nguyên nội dung nghiệp vụ.

        Đoạn yêu cầu gốc:
        #{question.content['requirement_text']}

        Các điểm mơ hồ đã được người soạn đề xác định:
        #{old_points.presence || '- (chưa ghi)'}

        Yêu cầu đầu ra:
        - statements: tách đoạn yêu cầu gốc thành 4-6 câu. Được viết thêm 1-2 câu MỚI nói rõ
          một quy tắc hoặc con số cụ thể, để đoạn có câu KHÔNG mơ hồ. Đọc liền nhau phải
          thành một đoạn tự nhiên.
        - ambiguous_statement_indexes: số thứ tự (đếm từ 1) các câu còn mơ hồ, khớp với danh
          sách điểm mơ hồ ở trên. PHẢI ít hơn tổng số câu.
        - clarifying_options: đúng 4 phương án câu hỏi làm rõ, key "a","b","c","d".
        - best_option_key: phương án đóng được điểm mơ hồ quan trọng nhất và trả lời được
          bằng một con số hoặc một quy tắc.
        - Ba phương án còn lại nghe hợp lý nhưng kém hơn rõ ràng: hỏi thứ đoạn text đã nói
          rõ, hỏi quá chung chung không đo được, hoặc hỏi chuyện ngoài phạm vi.
        - explanation: một câu nói rõ vì sao phương án tốt nhất hơn ba phương án kia.
      TEXT
    end

    def build_record(item)
      statements = Array(item["statements"]).map { |line| line.to_s.strip }.reject(&:blank?)
      options = Array(item["clarifying_options"]).filter_map do |option|
        next unless option.is_a?(Hash)

        key = option["key"].to_s.strip
        label = option["label"].to_s.strip
        { "key" => key, "label" => label } if key.present? && label.present?
      end

      {
        "content" => { "statements" => statements, "clarifying_options" => options },
        "answer_key" => {
          "ambiguous_statement_indexes" => Array(item["ambiguous_statement_indexes"])
                                             .map(&:to_i).select(&:positive?).uniq.sort,
          "best_option_key" => item["best_option_key"].to_s.strip,
          "explanation" => item["explanation"].to_s
        }
      }
    end
  end
end
