require "rails_helper"

RSpec.describe Gemini::CircuitBreaker do
  include ActiveSupport::Testing::TimeHelpers

  # Test env dùng :null_store nên phải cấp store thật, không thì breaker không giữ được
  # trạng thái và mọi assertion đều xanh giả.
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:breaker) { described_class.new(name: "gemini-test", cache: cache) }

  def fail_once
    breaker.run { raise Gemini::Client::RequestFailed, "boom" }
  rescue Gemini::Client::RequestFailed
    nil
  end

  it "trả về giá trị của block khi gọi thành công" do
    expect(breaker.run { :ok }).to eq(:ok)
    expect(breaker).not_to be_open
  end

  it "mở sau đúng 5 lần lỗi liên tiếp (spec §15)" do
    4.times { fail_once }
    expect(breaker).not_to be_open

    fail_once
    expect(breaker).to be_open
  end

  it "một lần thành công xoá bộ đếm lỗi" do
    4.times { fail_once }
    breaker.run { :ok }
    fail_once

    expect(breaker).not_to be_open
  end

  it "chặn lời gọi khi đang mở và không chạy block" do
    5.times { fail_once }
    called = false

    expect { breaker.run { called = true } }.to raise_error(described_class::OpenError)
    expect(called).to be false
  end

  it "lần gọi bị chặn không tính vào bộ đếm lỗi" do
    5.times { fail_once }

    3.times do
      breaker.run { :ok }
    rescue described_class::OpenError
      nil
    end

    # Bộ đếm đã được xoá lúc breaker mở và phải giữ nguyên rỗng — nếu lời gọi bị chặn
    # cũng bị tính là lỗi thì mỗi lần thử lại sẽ tự gia hạn trạng thái mở.
    expect(cache.read("gemini-test/circuit/failures")).to be_nil
  end

  it "chỉ tính lỗi Gemini, không tính lỗi lập trình" do
    5.times do
      breaker.run { raise ArgumentError, "lỗi code" }
    rescue ArgumentError
      nil
    end

    expect(breaker).not_to be_open
  end

  it "tự đóng lại sau 5 phút" do
    5.times { fail_once }
    expect(breaker).to be_open

    travel(described_class::OPEN_DURATION + 1.second) do
      expect(breaker).not_to be_open
    end
  end
end
