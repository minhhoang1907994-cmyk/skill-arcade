require "rails_helper"

RSpec.describe Gemini::SpecDetectiveGrader do
  let(:question) do
    build(:question,
          content: { "requirement_text" => "Hệ thống phải xử lý đơn hàng nhanh." },
          answer_key: { "ambiguous_points" => [ "nhanh là bao lâu", "đơn hàng trạng thái nào" ],
                        "sample_questions" => [ "SLA xử lý đơn là bao nhiêu giây?" ],
                        "rubric" => "Ưu tiên điểm về SLA." })
  end

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:breaker) { Gemini::CircuitBreaker.new(name: "grader-test", cache: cache) }

  # Client giả thay cho Net::HTTP: project không có webmock nên inject client là cách
  # duy nhất để test không chạm mạng.
  def fake_client(payload:, model: "gemini-test", latency_ms: 123)
    instance_double(
      Gemini::Client,
      model: model,
      generate: Gemini::Client::Response.new(
        text: payload.is_a?(String) ? payload : payload.to_json,
        raw_body: { "candidates" => [ { "content" => { "parts" => [ { "text" => "..." } ] } } ] },
        latency_ms: latency_ms
      )
    )
  end

  def grade(client)
    described_class.new(client: client, breaker: breaker).call(
      question: question,
      ambiguous_points: [ "nhanh là bao lâu" ],
      questions: [ "SLA xử lý đơn là bao nhiêu giây?" ]
    )
  end

  it "cộng hai thang điểm thành điểm của bước" do
    grading = grade(fake_client(payload: { ambiguity_score: 7, question_score: 8,
                                           feedback: "Thiếu điểm về trạng thái đơn." }))

    expect(grading).not_to be_failed
    expect(grading.score).to eq(15)
    expect(grading.explanation).to include("7/10", "8/10", "Thiếu điểm về trạng thái đơn.")
  end

  it "kẹp điểm Gemini trả về trong khoảng cho phép (BR-02)" do
    grading = grade(fake_client(payload: { ambiguity_score: 99, question_score: -5,
                                           feedback: "" }))

    expect(grading.score).to eq(described_class::AMBIGUITY_POINTS)
  end

  it "ghi đủ thuộc tính để tạo bản ghi ai_gradings khi thành công (BR-19)" do
    grading = grade(fake_client(payload: { ambiguity_score: 5, question_score: 5,
                                          feedback: "ok" }))

    expect(grading.attributes).to include(model: "gemini-test", score: 10, latency_ms: 123)
    expect(grading.attributes[:prompt]).to include("Hệ thống phải xử lý đơn hàng nhanh.")
    expect(grading.attributes[:error]).to be_nil
  end

  it "prompt gồm cả đáp án tham chiếu và bài làm của người chơi" do
    grading = grade(fake_client(payload: { ambiguity_score: 5, question_score: 5,
                                          feedback: "ok" }))

    expect(grading.attributes[:prompt]).to include("đơn hàng trạng thái nào", "Ưu tiên điểm về SLA.")
  end

  it "trả grading lỗi thay vì raise khi Gemini hỏng, để vẫn ghi được log (§8.5)" do
    client = instance_double(Gemini::Client, model: "gemini-test")
    allow(client).to receive(:generate).and_raise(Gemini::Client::RequestFailed, "Gemini timeout")

    grading = grade(client)

    expect(grading).to be_failed
    expect(grading.score).to eq(0)
    expect(grading.attributes[:score]).to be_nil
    expect(grading.attributes[:response]).to eq("")
    expect(grading.attributes[:error]).to include("Gemini timeout")
  end

  it "coi response không phải JSON là lỗi và tính vào circuit breaker" do
    client = fake_client(payload: "không phải json")

    grading = grade(client)

    expect(grading).to be_failed
    expect(grading.attributes[:error]).to include("không parse được JSON")
    expect(cache.read("grader-test/circuit/failures")).to eq(1)
  end

  it "không gọi Gemini khi circuit breaker đang mở" do
    client = instance_double(Gemini::Client, model: "gemini-test")
    allow(client).to receive(:generate).and_raise(Gemini::Client::RequestFailed, "down")

    Gemini::CircuitBreaker::FAILURE_THRESHOLD.times { grade(client) }
    expect(breaker).to be_open

    grading = grade(client)

    expect(grading).to be_failed
    expect(grading.attributes[:error]).to include("circuit breaker đang mở")
    expect(client).to have_received(:generate).exactly(Gemini::CircuitBreaker::FAILURE_THRESHOLD).times
  end
end
