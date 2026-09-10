# 导出 Windows 桌面版到 client/export/
param(
    [string]$GodotExe = "D:\Applications\Godot\Godot_v4.5.1-stable_win64.exe"
)
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $GodotExe)) { throw "未找到 Godot: $GodotExe" }

Push-Location (Join-Path $Root "client")
# TODO(M2): 创建 export_presets.cfg（Windows 预设 "Windows"）后取消下行注释
# & $GodotExe --headless --path . --export-release "Windows" export/symbiont.exe
Pop-Location
Write-Host "M2 阶段启用。"
