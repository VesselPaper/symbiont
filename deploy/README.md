# 部署 deploy/

对应课程交付 **4. 系统安装部署文档（包括 docker 镜像文件）**。

Web 版不是"一个 nginx 加一个后端"那么简单：浏览器到后端之间的那一层是**应用代理**，
它同时负责 TLS、限流、静态托管、把请求分给三台后端，并在某台挂掉时自动绕开。
这一层的配置、对照实验和实测工具都在这个目录里。

## 一、一键全栈

```powershell
# 前置：Docker Desktop 已启动
scripts/gen_cert.ps1         # 生成自签证书（只做一次）
docker compose -f deploy/docker-compose.yml up -d --build
```

| 服务 | 地址 | 说明 |
|---|---|---|
| proxy | https://localhost | 入口网关：TLS、限流、静态托管、`/api` 反代 |
| （无对外端口） | server-1/2/3 内网 8000 | 三台无状态后端，外面连不上 |
| （无对外端口） | mysql 内网 3306 | 数据库，只在容器网络内可见 |

浏览器首次访问会提示"证书不受信任"，这是自签证书的正常现象，点"继续访问"。
`https://localhost/status.html` 是网关状态页，能看到每次请求落到哪台后端。

## 二、这个入口到底做了什么

`nginx.conf` 里有四组东西，各自解决一件事：

| 配置 | 作用 |
|---|---|
| `upstream symbiont_backend` | 三台后端地址池，`least_conn` 调度，`max_fails` 摘除，`keepalive` 复用连接 |
| `listen 443 ssl` + 80 跳转 | TLS 在网关终止，后端之间跑明文但不出内网 |
| `limit_req` / `limit_conn` | 每 IP 8 请求/秒、最多 20 并发，超出返回 **429** |
| `server_tokens off` + 安全响应头 | 不报 nginx 版本，补 `nosniff` / `X-Frame-Options` / `Referrer-Policy` |

几个踩过的坑，都写在配置文件注释里：

- `upstream` 不加 `zone`，请求量小时看起来全打到第一台（多 worker 各算各的轮询）。
- `limit_req` 默认返回 **503** 而不是 429，要用 `limit_req_status 429` 改过来。
- `location` 里只要出现一个 `add_header`，整组继承来的头就会被覆盖，所以缓存只用 `expires` 控。
- 开源版 nginx 只有被动健康检查：摘掉死实例前，第一个请求要等 `proxy_connect_timeout`。
  实测停掉一台后端后，有一次请求耗时 5006 ms，之后全部正常。

## 三、对照实验：没有网关是什么样

```powershell
docker compose -f deploy/docker-compose.baseline.yml up -d --build
```

| | baseline（裸奔） | 网关 |
|---|---|---|
| 后端端口 | `18081` 直接对宿主机开放 | 只在内网，外部不可达 |
| 传输 | 明文 HTTP | 80 跳 443，TLS 加密 |
| 版本指纹 | `server: uvicorn` | `server: nginx`（版本已抹掉） |
| 后端数量 | 1 台，挂了就没 | 3 台，挂一台自动绕开 |
| 限流 | 无 | 8 r/s + burst 20 |

两份编排是独立项目（`symbiont` / `symbiont-baseline`），可以同时起，互不顶替。

## 四、实测工具

```powershell
python deploy/bench.py                        # 并发 40，看状态码与后端分布
python deploy/bench.py --mode seq --n 12      # 依次请求，看分流是否均匀
python deploy/tap.py --listen 18181 --target 18081   # 明文对照
python deploy/tap.py --listen 18182 --target 443     # 密文对照
```

`bench.py` 只用标准库，输出三段：状态码分布、每台后端命中次数、耗时 p50/p95。

`tap.py` 是一个"顺手把字节打出来"的 TCP 中继，用来把"有没有 TLS"变成屏幕上看得见的两段输出：

- 走 18081（明文）：中继直接打印出 `GET /api/v1/health` 和完整 JSON。
- 走 443（TLS）：中继只能打印一串十六进制，连请求行都看不见。

## 五、目录

| 文件 | 说明 |
|---|---|
| `docker-compose.yml` | 网关态：mysql + server-1/2/3 + proxy |
| `docker-compose.baseline.yml` | 对照态：mysql + 单后端，端口裸暴露 |
| `nginx.conf` | 网关配置：upstream / TLS / 限流 / 安全头 / 缓存 |
| `Dockerfile.proxy` | 网关镜像（nginx:alpine + 配置 + 静态页） |
| `Dockerfile.server` | 后端镜像（python:3.12-slim + uvicorn） |
| `html/` | 落地页与网关状态页 |
| `bench.py` | 并发实测 |
| `tap.py` | 明文/密文对照中继 |
| `certs/` | 自签证书，由 `scripts/gen_cert.ps1` 生成，不进仓库 |
