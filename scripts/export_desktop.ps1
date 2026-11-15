# 导出 Windows 桌面版到 client/export/
#
# 前置：装好与引擎同版本的导出模板。与 Web 不同的是，桌面模板体积更大，
# 同样不在仓库里。
#
# 用法： scripts/export_desktop.ps1

param(
    [string]$GodotExe = 'D:\Applications\Development\Tools\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe'
)

$Root = Split-Path -Parent $PSScriptRoot
$ClientDir = Join-Path $Root 'client'
$OutDir = Join-Path $ClientDir 'export'
$PresetFile = Join-Path $ClientDir 'export_presets.cfg'

if (-not (Test-Path $GodotExe)) { throw "未找到 Godot：$GodotExe" }
if (-not (Test-Path $PresetFile)) { throw "缺少导出预设：$PresetFile" }

$version = (& $GodotExe --headless --version 2>$null | Select-Object -First 1)
if (-not $version) { throw '读不到 Godot 版本' }
# --version 输出形如 4.7.2.stable.official.ed1daf0bf，而模板目录只用到 4.7.2.stable 这一段
# （Godot 自己也是按这个短版本号找模板的，带 .official.<hash> 反而找不到）
if ($version -match '(\d+\.\d+\.\d+\.\w+)') { $version = $Matches[1] } else { throw "无法从版本串解析目录名：$version" }
$templateDir = Join-Path $env:APPDATA "Godot\export_templates\$version"

if (-not (Test-Path $templateDir)) {
    Write-Host "缺少导出模板：$templateDir" -ForegroundColor Red
    Write-Host '装模板的办法见 scripts/export_web.ps1 的同名提示。'
    exit 2
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Push-Location $ClientDir
try {
    & $GodotExe --headless --path $ClientDir --export-release 'Windows' (Join-Path $OutDir 'symbiont.exe')
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($code -ne 0) { throw "导出失败（退出码 $code）" }

Get-ChildItem $OutDir | Select-Object Name, Length | Format-Table -AutoSize
Write-Host "导出完成：$OutDir"