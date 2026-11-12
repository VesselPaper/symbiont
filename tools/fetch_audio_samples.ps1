# 拉取音频素材的原始文件（录音库）。
#
# 为什么单独一个脚本：素材有 10MB 量级，不能塞进仓库；但来源和许可必须可追溯，
# 所以清单放在 tools/audio_sources.json，这个脚本只负责按清单下载到 tools/audio_samples/。
#
# 用法：
#   pwsh -File tools/fetch_audio_samples.ps1          # 缺什么补什么
#   pwsh -File tools/fetch_audio_samples.ps1 -Force   # 全部重下

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot 'audio_sources.json'
$outDir = Join-Path $root 'tools/audio_samples'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ok = 0
$skip = 0
$failed = @()

foreach ($src in $manifest.sources) {
    $ext = [System.IO.Path]::GetExtension($src.url)
    $dest = Join-Path $outDir ($src.key + $ext)
    if ((Test-Path $dest) -and -not $Force) {
        $skip++
        continue
    }
    try {
        Invoke-WebRequest -Uri $src.url -OutFile $dest -TimeoutSec 120 -UseBasicParsing
        $kb = [math]::Round((Get-Item $dest).Length / 1KB)
        Write-Host ("  ok   {0,-18} {1,5} KB" -f $src.key, $kb)
        $ok++
    }
    catch {
        Write-Host ("  FAIL {0,-18} {1}" -f $src.key, $_.Exception.Message)
        $failed += $src.key
    }
}

Write-Host ""
Write-Host ("下载完成：新增 {0} 个，已存在 {1} 个，失败 {2} 个" -f $ok, $skip, $failed.Count)
if ($failed.Count -gt 0) {
    Write-Host ("失败清单：" + ($failed -join ', '))
    exit 1
}

Write-Host ""
Write-Host "来源与许可："
foreach ($name in $manifest.attribution.PSObject.Properties.Name) {
    Write-Host ("  [{0}] {1}" -f $name, $manifest.attribution.$name)
}
