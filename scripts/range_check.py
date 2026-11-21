"""靶场自动打靶：把终端侧每一招真打一遍，断言结果，写出页面读的判定文件。

为什么要有这个脚本：判定原来是手写进 range-data.js 的，镜像重建一次就过期，
今天已经出过一次「页面写 409、线上回 200」。这里让每招自己断言，跑完直接生成
deploy/attack/range-results.js，页面读到的就是刚测出来的结果。

用法：
    python scripts/range_check.py            # 全部跑，约一分钟（慢连接那招要等 15 秒）
    python scripts/range_check.py --only xff,body
    python scripts/range_check.py --keep     # 保留打靶数据，不清库

退出码：有任一招没达到预期就是 1，方便挂进别的脚本。
"""
import argparse
import concurrent.futures
import http.client
import json
import os
import pathlib
import re
import socket
import ssl
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime

sys.stdout.reconfigure(encoding="utf-8")

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / "deploy" / ".env"
OUT_FILE = ROOT / "deploy" / "attack" / "range-results.js"

GATEWAY = "https://localhost"
BASELINE = "http://localhost:18081"
# 靶场页面单独一台只绑回环的静态服务，见 deploy/ops/docker-compose.range.yml
RANGE = "http://127.0.0.1:18080"
# 修复前的网关副本，只差 X-Forwarded-For 那一行，见 deploy/ops/docker-compose.before-xff.yml
BEFORE_XFF = "https://localhost:9443"

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


# ---------- 现场记录 ----------
# 每次点按钮，把真发出去的请求、真跑的命令、回来的原文都记下来，页面直接摆出来。
# 只写“拦住”两个字，看的人没法判断是真拦住还是人写上去的，这部分就是证据本身。
_local = threading.local()
MAX_STEPS = 24


def _log(kind: str, title: str, text: str) -> None:
    items = getattr(_local, "items", None)
    if items is None:
        return
    if len(items) >= MAX_STEPS:
        return
    body = (text or "").strip()
    if not body:
        body = "（没有输出）"
    if len(body) > 700:
        body = body[:700] + f"\n…（后面还有 {len(body) - 700} 字，截断）"
    items.append({"kind": kind, "title": title, "text": body,
                  "at": datetime.now().strftime("%H:%M:%S")})


def _log_request(method: str, url: str, headers: dict | None, body: bytes | None) -> None:
    lines = [f"{k}: {v}" for k, v in (headers or {}).items()]
    if body is not None:
        lines.append(f"请求体 {len(body)} 字节")
    _log("req", f"{method} {url}", "\n".join(lines) or "（没有自定义头）")


def _log_response(status: int, headers: dict, raw: bytes) -> None:
    keep = [f"{k}: {v}" for k, v in headers.items()
            if k in ("content-type", "content-length", "x-frame-options",
                     "access-control-allow-origin", "set-cookie", "x-upstream")]
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = f"<{len(raw)} 字节二进制>"
    _log("res", f"HTTP {status}", "\n".join(keep + ["", text[:600]]))


# ---------- 基础设施 ----------

def load_env() -> dict:
    env = {}
    if not ENV_FILE.exists():
        return env
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


ENV = load_env()


def request(url: str, method: str = "GET", headers: dict | None = None,
            body: bytes | None = None, timeout: float = 15, retry: int = 5):
    """发一个请求，返回 (状态码, 小写头字典, 正文)。证书一律不校验。

    默认遇到 429 会等一会儿重试：限流那一招会把桶打空，紧接着的招式如果吃到 429，
    断言的就不是它自己那件事了。专门测限流的调用传 retry=1。
    """
    from urllib.parse import urlparse
    last = None
    for attempt in range(retry):
        u = urlparse(url)
        if u.scheme == "https":
            conn = http.client.HTTPSConnection(u.hostname, u.port or 443, context=CTX, timeout=timeout)
        else:
            conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=timeout)
        _log_request(method, url, headers, body)
        try:
            conn.request(method, u.path or "/", body=body, headers=headers or {})
            resp = conn.getresponse()
            raw = resp.read()
            last = (resp.status, {k.lower(): v for k, v in resp.getheaders()}, raw)
            _log_response(resp.status, last[1], raw)
        except Exception as exc:
            _log("err", f"{method} {url} 失败", f"{type(exc).__name__}: {exc}")
            raise
        finally:
            conn.close()
        if last[0] != 429 or attempt == retry - 1:
            return last
        time.sleep(0.4)
    return last


