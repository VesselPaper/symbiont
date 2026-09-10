# 导出游戏 Web 版（HTML5）到 client/build/web
# 前置: Godot 编辑器 → 项目 → 安装导出模板(4.5.1)；导出预设 export_presets.cfg（M2 创建）
param(
    [string]$GodotExe = "D:\Applications\Godot\Godot_v4.5.1-stable_win64.exe"
)
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $GodotExe)) { throw "未找到 Godot: $GodotExe" }

Push-Location (Join-Path $Root "client")
# TODO(M2): 创建 export_presets.cfg（Web 预设 "Web"）后取消下行注释
# & $GodotExe --headless --path . --export-release "Web" build/web/index.html
Pop-Location
Write-Host "M2 阶段启用。参见 deploy/README.md 与 docs/04-系统安装部署文档.md"
