module Questions
  # Sinh đề theo lô bằng Gemini (offline, qua rake task — KHÔNG gọi lúc chơi).
  #
  # Quy trình chốt ở spec §6 và Open Question Q4: task này chỉ xuất YAML ra
  # `db/question_banks/`, người soạn đề đọc lại rồi mới `rake questions:import`.
  # Không có đường nào để đề do AI sinh vào thẳng DB.
  #
  # Cấu trúc trả về được ép bằng responseSchema của Gemini thay vì parse text tự do.
  # Vẫn còn hai chỗ phải tự dựng trong Ruby:
  # - `bug_types` của Bug Hunt lấy từ danh sách chuẩn `Question::BUG_HUNT_TYPES`,
  #   không để AI tự nghĩ ra, vì đó là danh sách lựa chọn hiển thị cho người chơi
  # - `option_effects` của hai game kịch bản là hash khoá động, mà responseSchema không
  #   diễn đạt được khoá động — nên AI trả array rồi Ruby gom lại thành hash
  class Generator
    class UnsupportedGame < StandardError; end

    # Sinh đề chạy offline nên chịu được timeout dài hơn lời gọi lúc chơi (10s ở §15).
    GENERATION_TIMEOUT_SECONDS = 120
    # Chia lô nhỏ: một response quá dài dễ bị cắt vì maxOutputTokens.
    BATCH_SIZE = 5
    # Đề bị loại ở bước validate (vd buggy_line trỏ sai dòng) làm lô đó hụt, nên phải cho
    # phép gọi thêm vài lô. Nhưng PHẢI có trần: nếu Gemini liên tục trả đề không dùng được
    # thì vòng lặp sẽ chạy mãi và nện API cho đến khi hết quota.
    EXTRA_BATCH_ALLOWANCE = 2
    MAX_OUTPUT_TOKENS = 8192
    DIFFICULTIES = [ "easy", "medium", "hard" ].freeze

    Batch = Struct.new(:records, :model, :prompts, keyword_init: true)

    def initialize(game:, language: nil, client: nil, breaker: Gemini::CircuitBreaker.new)
      @game = game
      @language = language.presence
      @client = client || Gemini::Client.new(read_timeout: GENERATION_TIMEOUT_SECONDS)
      @breaker = breaker

      raise UnsupportedGame, "chưa có blueprint cho game #{game.slug}" if blueprint.nil?
    end

    # Public vì các lambda trong BLUEPRINTS gọi từ ngoài instance.
    attr_reader :language

    def steps_per_session
      @game.steps_per_session
    end

    # Trả về ĐẾN count đề, có thể ít hơn nếu Gemini trả đề không dùng được. Người gọi
    # (rake task) tự quyết định chạy lại hay không — thà thiếu còn hơn gọi API vô hạn.
    def call(count:)
      records = []
      prompts = []
      max_batches = (count.to_f / BATCH_SIZE).ceil + EXTRA_BATCH_ALLOWANCE

      while records.size < count && prompts.size < max_batches
        wanted = [ count - records.size, BATCH_SIZE ].min
        prompt = build_prompt(wanted)
        prompts << prompt
        records.concat(generate_batch(prompt))
      end

      Batch.new(records: records.first(count), model: @client.model, prompts: prompts)
    end

    private

    def generate_batch(prompt)
      response = @breaker.run do
        raw = @client.generate(prompt, response_schema: response_schema,
                               temperature: 1.0, max_output_tokens: MAX_OUTPUT_TOKENS)
        JSON.parse(raw.text)
      end

      Array(response["questions"]).map { |item| build_record(item) }.compact
    rescue JSON::ParserError => e
      raise Gemini::Client::RequestFailed, "không parse được JSON từ Gemini: #{e.message}"
    end

    def build_record(item)
      record = blueprint[:build].call(item, self)
      return nil if record.nil?

      difficulty = item["difficulty"].to_s
      record.merge("difficulty" => DIFFICULTIES.include?(difficulty) ? difficulty : "medium")
    end

    def response_schema
      {
        type: "object",
        properties: { questions: { type: "array", items: blueprint[:item_schema] } },
        required: [ "questions" ]
      }
    end

    def build_prompt(count)
      <<~PROMPT
        Bạn là người soạn đề luyện tập cho dev/BA người Việt. Sinh #{count} đề cho game
        "#{@game.name}".

        #{blueprint[:instructions].call(self)}

        Yêu cầu chung:
        - Toàn bộ phần văn bản hiển thị cho người chơi và phần giải thích viết bằng TIẾNG VIỆT.
          Riêng code, log, tên biến/hàm/bảng giữ nguyên tiếng Anh.
        - Mỗi đề phải khác nhau rõ rệt, không xoay quanh cùng một tình huống.
        - difficulty chọn một trong: #{DIFFICULTIES.join(', ')}.
        - Không dùng tên người thật, tên công ty thật, hay dữ liệu cá nhân.
      PROMPT
    end

    # ------------------------------------------------------------------
    # Blueprint theo từng game
    # ------------------------------------------------------------------

    def blueprint
      @blueprint ||= BLUEPRINTS[@game.slug]
    end

    # Gom array [{option_key, ...}] thành hash {option_key => {...}} vì responseSchema
    # không diễn đạt được hash khoá động.
    def self.index_effects(effects, keys)
      Array(effects).each_with_object({}) do |effect, acc|
        option_key = effect["option_key"].to_s
        next if option_key.blank?

        acc[option_key] = keys.index_with { |key| effect[key] }
      end
    end

    NODE_SCHEMA = {
      type: "object",
      properties: {
        key: { type: "string" },
        prompt: { type: "string" },
        options: {
          type: "array",
          items: {
            type: "object",
            properties: { key: { type: "string" }, label: { type: "string" } },
            required: [ "key", "label" ]
          }
        }
      },
      required: [ "key", "prompt", "options" ]
    }.freeze

    BLUEPRINTS = {
      Game::BUG_HUNT => {
        item_schema: {
          type: "object",
          properties: {
            difficulty: { type: "string" },
            code_lines: { type: "array", items: { type: "string" } },
            buggy_line: { type: "integer" },
            bug_type: { type: "string", enum: Question::BUG_HUNT_TYPES },
            explanation: { type: "string" }
          },
          required: [ "code_lines", "buggy_line", "bug_type", "explanation" ]
        },
        instructions: lambda do |generator|
          <<~TEXT
            Mỗi đề là một đoạn code #{generator.language} dài 3-8 dòng, chứa ĐÚNG MỘT bug.
            - code_lines: mảng từng dòng code, không kèm số dòng.
            - buggy_line: số thứ tự dòng có bug, đếm từ 1 theo code_lines.
            - bug_type: chọn một giá trị trong danh sách cho phép, và phải khớp đúng bug
              đã cài trong code.
            - explanation: một câu nói rõ vì sao sai và cách sửa.
            Code phải trông như code thật trong dự án, không phải ví dụ sách giáo khoa.
          TEXT
        end,
        build: lambda do |item, generator|
          lines = Array(item["code_lines"]).map(&:to_s)
          buggy_line = item["buggy_line"].to_i
          # Bỏ đề mà AI đánh số dòng ngoài phạm vi — sai chỗ này thì chấm điểm sai theo.
          next nil unless lines.size >= 2 && (1..lines.size).cover?(buggy_line)

          {
            "content" => {
              "language" => generator.language,
              "code_lines" => lines,
              "bug_types" => Question::BUG_HUNT_TYPES
            },
            "answer_key" => {
              "buggy_line" => buggy_line,
              "bug_type" => item["bug_type"].to_s,
              "explanation" => item["explanation"].to_s
            }
          }
        end
      },

      Game::SPEC_DETECTIVE => {
        item_schema: {
          type: "object",
          properties: {
            difficulty: { type: "string" },
            requirement_text: { type: "string" },
            ambiguous_points: { type: "array", items: { type: "string" } },
            sample_questions: { type: "array", items: { type: "string" } },
            rubric: { type: "string" }
          },
          required: [ "requirement_text", "ambiguous_points", "sample_questions" ]
        },
        instructions: lambda do |_generator|
          <<~TEXT
            Mỗi đề là một đoạn yêu cầu nghiệp vụ 3-6 câu, viết như khách hàng thật viết:
            nghe hợp lý nhưng còn 3-5 điểm mơ hồ (thiếu ngưỡng số, thiếu quy tắc biên,
            thiếu định nghĩa trạng thái, dùng từ chủ quan như "nhanh", "dễ dùng").
            - requirement_text: nguyên văn đoạn yêu cầu.
            - ambiguous_points: liệt kê từng điểm mơ hồ, mỗi điểm một dòng ngắn.
            - sample_questions: câu hỏi làm rõ mẫu, mỗi câu đóng được một điểm mơ hồ,
              phải cụ thể và trả lời được bằng một con số hoặc một quy tắc.
            - rubric: ghi chú cho người chấm về điểm nào là quan trọng nhất.
          TEXT
        end,
        build: lambda do |item, _generator|
          points = Array(item["ambiguous_points"]).map(&:to_s).reject(&:blank?)
          next nil if item["requirement_text"].to_s.strip.blank? || points.empty?

          {
            "content" => { "requirement_text" => item["requirement_text"].to_s.strip },
            "answer_key" => {
              "ambiguous_points" => points,
              "sample_questions" => Array(item["sample_questions"]).map(&:to_s),
              "rubric" => item["rubric"].to_s
            }
          }
        end
      },

      Game::ESTIMATE_POKER => {
        item_schema: {
          type: "object",
          properties: {
            difficulty: { type: "string" },
            task_description: { type: "string" },
            context: { type: "string" },
            actual_hours: { type: "number" },
            reasoning: { type: "string" }
          },
          required: [ "task_description", "actual_hours", "reasoning" ]
        },
        instructions: lambda do |_generator|
          <<~TEXT
            Mỗi đề là một task phát triển có thể ước lượng được.
            - task_description: một câu mô tả task, cụ thể đủ để ước lượng.
            - context: bối cảnh ảnh hưởng đến effort (đã có sẵn gì, ràng buộc gì).
            - actual_hours: số giờ tham chiếu, trong khoảng 1 đến 80, phản ánh cả thời
              gian test và xử lý dữ liệu cũ chứ không chỉ thời gian gõ code.
            - reasoning: giải thích phần lớn thời gian nằm ở đâu.
            Trộn đủ các mức: task vài giờ, task một hai ngày, và task cả tuần.
          TEXT
        end,
        build: lambda do |item, _generator|
          hours = item["actual_hours"].to_f
          next nil if item["task_description"].to_s.strip.blank? || hours <= 0

          {
            "content" => {
              "task_description" => item["task_description"].to_s.strip,
              "context" => item["context"].to_s
            },
            "answer_key" => { "actual_hours" => hours, "reasoning" => item["reasoning"].to_s }
          }
        end
      },

      Game::INCIDENT_ESCAPE_ROOM => {
        item_schema: {
          type: "object",
          properties: {
            difficulty: { type: "string" },
            scenario: { type: "string" },
            initial_logs: { type: "string" },
            nodes: { type: "array", items: NODE_SCHEMA },
            effects: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  option_key: { type: "string" },
                  points: { type: "integer" },
                  minutes_cost: { type: "integer" },
                  next_node: { type: "string" },
                  explanation: { type: "string" }
                },
                required: [ "option_key", "points", "minutes_cost", "next_node", "explanation" ]
              }
            },
            recovery_node: { type: "string" }
          },
          required: [ "scenario", "initial_logs", "nodes", "effects", "recovery_node" ]
        },
        instructions: lambda do |generator|
          <<~TEXT
            Mỗi đề là một kịch bản sự cố production, chơi theo #{generator.steps_per_session}
            bước quyết định.
            - scenario: mô tả sự cố đang xảy ra.
            - initial_logs: đoạn log/metric mở đầu để người chơi bắt đầu chẩn đoán.
            - nodes: ít nhất #{generator.steps_per_session} node, mỗi node có key duy nhất,
              prompt là tình huống tại bước đó, và 3-4 options.
            - option_key của MỌI option phải duy nhất trong cả đề (không chỉ trong một node),
              vì hệ thống tra cứu hiệu ứng theo option_key ở phạm vi toàn đề.
            - effects: một phần tử cho mỗi option. points = 10 cho hành động chẩn đoán/khôi
              phục đúng, 5 cho hành động vô hại nhưng tốn thời gian, 0 cho hành động sai.
              minutes_cost là số phút giả lập bị tiêu (hành động sai tốn nhiều hơn).
              next_node là key của node kế tiếp.
            - recovery_node: key của node ứng với lúc sự cố đã được khắc phục.
            Tổng minutes_cost của một chuỗi lựa chọn đúng phải dưới 15 phút để người chơi
            giỏi còn ăn được điểm thưởng thời gian.
          TEXT
        end,
        build: lambda do |item, _generator|
          nodes = Array(item["nodes"])
          effects = Questions::Generator.index_effects(
            item["effects"], [ "points", "minutes_cost", "next_node", "explanation" ]
          )
          next nil if nodes.empty? || effects.empty? || item["recovery_node"].to_s.blank?

          {
            "content" => {
              "scenario" => item["scenario"].to_s,
              "initial_logs" => item["initial_logs"].to_s,
              "nodes" => nodes
            },
            "answer_key" => {
              "option_effects" => effects,
              "recovery_node" => item["recovery_node"].to_s
            }
          }
        end
      },

      Game::PROD_ROULETTE => {
        item_schema: {
          type: "object",
          properties: {
            difficulty: { type: "string" },
            scenario: { type: "string" },
            nodes: { type: "array", items: NODE_SCHEMA },
            effects: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  option_key: { type: "string" },
                  points: { type: "integer" },
                  irreversible: { type: "boolean" },
                  consequence_text: { type: "string" },
                  next_node: { type: "string" }
                },
                required: [ "option_key", "points", "irreversible", "consequence_text",
                            "next_node" ]
              }
            }
          },
          required: [ "scenario", "nodes", "effects" ]
        },
        instructions: lambda do |generator|
          <<~TEXT
            Mỗi đề là một kịch bản thao tác trên môi trường PRODUCTION, chơi theo
            #{generator.steps_per_session} bước quyết định.
            - scenario: bối cảnh (đang test tính năng gì, hệ thống đang ở trạng thái nào).
            - nodes: ít nhất #{generator.steps_per_session} node, mỗi node 3-4 options.
            - option_key của MỌI option phải duy nhất trong cả đề, vì hệ thống tra cứu hiệu
              ứng theo option_key ở phạm vi toàn đề.
            - effects: một phần tử cho mỗi option. points = 10 cho lựa chọn an toàn,
              3 cho lựa chọn rủi ro nhưng còn khôi phục được, 0 cho lựa chọn KHÔNG THỂ
              THU HỒI.
            - irreversible = true chỉ dành cho hành động không có cách nào lấy lại: đã gửi
              email/SMS/push notification thật cho người dùng thật, đã tạo giao dịch hoặc
              voucher thật, đã gọi API bên thứ ba thật. Xoá hoặc sửa dữ liệu KHÔNG tính là
              không thể thu hồi nếu còn backup.
            - consequence_text: hậu quả cụ thể của lựa chọn đó, viết như báo cáo sự cố thật.
            Mỗi đề phải có ít nhất một option irreversible = true.
          TEXT
        end,
        build: lambda do |item, _generator|
          nodes = Array(item["nodes"])
          effects = Questions::Generator.index_effects(
            item["effects"], [ "points", "irreversible", "consequence_text", "next_node" ]
          )
          next nil if nodes.empty? || effects.empty?

          {
            "content" => { "scenario" => item["scenario"].to_s, "nodes" => nodes },
            "answer_key" => { "option_effects" => effects }
          }
        end
      }
    }.freeze
  end
end
