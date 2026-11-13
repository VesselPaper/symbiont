# 共生之缚 —— 全量测试
# 数据管道 + server pytest + Godot headless 全量回归
param(
    [string]$GodotExe = "D:\Applications\Godot\Godot_v4.7.2-stable_win64_console.exe"
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

Write-Host "==> Godot headless 回归"
if (Test-Path $GodotExe) {
    & $GodotExe --headless --path (Join-Path $Root "client") --quit-after 30
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $fail = 0
    $failed = @()
    Get-ChildItem (Join-Path $Root "client\tests\*_test.gd") | Sort-Object Name | ForEach-Object {
        $name = $_.Name
        Write-Host ("  -- " + $name)
        # Godot 有几张测试会往 stderr 打无害告警（ObjectDB 泄漏、释放后的实例之类）。
        # 脚本开头是 $ErrorActionPreference = "Stop"，原生 stderr 会被当成终止错误，
        # 一张测试的告警就把整轮打断，日志停在一半还看不到是谁——这里只认退出码。
        $ErrorActionPreference = "Continue"
        & $GodotExe --headless --path (Join-Path $Root "client") --script ("res://tests/" + $name)
        $code = $LASTEXITCODE
        $ErrorActionPreference = "Stop"
        if ($code -ne 0) {
            $fail++
            $failed += $name
        }
    }
    if ($fail -ne 0) {
        Write-Host ("==> 失败 " + $fail + " 张：" + ($failed -join "、"))
        exit 1
    }
} else {
    Write-Warning "未找到 Godot，跳过客户端回归（$GodotExe）"
}

Write-Host "==> 全部通过"
