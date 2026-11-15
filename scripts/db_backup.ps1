# 备份 MySQL 到 backups/
#
# 在容器里导出、再 docker cp 出来：不经过 PowerShell 管道，避免二进制被重新编码。
# 保留最近 7 份，旧的自动删。
#
# 用法： scripts/db_backup.ps1
#        scripts/db_backup.ps1 -Keep 14

param(
    [int]$Keep = 7
)

$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root 'deploy\.env'
$BackupDir = Join-Path $Root 'backups'

if (-not (Test-Path $EnvFile)) { throw '缺少 deploy/.env，先运行 scripts/gen_env.ps1' }
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$env = @{}
foreach ($line in Get-Content $EnvFile -Encoding utf8) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $env[$Matches[1]] = $Matches[2] }
}
$db = if ($env['MYSQL_DATABASE']) { $env['MYSQL_DATABASE'] } else { 'symbiont' }
$rootPwd = $env['MYSQL_ROOT_PASSWORD']

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$name = "symbiont-$stamp.sql.gz"
$tmpInContainer = "/tmp/$name"

Push-Location $Root
try {
    # MYSQL_PWD 走环境变量，不出现在进程参数里
    docker compose -f deploy/docker-compose.yml exec -T -e "MYSQL_PWD=$rootPwd" mysql `
        sh -c "mysqldump -uroot --single-transaction --routines --triggers --default-character-set=utf8mb4 $db | gzip -9 > $tmpInContainer"
    if ($LASTEXITCODE -ne 0) { throw 'mysqldump 失败' }

    docker cp "symbiont-mysql-1:$tmpInContainer" (Join-Path $BackupDir $name)
    if ($LASTEXITCODE -ne 0) { throw 'docker cp 失败' }

    docker compose -f deploy/docker-compose.yml exec -T mysql rm -f $tmpInContainer
}
finally {
    Pop-Location
}

$file = Get-Item (Join-Path $BackupDir $name)
"已备份：{0}（{1:N1} KB）" -f $file.Name, ($file.Length / 1KB)

# 只留最近 N 份
$all = Get-ChildItem $BackupDir -Filter 'symbiont-*.sql.gz' | Sort-Object LastWriteTime -Descending
if ($all.Count -gt $Keep) {
    $all | Select-Object -Skip $Keep | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "已清理旧备份：$($_.Name)"
    }
}
Write-Host "当前保留 $([Math]::Min($all.Count, $Keep)) 份。"
