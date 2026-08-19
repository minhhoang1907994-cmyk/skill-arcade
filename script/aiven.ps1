# LƯU Ý: file này PHẢI có BOM UTF-8. Windows PowerShell 5.1 đọc .ps1 theo ANSI nếu thiếu BOM,
# và tiếng Việt trong file sẽ bị mangle thành ký tự làm vỡ cú pháp string.
# Chạy db:preflight / db:prepare lên DB Aiven mà không phải gõ mật khẩu ra dòng lệnh.
#
# Cách dùng:
#   1. Copy .env.aiven.example thành .env.aiven, điền thông số lấy từ console Aiven.
#      File .env.aiven nằm trong .gitignore (/.env*) nên không bị commit.
#   2. Kiểm trước, KHÔNG ghi gì lên DB:
#        powershell -File script/aiven.ps1
#   3. Tạo schema + seed (GHI lên DB production), rồi tự kiểm lại:
#        powershell -File script/aiven.ps1 -Prepare
#
# Vì sao tách -Prepare thành cờ riêng: bước 2 gần như chỉ đọc, còn bước 3 ghi thật lên DB
# production. Không nên để một lệnh vô tình làm cả hai.

param(
  [switch]$Prepare,
  # Chạy một lệnh rails tuỳ ý lên DB Aiven, vd:
  #   powershell -File script/aiven.ps1 -Command "runner db/seeds/sample_questions.rb"
  #   powershell -File script/aiven.ps1 -Command "questions:import[db/question_banks/...]"
  # Dùng cái này thay vì tự export biến ở shell, để mật khẩu không vào history.
  [string]$Command
)

# Console mac dinh cua Windows khong phai UTF-8 nen thong bao tieng Viet se ra ky tu la.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env.aiven"

if (-not (Test-Path $envFile)) {
  Write-Host "Không thấy $envFile" -ForegroundColor Red
  Write-Host "Copy .env.aiven.example thành .env.aiven rồi điền thông số từ console Aiven."
  exit 1
}

# Nạp file: mỗi dòng KEY=VALUE, bỏ qua dòng trống và dòng comment.
$loaded = @()
foreach ($line in Get-Content $envFile) {
  $trimmed = $line.Trim()
  if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }

  $idx = $trimmed.IndexOf("=")
  if ($idx -lt 1) { continue }

  $key = $trimmed.Substring(0, $idx).Trim()
  $value = $trimmed.Substring($idx + 1).Trim().Trim('"')
  if ($value -eq "") { continue }

  Set-Item -Path "Env:$key" -Value $value
  $loaded += $key
}

$env:RAILS_ENV = "production"

$required = @("DB_HOST", "DB_PORT", "DB_USERNAME", "DB_PASSWORD", "DB_NAME")
$missing = $required | Where-Object { -not (Test-Path "Env:$_") }
if ($missing.Count -gt 0) {
  Write-Host "Thiếu biến trong .env.aiven: $($missing -join ', ')" -ForegroundColor Red
  exit 1
}

# In ra để đối chiếu — cố ý KHÔNG in DB_PASSWORD.
Write-Host "RAILS_ENV = production"
Write-Host "Đích       = $($env:DB_USERNAME)@$($env:DB_HOST):$($env:DB_PORT)/$($env:DB_NAME)"
if (Test-Path "Env:DB_SSL_CA") {
  if (Test-Path $env:DB_SSL_CA) {
    Write-Host "CA cert    = $($env:DB_SSL_CA) (có file → ssl_mode=verify_identity)"
  } else {
    Write-Host "CA cert    = $($env:DB_SSL_CA) KHÔNG TỒN TẠI — sẽ lỗi lúc kết nối" -ForegroundColor Red
    exit 1
  }
} else {
  Write-Host "CA cert    = chưa khai → ssl_mode=required (mã hoá nhưng KHÔNG xác thực server)" -ForegroundColor Yellow
}
Write-Host "Biến đã nạp: $($loaded -join ', ')"
Write-Host ""

if ($Prepare) {
  if (-not (Test-Path "Env:ADMIN_PASSWORD")) {
    Write-Host "ADMIN_PASSWORD chưa khai trong .env.aiven." -ForegroundColor Yellow
    Write-Host "db:prepare vẫn chạy nhưng sẽ BỎ QUA việc tạo admin, và db:prepare chỉ tự seed"
    Write-Host "ĐÚNG MỘT LẦN lúc DB vừa được tạo. Nên khai trước rồi chạy lại."
    exit 1
  }

  Write-Host "=== db:prepare (GHI lên DB production) ===" -ForegroundColor Cyan
  ruby bin/rails db:prepare
  if (-not $?) { exit 1 }
  Write-Host ""
}

if ($Command) {
  Write-Host "=== rails $Command ===" -ForegroundColor Cyan
  $args = $Command -split ' '
  & ruby bin/rails @args
  exit $LASTEXITCODE
}

Write-Host "=== db:preflight ===" -ForegroundColor Cyan
ruby bin/rails db:preflight
