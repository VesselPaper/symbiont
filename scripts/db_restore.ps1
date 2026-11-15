# 从备份恢复到 MySQL
#
# 会把现有库整个覆盖掉，所以先停下来确认。
#
# 用法： scripts/db_restore.ps1 -File backups\symbiont-20261115-183000.sql.gz
#        scripts/db_restore.ps1 -File ... -Force     # 不确认，直接恢复

param(
    [Parameter(Mandatory = $true)][string]$File,
    [switch]$Force
)

$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root 'deploy\.env'
$BackupFile = if (Test-Path $File) { Get-Item $File } else { Get-Item (Join-Path $Root $File) }

if (-not (Test-Path $EnvFile)) { throw '缺少 deploy/.env' }

$env = @{}
foreach ($line in Get-Content $EnvFile -Encoding utf8) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $env[$Matches[1]] = $Matches[2] }
}
$db = if ($env['MYSQL_DATABASE']) { $env['MYSQL_DATABASE'] } else { 'symbiont' }
$rootPwd = $env['MYSQL_ROOT_PASSWORD']

Write-Host "将用 $($BackupFile.Name) 覆盖数据库 ${db}。现有数据会全部丢失。"
if (-not $Force) {
    $answer = Read-Host '确认请输入 yes'
    if ($answer -ne 'yes') { Write-Host '已取消。'; exit 1 }
}

$tmpInContainer = "/tmp/restore-$($BackupFile.Name)"

Push-Location $Root
try {
    docker cp $BackupFile.FullName "symbiont-mysql-1:$tmpInContainer"
    if ($LASTEXITCODE -ne 0) { throw 'docker cp 失败' }

    docker compose -f deploy/docker-compose.yml exec -T -e "MYSQL_PWD=$rootPwd" mysql `
        sh -c "gunzip -c $tmpInContainer | mysql -uroot --default-character-set=utf8mb4 $db"
    if ($LASTEXITCODE -ne 0) { throw '恢复写入失败' }

    docker compose -f deploy/docker-compose.yml exec -T mysql rm -f $tmpInContainer
}
finally {
    Pop-Location
}

Write-Host '恢复完成。用 scripts/smoke_test.ps1 校验服务是否正常。'
