# 运维手册

这份文档只写"出事时怎么办"和"要改东西时怎么改"，原理见 `README.md`，接口见 `doc/02`。

## 一、首次部署

```powershell
scripts/gen_env.ps1        # 生成随机数据库密码到 deploy/.env
scripts/make_ca.ps1        # 生成本地 CA 与服务端证书
scripts/trust_ca.ps1       # 把根证书装进当前用户（不需要管理员）
scripts/build_images.ps1   # 按 git 短 sha 构建两个镜像
docker compose -f deploy/docker-compose.yml up -d
scripts/smoke_test.ps1     # 七项检查，全绿才算部署成功
```

## 二、证书

| 事项 | 做法 |
|---|---|
| 换域名/换机器 | 改 `scripts/make_ca.ps1 -CommonName <名字>` 重签，或直接 `-Force` 重来 |
| 浏览器仍然报警 | `scripts/trust_ca.ps1` 装根证书；Chrome/Edge 需完全重启 |
| 命令行客户端报 `revocation status is unknown` | 加 `--ssl-no-revoke`。这是 Windows Schannel 在要求吊销检查，我们的内网 CA 没有 CRL 分发点 |
| 卸载根证书 | `scripts/trust_ca.ps1 -Remove` |

**关于吊销检查**：浏览器对本地安装的根证书是软失败（能连），但 Windows 的 Schannel 系客户端
（curl、WinHTTP、.NET）会把"查不到吊销状态"当成失败。要做彻底需要给 CA 发 CRL 并在网关上发布，
目前没做，取舍是：内网自用，命令行加一个参数即可；换正式证书后这个问题自动消失。

## 三、日常

```powershell
docker compose -f deploy/docker-compose.yml ps          # 状态
docker compose -f deploy/docker-compose.yml logs -f proxy
docker compose -f deploy/docker-compose.yml restart proxy
docker compose -f deploy/docker-compose.yml down        # 停（保留数据卷）
docker compose -f deploy/docker-compose.yml down -v     # 停并删数据（慎用）
```

日志按 10 MB × 3 轮转，不会把磁盘写满；访问日志是自定义格式，含 `rt`（总耗时）、
`urt`（上游耗时）、`ua`（这次是哪台后端接的）。

## 四、升级

```powershell
git pull
scripts/build_images.ps1                 # 构建出新 sha 的镜像，并写回 .env
docker compose -f deploy/docker-compose.yml up -d
scripts/smoke_test.ps1
```

镜像不可变，旧 tag 还在，出问题直接回滚。

## 五、回滚

```powershell
# 把 deploy/.env 里的 IMAGE_TAG 改成上一个 sha
docker compose -f deploy/docker-compose.yml up -d
scripts/smoke_test.ps1
```

数据库结构变更不走这条路：先跑 `scripts/db_backup.ps1`，再回滚，再按需恢复数据。

## 六、扩容

```powershell
docker compose -f deploy/docker-compose.yml -f deploy/docker-compose.scale.yml up -d
```

它只做两件事：多起两台同镜像后端（`server-2`、`server-3`），以及把网关地址池换成三台。
主配置与 nginx 主模板一个字不改。缩回单副本：

```powershell
docker compose -f deploy/docker-compose.yml up -d --remove-orphans
```

**什么时候该扩容**：单台 CPU 打满或连接被占满，且压测确认瓶颈在应用层而不是数据库。
本项目目前不需要，这条路径是可用的预留，不是常开配置。

## 七、备份与恢复

```powershell
scripts/db_backup.ps1                      # 导出到 backups/，保留最近 7 份
scripts/db_restore.ps1 -File backups\symbiont-20261115-185033.sql.gz
```

恢复会覆盖整个库，脚本会先要求输入 `yes` 确认；`-Force` 跳过确认。

**演练记录（2026-11-15）**：写入一条标记事件 → 备份 → 删掉标记（计数 0）→ 恢复 → 计数回到 1。
备份文件约 1.3 KB（当前数据量）。

## 八、故障处置

| 现象 | 先看 | 处理 |
|---|---|---|
| 浏览器打不开 | `docker compose ps` | 网关没起来 → `up -d`；证书报错 → 重跑 `make_ca.ps1` |
| `/api` 全 429 | 网关日志 | 限流触发。临时放宽 `SYMBIONT_RATE_LIMIT` 后 `up -d` |
| `/api` 502 | `logs server-1` | 后端崩了或健康检查失败；看 uvicorn 报错 |
| `/api` 504 | 网关日志里的 `urt` | 后端慢；先看数据库慢查询 |
| 只有一个副本在工作 | `nginx-scale.conf` 是否挂上 | 叠加层没加 `-f deploy/docker-compose.scale.yml` |
| 数据库连不上 | `logs mysql` | 密码与 `.env` 不一致（换过 `.env` 但没重建卷） |
| 80/443 被占用 | `Get-NetTCPConnection -LocalPort 80` | 改 compose 的 `ports` 映射 |
| 证书过期 | `openssl x509 -in deploy/certs/server.crt -noout -dates` | 重跑 `make_ca.ps1` |

## 九、已知限制

1. 代理自身是单点：只有一台网关，它挂了服务就断。要消除得在外层再做一次均衡，未做。
2. 内网 CA 没有 CRL，Windows 命令行客户端需要 `--ssl-no-revoke`。
3. Web 版游戏包需要先 `scripts/export_web.ps1` 导出，当前导出脚本尚未实现，所以根路径会回退到落地页。
4. 没有监控面板：靠日志、`smoke_test.ps1` 和 `ops/bench.py` 手工验。
