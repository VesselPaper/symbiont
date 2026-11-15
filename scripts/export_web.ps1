# 导出游戏 Web 版到 client/build/web
#
# 前置：Godot 编辑器里装好与引擎同版本的导出模板（编辑器 → 管理导出模板）。
# 模板不在仓库里，也不该在：它是几百 MB 的二进制产物，按引擎版本装一次即可。
#
# 用法： scripts/export_web.ps1
#        scripts/export_web.ps1 -GodotExe <别的路径>

param(
    [string]$GodotExe = 'D:\Applications\Development\Tools\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe'
)

$Root = Split-Path -Parent $PSScriptRoot
$ClientDir = Join-Path $Root 'client'
$OutDir = Join-Path $ClientDir 'build\web'
$PresetFile = Join-Path $ClientDir 'export_presets.cfg'

if (-not (Test-Path $GodotExe)) { throw "未找到 Godot：$GodotExe" }
if (-not (Test-Path $PresetFile)) { throw "缺少导出预设：$PresetFile" }

# 模板目录：Godot 4 把模板放在 AppData\Roaming\Godot\export_templates\<版本>\
$version = (& $GodotExe --headless --version 2>$null | Select-Object -First 1)
if (-not $version) { throw '读不到 Godot 版本' }
$version = ($version -replace '^.*v', '').Trim()
$templateDir = Join-Path $env:APPDATA "Godot\export_templates\$version"

if (-not (Test-Path $templateDir) -or -not (Get-ChildItem $templateDir -Filter 'web*' -ErrorAction SilentlyContinue)) {
    Write-Host "缺少 Web 导出模板：$templateDir" -ForegroundColor Red
    Write-Host ''
    Write-Host '处理办法：'
    Write-Host '  1. 打开 Godot 编辑器 → 编辑器 → 管理导出模板 → 下载并安装（选与引擎相同的版本）'
    Write-Host '  2. 或者手动把 export_templates.tpz 解压到上面的目录'
    Write-Host ''
    Write-Host '装好之后重跑本脚本即可，不需要改代码。'
    exit 2
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Push-Location $ClientDir
try {
    & $GodotExe --headless --path $ClientDir --export-release 'Web' (Join-Path $OutDir 'index.html')
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($code -ne 0) { throw "导出失败（退出码 $code）" }

# 导出成功至少要有 index.html 与 pck；wasm 与 pck 的名字随版本变，所以按后缀查
$required = @('index.html')
$optional = @('*.wasm', '*.pck', '*.js')
$missing = @()
foreach ($pat in $required) {
    if (-not (Get-ChildItem $OutDir -Filter $pat -ErrorAction SilentlyContinue)) { $missing += $pat }
}
$found = @()
foreach ($pat in $optional) {
    $found += (Get-ChildItem $OutDir -Filter $pat -ErrorAction SilentlyContinue).Name
}

if ($missing.Count -gt 0) { throw "导出产物不完整，缺少：$($missing -join ', ')" }

Get-ChildItem $OutDir | Select-Object Name, Length | Format-Table -AutoSize
Write-Host "导出完成：$OutDir"
Write-Host '下一步：docker compose -f deploy/docker-compose.yml up -d，浏览器打开 https://localhost'
