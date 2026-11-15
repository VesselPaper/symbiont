# 生成自签证书，给 deploy/nginx.conf 的 HTTPS 入口用。
#
# 只用于本机演示和课程验收：浏览器会提示"连接不安全"，点"继续访问"即可。
# 正式上线要换成 CA 签发的证书，把 deploy/certs 里的两个文件换掉就行。
#
# 用法： scripts/gen_cert.ps1

param(
    [string]$CertDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'deploy\certs')
)

$openssl = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $openssl) { throw '未找到 openssl。装了 Git for Windows 的话它自带，检查 PATH。' }

New-Item -ItemType Directory -Force -Path $CertDir | Out-Null

$keyPath = Join-Path $CertDir 'server.key'
$crtPath = Join-Path $CertDir 'server.crt'

# CN 与 SAN 都写 localhost：浏览器按 SAN 校验，只写 CN 会额外报一个名字不匹配
$opensslArgs = @(
    'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-days', '365'
    '-keyout', $keyPath
    '-out', $crtPath
    '-subj', '/CN=localhost'
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'
)

& $openssl @opensslArgs 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'openssl 生成证书失败' }

Get-ChildItem $CertDir | Select-Object Name, Length | Format-Table -AutoSize
Write-Host "证书已生成：$CertDir"
Write-Host '自签证书，浏览器首次访问会提示不安全，点"继续访问"即可。'