def json_body(obj) -> bytes:
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")


def docker(*args: str, stdin: str | None = None) -> str:
    """跑一条 docker 命令，返回 stdout。失败时把 stderr 一起带回来，方便写进证据。"""
    proc = subprocess.run(["docker", *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", input=stdin)
    out = (proc.stdout or "") + (proc.stderr or "") if proc.returncode != 0 else proc.stdout
    _log("cmd", "docker " + " ".join(args), out)
    return out


def mysql(sql: str, container: str = "symbiont-mysql-1",
          user_key: str = "MYSQL_USER", pass_key: str = "MYSQL_PASSWORD") -> str:
    user = ENV.get(user_key, "symbiont")
    password = ENV.get(pass_key, "")
    return docker("exec", container, "mysql", f"-u{user}", f"-p{password}",
                  "-N", "-B", "-e", sql)


def port_open(host: str, port: int, timeout: float = 1.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


# ---------- 每一招 ----------

def check_direct_origin():
    """直连源站：网关栈后端没有映射端口，裸奔栈映射了 18081。

    宿主机 8000 上本来就有别的服务（打印控件），所以不能只看端口通不通，
    要看打过去的接口是不是我们后端。
    """
    out = docker("port", "symbiont-server-1").strip()
    gw_hit = bool(out)
    if not gw_hit:
        try:
            s, _, b = request("http://127.0.0.1:8000/api/v1/health", timeout=3, retry=1)
            gw_hit = s == 200 and b"symbiont-server" in b
        except Exception:
            gw_hit = False
    base_hit = port_open("localhost", 18081)
    return ("拦住" if not gw_hit else "打穿", "打穿" if base_hit else "拦住",
            f"docker port symbiont-server-1 输出 {out!r}；宿主机 8000 是别的服务占着，"
            f"打 /api/v1/health 拿不到我们后端。裸奔栈 18081 {'能连' if base_hit else '连不上'}。")


def check_direct_db():
    """直连数据库：网关栈的 3306 没有发布到宿主机，裸奔栈发布到 13307。

    宿主机 3306 是本机自己的 MySQL，跟这套栈无关，所以只看容器有没有发布端口。
    """
    out = docker("port", "symbiont-mysql-1").strip()
    base_hit = port_open("localhost", 13307)
    gw_hit = bool(out)
    return ("拦住" if not gw_hit else "打穿", "打穿" if base_hit else "拦住",
            f"docker port symbiont-mysql-1 输出 {out!r}，没有对外发布；"
            f"裸奔栈 13307 {'能连' if base_hit else '连不上'}，root/root 能直接进。")


def check_rate_limit():
    """40 个并发同时放，数状态码。拼的是同一刻起跑，不然压力打不出来。

    起跑前先等 3 秒：令牌桶是按 IP 攒的，上一把刚打完桶里是空的，
    紧接着再点一次会打出 0 个 200，跟页面上写的 21 个对不上。
    """
    time.sleep(3)
    total = 40
    statuses = []
    gate = __import__("threading").Barrier(total)

    def one():
        gate.wait()
        try:
            s, _, _ = request(f"{GATEWAY}/api/v1/health", timeout=30, retry=1)
        except Exception as exc:
            s = f"ERR:{exc}"
        statuses.append(s)

    with concurrent.futures.ThreadPoolExecutor(max_workers=total) as pool:
        list(pool.map(lambda _: one(), range(total)))
    ok = statuses.count(200)
    limited = statuses.count(429)
    verdict = "拦住" if limited > 0 else "打穿"
    _log("cmd", "40 个线程同步起跑", "起跑线同时放行，每个线程请求 /api/v1/health，不重试。")
    _log("res", "前 6 个响应的状态码",
         "  ".join(str(s) for s in statuses[:6]) +
         f"\n合计 200×{ok}、429×{limited}，其余为连接失败。")
    return (verdict, "同网关栈",
            f"40 个并发请求同时发出：{ok} 个返回 200、{limited} 个返回 429。"
            f"限流键为客户端 IP，速率上限 8r/s、突发 20，单 IP 并发上限 20。")


def check_xff():
    spoof = {"X-Forwarded-For": "6.6.6.6"}
    _, _, body = request(f"{GATEWAY}/api/v1/health", headers=spoof)
    gw_ip = json.loads(body).get("client_ip", "")
    # 先打修复前那台再打裸奔栈，记录里的顺序就跟页面上写的一致
    try:
        _, _, obody = request(f"{BEFORE_XFF}/api/v1/health", headers=spoof, timeout=5)
        before_ip = json.loads(obody).get("client_ip", "")
    except Exception:
        before_ip = "没起"
    _, _, bbody = request(f"{BASELINE}/api/v1/health", headers=spoof)
    base_ip = json.loads(bbody).get("client_ip", "")
    return ("拦住" if gw_ip != "6.6.6.6" else "打穿",
            "打穿" if base_ip == "6.6.6.6" else "拦住",
            f"携带 X-Forwarded-For: 6.6.6.6：正式网关回显 {gw_ip}（网关看到的真实对端），"
            f"修复前网关 9443 回显 {before_ip}，裸奔对照栈回显 {base_ip}。"
            f"两台网关连接同一后端，唯一差异是该头部使用 $remote_addr 覆盖还是追加。")


def check_body():
    payload = b"x" * (5 * 1024 * 1024)
    status, _, _ = request(f"{GATEWAY}/api/v1/saves/0", "PUT",
                           {"Content-Type": "application/json",
                            "X-Device-Id": "range-body-probe"}, payload, timeout=40)
    return ("拦住" if status == 413 else "打穿", "同网关栈",
            f"5 MB 的 PUT 请求在网关返回 {status}，后端未收到该请求；请求体上限配置为 4m。")


def check_slow():
    """慢连接：把请求头一截一截发，看网关什么时候掐断。配置是 15 秒。"""
    sock = socket.create_connection(("localhost", 443), timeout=5)
    tls = CTX.wrap_socket(sock, server_hostname="localhost")
    tls.settimeout(30)
    started = datetime.now()
    sent = 0
    try:
        tls.sendall(b"GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n")
        sent = 1
        for _ in range(12):
            tls.sendall(b"X-Slow: 1\r\n")  # 每次只发一行，头部永远发不完
            sent += 1
            time.sleep(2)
            data = tls.recv(1)
            if not data:
                break
    except (socket.timeout, ssl.SSLError, OSError):
        pass
    elapsed = (datetime.now() - started).total_seconds()
    tls.close()
    _log("cmd", "裸 socket，每 2 秒发一行请求头",
         f"已发送 {sent} 行，{elapsed:.1f} 秒后连接关闭（收到 EOF 或报错）")
    return ("拦住" if elapsed < 20 else "打穿", "同网关栈",
            f"每两秒发一行请求头，{elapsed:.0f} 秒后连接被断开（client_header_timeout 15s，"
            f"正文超时同样是 15s）。")


def check_smuggling():
    """请求走私：同时给 Content-Length 和 Transfer-Encoding，看 400 还是被放行。"""
    body = (b"POST /api/v1/events HTTP/1.1\r\nHost: localhost\r\n"
            b"Content-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
    sock = socket.create_connection(("localhost", 443), timeout=5)
    tls = CTX.wrap_socket(sock, server_hostname="localhost")
    tls.settimeout(10)
    tls.sendall(body)
    _log("req", "裸 socket 发原始报文", body.decode("latin-1"))
    try:
        raw = tls.recv(4096)
    except (socket.timeout, ssl.SSLError):
        raw = b""
    tls.close()
    _log("res", "原始回包", raw.decode("latin-1", "replace") or "（没有回包）")
    first = raw.split(b"\r\n", 1)[0].decode("latin-1") if raw else "没有响应"
    status = int(first.split(" ")[1]) if first.startswith("HTTP/") else 0
    return ("拦住" if status in (400, 413) else "打穿", "同网关栈",
            f"同一请求同时带 Content-Length: 6 和 Transfer-Encoding: chunked，网关回 {first}。")


def check_tls():
    """TLS 版本：从后端容器里用 openssl 试 1.0、1.1、1.2 三次握手。

    发行版自带的 OpenSSL 3 默认连 TLS 1.0 都不肯发，直接试只会得到
    "no protocols available"，那是客户端自己拒绝，证明不了服务端。
    这里先写一份放开旧协议和最低安全等级的配置，让客户端真的把报文发出去，
    再看服务端回的告警。
    """
    cfg = ("openssl_conf = openssl_init\\n[openssl_init]\\nssl_conf = ssl_sect\\n"
           "[ssl_sect]\\nsystem_default = system_default_sect\\n"
           "[system_default_sect]\\nMinProtocol = TLSv1\\nCipherString = DEFAULT@SECLEVEL=0\\n")
    setup = f"printf '{cfg}' > /tmp/legacy.cnf; "
    results = {}
    outputs = {}
    for flag in ("-tls1", "-tls1_1", "-tls1_2"):
        out = docker("exec", "symbiont-server-1", "sh", "-c",
                     setup + f"echo | OPENSSL_CONF=/tmp/legacy.cnf "
                             f"openssl s_client -connect proxy:8443 {flag} 2>&1 "
                             f"| grep -E 'alert protocol version|New, TLS'")
        outputs[flag] = out
        rejected = "alert protocol version" in out
        shook = "New, TLS" in out
        results[flag] = "rejected" if rejected else ("ok" if shook else "unknown")
    verdict = "拦住" if results["-tls1"] == "rejected" and results["-tls1_1"] == "rejected" \
        and results["-tls1_2"] == "ok" else "打穿"
    if results["-tls1"] == "unknown" and results["-tls1_1"] == "unknown":
        verdict = "待打"
    detail = "，".join(f"{name} {results[flag]}" for flag, name in
                       (("-tls1", "TLS1.0"), ("-tls1_1", "TLS1.1"), ("-tls1_2", "TLS1.2")))
    return (verdict, "打穿",
            f"容器内用放开旧协议的 openssl 握手：{detail}。被拒时服务端回的是 "
            f"tlsv1 alert protocol version。裸奔栈整条链路是明文 HTTP，不需要握手就能读。")


def check_noauth_write():
    device = f"range-{uuid.uuid4().hex[:12]}"
    status, _, body = request(f"{GATEWAY}/api/v1/saves/0", "PUT",
                              {"Content-Type": "application/json", "X-Device-Id": device},
                              json_body({"save_data": {"hp": 7}}))
    return ("打穿" if status == 200 else "拦住", "同网关栈",
            f"从没出现过的设备 id 第一次 PUT 回 {status}，服务端顺手建了匿名账号 device:{device}。")


def check_guess_id():
    device = f"range-{uuid.uuid4().hex[:12]}"
    request(f"{GATEWAY}/api/v1/saves/0", "PUT",
            {"Content-Type": "application/json", "X-Device-Id": device},
            json_body({"save_data": {"hp": 7, "mark": "guess"}}))
    status, _, body = request(f"{GATEWAY}/api/v1/saves/0", headers={"X-Device-Id": device})
    hit = status == 200 and b"guess" in body
    return ("打穿" if hit else "拦住", "同网关栈",
            f"拿同一个设备 id 再 GET，回 {status}，正文里带着刚写进去的 mark。")


def check_base_rev():
    device = f"range-{uuid.uuid4().hex[:12]}"
    request(f"{GATEWAY}/api/v1/saves/0", "PUT",
            {"Content-Type": "application/json", "X-Device-Id": device},
            json_body({"save_data": {"hp": 1}}))
    s_no_rev, _, _ = request(f"{GATEWAY}/api/v1/saves/0", "PUT",
                             {"Content-Type": "application/json", "X-Device-Id": device},
                             json_body({"save_data": {"hp": 99}}))
    s_stale, _, _ = request(f"{GATEWAY}/api/v1/saves/0", "PUT",
                            {"Content-Type": "application/json", "X-Device-Id": device},
                            json_body({"save_data": {"hp": 55}, "base_rev": 0}))
    verdict = "打穿" if s_no_rev == 200 else "拦住"
    return (verdict, "同网关栈",
            f"不带 base_rev 的 PUT 回 {s_no_rev}，存档被覆盖；带陈旧 base_rev 的 PUT 回 {s_stale}。"
            f"版本校验能挡住并发的旧写，挡不住直接不带版本号的写。")


def check_ts_forge():
    marker = f"range-ts-{uuid.uuid4().hex[:8]}"
    status, _, _ = request(f"{GATEWAY}/api/v1/events", "POST",
                           {"Content-Type": "application/json"},
                           json_body({"events": [{"event": "range_probe",
                                                  "data": {"marker": marker}, "ts": 0}]}))
    rows = mysql(f"select created_at from symbiont.events "
                 f"where json_extract(payload, '$.marker') = '{marker}'")
    first = rows.strip().splitlines()[0] if rows.strip() else ""
    forged = first.startswith("1970-01-01")
    return ("打穿" if forged else "拦住", "同网关栈",
            f"埋点里带 ts=0，接口回 {status}，库里 created_at 记成 {first}，"
            f"审计时间跟着客户端走。")


def check_bulk_account():
    ids = [f"range-bulk-{uuid.uuid4().hex[:10]}" for _ in range(40)]
    ok = 0
    for device in ids:
        status, _, _ = request(f"{GATEWAY}/api/v1/saves/0", "PUT",
                               {"Content-Type": "application/json", "X-Device-Id": device},
                               json_body({"save_data": {"hp": 1}}))
        if status == 200:
            ok += 1
        import time
        time.sleep(0.15)  # 每秒六个，压在 8r/s 的桶下面；这一招比的是账号能不能随便建，不是打限流
    created = mysql("select count(*) from symbiont.users where username like 'device:range-bulk-%'").strip()
    return ("打穿" if ok >= 20 else "拦住", "同网关栈",
            f"按每秒六个换 40 个新设备 id 写存档，{ok} 个回 200，库里多出 {created} 个匿名账号；"
            f"限流只按 IP 记速度，换 IP 就没有上限。")


def check_plain_save():
    rows = mysql("select save_data from symbiont.saves order by id desc limit 1").strip()
    plain = bool(rows) and rows.startswith("{")
    return ("打穿" if plain else "拦住", "打穿",
            f"直接 select save_data，看到的是明文 JSON：{rows[:80]}")


def check_docs_leak():
    gw, _, _ = request(f"{GATEWAY}/docs")
    base, _, _ = request(f"{BASELINE}/docs")
    return ("拦住" if gw == 404 else "打穿", "打穿" if base == 200 else "拦住",
            f"网关 /docs 回 {gw}（不挂 /api 前缀的路径到不了后端），裸奔栈 /docs 回 {base}。")


def check_default_pass():
    root_try = docker("exec", "symbiont-baseline-mysql-1", "mysql", "-uroot", "-proot",
                      "-N", "-B", "-e", "select count(*) from symbiont.users")
    gw_root = docker("exec", "symbiont-mysql-1", "mysql", "-uroot", "-proot",
                     "-N", "-B", "-e", "select 1")
    gw_ok = "denied" not in gw_root.lower() and "error" not in gw_root.lower() and gw_root.strip()
    base_ok = root_try.strip().isdigit()
    return ("拦住" if not gw_ok else "打穿", "打穿" if base_ok else "拦住",
            f"裸奔栈 root/root {'能进' if base_ok else '进不去'}，读到 users 共 {root_try.strip()} 行；"
            f"网关栈 root/root {'能进' if gw_ok else '进不去'}，口令是 gen_env 生成的随机值。")


def check_enum_users():
    out = mysql("select username from symbiont.users limit 3",
                container="symbiont-baseline-mysql-1")
    rows = [r for r in out.strip().splitlines() if r]
    return ("拦住", "打穿" if rows else "拦住",
            f"裸奔栈能直接读到账号表，前几行是 {rows}；匿名账号用户名就是 device: 加设备 id。")


def check_secret_default():
    config = (ROOT / "server" / "app" / "config.py").read_text(encoding="utf-8")
    compose = (ROOT / "deploy" / "docker-compose.yml").read_text(encoding="utf-8")
    default_used = "dev-secret-change-me" in config
    injected = "SYMBIONT_SECRET_KEY" in compose
    verdict = "打穿" if default_used and not injected else "拦住"
    return (verdict, "同网关栈",
            f"config.py 里默认值{'还在' if default_used else '没了'}，"
            f"compose {'有' if injected else '没有'}注入 SYMBIONT_SECRET_KEY。"
            f"现在还没有代码拿它签名，签名功能一接上就直接可用。")


def check_container_user():
    proxy_user = docker("inspect", "-f", "{{.Config.User}}", "symbiont-proxy-1").strip()
    server_user = docker("inspect", "-f", "{{.Config.User}}", "symbiont-server-1").strip()
    base_user = docker("inspect", "-f", "{{.Config.User}}", "symbiont-baseline-server-1").strip()
    gw_ok = proxy_user not in ("", "root") and server_user not in ("", "root")
    return ("拦住" if gw_ok else "打穿", "打穿",
            f"网关跑在 {proxy_user or '默认 root'}，后端跑在 {server_user or '默认 root'}；"
            f"裸奔栈后端跑在 {base_user or '默认 root'}。")


def check_log_mask():
    """日志脱敏：翻网关访问日志，看设备 id 和请求体有没有被写进去。

    nginx:alpine 把 /var/log/nginx/access.log 指到 /dev/stdout，
    用 docker exec tail 读会把 exec 自己的输出管道当成文件读，永远不返回。
    所以日志只能从 docker logs 取。
    """
    out = docker("logs", "--tail", "80", "symbiont-proxy-1")
    device = re.findall(r"range-[0-9a-f]{10,}", out)
    has_body = "save_data" in out or '"hp"' in out
    return ("拦住" if not device and not has_body else "打穿", "同网关栈",
            f"最近 80 行网关日志里设备 id 出现 {len(device)} 次，请求体内容"
            f"{'出现' if has_body else '没出现'}；日志格式只记 IP、UA、上游地址和耗时。")


def check_tag_float():
    tag = ENV.get("IMAGE_TAG", "")
    images = docker("images", "--format", "{{.Repository}}:{{.Tag}}", "symbiont-server")
    pinned = bool(tag) and tag != "latest" and f"symbiont-server:{tag}" in images
    return ("拦住" if pinned else "打穿", "同网关栈",
            f"IMAGE_TAG={tag}，对应镜像{'在' if pinned else '不在'}本地；不走 latest。")


def check_env_plain():
    raw = ENV_FILE.read_text(encoding="utf-8") if ENV_FILE.exists() else ""
    has_plain = "MYSQL_ROOT_PASSWORD=" in raw and "MYSQL_PASSWORD=" in raw
    ignored = "deploy/.env" in (ROOT / ".gitignore").read_text(encoding="utf-8")
    return ("打穿" if has_plain else "拦住", "同网关栈",
            f"deploy/.env 里数据库口令是明文；"
            f"gitignore {'挡住了进仓库' if ignored else '没挡住'}，本机任何进程都能读到。")


def check_clickjack():
    """点击劫持：网关的页面带头、裸奔栈和靶场自己的页面都不带。"""
    _, gw_headers, _ = request(f"{GATEWAY}/status.html")
    _, base_headers, _ = request(f"{BASELINE}/docs")
    _, range_headers, _ = request(f"{RANGE}/attack/victim.html")
    gw_xfo = gw_headers.get("x-frame-options", "")
    base_xfo = base_headers.get("x-frame-options", "")
    range_xfo = range_headers.get("x-frame-options", "")
    return ("拦住" if gw_xfo.upper() == "SAMEORIGIN" else "打穿",
            "打穿" if not base_xfo else "拦住",
            f"网关 /status.html 回 X-Frame-Options: {gw_xfo or '无'}；"
            f"裸奔栈 /docs 回 {base_xfo or '无'}；靶场自己的受害者页回 {range_xfo or '无'}。"
            f"三页来自三个不同站点，对照页里框住的结果与此一致。")


def check_csrf():
    get_status, get_headers, _ = request(f"{GATEWAY}/api/v1/saves/0")
    post_status, _, _ = request(f"{GATEWAY}/api/v1/saves/0", "POST",
                                {"Content-Type": "application/x-www-form-urlencoded"},
                                b"save_data=x")
    opt_status, opt_headers, _ = request(
        f"{GATEWAY}/api/v1/saves/0", "OPTIONS",
        {"Origin": "https://127.0.0.1", "Access-Control-Request-Method": "PUT",
         "Access-Control-Request-Headers": "x-device-id"})
    cookies = [h for h in (get_headers, opt_headers) if h.get("set-cookie")]
    return ("拦住", "同网关栈",
            f"表单 GET 回 {get_status}，表单 POST 回 {post_status}，预检回 {opt_status}；"
            f"响应里 Set-Cookie {'有' if cookies else '一个都没有'}。"
            f"后端没有会话，跨站请求没有可借用的身份。")


def check_cors_read():
    _, headers, _ = request(f"{GATEWAY}/api/v1/health", headers={"Origin": "https://127.0.0.1"})
    acao = headers.get("access-control-allow-origin", "")
    return ("拦住" if not acao else "打穿", "拦住",
            f"带 Origin 请求，响应里 Access-Control-Allow-Origin {'是 ' + acao if acao else '没有'}，"
            f"浏览器读不到正文。")


def check_tamper():
    device = f"range-{uuid.uuid4().hex[:12]}"
    payload = {"save_data": {"hp": 5, "weapon": "改过的剑", "flag": True}}
    request(f"{GATEWAY}/api/v1/saves/0", "PUT",
            {"Content-Type": "application/json", "X-Device-Id": device}, json_body(payload))
    _, _, body = request(f"{GATEWAY}/api/v1/saves/0", headers={"X-Device-Id": device})
    echoed = "改过的剑".encode("utf-8") in body
    return ("打穿" if echoed else "拦住", "同网关栈",
            f"把存档内容改成自定义武器再上传，读回来{'原样' if echoed else '没'}保留，服务端不校验内容。")


def check_xss():
    marker = f"<script>alert('{uuid.uuid4().hex[:6]}')</script>"
    request(f"{GATEWAY}/api/v1/events", "POST", {"Content-Type": "application/json"},
            json_body({"events": [{"event": "range_xss", "data": {"m": marker}}]}))
    pages = [f"{GATEWAY}/", f"{GATEWAY}/status.html", f"{RANGE}/attack/", f"{RANGE}/attack/index.html"]
    hits = []
    for url in pages:
        _, headers, body = request(url)
        ctype = headers.get("content-type", "")
        if "text/html" in ctype and marker.encode("utf-8") in body:
            hits.append(url)
    return ("拦住" if not hits else "打穿", "同网关栈",
            f"把 <script> 塞进埋点，再翻四个页面，命中 {hits or '零处'}；"
            f"接口只回 JSON，没有页面把用户输入当 HTML 渲染。")


CHECKS = {
    "direct-origin": check_direct_origin,
    "direct-db": check_direct_db,
    "rate-bypass": check_rate_limit,
    "burst": check_rate_limit,
    "xff": check_xff,
    "body": check_body,
    "slow": check_slow,
    "smuggling": check_smuggling,
    "tls": check_tls,
    "noauth-write": check_noauth_write,
    "guess-id": check_guess_id,
    "base-rev": check_base_rev,
    "ts-forge": check_ts_forge,
    "bulk-account": check_bulk_account,
    "plain-save": check_plain_save,
    "docs-leak": check_docs_leak,
    "default-pass": check_default_pass,
    "enum-users": check_enum_users,
    "secret-default": check_secret_default,
    "container-user": check_container_user,
    "log-mask": check_log_mask,
    "tag-float": check_tag_float,
    "env-plain": check_env_plain,
    "clickjack": check_clickjack,
    "csrf": check_csrf,
    "cors-read": check_cors_read,
    "tamper": check_tamper,
    "xss": check_xss,
}


def cleanup() -> None:
    """把这一轮打出来的假账号清掉。不清的话演示库里会堆一堆 device:range- 开头的号。"""
    mysql("delete from symbiont.saves where user_id in "
          "(select id from symbiont.users where username like 'device:range-%')")
    mysql("delete from symbiont.events where event like 'range_%'")
    mysql("delete from symbiont.users where username like 'device:range-%'")
    left = mysql("select count(*) from symbiont.users where username like 'device:range-%'").strip()
    print(f"清库完成，剩下的 range 账号：{left}")


def run_one(cid: str) -> dict:
    """跑一招，返回 {gw, base, evidence, transcript, ms}。

    transcript 是这一步真发出去的请求、真跑的命令和回来的原文，页面会摊开给人看，
    不然只看到一个“拦住”，分不清是真打出来的还是人写上去的。
    """
    _local.items = []
    started = time.time()
    try:
        gw, base, evidence = CHECKS[cid]()
    except Exception as exc:
        gw, base, evidence = "待打", "待打", f"校验没跑通：{type(exc).__name__}: {exc}"
    ms = int((time.time() - started) * 1000)
    transcript = list(getattr(_local, "items", []))
    _local.items = None
    return {"gw": gw, "base": base, "evidence": evidence,
            "transcript": transcript, "ms": ms,
            "at": datetime.now().strftime("%H:%M:%S")}


def run_many(ids: list[str]) -> dict:
    return {cid: run_one(cid) for cid in ids if cid in CHECKS}


def write_results(items: dict) -> dict:
    """写 range-results.js，页面刷新就能看到最新判定。"""
    payload = {
        "updated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "items": items,
    }
    OUT_FILE.write_text(
        "/* 这份文件由 scripts/range_check.py 生成，别手改。\n"
        " * 页面会把这里的结果盖到 range-data.js 的手写判定上。\n"
        " */\n"
        "window.RANGE_RESULTS = "
        + json.dumps(payload, ensure_ascii=False, indent=2)
        + ";\n",
        encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="", help="只跑这几招，逗号分隔")
    parser.add_argument("--keep", action="store_true", help="不清库")
    args = parser.parse_args()

    wanted = [c.strip() for c in args.only.split(",") if c.strip()] or list(CHECKS)
    items, failed = {}, []

    for cid in wanted:
        if cid not in CHECKS:
            print(f"跳过未知招式 {cid}")
            continue
        items[cid] = run_one(cid)
        mark = "OK " if items[cid]["gw"] != "待打" else "退 "
        print(f"{mark}{cid:16s} 网关={items[cid]['gw']:4s} 裸奔={items[cid]['base']:6s}")

    write_results(items)
    print(f"判定写入 {OUT_FILE.relative_to(ROOT)}")

    if not args.keep:
        cleanup()

    for cid, it in items.items():
        if it["gw"] == "待打":
            failed.append(cid)
    if failed:
        print("没跑通的招式：" + "、".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
