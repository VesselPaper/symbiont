# 生成本地 CA 与服务端证书
#
# 之前的做法是"一张自签证书"，浏览器和 Godot 客户端都不信任它，只能在命令行加 -k 绕过。
# 本地 CA 是内网环境的通行做法：根证书装一次，之后所有签出来的服务端证书都被信任，
# 换机器、换域名只要重新签一张，不用再动浏览器。
#
# 用法： scripts/make_ca.ps1
#        scripts/make_ca.ps1 -Force    # 重新生成（会作废已签发的服务端证书）

param(
    [switch]$Force,
    [string]$CommonName = 'localhost'
)

$Root = Split-Path -Parent $PSScriptRoot
$CertDir = Join-Path $Root 'deploy\certs'

$openssl = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $openssl) { throw '未找到 openssl。装了 Git for Windows 的话它自带，检查 PATH。' }

New-Item -ItemType Directory -Force -Path $CertDir | Out-Null

$caCrt = Join-Path $CertDir 'ca.crt'
if ((Test-Path $caCrt) -and -not $Force) {
    Write-Host "CA 已存在，保持不动：$caCrt"
    Write-Host '要重新生成请加 -Force（已安装的根证书会失效）。'
    exit 0
}

function Invoke-OpenSsl {
    param([string[]]$Arguments, [string]$Step)
    & $openssl @Arguments
    if ($LASTEXITCODE -ne 0) { throw "openssl 失败：$Step" }
}

$caKey = Join-Path $CertDir 'ca.key'
$serverKey = Join-Path $CertDir 'server.key'
$serverCsr = Join-Path $CertDir 'server.csr'
$serverCrt = Join-Path $CertDir 'server.crt'
$extFile = Join-Path $CertDir 'server.ext'

# ---- 根 CA（10 年）----
Invoke-OpenSsl -Step '生成 CA 私钥' -Arguments @('genrsa', '-out', $caKey, '4096')
Invoke-OpenSsl -Step '签发自签 CA 证书' -Arguments @(
    'req', '-x509', '-new', '-key', $caKey, '-sha256', '-days', '3650'
    '-subj', '/CN=Symbiont Local CA/O=Symbiont Dev'
    '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0'
    '-addext', 'keyUsage=critical,keyCertSign,cRLSign'
    '-out', $caCrt
)

# ---- 服务端证书（397 天，浏览器对公有 CA 的上限是 398 天，内网也照这个习惯）----
# SAN 必须写：浏览器按 SAN 校验，只写 CN 会额外报一个名字不匹配
$ext = @"
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$CommonName,DNS:localhost,IP:127.0.0.1
"@
[System.IO.File]::WriteAllText($extFile, $ext, (New-Object System.Text.UTF8Encoding($false)))

Invoke-OpenSsl -Step '生成服务端私钥' -Arguments @('genrsa', '-out', $serverKey, '2048')
Invoke-OpenSsl -Step '生成服务端 CSR' -Arguments @(
    'req', '-new', '-key', $serverKey, '-subj', "/CN=$CommonName", '-out', $serverCsr
)
Invoke-OpenSsl -Step '用 CA 签发服务端证书' -Arguments @(
    'x509', '-req', '-in', $serverCsr
    '-CA', $caCrt, '-CAkey', $caKey, '-CAcreateserial'
    '-days', '397', '-sha256', '-extfile', $extFile
    '-out', $serverCrt
)
Invoke-OpenSsl -Step '校验证书链' -Arguments @(
    'verify', '-CAfile', $caCrt, $serverCrt
)

Remove-Item $serverCsr -ErrorAction SilentlyContinue

Get-ChildItem $CertDir | Select-Object Name, Length | Format-Table -AutoSize
Write-Host ""
Write-Host "CA 证书：$caCrt"
Write-Host '下一步：scripts/trust_ca.ps1 把根证书装进当前用户，浏览器与客户端就不再报警。'
Write-Host '提示：ca.key 是签发凭据，不能外传；它和 server.key 都不进仓库（见 .gitignore）。'
