# 启动后端（开发模式，热重载）
$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $Root "server\.venv\Scripts\python.exe"
if (-not (Test-Path $Python)) { $Python = "python" }
Push-Location (Join-Path $Root "server")
& $Python -m uvicorn app.main:app --reload --port 8000
Pop-Location
