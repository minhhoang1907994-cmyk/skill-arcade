require "rails_helper"

RSpec.describe Questions::Generator do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:breaker) { Gemini::CircuitBreaker.new(name: "generator-test", cache: cache) }

  def fake_client(*payloads)
    responses = payloads.map do |payload|
      Gemini::Client::Response.new(text: payload.to_json, raw_body: {}, latency_ms: 1)
    end

    instance_double(Gemini::Client, model: "gemini-test").tap do |client|
      allow(client).to receive(:generate).and_return(*responses)
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
