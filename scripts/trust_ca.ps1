# 把本地 CA 根证书装进"当前用户"的受信任根存储
#
# 装当前用户而不是本机，所以不需要管理员权限；卸载也简单。
# 装完之后浏览器访问 https://localhost 不再报不安全，Godot 的 HTTPRequest
# 也会按系统信任链校验通过。
#
# 用法： scripts/trust_ca.ps1
#        卸载： scripts/trust_ca.ps1 -Remove

param(
    [switch]$Remove
)

$Root = Split-Path -Parent $PSScriptRoot
$caCrt = Join-Path $Root 'deploy\certs\ca.crt'

if (-not (Test-Path $caCrt)) {
    throw "找不到 $caCrt，先运行 scripts/make_ca.ps1"
}

if ($Remove) {
    certutil -delstore -user Root 'Symbiont Local CA'
    Write-Host '已从当前用户的受信任根存储移除。'
    exit $LASTEXITCODE
}

certutil -addstore -user Root $caCrt
if ($LASTEXITCODE -ne 0) { throw '安装根证书失败' }

Write-Host ''
Write-Host '已装入当前用户受信任根存储。'
Write-Host '验证：'
Write-Host '  curl.exe https://localhost/api/v1/health     # 不加 -k 也应该通'
Write-Host '卸载：scripts/trust_ca.ps1 -Remove'
