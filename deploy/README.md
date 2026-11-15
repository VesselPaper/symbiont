# 部署 deploy/

对应课程交付 **4. 系统安装部署文档（包括 docker 镜像文件）**。

Web 版不是"nginx 托管静态文件 + 后端各开一个端口"。浏览器和后端之间那一层是**应用代理**：
它同时负责 TLS、限流、静态托管、安全响应头，并在单副本时直接转发、多副本时分流与故障转移。

## 一、首次部署

```powershell
scripts/gen_env.ps1          # 生成 deploy/.env（随机数据库密码）
scripts/make_ca.ps1          # 生成本地 CA 与服务端证书
scripts/build_images.ps1     # 按 git 短 sha 构建两个镜像
docker compose -f deploy/docker-compose.yml up -d
```

浏览器首次访问 `https://localhost` 会提示证书不受信任 —— 装一次根证书
（`deploy/certs/ca.crt`）就不再提示，详见 `OPERATIONS.md`。

## 二、两种运行形态

| 形态 | 命令 | 什么时候用 |
|---|---|---|
| 单副本（默认） | `docker compose -f deploy/docker-compose.yml up -d` | 日常与验收。本项目真实用量就属于这一档 |
| 三副本 | 再加 `-f deploy/docker-compose.scale.yml` | 需要验证分流与故障转移，或真的扛不住单台时 |

副本数是部署决策，不是代码：扩容只叠加一个文件，主配置与 nginx 主模板一个字都不改。

## 三、这个入口做了什么

| 职责 | 配置位置 | 效果 |
|---|---|---|
| TLS 终止 | `nginx/templates/default.conf.template` | 80 只做 308 跳转，内容只走 443 |
| 藏源站 | `docker-compose.yml` 的 `expose` | 后端 8000、数据库 3306 都不映射宿主机 |
| 限流 | 同上 | 每 IP 8 r/s、突发 20、并发 20，超出 429（不是默认的 503） |
| 地址池 | `nginx/templates/upstream.conf.template` | `least_conn` + `max_fails` 摘除 + `keepalive` 复用 |
| 指纹收敛 | 同上 | `server_tokens off`；后端还加了 `--no-server-header` |
| 安全响应头 | 同上 | `nosniff`、`X-Frame-Options`、`Referrer-Policy` |
| 缓存分级 | 同上 | 入口页不缓存，`wasm`/`pck` 长缓存 30 天 |

配置是**模板**：镜像里放 `.template`，启动时按 `SYMBIONT_` 前缀的环境变量渲染。
同一个镜像换环境只改 `.env`，不需要重建镜像。

## 四、目录

| 路径 | 说明 |
|---|---|
| `docker-compose.yml` | 默认编排：mysql + server + proxy |
| `docker-compose.scale.yml` | 三副本叠加层 |
| `Dockerfile.proxy` | 网关镜像：非 root、非特权端口、内置健康检查 |
| `nginx/templates/` | 网关配置模板（主配置 + 地址池） |
| `nginx/scale/` | 三副本地址池，只在叠加层挂载 |
| `server/Dockerfile` | 后端镜像：多阶段、非 root、内置健康检查 |
| `html/` | 落地页与网关状态页（`/status.html`） |
| `ops/` | 排障工具：压测、明文/密文对照、无网关对照编排 |
| `.env.example` | 环境变量字段说明，可提交 |

## 五、几个踩过的坑

- `upstream` 不加 `zone`：每个 worker 各算各的轮询，请求量小时看起来全打第一台。
- `limit_req` 默认返回 503，要显式 `limit_req_status 429`。
- `location` 里出现一个 `add_header` 就会覆盖整组继承来的头，所以缓存只用 `expires` 控。
- nginx 的 `server` 级 `return` 在 location 匹配之前生效，写在那里的 `location` 是死代码。
- 非 root 运行时 `/var/run` 只是指向 `/run` 的符号链接，要改属主的是 `/run`。
- 健康检查别放在会 308 的端口上，探针会跟着跳到容器里没监听的端口。
- 两个编排都在 `deploy/` 下，不写 `name:` 会被当成同一个 compose 项目互相顶替。

## 六、镜像

| 镜像 | 大小 | 说明 |
|---|---|---|
| `symbiont-server:<sha>` | 329 MB | python:3.12-slim + venv + app，非 root |
| `symbiont-proxy:<sha>` | 94 MB | nginx:alpine + 配置模板 + 页面 |

tag 是 git 短 sha（工作区有未提交改动时带 `-dirty`）。回滚就是把 `.env` 里的
`IMAGE_TAG` 指回上一个 sha 再 `up -d`，不需要重新构建。
