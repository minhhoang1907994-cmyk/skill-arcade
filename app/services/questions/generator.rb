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
    # Hai game kịch bản khai batch_size riêng trong BLUEPRINTS vì một đề của chúng gồm cả
    # nodes + options + effects, gấp nhiều lần một đề Bug Hunt. Để 5 thì Gemini dừng giữa
    # chừng với finishReason = MAX_TOKENS — đã gặp thật với incident_escape_room.
    BATCH_SIZE = 5
    # Đề bị loại ở bước validate (vd buggy_line trỏ sai dòng) làm lô đó hụt, nên phải cho
    # phép gọi thêm vài lô. Nhưng PHẢI có trần: nếu Gemini liên tục trả đề không dùng được
    # thì vòng lặp sẽ chạy mãi và nện API cho đến khi hết quota.
    EXTRA_BATCH_ALLOWANCE = 2
    MAX_OUTPUT_TOKENS = 16_384
    # Sinh đề chạy offline nên cho model suy nghĩ nhiều hơn lúc chấm (128) để đề khá hơn.
    # Vẫn phải chừa phần lớn MAX_OUTPUT_TOKENS cho nội dung vì thinking token tính chung.
    THINKING_BUDGET = 1024
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
      max_batches = (count.to_f / batch_size).ceil + EXTRA_BATCH_ALLOWANCE

      while records.size < count && prompts.size < max_batches
        wanted = [ count - records.size, batch_size ].min
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
                               temperature: 1.0, max_output_tokens: MAX_OUTPUT_TOKENS,
                               thinking_budget: THINKING_BUDGET)
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

    def batch_size
      blueprint[:batch_size] || BATCH_SIZE
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

      # Trước 1.19 game này chấm bằng Gemini lúc chơi nên đề chỉ cần `ambiguous_points`
      # dạng text tự do. Giờ chấm từ DB nên đề phải mang sẵn cả thang điểm: câu nào mơ hồ
      # (theo số thứ tự) và phương án câu hỏi làm rõ nào là tốt nhất.
      Game::SPEC_DETECTIVE => {
        item_schema: {
          type: "object",
          properties: {
            difficulty: { type: "string" },
            statements: { type: "array", items: { type: "string" } },
            ambiguous_statement_indexes: { type: "array", items: { type: "integer" } },
            clarifying_options: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  key: { type: "string" },
                  label: { type: "string" }
                },
                required: [ "key", "label" ]
              }
            },
            best_option_key: { type: "string" },
            explanation: { type: "string" }
          },
          required: [ "statements", "ambiguous_statement_indexes", "clarifying_options",
                      "best_option_key", "explanation" ]
        },
        instructions: lambda do |_generator|
          <<~TEXT
            Mỗi đề là một đoạn yêu cầu nghiệp vụ do khách hàng viết, tách thành từng câu.
            - statements: 4-7 câu, mỗi phần tử một câu hoàn chỉnh. Đọc liền nhau phải thành
              một đoạn yêu cầu tự nhiên, nghe hợp lý như khách hàng thật viết.
            - ambiguous_statement_indexes: số thứ tự (đếm từ 1) những câu CÒN MƠ HỒ — thiếu
              ngưỡng số, thiếu quy tắc biên, thiếu định nghĩa trạng thái, hoặc dùng từ chủ
              quan như "nhanh", "phù hợp", "nếu cần". Phải có 2-4 câu mơ hồ, và phải còn ít
              nhất 2 câu KHÔNG mơ hồ (nói rõ con số hoặc quy tắc cụ thể) để người chơi có
              thể tick sai.
            - clarifying_options: ĐÚNG 4 phương án câu hỏi làm rõ, key lần lượt "a","b","c","d".
            - best_option_key: key của phương án tốt nhất — câu hỏi đóng được điểm mơ hồ
              QUAN TRỌNG NHẤT và trả lời được bằng một con số hoặc một quy tắc.
            - Ba phương án còn lại phải nghe hợp lý nhưng kém hơn rõ ràng, mỗi cái sai một
              kiểu: hỏi về thứ đoạn text đã nói rõ, hỏi quá chung chung không đo được, hoặc
              hỏi chuyện ngoài phạm vi yêu cầu.
            - explanation: một câu nói rõ vì sao phương án tốt nhất hơn ba phương án kia.
          TEXT
        end,
        build: lambda do |item, _generator|
          statements = Array(item["statements"]).map { |line| line.to_s.strip }
                                               .reject(&:blank?)
          indexes = Array(item["ambiguous_statement_indexes"]).map(&:to_i)
                                                             .select(&:positive?).uniq.sort
          options = Array(item["clarifying_options"]).filter_map do |option|
            key = option.is_a?(Hash) ? option["key"].to_s.strip : ""
            label = option.is_a?(Hash) ? option["label"].to_s.strip : ""
            { "key" => key, "label" => label } if key.present? && label.present?
          end
          best = item["best_option_key"].to_s.strip
          keys = options.map { |option| option["key"] }

          # Bỏ đề mà thang điểm không tự nhất quán — chấm từ DB nên sai ở đây là chấm sai
          # theo, không còn tầng AI nào đứng giữa để đỡ.
          next nil if statements.size < 3
          next nil unless indexes.any? && indexes.all? { |index| index <= statements.size }
          # Phải còn câu không mơ hồ, không thì tick hết là đủ điểm.
          next nil unless indexes.size < statements.size
          next nil unless options.size >= 3 && keys.uniq.size == keys.size
          next nil unless keys.include?(best)

          {
            "content" => { "statements" => statements, "clarifying_options" => options },
            "answer_key" => {
              "ambiguous_statement_indexes" => indexes,
              "best_option_key" => best,
              "explanation" => item["explanation"].to_s
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
            breakdown: {
              type: "array",
              items: {
                type: "object",
                properties: { step: { type: "string" }, hours: { type: "number" } },
                required: [ "step", "hours" ]
              }
            },
            reasoning: { type: "string" }
          },
          required: [ "task_description", "breakdown", "reasoning" ]
        },
        instructions: lambda do |_generator|
          <<~TEXT
            Mỗi đề là một task phát triển có thể ước lượng được.
            - task_description: một câu mô tả task, cụ thể đủ để ước lượng.
            - context: bối cảnh ảnh hưởng đến effort (đã có sẵn gì, ràng buộc gì).
            - breakdown: mảng 3-7 dòng, mỗi dòng { step, hours } — chia task thành từng
              thao tác cụ thể và số giờ của thao tác đó. Đây là phần hiện cho người chơi
              sau khi trả lời, nên step phải là việc làm được ("viết migration thêm cột",
              "sửa test cũ vỡ"), không phải giai đoạn chung chung ("phát triển", "kiểm thử").
              hours là bội của 0.25. Tổng các dòng phải nằm trong khoảng
              #{Question::ESTIMATE_HOURS_RANGE.min} đến #{Question::ESTIMATE_HOURS_RANGE.max} giờ.
              Mỗi dòng chỉ tính điều tra + gõ code + tự viết test + sửa sau review. KHÔNG
              thêm dòng cho QA, họp, chờ review, deploy hay buffer rủi ro — người chơi ước
              lượng phần việc của dev nên đáp án cộng thêm các khoản đó là chấm sai họ.
              Task đã có sẵn hạ tầng và chỉ thêm một field/một tham số thì tổng thuộc mức
              1-2 giờ, đừng đẩy lên vài ngày. Đừng phóng đại dòng nào: việc mà thư viện/SDK
              đã có sẵn hàm thì tính theo thời gian gọi hàm đó, không tính như tự viết lại.
            - reasoning: một câu nói phần lớn thời gian nằm ở đâu, không lặp lại breakdown.
            Trộn đủ các mức: task 1-2 giờ, task nửa ngày, task một hai ngày, và task cả tuần.
          TEXT
        end,
        build: lambda do |item, _generator|
          # actual_hours KHÔNG hỏi model mà cộng từ breakdown. Hỏi cả hai thì model thường
          # trả về một tổng lệch với chính bảng nó vừa liệt kê, và Validator sẽ loại đề —
          # tức mỗi lần refill mất đề vì một phép cộng, không phải vì nội dung sai.
          rows = Array(item["breakdown"]).filter_map do |row|
            next nil unless row.is_a?(Hash) && row["step"].to_s.strip.present?
            next nil unless row["hours"].to_f.positive?

            { "step" => row["step"].to_s.strip, "hours" => row["hours"].to_f }
          end
          hours = rows.sum { |row| row["hours"] }.round(2)
          next nil if item["task_description"].to_s.strip.blank? || rows.empty? || hours <= 0

          {
            "content" => {
              "task_description" => item["task_description"].to_s.strip,
              "context" => item["context"].to_s
            },
            "answer_key" => {
              "actual_hours" => hours,
              "breakdown" => rows,
              "reasoning" => item["reasoning"].to_s
            }
          }
        end
      },

      Game::INCIDENT_ESCAPE_ROOM => {
        # Một đề gồm cả nodes + options + effects nên nặng gấp nhiều lần Bug Hunt.
        batch_size: 2,
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
        # Một đề gồm cả nodes + options + effects nên nặng gấp nhiều lần Bug Hunt.
        batch_size: 2,
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
