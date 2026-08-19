require "rails_helper"

# Guard cho một lỗi đã làm fail deploy thật (2026-08-19).
#
# `Gemfile.lock` sinh trên máy Windows chỉ ghi PLATFORMS `x64-mingw-ucrt`. Dockerfile đặt
# `BUNDLE_DEPLOYMENT="1"` nên bundler ở chế độ frozen và KHÔNG được tự thêm platform, khiến
# `bundle install` trong image Linux fail với exit code 16 (`Bundler::ProductionError`).
#
# CI không bắt được: `ruby/setup-ruby` với `bundler-cache: true` không bật deployment mode nên nó
# lặng lẽ thêm platform vào lock của runner rồi chạy tiếp. Vì vậy phải kiểm bằng spec.
#
# Sửa khi spec này đỏ: `bundle lock --add-platform x86_64-linux`
RSpec.describe "Gemfile.lock" do
  let(:platforms) do
    File.read(Rails.root.join("Gemfile.lock"))[/^PLATFORMS\n(.*?)\n\n/m, 1].to_s.split("\n").map(&:strip)
  end

  it "khai platform Linux để build được Docker image" do
    expect(platforms).to include("x86_64-linux")
  end
end
