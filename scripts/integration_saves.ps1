# 端到端联调：远程存档往返
#
# 本地存档 → 推云端 → 删掉本地（模拟换机器）→ 从云端拉回 → 比对内容。
#
# 用法： scripts/integration_saves.ps1
#        scripts/integration_saves.ps1 -SkipBuild

param(
    [switch]$SkipBuild,
    [string]$GodotExe = 'D:\Applications\Development\Tools\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe'
)

$Root = Split-Path -Parent $PSScriptRoot
$CaFile = Join-Path $Root 'deploy\certs\ca.crt'
$compose = 'deploy/docker-compose.yml'

if (-not (Test-Path $GodotExe)) { throw "找不到 Godot：$GodotExe" }
if (-not (Test-Path $CaFile)) { throw '缺少 deploy/certs/ca.crt，先运行 scripts/make_ca.ps1' }

Push-Location $Root
try {
    if (-not $SkipBuild) {
        Write-Host '== 重建镜像'
        & "$PSScriptRoot\build_images.ps1"
        if ($LASTEXITCODE -ne 0) { throw '镜像构建失败' }
    }

    Write-Host '== 起栈'
    docker compose -f $compose up -d | Out-Null
    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
        $bad = @(docker compose -f $compose ps --format '{{.Name}}|{{.Status}}' | Where-Object { $_ -notmatch 'healthy|Up' })
    } while ($bad.Count -gt 0 -and (Get-Date) -lt $deadline)
    if ($bad.Count -gt 0) { throw "容器没有全部就绪：$($bad -join '; ')" }

    Write-Host '== 跑客户端往返'
    $env:SYMBIONT_API_BASE = 'https://localhost/api/v1'
    $env:SYMBIONT_CA_FILE = $CaFile
    & $GodotExe --headless --path (Join-Path $Root 'client') --script 'res://tests/integration_saves.gd'
    $godotExit = $LASTEXITCODE
    Remove-Item Env:\SYMBIONT_API_BASE -ErrorAction SilentlyContinue
    Remove-Item Env:\SYMBIONT_CA_FILE -ErrorAction SilentlyContinue
    if ($godotExit -ne 0) { throw "存档往返失败（退出码 $godotExit）" }

    Write-Host '== 库里核对'
    $rows = & "$PSScriptRoot\db_query.ps1" -Sql "select slot, length(save_data) from saves where slot = 2"
    Write-Host "saves 表 slot=2 的记录：$rows"
    if (-not $rows) { throw '库里没有 slot 2 的存档' }

    Write-Host ''
    Write-Host '联调通过：存档推上去、删本地、再从云端拉回来，内容一致。' -ForegroundColor Green
}
finally {
    Pop-Location
}
