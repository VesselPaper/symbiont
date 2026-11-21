# 靶场演示环境，一条命令起齐。
#
#   .\scripts\range_up.ps1        起网关栈、裸奔栈、靶场页面、修复前网关、靶站、演示服务
#   .\scripts\range_up.ps1 -Down  全停
#
# 起好之后打开 http://127.0.0.1:18080/attack/ ，页面上点按钮就能打，
# 不用再敲任何命令。

param([switch]$Down)

$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root

# 控制服务用哪个解释器：优先用打包的那个，它一定有；没有就退回 PATH 里的 python
$Py = "C:\Users\TIME\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
if (-not (Test-Path $Py)) { $Py = "python" }

function Stop-Control {
    $conn = Get-NetTCPConnection -LocalPort 18082 -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        Write-Host "演示服务已停"
    }
}

# docker compose 把进度写到 stderr，直接跑时 PowerShell 会把每一行当红色报错打出来。
# 这里收起来，只在真的失败时原样吐出去。
function Invoke-Compose {
    param([string[]]$ComposeArgs)
    $out = & docker compose @ComposeArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $out | Write-Host
        Write-Host ""
        Write-Host "上面这条没跑通：docker compose $($ComposeArgs -join ' ')"
        exit 1
    }
}

if ($Down) {
    Stop-Control
    Invoke-Compose @("--env-file", "deploy/.env", "-f", "deploy/docker-compose.yml", "-f", "deploy/docker-compose.scale.yml", "down")
    Invoke-Compose @("-f", "deploy/ops/docker-compose.before.yml", "down")
    Invoke-Compose @("-f", "deploy/ops/docker-compose.range.yml", "down")
    Invoke-Compose @("-f", "deploy/ops/docker-compose.before-xff.yml", "down")
    Invoke-Compose @("--env-file", "deploy/.env", "-f", "deploy/ops/docker-compose.lab.yml", "down")
    Pop-Location
    exit 0
}

# 顺序就是演示表的顺序：先裸奔栈，再网关栈，最后靶站和靶场页面。
Write-Host "起裸奔栈（18081 / 13307）"
Invoke-Compose @("-f", "deploy/ops/docker-compose.before.yml", "up", "-d")
Write-Host "起网关栈（80 / 443，三副本）"
Invoke-Compose @("--env-file", "deploy/.env", "-f", "deploy/docker-compose.yml", "-f", "deploy/docker-compose.scale.yml", "up", "-d")
Write-Host "起修复前的网关（9443）"
Invoke-Compose @("-f", "deploy/ops/docker-compose.before-xff.yml", "up", "-d")
Write-Host "起靶站（18090）"
Invoke-Compose @("--env-file", "deploy/.env", "-f", "deploy/ops/docker-compose.lab.yml", "up", "-d")
Write-Host "起靶场页面（18080）"
Invoke-Compose @("-f", "deploy/ops/docker-compose.range.yml", "up", "-d")

# 已经在跑就不再起第二个，避免端口被占
if (-not (Get-NetTCPConnection -LocalPort 18082 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $Py -ArgumentList "scripts\range_control.py" -WorkingDirectory $Root -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "演示表：http://127.0.0.1:18080/attack/demo.html"
Write-Host "靶站：http://127.0.0.1:18090/"
Write-Host "靶场：http://127.0.0.1:18080/attack/"
Write-Host "演示服务：http://127.0.0.1:18082/status"
Pop-Location

