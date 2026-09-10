# 共生之缚 —— 全量测试
# 数据管道 + server pytest + Godot headless 冒烟
param(
    [string]$GodotExe = "D:\Applications\Godot\Godot_v4.5.1-stable_win64.exe"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $Root "server\.venv\Scripts\python.exe"
if (-not (Test-Path $Python)) { $Python = "python" }

Write-Host "==> 数据管道"
Push-Location $Root
& $Python tools\build_game_data.py
& $Python tools\db_export.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Python -m pytest tools\tests -q
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Pop-Location

Write-Host "==> server pytest"
& $Python -m pytest (Join-Path $Root "server") -q
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "==> Godot headless 冒烟"
if (Test-Path $GodotExe) {
    & $GodotExe --headless --path (Join-Path $Root "client") --quit-after 30
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $GodotExe --headless --path (Join-Path $Root "client") --script res://tests/smoke_test.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Warning "未找到 Godot，跳过客户端冒烟（$GodotExe）"
}

Write-Host "==> 全部通过"
