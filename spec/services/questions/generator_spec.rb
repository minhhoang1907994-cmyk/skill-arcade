require "rails_helper"

RSpec.describe Questions::Generator do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:breaker) { Gemini::CircuitBreaker.new(name: "generator-test", cache: cache) }

  # Mỗi phần tử: một Exception để raise, hoặc một payload để trả về — theo đúng thứ tự gọi.
  # Hết step mà vẫn bị gọi thì fail ngay thay vì lặp lại step cuối: số lô là thứ các test ở
  # đây đang kiểm, nên test khai thiếu step phải đỏ chứ không được im lặng chạy tiếp.
  def failing_client(*steps)
    calls = -1
    instance_double(Gemini::Client, model: "gemini-test").tap do |client|
      allow(client).to receive(:generate) do
        calls += 1
        step = steps.fetch(calls) do
          raise "failing_client: gọi lần #{calls + 1} nhưng chỉ khai #{steps.size} step"
        end
        raise step if step.is_a?(Exception)

        Gemini::Client::Response.new(text: step.to_json, raw_body: {}, latency_ms: 1)
      end
    end
  end

  def fake_client(*payloads)
    responses = payloads.map do |payload|
      Gemini::Client::Response.new(text: payload.to_json, raw_body: {}, latency_ms: 1)
    end

    instance_double(Gemini::Client, model: "gemini-test").tap do |client|
      allow(client).to receive(:generate).and_return(*responses)
    end
  end

  describe "Batch" do
    it "failures mặc định là [] khi caller không truyền, và to_h khớp reader" do
      batch = described_class::Batch.new(records: [], model: "gemini-test", prompts: [])

      expect(batch.failures).to eq([])
      expect(batch.to_h[:failures]).to eq([])
    end
  end

  describe "bug_hunt" do
    let(:game) { create(:game) }

    let(:payload) do
      { questions: [ {
        difficulty: "hard",
        code_lines: [ "public void save(User u) {", "    repo.save(u);", "}" ],
        buggy_line: 2,
        bug_type: "missing_transaction",
        explanation: "Thiếu @Transactional."
      } ] }
    end

    def generate(count: 1, client: fake_client(payload))
      described_class.new(game: game, language: "java", client: client, breaker: breaker)
                     .call(count: count)
    end

    it "dựng content/answer_key đúng cấu trúc §4.3" do
      record = generate.records.first

      expect(record["content"]).to eq(
        "language" => "java",
        "code_lines" => [ "public void save(User u) {", "    repo.save(u);", "}" ],
        "bug_types" => Question::BUG_HUNT_TYPES
      )
      expect(record["answer_key"]).to eq(
        "buggy_line" => 2, "bug_type" => "missing_transaction",
        "explanation" => "Thiếu @Transactional."
      )
      expect(record["difficulty"]).to eq("hard")
    end

    it "lấy bug_types từ danh sách chuẩn, không để Gemini tự nghĩ" do
      expect(generate.records.first["content"]["bug_types"]).to eq(Question::BUG_HUNT_TYPES)
    end

    it "loại đề có buggy_line trỏ ra ngoài số dòng code" do
      bad = { questions: [ payload[:questions].first.merge(buggy_line: 99) ] }

      expect(generate(client: fake_client(bad)).records).to be_empty
    end

    it "dừng sau số lô tối đa khi Gemini toàn trả đề không dùng được" do
      bad = { questions: [ payload[:questions].first.merge(buggy_line: 99) ] }
      client = fake_client(bad)

      batch = generate(count: 1, client: client)

      expect(batch.records).to be_empty
      expect(batch.prompts.size).to eq(1 + described_class::EXTRA_BATCH_ALLOWANCE)
      expect(client).to have_received(:generate).exactly(batch.prompts.size).times
    end

    # Trước 2026-09-03 một lô lỗi làm mất luôn đề của các lô đã xong: đo trên production
    # 2026-08-30..09-03, mọi lần refill [failed] đều là 503/timeout lẻ ở một lô.
    it "giữ lại đề của lô đã xong khi một lô lỗi" do
      many = { questions: Array.new(described_class::BATCH_SIZE) { payload[:questions].first } }
      client = failing_client(Gemini::Client::RequestFailed.new("Gemini trả HTTP 503"), many)

      batch = generate(count: described_class::BATCH_SIZE, client: client)

      expect(batch.records.size).to eq(described_class::BATCH_SIZE)
      expect(batch.failures.map(&:message)).to eq([ "Gemini trả HTTP 503" ])
    end

    it "vẫn raise khi mọi lô đều lỗi — người gọi phải thấy lỗi gốc" do
      error = Gemini::Client::RequestFailed.new("Gemini trả HTTP 503")
      client = failing_client(error, error, error)

      expect { generate(count: 1, client: client) }
        .to raise_error(Gemini::Client::RequestFailed, "Gemini trả HTTP 503")
    end

    # Không có test này thì nhánh `break if @breaker.open?` chưa từng chạy. count suy ra từ
    # hằng số chứ không viết số cứng: nhánh này chỉ chạm được khi max_batches > 1 + threshold,
    # mà max_batches lại phụ thuộc BATCH_SIZE — viết số cứng thì đổi BATCH_SIZE là test đỏ
    # với thông báo không nói được lý do thật.
    it "dừng sớm khi circuit breaker mở, không tiêu hết quota lô" do
      many = { questions: Array.new(described_class::BATCH_SIZE) { payload[:questions].first } }
      error = Gemini::Client::RequestFailed.new("Gemini trả HTTP 503")
      threshold = Gemini::CircuitBreaker::FAILURE_THRESHOLD
      client = failing_client(many, *Array.new(threshold) { error })

      # max_batches = (threshold + 1) + EXTRA_BATCH_ALLOWANCE, dư 2 lô so với mốc phải dừng.
      batch = generate(count: described_class::BATCH_SIZE * (threshold + 1), client: client)

      expect(batch.prompts.size).to eq(1 + threshold)
      expect(batch.records.size).to eq(described_class::BATCH_SIZE)
      expect(batch.failures.size).to eq(threshold)
      expect(breaker).to be_open
    end

    it "difficulty lạ thì về medium" do
      odd = { questions: [ payload[:questions].first.merge(difficulty: "impossible") ] }

      expect(generate(client: fake_client(odd)).records.first["difficulty"]).to eq("medium")
    end

    it "gọi nhiều lô khi count vượt BATCH_SIZE" do
      many = { questions: Array.new(described_class::BATCH_SIZE) { payload[:questions].first } }
      client = fake_client(many, many)

      batch = generate(count: described_class::BATCH_SIZE + 1, client: client)

      expect(batch.records.size).to eq(described_class::BATCH_SIZE + 1)
      expect(batch.prompts.size).to eq(2)
    end

    it "prompt nêu rõ ngôn ngữ được yêu cầu" do
      expect(generate.prompts.first).to include("java")
    end
  end

  describe "prod_roulette" do
    let(:game) { create(:game, :scenario_based) }

    let(:payload) do
      { questions: [ {
        difficulty: "medium",
        scenario: "Đang test tính năng tặng voucher trên PROD.",
        nodes: [ { key: "n1", prompt: "Làm gì trước?",
                   options: [ { key: "safe", label: "Tắt kênh gửi thật" },
                              { key: "fatal", label: "Bấm gửi cho toàn bộ user" } ] } ],
        effects: [
          { option_key: "safe", points: 10, irreversible: false,
            consequence_text: "Không ai nhận thông báo.", next_node: "n2" },
          { option_key: "fatal", points: 10, irreversible: true,
            consequence_text: "50k user nhận SMS thật.", next_node: "n2" }
        ]
      } ] }
    end

    it "gom effects thành hash option_effects khoá theo option_key" do
      record = described_class.new(game: game, client: fake_client(payload), breaker: breaker)
                             .call(count: 1).records.first

      expect(record["answer_key"]["option_effects"].keys).to contain_exactly("safe", "fatal")
      expect(record["answer_key"]["option_effects"]["fatal"]).to eq(
        "points" => 10, "irreversible" => true,
        "consequence_text" => "50k user nhận SMS thật.", "next_node" => "n2"
      )
    end

    # Game kịch bản khai batch_size = 2 nên 4 đề cần 2 lô thành công — đây chính là dạng
    # mục tiêu mà một 503 lẻ từng làm mất trắng (production 2026-08-30..09-03).
    it "một lô lỗi không làm mất đề của các lô còn lại dù batch_size = 2" do
      two = { questions: Array.new(2) { payload[:questions].first } }
      error = Gemini::Client::RequestFailed.new("Gemini trả HTTP 503")

      batch = described_class.new(game: game, client: failing_client(error, two, two),
                                  breaker: breaker).call(count: 4)

      expect(batch.records.size).to eq(4)
      expect(batch.prompts.size).to eq(3)
      expect(batch.failures.map(&:message)).to eq([ "Gemini trả HTTP 503" ])
    end

    it "hiệu ứng gom được chấm đúng bởi scorer thật" do
      record = described_class.new(game: game, client: fake_client(payload), breaker: breaker)
                             .call(count: 1).records.first
      question = create(:question, game: game, content: record["content"],
                        answer_key: record["answer_key"])
      session = create(:game_session, game: game)

      result = Scoring::ProdRoulette.new.call(
        session: session, question: question,
        answer: { "node_key" => "n1", "option_key" => "fatal" }, elapsed_ms: 1_000
      )

      expect(result.score).to eq(0)
      expect(result).to be_terminal
    end
  end

  describe "spec_detective (BR-26 — dạng chọn từ 1.19)" do
    let(:game) { create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective") }

    let(:item) do
      {
        difficulty: "medium",
        statements: [ "Xử lý đơn nhanh.", "Lưu vào bảng orders.", "Thông báo nếu cần." ],
        ambiguous_statement_indexes: [ 3, 1, 1 ],
        clarifying_options: [ { key: "a", label: "Nhanh là mấy giây?" },
                              { key: "b", label: "Lưu ở bảng nào?" },
                              { key: "c", label: "Có cần nhanh hơn đối thủ?" },
                              { key: "d", label: "Email gửi bằng gì?" } ],
        best_option_key: "a",
        explanation: "a đo được bằng con số."
      }
    end

    def generate(payload)
      described_class.new(game: game, client: fake_client(payload), breaker: breaker)
                     .call(count: 1).records
    end

    it "dựng content/answer_key đúng format chọn, index đã uniq và sort" do
      record = generate({ questions: [ item ] }).first

      expect(record["content"]).to eq(
        "statements" => [ "Xử lý đơn nhanh.", "Lưu vào bảng orders.", "Thông báo nếu cần." ],
        "clarifying_options" => [ { "key" => "a", "label" => "Nhanh là mấy giây?" },
                                  { "key" => "b", "label" => "Lưu ở bảng nào?" },
                                  { "key" => "c", "label" => "Có cần nhanh hơn đối thủ?" },
                                  { "key" => "d", "label" => "Email gửi bằng gì?" } ]
      )
      expect(record["answer_key"]).to eq(
        "ambiguous_statement_indexes" => [ 1, 3 ],
        "best_option_key" => "a",
        "explanation" => "a đo được bằng con số."
      )
    end

    it "loại đề có index trỏ ra ngoài danh sách câu" do
      expect(generate({ questions: [ item.merge(ambiguous_statement_indexes: [ 9 ]) ] })).to be_empty
    end

    it "loại đề đánh dấu mọi câu là mơ hồ" do
      payload = { questions: [ item.merge(ambiguous_statement_indexes: [ 1, 2, 3 ]) ] }

      expect(generate(payload)).to be_empty
    end

    it "loại đề có best_option_key không thuộc danh sách phương án" do
      expect(generate({ questions: [ item.merge(best_option_key: "z") ] })).to be_empty
    end

    it "đề sinh ra được scorer thật chấm đúng" do
      record = generate({ questions: [ item ] }).first
      question = create(:question, game: game, content: record["content"],
                        answer_key: record["answer_key"])

      result = Scoring::SpecDetective.new.call(
        session: create(:game_session, game: game), question: question,
        answer: { "statement_indexes" => [ 1, 3 ], "option_key" => "a" }, elapsed_ms: nil
      )

      expect(result.score).to eq(20)
    end
  end


  it "báo lỗi với game chưa có blueprint" do
    game = create(:game)
    allow(game).to receive(:slug).and_return("unknown_game")

    expect { described_class.new(game: game, client: fake_client({}), breaker: breaker) }
      .to raise_error(described_class::UnsupportedGame)
  end
end
