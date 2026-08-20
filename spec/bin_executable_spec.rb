require "rails_helper"

# Guard cho một lỗi đã làm fail GitHub Actions thật (2026-08-20).
#
# Repo được tạo trên Windows nên mọi file trong `bin/` vào git với mode `100644` — KHÔNG có
# bit thực thi. Trên Linux, `bin/rails questions:refill` khi đó dừng với **exit code 126**
# ("command found but not executable"), không phải lỗi Rails nào.
#
# Vì sao đường Docker không lộ ra: `Dockerfile` có `RUN chmod +x bin/*`, nên image production
# tự sửa mode lúc build. Chỉ runner của GitHub Actions — chạy thẳng từ checkout — mới gặp.
#
# Vì sao CI cũng không bắt được: `ci.yml` gọi `bin/brakeman`, `bin/rubocop`, `bin/rails` nên
# lẽ ra fail y hệt, nhưng nó trigger `push: branches: [master]` trong khi default branch là
# `main`, nên CI chưa từng chạy lần nào.
#
# Kiểm bằng git index chứ không bằng `File.executable?`: trên Windows, filesystem không mang
# bit +x nên `File.executable?` trả kết quả vô nghĩa. Cái đi vào runner là mode trong git.
#
# Sửa khi spec này đỏ:
#   git update-index --chmod=+x bin/<file>
RSpec.describe "bin/ trong git index" do
  # mode 100755 = có bit thực thi, 100644 = không.
  let(:modes) do
    `git ls-files -s bin/`.lines.filter_map do |line|
      mode, _hash, _stage_and_path = line.split(" ", 3)
      path = line.split("\t", 2).last.to_s.strip
      [ path, mode ] if path.present?
    end.to_h
  end

  it "có file để kiểm — nếu rỗng thì git không chạy được và spec này vô nghĩa" do
    expect(modes).not_to be_empty
  end

  it "mọi script trong bin/ đều executable, không thì Actions dừng với exit code 126" do
    not_executable = modes.reject { |_path, mode| mode == "100755" }.keys

    expect(not_executable).to be_empty,
      "thiếu bit thực thi: #{not_executable.join(', ')}\n" \
      "sửa bằng: git update-index --chmod=+x #{not_executable.join(' ')}"
  end
end
