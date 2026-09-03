require "rails_helper"

# Guard cho quy ước ở CLAUDE.md mục Error Handling: mỗi namespace trong app/services/ có một
# base error riêng, và mọi lỗi trong namespace kế thừa base đó thay vì kế thừa thẳng
# StandardError.
#
# Vì sao cần guard bằng spec: lỗi kế thừa sai vẫn chạy đúng ở mọi test khác — nó chỉ lộ ra
# lúc một chỗ `rescue Questions::Error` bỏ sót lỗi mới thêm, mà chỗ đó thường là đường lỗi
# hiếm gặp trên production. Trước 2026-09-03 Api::V1::BaseController và Questions::Refiller
# đều phải liệt kê từng class vì các namespace chưa có base.
RSpec.describe "Cây exception của app/services" do
  BASES = {
    "Gemini" => Gemini::Error,
    "Questions" => Questions::Error,
    "GameSessions" => GameSessions::Error,
    "Scoring" => Scoring::Error
  }.freeze

  # Eager load để mọi lỗi đều đã được định nghĩa: ở test Zeitwerk load lười, không có bước
  # này thì descendants trả về danh sách rỗng và spec xanh giả.
  before(:all) { Rails.application.eager_load! }

  BASES.each do |namespace, base|
    it "#{namespace}::Error kế thừa StandardError" do
      expect(base.superclass).to eq(StandardError)
    end
  end

  it "mọi lỗi trong app/services kế thừa base error của namespace mình" do
    orphans = ObjectSpace.each_object(Class).select do |klass|
      next false unless klass < StandardError
      next false unless klass.name.to_s.start_with?(*BASES.keys.map { |ns| "#{ns}::" })

      base = BASES.fetch(klass.name.split("::").first)
      klass != base && !(klass < base)
    end

    expect(orphans).to be_empty,
                       "kế thừa thẳng StandardError thay vì base của namespace: " \
                       "#{orphans.map(&:name).sort.join(', ')}"
  end

  it "lỗi 'không đủ đề' quy về một class để chỗ rescue chỉ cần biết một cái" do
    expect(Questions::Drawer::NotEnoughQuestions).to be < Questions::NoQuestionsAvailable
    expect(Questions::NoQuestionsAvailable).to be < Questions::Error
  end
end
