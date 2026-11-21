"""并发打一次站，数状态码，用来量限流到底拦住了多少。

为什么用线程加 http.client 而不是 requests：本机 python 没装 requests，
而这件事只需要拿状态码，不值得为它装依赖。

    python tmp/measure_rate.py https://localhost/api/v1/health 40
"""
import http.client
import ssl
import sys
import threading
from urllib.parse import urlparse

url = sys.argv[1] if len(sys.argv) > 1 else "https://localhost/api/v1/health"
total = int(sys.argv[2]) if len(sys.argv) > 2 else 40

u = urlparse(url)
hostname, port, path = u.hostname, u.port or 443, u.path or "/"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

statuses = []
gate = threading.Barrier(total)


def one() -> None:
    gate.wait()  # 卡在同一刻一起放，不然线程起得慢，压力打不出来
    conn = http.client.HTTPSConnection(hostname, port, context=ctx, timeout=30)
    try:
        conn.request("GET", path)
        statuses.append(conn.getresponse().status)
    except Exception as exc:  # 连不上也算一种结果，别让整批静默丢
        statuses.append(str(exc))
    finally:
        conn.close()


threads = [threading.Thread(target=one) for _ in range(total)]
for t in threads:
    t.start()
for t in threads:
    t.join()

counts = {}
for s in statuses:
    counts[s] = counts.get(s, 0) + 1
for code in sorted(counts, key=str):
    print(f"{code}\t{counts[code]}")
