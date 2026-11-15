# 部署后冒烟：把"起来了"和"能用"分开检查
#
# 只检查"容器在跑"是不够的：TLS、转发、限流、数据库任何一环断了都算部署失败。
#
# 用法： scripts/smoke_test.ps1
#        scripts/smoke_test.ps1 -BaseUrl https://localhost

param(
    [string]$BaseUrl = 'https://localhost'
)

$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root 'deploy\.env'
$caFile = Join-Path $Root 'deploy\certs\ca.crt'
$compose = 'deploy/docker-compose.yml'

Push-Location $Root
$fail = 0

function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) {
        Write-Host ("  ok   " + $Name) -ForegroundColor Green
        if ($Detail) { Write-Host ("       " + $Detail) -ForegroundColor DarkGray }
    }
    else {
        Write-Host ("  FAIL " + $Name) -ForegroundColor Red
        if ($Detail) { Write-Host ("       " + $Detail) -ForegroundColor DarkGray }
        $script:fail++
    }
}

Write-Host '== 1 容器状态'
$ps = docker compose -f $compose ps --format '{{.Name}}|{{.Status}}'
foreach ($line in $ps) {
    $parts = $line -split '\|'
    Check "$($parts[0]) 在跑" ($parts[1] -match 'healthy|Up') $parts[1]
}

Write-Host '== 2 端口可见性（后端与数据库不该对外）'
$proxyPorts = docker port symbiont-proxy-1 2>$null
$serverPorts = docker port symbiont-server-1 2>$null
$mysqlPorts = docker port symbiont-mysql-1 2>$null
Check '网关映射了 80/443' (($proxyPorts -join ' ') -match '80' -and ($proxyPorts -join ' ') -match '443') ($proxyPorts -join ', ')
Check '后端没有对外端口' (-not $serverPorts) ($serverPorts -join ', ')
Check '数据库没有对外端口' (-not $mysqlPorts) ($mysqlPorts -join ', ')

Write-Host '== 3 明文入口只做跳转'
$code = (curl.exe -s -o NUL -w '%{http_code}' --max-time 5 "http://localhost/healthz")
Check 'http 返回 308' ($code -eq '308') "code=$code"

Write-Host '== 4 HTTPS 探针'
$curlTls = @('--ssl-no-revoke')
if (Test-Path $caFile) { $curlTls += @('--cacert', $caFile) }
$body = (curl.exe -s @curlTls --max-time 8 "$BaseUrl/api/v1/health")
Check 'HTTPS 200 且返回 ok' ($body -match '"status":"ok"') $body

Write-Host '== 5 安全响应头'
$headers = (curl.exe -s -D - -o NUL @curlTls --max-time 8 "$BaseUrl/api/v1/health") -join "`n"
Check '不报 nginx 版本' ($headers -match 'Server: nginx\r?\n') ''
Check '有 X-Upstream' ($headers -match 'X-Upstream:') ''
Check '有 nosniff' ($headers -match 'X-Content-Type-Options: nosniff') ''

Write-Host '== 6 限流生效'
# 必须并发：顺序发 40 个请求每个间隔几十毫秒，永远不会撞上限流
$urls = @(1..40 | ForEach-Object { "$BaseUrl/api/v1/health" })
$codes = & curl.exe --parallel --parallel-max 40 -s -o NUL -w '%{http_code}\n' @curlTls @urls
$tooMany = @($codes | Where-Object { $_ -eq '429' }).Count
Check '并发 40 次出现 429' ($tooMany -gt 0) "429 出现 $tooMany 次"

Write-Host '== 7 数据库可查'
$envMap = @{}
foreach ($line in Get-Content $EnvFile -Encoding utf8) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $envMap[$Matches[1]] = $Matches[2] }
}
$db = if ($envMap['MYSQL_DATABASE']) { $envMap['MYSQL_DATABASE'] } else { 'symbiont' }
$tables = docker compose -f $compose exec -T -e "MYSQL_PWD=$($envMap['MYSQL_ROOT_PASSWORD'])" mysql `
    sh -c "mysql -uroot -N -B -e 'show tables' $db" 2>$null
Check '数据库里有表' ([bool](@($tables) -match 'users')) (@($tables) -join ', ')

Pop-Location

Write-Host ''
if ($fail -eq 0) {
    Write-Host '冒烟通过：这一套现在是可以用的。' -ForegroundColor Green
    exit 0
}
Write-Host "冒烟失败：$fail 项。" -ForegroundColor Red
exit 1
