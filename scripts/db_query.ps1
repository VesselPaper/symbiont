# 在容器里的 MySQL 上跑一条 SQL，结果按行输出
#
# 为什么不直接拼 shell 命令：SQL 里有单引号和双引号，经 PowerShell → sh -c 两层转义
# 必然出错（已经踩过两次）。这里把 SQL 写进临时文件、docker cp 进容器、再用 mysql 读，
# 全程不经过字符串拼接。
#
# 用法： scripts/db_query.ps1 -Sql "select count(*) from events"
#        $n = & scripts/db_query.ps1 -Sql "select 1"     # 结果可以被赋值

param(
    [Parameter(Mandatory = $true)][string]$Sql
)

$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root 'deploy\.env'
$compose = 'deploy/docker-compose.yml'

if (-not (Test-Path $EnvFile)) { throw '缺少 deploy/.env' }

$envMap = @{}
foreach ($line in Get-Content $EnvFile -Encoding utf8) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $envMap[$Matches[1]] = $Matches[2] }
}
$db = if ($envMap['MYSQL_DATABASE']) { $envMap['MYSQL_DATABASE'] } else { 'symbiont' }

$tmp = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($tmp, $Sql + "`n", (New-Object System.Text.UTF8Encoding($false)))
    docker cp $tmp 'symbiont-mysql-1:/tmp/q.sql' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'docker cp 失败' }

    Push-Location $Root
    docker compose -f $compose exec -T -e "MYSQL_PWD=$($envMap['MYSQL_ROOT_PASSWORD'])" mysql `
        sh -c "mysql -uroot -N -B --default-character-set=utf8mb4 $db < /tmp/q.sql"
    $code = $LASTEXITCODE
    Pop-Location

    docker compose -f $compose exec -T mysql rm -f /tmp/q.sql | Out-Null
    exit $code
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
