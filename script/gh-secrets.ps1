# Đẩy 7 secret cần cho .github/workflows/questions-refill.yml lên GitHub Actions.
#
# Đọc giá trị từ chính các file đang dùng trên máy này, KHÔNG in giá trị ra màn hình và
# KHÔNG gõ giá trị vào dòng lệnh tương tác (nên không vào PSReadLine history):
#   config/master.key  -> RAILS_MASTER_KEY
#   .env.aiven         -> DB_HOST, DB_PORT, DB_USERNAME, DB_PASSWORD, DB_NAME
#   .env               -> GEMINI_API_KEY
#
# Chạy từ gốc repo:
#   powershell -File <đường dẫn file này>
#
# Kiểm lại sau khi chạy:
#   gh secret list

$ErrorActionPreference = "Stop"

function Read-EnvFile([string]$path) {
  $map = @{}
  if (-not (Test-Path $path)) { return $map }
  $first = $true
  foreach ($line in Get-Content $path) {
    # .env.aiven có BOM UTF-8. Get-Content thường tự bỏ, nhưng nếu lọt thì key đầu tiên
    # thành "﻿DB_HOST" và tra cứu trượt — bỏ tường minh cho chắc.
    if ($first) { $line = $line -replace "^﻿", ""; $first = $false }
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $i = $t.IndexOf("=")
    if ($i -lt 1) { continue }
    $map[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
  }
  return $map
}

# gh phải đã đăng nhập và có scope "workflow".
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "gh chưa đăng nhập. Chạy: gh auth login" }

$repoRoot = (Get-Location).Path
$aiven = Read-EnvFile (Join-Path $repoRoot ".env.aiven")
$dotenv = Read-EnvFile (Join-Path $repoRoot ".env")

$masterKeyPath = Join-Path $repoRoot "config/master.key"
if (-not (Test-Path $masterKeyPath)) { throw "Không thấy config/master.key" }
# Trim bắt buộc: master.key kèm newline sẽ làm Rails không giải mã được credentials.
$masterKey = (Get-Content $masterKeyPath -Raw).Trim()

$secrets = [ordered]@{
  RAILS_MASTER_KEY = $masterKey
  DB_HOST          = $aiven["DB_HOST"]
  DB_PORT          = $aiven["DB_PORT"]
  DB_USERNAME      = $aiven["DB_USERNAME"]
  DB_PASSWORD      = $aiven["DB_PASSWORD"]
  DB_NAME          = $aiven["DB_NAME"]
  GEMINI_API_KEY   = $dotenv["GEMINI_API_KEY"]
}

# Kiểm đủ giá trị TRƯỚC khi set cái nào, để không set nửa vời.
$missing = @()
foreach ($k in $secrets.Keys) {
  if ([string]::IsNullOrWhiteSpace($secrets[$k])) { $missing += $k }
}
if ($missing.Count -gt 0) {
  throw "Thiếu giá trị cho: $($missing -join ', '). Kiểm .env.aiven / .env / config/master.key"
}

Write-Host "Sẽ set $($secrets.Count) secret cho repo $(gh repo view --json nameWithOwner -q .nameWithOwner)" -ForegroundColor Cyan
foreach ($k in $secrets.Keys) {
  # --body thay vì stdin: PowerShell thêm newline vào pipeline, mà RAILS_MASTER_KEY thì
  # newline làm Rails không giải mã được credentials.
  gh secret set $k --body $secrets[$k]
  if ($LASTEXITCODE -ne 0) { throw "Set $k thất bại" }
  # In TÊN, không in giá trị. Chỉ in độ dài để đối chiếu nhanh nếu nghi sai giá trị.
  Write-Host ("  OK {0,-18} ({1} ký tự)" -f $k, $secrets[$k].Length) -ForegroundColor Green
}

Write-Host ""
Write-Host "Xong. Kiểm lại:" -ForegroundColor Cyan
gh secret list
