"""明文 / 密文对照工具：一个只会"顺手把看到的字节打出来"的 TCP 中继。

它扮演的是链路上一个不怀好意（或者只是好奇）的中间节点。
用它就能把"加没加 TLS"这件事变成屏幕上看得见的两段输出，不需要抓包软件。

用法：

    # 终端 A：把 18100 的流量原样转到 18000（baseline 的明文后端）
    python deploy/tap.py --listen 18100 --target 18000

    # 终端 B：走中继访问
    curl -s http://localhost:18100/api/v1/health
    # 终端 A 会直接打印出明文请求行、头和 JSON 正文

    # 换成 TLS 一侧再看一遍
    python deploy/tap.py --listen 1443 --target 443
    curl -sk https://localhost:1443/api/v1/health
    # 这次终端 A 只能打印出乱码——因为它看不到 TLS 里面的东西

注意：只用来演示，别把真流量往上接。
"""
from __future__ import annotations

import argparse
import socket
import sys
import threading

MAX_PRINT = 600  # 单段最多打印多少字节，够看就行，免得刷屏


def pump(src: socket.socket, dst: socket.socket, label: str, dump: bool) -> None:
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            if dump:
                show(data, label)
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.close()
            except OSError:
                pass


def show(data: bytes, label: str) -> None:
    """能当文本看就当文本看，看不出来就直说它是二进制。"""
    chunk = data[:MAX_PRINT]
    try:
        text = chunk.decode("utf-8")
    except UnicodeDecodeError:
        text = None

    printable = text is not None and all(c.isprintable() or c in "\r\n\t" for c in text)

    print(f"\n--- {label}（{len(data)} 字节）---")
    if printable:
        print(text.strip() or "（空）")
    else:
        hexed = " ".join(f"{b:02x}" for b in chunk[:64])
        print(f"二进制，不是能读的文本。前 64 字节：\n{hexed}")
        print("……里面是 TLS 加密之后的内容，中继看不到明文。")


def handle(client: socket.socket, target_host: str, target_port: int) -> None:
    try:
        upstream = socket.create_connection((target_host, target_port), timeout=10)
    except OSError as exc:
        print(f"连不上目标 {target_host}:{target_port} —— {exc}")
        client.close()
        return

    print(f"\n=== 新连接 {client.getpeername()} -> {target_host}:{target_port} ===")
    t1 = threading.Thread(target=pump, args=(client, upstream, "客户端 → 服务端", True), daemon=True)
    t2 = threading.Thread(target=pump, args=(upstream, client, "服务端 → 客户端", True), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()


def main() -> int:
    # 输出被重定向到文件或管道时 Python 会缓冲，演示里看着像"没反应"。强制逐行刷新。
    sys.stdout.reconfigure(line_buffering=True)

    ap = argparse.ArgumentParser(description="明文/密文对照用的 TCP 中继")
    ap.add_argument("--listen", type=int, required=True, help="本机监听端口")
    ap.add_argument("--target", type=int, required=True, help="转发到本机哪个端口")
    ap.add_argument("--host", default="127.0.0.1", help="目标主机，默认本机")
    args = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.listen))
    srv.listen(16)

    print(f"中继已就绪：127.0.0.1:{args.listen} -> {args.host}:{args.target}")
    print("另开一个终端发请求，这边的输出就是链路上能看见的东西。Ctrl+C 结束。\n")

    try:
        while True:
            client, _ = srv.accept()
            threading.Thread(target=handle, args=(client, args.host, args.target), daemon=True).start()
    except KeyboardInterrupt:
        print("\n已停止。")
    finally:
        srv.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
