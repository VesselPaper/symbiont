# 构建两个运行镜像，并按 git 短 sha 打 tag
#
# 用法： scripts/build_images.ps1
#
# 为什么按 sha 打 tag：镜像不可变，回滚是把 IMAGE_TAG 指回上一个 sha，
# 而不是"重新跑一次 build 看能不能复现"。同一份代码建出九个 438 MB 镜像的老做法，
# 问题就在于没人说得清线上跑的是哪一个。

$Root = Split-Path -Parent $PSScriptRoot
$DeployDir = Join-Path $Root 'deploy'
$ServerDir = Join-Path $Root 'server'
$EnvFile = Join-Path $DeployDir '.env'

Push-Location $Root
$sha = (& git rev-parse --short HEAD).Trim()
$dirty = (& git status --porcelain | Measure-Object -Line).Lines
Pop-Location

if ($dirty -gt 0) { $tag = "$sha-dirty" } else { $tag = $sha }
Write-Host "镜像 tag：$tag"

# 后端：上下文是 server/，Dockerfile 就在里面
& docker build --pull=false -t "symbiont-server:$tag" -t symbiont-server:local $ServerDir
if ($LASTEXITCODE -ne 0) { throw '后端镜像构建失败' }

# 网关：上下文是 deploy/，里面只有配置与页面
& docker build --pull=false -f (Join-Path $DeployDir 'Dockerfile.proxy') -t "symbiont-proxy:$tag" -t symbiont-proxy:local $DeployDir
if ($LASTEXITCODE -ne 0) { throw '网关镜像构建失败' }

if (Test-Path $EnvFile) {
    $lines = Get-Content -Path $EnvFile -Encoding utf8
    $new = foreach ($line in $lines) {
        if ($line -match '^IMAGE_TAG=') { "IMAGE_TAG=$tag" } else { $line }
    }
    [System.IO.File]::WriteAllLines($EnvFile, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已写入 deploy/.env：IMAGE_TAG=$tag"
}
else {
    Write-Host 'deploy/.env 不存在，先运行 scripts/gen_env.ps1'
}

Write-Host ''
docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' --filter 'reference=symbiont-*'
