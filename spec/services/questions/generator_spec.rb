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

  it "báo lỗi với game chưa có blueprint" do
    game = create(:game)
    allow(game).to receive(:slug).and_return("unknown_game")

    expect { described_class.new(game: game, client: fake_client({}), breaker: breaker) }
      .to raise_error(described_class::UnsupportedGame)
  end
end
