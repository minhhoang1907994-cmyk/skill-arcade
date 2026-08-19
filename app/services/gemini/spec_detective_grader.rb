module Gemini
  # BR-26: mỗi đoạn spec tối đa 20 điểm — 10đ cho việc tìm đủ điểm mơ hồ, 10đ cho
  # chất lượng câu hỏi làm rõ. Không có hệ số tốc độ vì người chơi phải gõ text.
  #
  # BR-02 vẫn được giữ: điểm cuối cùng do server quyết. Gemini chỉ đưa đề xuất, và
  # mọi con số nhận về đều bị kẹp lại trong khoảng cho phép trước khi dùng.
  #
  # Kết quả trả về LUÔN kèm `attributes` để ghi một bản ghi `ai_gradings`, kể cả khi
  # gọi thất bại (BR-19). Đó là lý do grader không tự raise: người gọi cần dữ liệu log
  # trước khi quyết định trả 503.
  class SpecDetectiveGrader
    class InvalidResponse < Error; end

    AMBIGUITY_POINTS = 10
    QUESTION_POINTS = 10
    MAX_OUTPUT_TOKENS = 512

    RESPONSE_SCHEMA = {
      type: "object",
      properties: {
        ambiguity_score: { type: "integer" },
        question_score: { type: "integer" },
        feedback: { type: "string" }
      },
      required: [ "ambiguity_score", "question_score", "feedback" ]
    }.freeze

    Grading = Struct.new(:score, :explanation, :attributes, keyword_init: true) do
      def failed?
        attributes[:error].present?
      end
    end

    def initialize(client: Client.new, breaker: CircuitBreaker.new)
      @client = client
      @breaker = breaker
    end

    def call(question:, ambiguous_points:, questions:)
      prompt = build_prompt(question, ambiguous_points, questions)
      response = nil

      begin
        response = @breaker.run do
          raw = @client.generate(prompt, response_schema: RESPONSE_SCHEMA,
                                 max_output_tokens: MAX_OUTPUT_TOKENS)
          # Parse nằm TRONG breaker: response không đọc được cũng là API đang hỏng.
          [ raw, parse(raw.text) ]
        end
      rescue Error => e
        return failure(prompt, response, e)
      end

      raw, parsed = response
      success(prompt, raw, parsed)
    end

    private

    def success(prompt, raw, parsed)
      ambiguity = clamp(parsed["ambiguity_score"], AMBIGUITY_POINTS)
      question_quality = clamp(parsed["question_score"], QUESTION_POINTS)
      score = ambiguity + question_quality

      Grading.new(
        score: score,
        explanation: explain(ambiguity, question_quality, parsed["feedback"]),
        attributes: {
          model: @client.model, prompt: prompt,
          response: raw.raw_body.to_json, score: score, latency_ms: raw.latency_ms
        }
      )
    end

    def failure(prompt, _response, error)
      Rails.logger.warn("[gemini] chấm Spec Detective thất bại: #{error.class}: #{error.message}")

      Grading.new(
        score: 0,
        explanation: nil,
        # response NOT NULL ở DB nhưng lần gọi lỗi thì không có body — ghi chuỗi rỗng
        # và để cột error là nơi mang thông tin.
        attributes: {
          model: @client.model, prompt: prompt, response: "",
          score: nil, latency_ms: nil, error: "#{error.class}: #{error.message}"
        }
      )
    end

    def parse(text)
      parsed = JSON.parse(text)
      raise InvalidResponse, "Gemini trả JSON không phải object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => e
      raise InvalidResponse, "không parse được JSON từ Gemini: #{e.message}"
    end

    # Kẹp về khoảng hợp lệ: Gemini có thể trả số ngoài thang hoặc không phải số.
    def clamp(value, max)
      [ [ value.to_i, 0 ].max, max ].min
    end

    def explain(ambiguity, question_quality, feedback)
      parts = [ "Điểm mơ hồ: #{ambiguity}/#{AMBIGUITY_POINTS}. " \
                "Câu hỏi làm rõ: #{question_quality}/#{QUESTION_POINTS}." ]
      parts << feedback.to_s.strip if feedback.present?
      parts.join(" ")
    end

    def build_prompt(question, ambiguous_points, questions)
      key = question.answer_key

      <<~PROMPT
        Bạn là reviewer spec kỳ cựu, đang chấm bài luyện tập của một dev/BA.

        ĐOẠN YÊU CẦU GỐC:
        #{question.content['requirement_text']}

        ĐÁP ÁN THAM CHIẾU — các điểm mơ hồ cần phát hiện:
        #{bullets(key['ambiguous_points'])}

        ĐÁP ÁN THAM CHIẾU — câu hỏi làm rõ mẫu:
        #{bullets(key['sample_questions'])}
        #{rubric_section(key['rubric'])}
        BÀI LÀM CỦA NGƯỜI CHƠI — các điểm mơ hồ họ chỉ ra:
        #{bullets(ambiguous_points)}

        BÀI LÀM CỦA NGƯỜI CHƠI — câu hỏi làm rõ họ đặt:
        #{Array(questions).join("\n")}

        Hãy chấm theo hai thang, mỗi thang số nguyên:
        - ambiguity_score (0-#{AMBIGUITY_POINTS}): mức độ bao phủ các điểm mơ hồ ở đáp án
          tham chiếu. Cách diễn đạt khác nhưng cùng ý thì vẫn tính đúng. Nêu thêm điểm mơ hồ
          hợp lý không có trong đáp án tham chiếu thì không bị trừ.
        - question_score (0-#{QUESTION_POINTS}): câu hỏi có cụ thể, trả lời được, và thực sự
          đóng được điểm mơ hồ hay không. Câu hỏi chung chung kiểu "yêu cầu này nghĩa là gì?"
          bị điểm thấp.

        feedback: nhận xét tiếng Việt, tối đa 3 câu, nói rõ họ bỏ sót điểm mơ hồ nào và
        câu hỏi nào cần cụ thể hơn. Không tiết lộ nguyên văn đáp án tham chiếu.
      PROMPT
    end

    def bullets(values)
      list = Array(values).map { |value| "- #{value}" }
      list.empty? ? "- (không có)" : list.join("\n")
    end

    def rubric_section(rubric)
      return "\n" if rubric.blank?

      "\nRUBRIC BỔ SUNG TỪ NGƯỜI SOẠN ĐỀ:\n#{rubric}\n"
    end
  end
end
