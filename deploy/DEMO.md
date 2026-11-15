# 演示流程

按顺序跑，每一步都有"预期看到什么"和"这时候说什么"。
所有数字都是本机实测值（2026-11-15），不是估的。

前置：Docker Desktop 已启动，`scripts/gen_cert.ps1` 已跑过。

```powershell
scripts/gen_cert.ps1
docker compose -f deploy/docker-compose.yml up -d --build
docker compose -f deploy/docker-compose.baseline.yml up -d --build
```

---

## 一、先看"没有代理"是什么样（约 90 秒）

```powershell
curl.exe -i http://localhost:18081/api/v1/health
```

预期：

```
HTTP/1.1 200 OK
server: uvicorn
{"status":"ok","service":"symbiont-server","version":"0.1.0","instance":"","client_ip":"172.19.0.1"}
```

**说法**：这台后端直接开在 18081 上，谁拿到端口谁就能打。注意三件事：

1. `http` 不是 `https` —— 链路上任何一段都能看见内容；
2. `server: uvicorn` —— 连用什么框架都告诉你了；
3. `instance` 是空的 —— 只有一台，它挂了就没有第二台。

再补一句：真实项目里数据库端口也常常这样开在外面。

```powershell
curl.exe -i --max-time 3 http://localhost:13307/ 2>&1 | Select-Object -First 3
```

---

## 二、明文能被看见（约 2 分钟）

开一个终端当中继：

```powershell
python deploy/tap.py --listen 18181 --target 18081
```

另开一个终端：

```powershell
curl.exe -s http://localhost:18181/api/v1/health
```

中继那边会打印：

```
--- 客户端 → 服务端（92 字节）---
GET /api/v1/health HTTP/1.1
Host: localhost:18181
User-Agent: curl/8.21.0
Accept: */*

--- 服务端 → 客户端（226 字节）---
HTTP/1.1 200 OK
server: uvicorn
{"status":"ok","service":"symbiont-server",...}
```

**说法**：这个中继只是"把转发的字节顺手打出来"，它没有破解任何东西。
明文 HTTP 下，请求行、请求头、JSON 正文全都躺在链路上。
真实场景里登录请求长这样：`POST /api/v1/auth/login`，正文里就是账号和密码。

---

## 三、换成 HTTPS 再看一遍（约 60 秒）

```powershell
python deploy/tap.py --listen 18182 --target 443
```

```powershell
curl.exe -sk https://localhost:18182/api/v1/health
```

中继这回只能打印：

```
--- 客户端 → 服务端（447 字节）---
二进制，不是能读的文本。前 64 字节：
16 03 01 01 ba 01 00 01 b6 03 03 ...
……里面是 TLS 加密之后的内容，中继看不到明文。
```

**说法**：同一件事，同一台中继，加了一层 TLS 之后它只能看见十六进制。
注意 `16 03 01` 是 TLS 握手的第一条记录——连 `GET` 这三个字母都看不见了。

---

## 四、走网关访问（约 60 秒）

```powershell
curl.exe -i http://localhost/api/v1/health          # 308 跳到 https
curl.exe -ik https://localhost/api/v1/health
```

预期响应头：

```
HTTP/2 200
server: nginx
x-upstream: 172.18.0.5:8000
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
referrer-policy: no-referrer-when-downgrade
```

**说法**：

- `server: nginx` —— 版本号没了（`server_tokens off`）；
- `x-upstream` —— 这次是哪台后端接的；
- 后端 8000、数据库 3306 现在**没有任何对外端口**，`docker port` 查得到：

```powershell
docker port symbiont-server-1-1     # 空
docker port symbiont-mysql-1        # 空
```

---

## 五、分流（约 90 秒）

```powershell
python deploy/bench.py --mode seq --n 12
```

实测：

```
后端分布（只看成功的请求）
  node-1      4 次  ####
  node-2      4 次  ####
  node-3      4 次  ####
```

**说法**：12 个请求，三台各 4 个。算法是 `least_conn`（谁手上连接少给谁），
请求稀疏时看起来跟轮询一样；把 `nginx.conf` 里那行注释掉换成默认轮询，
分布也是这个样子——差别要到有慢请求时才显出来。

也可以打开浏览器 `https://localhost/status.html`，点"依次请求 12 次"，
三根进度条会一起长。

---

## 六、限流（约 90 秒）

```powershell
python deploy/bench.py --n 40 --concurrency 40
```

实测：

```
状态码
  200      21 次
  429      19 次

成功率 21/40 = 52%
```

**说法**：配置是 `rate=8r/s` + `burst=20`，所以一瞬间最多放过 21 个，其余直接 429。
注意这里是 **429 不是 503** —— nginx 限流默认返回 503，那会让客户端以为服务坏了，
所以配置里显式写了 `limit_req_status 429`。

补一句坑：限流按 `$binary_remote_addr` 算。如果网关前面还有一层 CDN，
所有用户都会变成同一个 IP，一起被限——那时候必须用 realip 模块取真实地址。

---

## 七、故障转移（约 2 分钟）

```powershell
docker stop symbiont-server-2-1
python deploy/bench.py --mode seq --n 9
```

实测：

```
成功率 9/9 = 100%
  node-1      5 次
  node-3      4 次
  最慢 5006 ms
```

**说法**：node-2 停了，请求一个都没失败，自动落到另外两台。
但注意那个 5006 ms——开源版 nginx 只有**被动**健康检查：
第一个撞上死实例的请求要等 `proxy_connect_timeout` 超时才重试。
想避免这个，要么把超时调短，要么换成有主动探测的方案（NGINX Plus、Envoy）。

恢复：

```powershell
docker start symbiont-server-2-1
```

`max_fails=2` / `fail_timeout=10s`：10 秒后它会被重新放回地址池。

---

## 八、收尾（30 秒）

```powershell
docker compose -f deploy/docker-compose.yml down
docker compose -f deploy/docker-compose.baseline.yml down
```

**说法**：整套加起来是三个配置文件——`nginx.conf`、`docker-compose.yml`、
`docker-compose.baseline.yml`。网关这一层做的事，全在 `nginx.conf` 的四组配置里：
地址池、TLS、限流、安全头。

---

## 万一现场翻车

1. **Docker 起不来**：先跑 `docker compose ps`，再跑 `docker compose logs proxy`。
2. **证书报错**：重跑 `scripts/gen_cert.ps1`。
3. **80/443 被占**：本机 Apache 占 8080、打印控件占 8000 和 18000，别用那几个。
4. **最坏情况**：直接放录屏。录屏里同样是这七步，数据一模一样。

时间分配建议：一到三步 5 分钟（这部分最抓人），四到七步 8 分钟，
留 2 分钟给"什么时候才需要负载均衡"的结论。
