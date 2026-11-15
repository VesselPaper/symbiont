# 生成 deploy/.env：随机强密码 + 默认网关参数
#
# 用法： scripts/gen_env.ps1
#        scripts/gen_env.ps1 -Force    # 覆盖已有 .env（数据库密码会变，容器里的旧数据连不上）

param(
    [switch]$Force
)

$DeployDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'deploy'
$EnvFile = Join-Path $DeployDir '.env'
$Example = Join-Path $DeployDir '.env.example'

if ((Test-Path $EnvFile) -and -not $Force) {
    Write-Host ".env 已存在，保持不动：$EnvFile"
    Write-Host '要重新生成请加 -Force。'
    exit 0
}

if (-not (Test-Path $Example)) { throw "缺少 $Example" }

function New-Secret {
    param([int]$Length = 32)
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

$rootPwd = New-Secret
$appPwd = New-Secret

$lines = Get-Content -Path $Example -Encoding utf8
$result = foreach ($line in $lines) {
    if ($line -match '^MYSQL_ROOT_PASSWORD=') { "MYSQL_ROOT_PASSWORD=$rootPwd" }
    elseif ($line -match '^MYSQL_PASSWORD=') { "MYSQL_PASSWORD=$appPwd" }
    else { $line }
}

[System.IO.File]::WriteAllLines($EnvFile, $result, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "已生成：$EnvFile"
Write-Host '数据库密码已随机生成（32 字节十六进制），不在此打印。'
Write-Host '下一步：scripts/make_ca.ps1 生成证书，然后 scripts/build_images.ps1 构建镜像。'
