"""靶场演示服务：页面上点一下，就在宿主机上把那招打一遍。

为什么要有它：组长演示时不想敲命令，只要点按钮。浏览器自己发不出这些请求
（要伪造 X-Forwarded-For、要灌 5 兆、要看 TCP 什么时候断），也看不到 docker 和库里的东西，
所以这些活交给宿主机上的这个进程，页面用 fetch 调它。

只绑 127.0.0.1，不对外。跨源只放行靶场页面那两个地址。

    python scripts/range_control.py
    # 页面 http://127.0.0.1:18080/attack/
"""
import json
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import range_check as rc  # noqa: E402

HOST, PORT = "127.0.0.1", 18082
ALLOWED_ORIGINS = {"http://127.0.0.1:18080", "http://localhost:18080"}
JSON_HEADERS = {"Content-Type": "application/json; charset=utf-8"}


def load_existing() -> dict:
    """把上次跑出来的判定读回来，单招重打时只覆盖那一招，别的保持不动。"""
    if not rc.OUT_FILE.exists():
        return {}
    text = rc.OUT_FILE.read_text(encoding="utf-8")
    start = text.find("{")
    end = text.rfind("};")
    if start < 0 or end < 0:
        return {}
    try:
        return json.loads(text[start:end + 1]).get("items", {})
    except json.JSONDecodeError:
        return {}


class Handler(BaseHTTPRequestHandler):
    def _cors(self) -> None:
        origin = self.headers.get("Origin", "")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
        else:
            self.send_header("Access-Control-Allow-Origin", "null")

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self._cors()
        for k, v in JSON_HEADERS.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/status":
            self._send(200, {"ok": True, "checks": list(rc.CHECKS)})
        else:
            self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        try:
            if path == "/run/all":
                items = rc.run_many(list(rc.CHECKS))
                rc.write_results(items)
                rc.cleanup()
                self._send(200, {"ok": True, "items": items, "updated": "now"})
                return
            if path.startswith("/run/"):
                cid = path[len("/run/"):]
                if cid not in rc.CHECKS:
                    self._send(404, {"ok": False, "error": f"没有这一招：{cid}"})
                    return
                item = rc.run_one(cid)
                items = load_existing()
                items[cid] = item
                rc.write_results(items)
                self._send(200, {"ok": True, "id": cid, **item})
                return
            if path == "/xff":
                # 同一招打到三座栈上，把回显的来源摆在一起，现场不用敲 curl
                spoof = {"X-Forwarded-For": "6.6.6.6"}
                out = {}
                for name, base in (("now", rc.GATEWAY), ("before", rc.BEFORE_XFF),
                                   ("baseline", rc.BASELINE)):
                    try:
                        _, _, body = rc.request(base + "/api/v1/health",
                                                headers=spoof, timeout=5, retry=1)
                        out[name] = json.loads(body).get("client_ip", "")
                    except Exception as exc:
                        out[name] = f"没起（{type(exc).__name__}）"
                self._send(200, {"ok": True, **out})
                return
            if path == "/cleanup":
                rc.cleanup()
                self._send(200, {"ok": True})
                return
            self._send(404, {"ok": False, "error": "not found"})
        except Exception as exc:  # 演示服务不能因为一招崩掉就整个断
            self._send(500, {"ok": False, "error": f"{type(exc).__name__}: {exc}"})

    def log_message(self, fmt, *args):  # 默认每个请求打一行，演示时刷屏
        pass


if __name__ == "__main__":
    print(f"演示服务在 http://{HOST}:{PORT}，页面点按钮就用它", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
