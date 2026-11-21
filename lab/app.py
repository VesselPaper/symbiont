"""课堂演示用的存档服务。

这是给台上演示用的站，内容照着项目里真有的东西做：设备 id、三个存档槽、排行榜、昵称。
不是游戏世界观里的角色扮演，也不设关卡和 flag。

故意留的洞，一共五处：
    1. 排行榜搜索拼 SQL       —— 注入，输 ' OR '1'='1' -- 把所有人拖出来
    2. 昵称原样回显           —— 存储型 XSS，改个昵称就带上脚本
    3. 存档只认 device 参数    —— 越权，把 device 换成别人的就读到别人的存档
    4. 改昵称没有令牌、还能 GET —— CSRF，跨站一条链接就改掉
    5. 后台不校验             —— 未授权访问，全部设备和存档都看得到

身份就是设备 id，跟客户端一个思路：第一次进来种一个 cookie，之后按它认人。
数据库用 SQLite 放在 /tmp，容器重启就回到初始状态。
"""
import html
import json
import os
import sqlite3
from urllib.parse import parse_qs

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse

DB_PATH = os.environ.get("LAB_DB", "/tmp/lab.db")
DEFAULT_DEVICE = "alice-0001"

SEED = [
    ("alice-0001", "alice", 1200, '{"hp": 5, "floor": 2, "weapon": "铁剑"}'),
    ("bob-0002", "bob", 900, '{"hp": 2, "floor": 3, "weapon": "断刃"}'),
    ("admin-0003", "admin", 5000, '{"hp": 5, "floor": 3, "weapon": "长矛"}'),
]

app = FastAPI(title="共生之缚 云端存档", docs_url=None, redoc_url=None, openapi_url=None)


def db() -> sqlite3.Connection:
    return sqlite3.connect(DB_PATH)


def init_db() -> None:
    conn = db()
    conn.executescript(
        """
        create table if not exists devices (
            device_id text primary key,
            nickname text,
            score integer default 0
        );
        create table if not exists saves (
            device_id text,
            slot integer,
            data text,
            updated_at text default current_timestamp,
            primary key (device_id, slot)
        );
        """
    )
    for device_id, nickname, score, data in SEED:
        conn.execute("insert or ignore into devices (device_id, nickname, score) values (?, ?, ?)",
                     (device_id, nickname, score))
        conn.execute("insert or ignore into saves (device_id, slot, data) values (?, 0, ?)",
                     (device_id, data))
    conn.commit()
    conn.close()


@app.on_event("startup")
def on_startup() -> None:
    init_db()


def device_of(request: Request) -> str:
    return request.cookies.get("device", "")


