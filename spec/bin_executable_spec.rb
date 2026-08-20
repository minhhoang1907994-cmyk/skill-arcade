require "rails_helper"

# Guard cho một lớp lỗi đã làm fail GitHub Actions thật (2026-08-20), gặp liên tiếp hai lần.
#
# Repo được tạo trên Windows, và `Dockerfile` chuẩn hoá lại ba thứ lúc build image:
#
#   RUN chmod +x bin/* && \
#       sed -i "s/<CR>$//g" bin/* && \
#       sed -i 's/ruby\.exe$/ruby/' bin/*
#
# Nghĩa là production LUÔN xanh, còn mọi đường không đi qua Docker — GitHub Actions, chạy tay
# trên máy Linux — đều vỡ. Đã vỡ thật, bóc từng lớp một:
#
#   1. mode `100644` (thiếu bit thực thi) → `bin/rubocop: Permission denied`, **exit 126**
#   2. sửa mode xong thì lộ tiếp shebang `#!/usr/bin/env ruby.exe` → Linux không có `ruby.exe`
#      → `env: 'ruby.exe': No such file or directory`, **exit 127**
#   3. lớp thứ ba chưa nổ nhưng có thật: `core.autocrlf=true` trên máy dev, nên nếu CRLF lọt
#      vào blob thì shebang mang ký tự CR và Linux lại đi tìm interpreter không tồn tại.
#      `.gitattributes` chốt `bin/* text eol=lf` để chặn
#
# Spec này kiểm cả ba để lần sau không phải bóc lại từng lớp.
RSpec.describe "bin/ phải chạy được trên Linux" do
  # Mode đọc từ git index, KHÔNG dùng `File.executable?`: filesystem Windows không mang bit +x
  # nên hàm đó trả kết quả vô nghĩa. Thứ đi vào runner là mode trong git.
  let(:git_modes) do
    `git ls-files -s bin/`.lines.filter_map do |line|
      mode = line.split(" ", 2).first
      path = line.split("\t", 2).last.to_s.strip
      [ path, mode ] if path.present?
    end.to_h
  end

  # Nội dung cũng đọc từ git index, không phải working tree: với `core.autocrlf=true` thì
  # working tree trên Windows là CRLF trong khi blob đi vào runner vẫn là LF — kiểm working
  # tree sẽ báo đỏ oan. Đây là kiểm đúng thứ runner nhận.
  let(:indexed) do
    git_modes.keys.to_h { |path| [ path, `git show :#{path}` ] }
  end

  it "có file để kiểm — rỗng thì git không chạy được và spec này vô nghĩa" do
    expect(git_modes).not_to be_empty
    expect(indexed.values).to all(be_present)
  end

  it "mọi script executable, không thì runner dừng với exit 126" do
    not_executable = git_modes.reject { |_path, mode| mode == "100755" }.keys

    expect(not_executable).to be_empty,
      "thiếu bit thực thi: #{not_executable.join(', ')}\n" \
      "sửa: git update-index --chmod=+x #{not_executable.join(' ')}"
  end

  it "không có shebang ruby.exe, không thì runner dừng với exit 127" do
    windows_shebang = indexed.select { |_path, body| body.lines.first.to_s.include?("ruby.exe") }

    expect(windows_shebang.keys).to be_empty,
      "shebang Windows: #{windows_shebang.keys.join(', ')}\n" \
      "sửa: đổi shebang thành /usr/bin/env ruby (bỏ hậu tố .exe)"
  end

  it "blob không có CRLF, không thì shebang mang ký tự CR và runner cũng dừng" do
    crlf = indexed.select { |_path, body| body.include?("\r\n") }

    expect(crlf.keys).to be_empty,
      "có CRLF trong git: #{crlf.keys.join(', ')}\n" \
      "sửa: kiểm .gitattributes có dòng `bin/* text eol=lf`, rồi git add --renormalize bin/"
  end
end
