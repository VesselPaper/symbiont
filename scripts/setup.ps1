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

# 找一个可用的 Python 3（优先 py 启动器，其次 python / python3）
function Resolve-Python {
    foreach ($cand in @("py", "python", "python3")) {
        if (-not (Get-Command $cand -ErrorAction SilentlyContinue)) { continue }
        try { $ver = & $cand --version 2>&1 } catch { continue }
        if ("$ver" -match "Python 3") {
            if ($cand -eq "py") { return @("py", "-3") }
            return @($cand)
        }
    }
    throw "未找到可用的 Python 3。请先安装 Python 3.12（https://www.python.org/downloads/），安装时勾选 'Add python.exe to PATH'，然后重开一个 PowerShell 再运行本脚本。"
}

Write-Host "==> [1/4] Godot $GodotVersion"
$godotExe = Join-Path $InstallDir "Godot_v${GodotVersion}_win64.exe"
if (-not (Test-Path $godotExe)) {
    Write-Host "    未找到，正在下载（约 163MB）..."
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $zip = Join-Path $InstallDir "godot.zip"
    $url = "https://github.com/godotengine/godot/releases/download/$GodotVersion/Godot_v${GodotVersion}_win64.exe.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip
    } catch {
        Write-Host "    Invoke-WebRequest 失败，改用 curl 重试..."
        & curl.exe -L --retry 5 --retry-delay 3 -o $zip $url
    }
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    Remove-Item $zip
}
Write-Host "    OK -> $godotExe"

Write-Host "==> [2/4] server 虚拟环境"
$python = Resolve-Python
$venv = Join-Path $Root "server\.venv"
if (-not (Test-Path (Join-Path $venv "Scripts\python.exe"))) {
    $pyExe = $python[0]
    $pyArgs = @()
    if ($python.Count -gt 1) { $pyArgs = $python[1..($python.Count - 1)] }
    & $pyExe @pyArgs -m venv $venv
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
