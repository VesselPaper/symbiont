# 共生之缚 —— 环境初始化脚本（Windows）
# 1) 安装/定位 Godot 4.5.1（仓库外目录，全组统一版本）
# 2) 创建 server/.venv 并安装依赖
# 3) 构建游戏内容库并导出 JSON（验证数据管道）
param(
    [string]$GodotVersion = "4.5.1-stable",
    [string]$InstallDir   = "D:\Applications\Godot"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "==> [1/4] Godot $GodotVersion"
$godotExe = Join-Path $InstallDir "Godot_v${GodotVersion}_win64.exe"
if (-not (Test-Path $godotExe)) {
    Write-Host "    未找到，正在下载（约 163MB）..."
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $zip = Join-Path $InstallDir "godot.zip"
    Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/$GodotVersion/Godot_v${GodotVersion}_win64.exe.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    Remove-Item $zip
}
Write-Host "    OK -> $godotExe"

Write-Host "==> [2/4] server 虚拟环境"
$venv = Join-Path $Root "server\.venv"
if (-not (Test-Path (Join-Path $venv "Scripts\python.exe"))) {
    python -m venv $venv
}
& (Join-Path $venv "Scripts\python.exe") -m pip install --upgrade pip --quiet
& (Join-Path $venv "Scripts\python.exe") -m pip install -r (Join-Path $Root "server\requirements.txt")

Write-Host "==> [3/4] 构建游戏内容库 + 导出 JSON"
Push-Location $Root
& (Join-Path $venv "Scripts\python.exe") tools\build_game_data.py
& (Join-Path $venv "Scripts\python.exe") tools\db_export.py
Pop-Location

Write-Host "==> [4/4] 完成"
Write-Host "    打开游戏: Godot 编辑器打开 client/project.godot，按 F5"
Write-Host "    跑测试:    scripts\test_all.ps1"
