require "rails_helper"

RSpec.describe Questions::Importer do
  let(:game) { create(:game) }
  let(:dir) { Rails.root.join("tmp", "importer_spec") }

  before { dir.mkpath }
  after { FileUtils.rm_rf(dir) }

  def write_file(questions, game_slug: game.slug, extra: {})
    path = dir.join("bank-#{SecureRandom.hex(4)}.yml")
    payload = { "game" => game_slug, "model" => "gemini-test",
                "generated_at" => "2026-08-19T10:00:00+07:00",
                "questions" => questions }.merge(extra)
    path.write(payload.to_yaml)
    path
  end

  def bug_hunt_record(overrides = {})
    {
      "difficulty" => "easy",
      "content" => {
        "language" => "java",
        "code_lines" => [ "void a() {", "    repo.save(u);", "}" ],
        "bug_types" => Question::BUG_HUNT_TYPES
      },
      "answer_key" => { "buggy_line" => 2, "bug_type" => "missing_transaction",
                        "explanation" => "Thiếu @Transactional." }
    }.deep_merge(overrides)
  end

  def import(path)
    described_class.new(path: path).call
  end

  it "nạp câu hợp lệ với source ai_generated và generated_at từ file" do
    report = import(write_file([ bug_hunt_record ]))

    expect(report.created).to eq(1)
    question = Question.last
    expect(question.source).to eq("ai_generated")
    expect(question.language).to eq("java")
    expect(question.difficulty).to eq("easy")
    expect(question.generated_at).to eq(Time.zone.parse("2026-08-19T10:00:00+07:00"))
  end

  it "chạy lại cùng file không tạo bản ghi trùng" do
    path = write_file([ bug_hunt_record ])

    import(path)
    report = import(path)

    expect(report.created).to eq(0)
    expect(report.updated).to eq(1)
    expect(Question.count).to eq(1)
  end

  it "loại câu thiếu khoá bắt buộc, vẫn nạp các câu còn lại" do
    broken = bug_hunt_record.tap { |r| r["answer_key"].delete("buggy_line") }
    valid = bug_hunt_record("content" => { "code_lines" => [ "void b() {", "    x();", "}" ] })

    report = import(write_file([ broken, valid ]))

    expect(report.created).to eq(1)
    expect(report.rejected.first).to include("answer_key.buggy_line")
  end

  it "loại câu Bug Hunt có buggy_line ngoài phạm vi code_lines" do
    report = import(write_file([ bug_hunt_record("answer_key" => { "buggy_line" => 9 }) ]))

    expect(report.created).to eq(0)
    expect(report.rejected.first).to include("nằm ngoài 3 dòng code")
  end

  it "loại câu Bug Hunt có bug_type không nằm trong danh sách chuẩn" do
    report = import(write_file([ bug_hunt_record("answer_key" => { "bug_type" => "typo" }) ]))

    expect(report.created).to eq(0)
    expect(report.rejected.first).to include("bug_type không hợp lệ")
  end

  it "báo lỗi khi game slug trong file không tồn tại" do
    path = write_file([ bug_hunt_record ], game_slug: "khong_ton_tai")

    expect { import(path) }.to raise_error(described_class::InvalidFile, /game không tồn tại/)
  end

  it "báo lỗi khi không thấy file" do
    expect { import(dir.join("thieu.yml")) }
      .to raise_error(described_class::InvalidFile, /không thấy file/)
  end

  it "báo lỗi khi file thiếu khoá questions" do
    path = dir.join("xau.yml")
    path.write({ "game" => game.slug }.to_yaml)

    expect { import(path) }.to raise_error(described_class::InvalidFile, /questions/)
  end
end
