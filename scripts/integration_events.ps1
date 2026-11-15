# 端到端联调：游戏 → 网关 → 后端 → MySQL
#
# 不开玩笑的那种：跑的是 Godot 客户端进程，请求真的经过 nginx 的 TLS、限流与转发，
# 最后在库里查得到。回归测试跑在无头环境、不联网，这条链路只能这样验。
#
# 用法： scripts/integration_events.ps1
#        scripts/integration_events.ps1 -SkipBuild    # 后端代码没变时跳过重建

param(
    [switch]$SkipBuild,
    [string]$GodotExe = 'D:\Applications\Development\Tools\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe'
)

$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root 'deploy\.env'
$CaFile = Join-Path $Root 'deploy\certs\ca.crt'
$compose = 'deploy/docker-compose.yml'

if (-not (Test-Path $GodotExe)) { throw "找不到 Godot：$GodotExe" }
if (-not (Test-Path $EnvFile)) { throw '缺少 deploy/.env，先运行 scripts/gen_env.ps1' }

$envMap = @{}
foreach ($line in Get-Content $EnvFile -Encoding utf8) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $envMap[$Matches[1]] = $Matches[2] }
}

Push-Location $Root
try {
    if (-not $SkipBuild) {
        Write-Host '== 重建镜像（后端代码有改动）'
        & "$PSScriptRoot\build_images.ps1"
        if ($LASTEXITCODE -ne 0) { throw '镜像构建失败' }
    }

    Write-Host '== 起栈'
    docker compose -f $compose up -d | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'compose up 失败' }

    Write-Host '== 等后端健康'
    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
        $health = docker compose -f $compose ps --format '{{.Name}}|{{.Status}}'
        $bad = @($health | Where-Object { $_ -notmatch 'healthy|Up' })
    } while ($bad.Count -gt 0 -and (Get-Date) -lt $deadline)
    if ($bad.Count -gt 0) { throw "容器没有全部就绪：$($bad -join '; ')" }

    Write-Host '== 让游戏进程发事件（带 CA 证书，走 https://localhost）'
    $before = [int](& "$PSScriptRoot\db_query.ps1" -Sql "select count(*) from events where event = 'integration_probe'")

    $env:SYMBIONT_API_BASE = 'https://localhost/api/v1'
    $env:SYMBIONT_CA_FILE = $CaFile
    & $GodotExe --headless --path (Join-Path $Root 'client') --script 'res://tests/integration_events.gd'
    $godotExit = $LASTEXITCODE
    Remove-Item Env:\SYMBIONT_API_BASE -ErrorAction SilentlyContinue
    Remove-Item Env:\SYMBIONT_CA_FILE -ErrorAction SilentlyContinue

    if ($godotExit -ne 0) { throw "客户端上报失败（退出码 $godotExit）" }

    Start-Sleep -Seconds 1
    $after = [int](& "$PSScriptRoot\db_query.ps1" -Sql "select count(*) from events where event = 'integration_probe'")

    Write-Host "== 库里的 integration_probe：$before -> $after"
    if ($after - $before -lt 2) { throw '库里没看到新事件' }

    Write-Host ''
    Write-Host '联调通过：游戏进程 → HTTPS 网关 → 后端 → MySQL，整条链路是通的。' -ForegroundColor Green
}
finally {
    Pop-Location
}
