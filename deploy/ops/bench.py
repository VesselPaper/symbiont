"""网关实测：并发打一批请求，统计状态码与后端分布。

只用标准库，不装依赖。演示时直接跑这个，比截图可信。

    python deploy/bench.py                        # 默认并发 40，打 https://localhost
    python deploy/bench.py --mode seq --n 12      # 依次请求，看分流是否均匀
    python deploy/bench.py --n 200 --concurrency 40

输出三段：状态码分布、每台后端命中次数、耗时 p50 / p95。
"""
from __future__ import annotations

import argparse
import json
import ssl
import statistics
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

DEFAULT_URL = "https://localhost/api/v1/health"


def _ssl_context() -> ssl.SSLContext:
    """自签证书不该让压测失败：这里只验证加密，不验证证书链。

    演示环境是本机自签；换成真证书后可以把这个 context 去掉。
    """
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def one(url: str, ctx: ssl.SSLContext) -> dict:
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(url, context=ctx, timeout=10) as resp:
            body = resp.read()
            code = resp.status
            upstream = resp.headers.get("X-Upstream", "")
    except urllib.error.HTTPError as exc:
        body = exc.read()
        code = exc.code
        upstream = exc.headers.get("X-Upstream", "")
    except Exception as exc:  # 连不上、超时、TLS 失败
        return {"code": 0, "ms": 0.0, "instance": "", "upstream": "", "error": str(exc)}

    ms = (time.perf_counter() - start) * 1000
    instance = ""
    try:
        instance = json.loads(body).get("instance", "")
    except Exception:
        pass
    return {"code": code, "ms": ms, "instance": instance, "upstream": upstream, "error": ""}


def run(url: str, n: int, concurrency: int, mode: str, gap: float) -> list[dict]:
    ctx = _ssl_context()
    if mode == "seq":
        out = []
        for _ in range(n):
            out.append(one(url, ctx))
            time.sleep(gap)
        return out
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        return list(pool.map(lambda _: one(url, ctx), range(n)))


def report(results: list[dict]) -> int:
    total = len(results)
    codes: dict[int, int] = {}
    nodes: dict[str, int] = {}
    latencies = []
    errors = []

    for r in results:
        codes[r["code"]] = codes.get(r["code"], 0) + 1
        if r["code"] == 200:
            latencies.append(r["ms"])
            key = r["instance"] or "（未标注实例）"
            nodes[key] = nodes.get(key, 0) + 1
        elif r["error"]:
            errors.append(r["error"])

    print(f"\n请求数 {total}\n")

    print("状态码")
    for code in sorted(codes):
        label = "连不上" if code == 0 else str(code)
        print(f"  {label:<6} {codes[code]:>4} 次")

    ok = codes.get(200, 0)
    print(f"\n成功率 {ok}/{total} = {ok / total * 100:.0f}%")

    if nodes:
        print("\n后端分布（只看成功的请求）")
        for name in sorted(nodes):
            bar = "#" * nodes[name]
            print(f"  {name:<8} {nodes[name]:>4} 次  {bar}")

    if latencies:
        print("\n耗时")
        print(f"  p50 {statistics.median(latencies):.0f} ms")
        if len(latencies) >= 20:
            p95 = sorted(latencies)[int(len(latencies) * 0.95) - 1]
            print(f"  p95 {p95:.0f} ms")
        print(f"  最快 {min(latencies):.0f} ms / 最慢 {max(latencies):.0f} ms")

    if errors:
        print("\n连接异常（前 3 条）")
        for msg in errors[:3]:
            print(f"  {msg}")

    print()
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="网关实测：状态码、后端分布、耗时")
    ap.add_argument("--url", default=DEFAULT_URL, help=f"目标地址，默认 {DEFAULT_URL}")
    ap.add_argument("--n", type=int, default=40, help="请求总数，默认 40")
    ap.add_argument("--concurrency", type=int, default=20, help="并发线程数，默认 20")
    ap.add_argument("--mode", choices=["burst", "seq"], default="burst", help="burst 并发 / seq 依次")
    ap.add_argument("--gap", type=float, default=0.15, help="seq 模式下每次间隔秒数，默认 0.15")
    args = ap.parse_args(argv)

    print(f"目标 {args.url}  模式 {args.mode}  共 {args.n} 次", end="")
    if args.mode == "burst":
        print(f"  并发 {args.concurrency}")
    else:
        print(f"  间隔 {args.gap}s")

    results = run(args.url, args.n, args.concurrency, args.mode, args.gap)
    return report(results)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