def page(title: str, body: str, device: str) -> str:
    who = f'设备 {html.escape(device)}' if device else '还没有设备 id'
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · 共生之缚 云端存档</title>
<style>
  /* 存档服务是给观众看的产品，暖色、圆角、沙地纸面这一路。
     靶场那套是黑底等宽的演示台，两边风格刻意分开。 */
  * {{ box-sizing: border-box; }}
  body {{ margin:0; background:#e8dcc7; color:#2e2a22; position:relative;
         font:16px/1.85 "Segoe UI","Microsoft YaHei",system-ui,sans-serif; }}
  body::after {{ content:""; position:fixed; inset:0; pointer-events:none; opacity:.04;
    background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='140' height='140'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='2'/></filter><rect width='140' height='140' filter='url(%23n)'/></svg>"); }}
  header {{ background:#606c38; color:#f3eada; padding:20px 34px 22px;
           display:flex; justify-content:space-between; align-items:center;
           border-radius:0 0 30px 30px; }}
  header a {{ color:#f3eada; text-decoration:none; border-bottom:1px solid rgba(243,234,218,.45); }}
  header .brand {{ font-family:Georgia,"Songti SC",serif; font-size:19px; letter-spacing:.06em; }}
  main {{ max-width:900px; margin:0 auto; padding:38px 26px 72px; }}
  h1 {{ font-family:Georgia,"Songti SC",serif; font-size:30px; font-weight:600;
        letter-spacing:.02em; margin:0 0 24px; }}
  h2 {{ font-family:Georgia,"Songti SC",serif; font-size:19px; margin:32px 0 12px; }}
  p {{ margin:0 0 14px; }}
  a {{ color:#a8542c; text-decoration:none; border-bottom:1px solid rgba(168,84,44,.35); }}
  a:hover {{ border-bottom-color:#a8542c; }}
  input[type=text], input[type=password], textarea {{ font:inherit; padding:12px 14px; width:100%;
        border:1px solid #cdb897; border-radius:12px; background:#fbf5e9; color:#2e2a22; }}
  textarea {{ min-height:110px; resize:vertical; }}
  input:focus, textarea:focus, button:focus-visible {{ outline:2px solid #c66b3d; outline-offset:2px; }}
  button {{ font:inherit; padding:12px 22px; border:0; border-radius:999px;
            background:#c66b3d; color:#fdf7ec; cursor:pointer; }}
  button:hover {{ background:#ad5730; }}
  .card {{ background:#f3eada; border:1px solid #dccdae; border-radius:20px;
           padding:22px 24px; margin:16px 0; }}
  .muted {{ color:#7d7364; }}
  table {{ border-collapse:separate; border-spacing:0; width:100%; background:#f7f0e1;
           border:1px solid #dccdae; border-radius:16px; overflow:hidden; }}
  th, td {{ border-bottom:1px solid #e4d7bd; padding:11px 14px; text-align:left; }}
  th {{ background:#ede0c9; font-weight:600; }}
  tr:last-child td {{ border-bottom:0; }}
  code {{ background:#ede0c9; padding:1px 6px; border-radius:6px; }}
  ul {{ padding-left:20px; }}
  li {{ margin:6px 0; }}
  .tiles {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr));
            gap:14px; margin:24px 0 8px; }}
  .tile {{ display:block; background:#f3eada; border:1px solid #dccdae; border-radius:20px;
           padding:24px 24px; font-size:17px; color:#2e2a22; border-bottom:1px solid #dccdae;
           transition:transform .15s ease, background .15s ease; }}
  .tile:hover {{ background:#f7f0e1; transform:translateY(-2px); border-bottom-color:#dccdae; }}
</style>
</head>
<body>
<header><span class="brand">共生之缚 · 云端存档</span><span>{who}</span></header>
<main>{body}</main>
</body>
</html>"""


def respond(html_text: str, device: str) -> HTMLResponse:
    resp = HTMLResponse(html_text)
    if device:
        resp.set_cookie("device", device, httponly=False)
    return resp


@app.get("/healthz", include_in_schema=False)
def healthz() -> dict:
    return {"status": "ok", "service": "symbiont-lab"}


@app.get("/", response_class=HTMLResponse)
def home(request: Request) -> HTMLResponse:
    device = device_of(request) or DEFAULT_DEVICE
    conn = db()
    rows = conn.execute("select slot, data, updated_at from saves where device_id = ? order by slot",
                        (device,)).fetchall()
    conn.close()
    slots = "".join(
        f'<div class="card"><p class="muted">槽位 {r[0]} · {html.escape(str(r[2]))}</p>'
        f"<pre style=\"margin:0\">{html.escape(str(r[1]))}</pre></div>" for r in rows
    ) or '<p class="muted">这台设备还没有存档。</p>'
    body = f"""
<h1>云端存档</h1>
<div class="tiles">
  <a class="tile" href="/rank">排行榜</a>
  <a class="tile" href="/nickname">改昵称</a>
  <a class="tile" href="/save?slot=0">槽位 0</a>
</div>
<h2>我的存档</h2>
{slots}
<p class="muted">设备 id：{html.escape(device)}</p>
"""
    return respond(page("云端存档", body, device), device)


@app.get("/rank", response_class=HTMLResponse)
def rank(request: Request) -> HTMLResponse:
    device = device_of(request) or DEFAULT_DEVICE
    q = request.query_params.get("q", "")
    rows, error = [], ""
    conn = db()
    try:
        if q:
            # 故意拼接：输 ' OR '1'='1' -- 能把所有设备拖出来
            sql = (f"select d.device_id, d.nickname, d.score from devices d "
                   f"where d.nickname like '%{q}%' order by d.score desc")
        else:
            # 没有搜索词就按分数列全员。排行榜本来一打开就该有人，
            # 存储型 XSS 也正是靠这一页被看见的
            sql = ("select d.device_id, d.nickname, d.score from devices d "
                   "order by d.score desc")
        rows = conn.execute(sql).fetchall()
    except sqlite3.Error as exc:
        error = str(exc)
    finally:
        conn.close()
    table = ""
    if rows:
        # 昵称故意不转义：存储型 XSS 就出在这一列
        table = "<table><tr><th>昵称</th><th>设备</th><th>分数</th></tr>" + "".join(
            f"<tr><td>{r[1]}</td><td>{html.escape(str(r[0]))}</td><td>{r[2]}</td></tr>"
            for r in rows
        ) + "</table>"
    elif q:
        table = "<p>没有匹配的玩家。</p>"
    body = f"""
<h1>排行榜</h1>
<div class="card">
  <form method="get" action="/rank">
    <p><input type="text" name="q" value="{html.escape(q)}" placeholder="按昵称找"></p>
    <p><button>搜索</button></p>
  </form>
</div>
{('<div class="card">SQL 报错：' + html.escape(error) + '</div>') if error else ''}
<div class="card">{table or '<span class="muted">还没有搜过。</span>'}</div>
"""
    return respond(page("排行榜", body, device), device)


@app.get("/nickname", response_class=HTMLResponse)
def nickname(request: Request) -> HTMLResponse:
    """改昵称只有一个入口：带 name 就直接改，不带就显示表单。

    故意做成：没有令牌、不看来源、而且 GET 也能改。
    GET 是关键：SameSite=lax 允许跨站的顶层 GET 导航带上 cookie，一条链接就够。
    """
    device = device_of(request) or DEFAULT_DEVICE
    name = request.query_params.get("name", "")
    if name:
        conn = db()
        conn.execute("update devices set nickname = ? where device_id = ?", (name, device))
        conn.commit()
        conn.close()
        body = f"""
<h1>改昵称</h1>
<div class="card">已把昵称改成 {html.escape(name)}。</div>
<p><a href="/rank">去排行榜看看</a></p>
"""
        return respond(page("改昵称", body, device), device)
    conn = db()
    row = conn.execute("select nickname from devices where device_id = ?", (device,)).fetchone()
    conn.close()
    current = row[0] if row else ""
    body = f"""
<h1>改昵称</h1>
<p>当前昵称：{html.escape(str(current))}</p>
<div class="card">
  <form method="post" action="/nickname">
    <p><input type="text" name="name" placeholder="新昵称"></p>
    <p><button>保存</button></p>
  </form>
</div>
"""
    return respond(page("改昵称", body, device), device)


@app.post("/nickname")
async def nickname_post(request: Request) -> HTMLResponse:
    device = device_of(request) or DEFAULT_DEVICE
    raw = (await request.body()).decode("utf-8")
    name = parse_qs(raw).get("name", [""])[0]
    conn = db()
    conn.execute("update devices set nickname = ? where device_id = ?", (name, device))
    conn.commit()
    conn.close()
    body = f"""
<h1>改昵称</h1>
<div class="card">已把昵称改成 {html.escape(name)}。</div>
<p><a href="/rank">去排行榜看看</a></p>
"""
    return respond(page("改昵称", body, device), device)


@app.get("/save", response_class=HTMLResponse)
def save(request: Request) -> HTMLResponse:
    """存档页只认 URL 里的 device，不跟 cookie 对，所以换成别人的 id 就能读别人的存档。"""
    me = device_of(request) or DEFAULT_DEVICE
    device = request.query_params.get("device", me)
    slot = request.query_params.get("slot", "0")
    conn = db()
    row = conn.execute("select data, updated_at from saves where device_id = ? and slot = ?",
                       (device, slot)).fetchone()
    conn.close()
    content = html.escape(str(row[0])) if row else ""
    body = f"""
<h1>存档</h1>
<div class="card">
  <form method="post" action="/save?slot={html.escape(slot)}&device={html.escape(device)}">
    <p><textarea name="data">{content}</textarea></p>
    <p><button>保存</button></p>
  </form>
</div>
<p class="muted">{'读到 ' + html.escape(device) + ' 的槽位 ' + html.escape(slot) if row else '这个槽位是空的'}</p>
"""
    return respond(page("存档", body, me), me)


@app.post("/save")
async def save_post(request: Request) -> RedirectResponse:
    device = request.query_params.get("device", device_of(request) or DEFAULT_DEVICE)
    slot = request.query_params.get("slot", "0")
    raw = (await request.body()).decode("utf-8")
    data = parse_qs(raw).get("data", [""])[0]
    conn = db()
    conn.execute("insert into saves (device_id, slot, data) values (?, ?, ?) "
                 "on conflict(device_id, slot) do update set data = excluded.data, "
                 "updated_at = current_timestamp", (device, slot, data))
    conn.commit()
    conn.close()
    return RedirectResponse(f"/save?slot={slot}&device={device}", status_code=303)


@app.get("/admin", response_class=HTMLResponse)
def admin(request: Request) -> HTMLResponse:
    """后台页故意不校验：全部设备和存档都能看。"""
    device = device_of(request) or DEFAULT_DEVICE
    conn = db()
    rows = conn.execute(
        "select d.device_id, d.nickname, d.score, count(s.slot) "
        "from devices d left join saves s on s.device_id = d.device_id "
        "group by d.device_id order by d.score desc"
    ).fetchall()
    conn.close()
    table = "".join(
        f"<tr><td>{html.escape(str(r[0]))}</td><td>{html.escape(str(r[1]))}</td>"
        f"<td>{r[2]}</td><td>{r[3]}</td></tr>" for r in rows
    )
    body = f"""
<h1>后台</h1>
<div class="card">
  <table>
    <tr><th>设备</th><th>昵称</th><th>分数</th><th>存档数</th></tr>
    {table}
  </table>
</div>
"""
    return respond(page("后台", body, device), device)
