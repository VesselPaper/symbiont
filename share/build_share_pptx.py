"""生成技术分享 PPT：Web 访问安全中的应用代理与负载均衡（以《共生之缚》Web 入口为例）。

设计约定：
- 16:9，深底冷青，和游戏 UI 同一套色；每页一句话主旨，字少图大。
- 数字全部来自 share/应用代理与负载均衡-技术报告.md 的实测记录和本仓库配置，不编。
"""

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pathlib import Path

ROOT = Path(__file__).resolve().parent

BG = RGBColor(0x0B, 0x11, 0x14)
CARD = RGBColor(0x13, 0x1C, 0x21)
CYAN = RGBColor(0x5F, 0xD6, 0xD0)
BONE = RGBColor(0xD8, 0xCF, 0xA8)
WHITE = RGBColor(0xE6, 0xEE, 0xEF)
MUTED = RGBColor(0x8E, 0x9E, 0xA2)
DIM = RGBColor(0x6B, 0x7A, 0x7E)
RED = RGBColor(0xD2, 0x7A, 0x6C)
GREEN = RGBColor(0x8F, 0xC9, 0x92)

FONT = "微软雅黑"
MONO = "Consolas"

W = Inches(13.333)
H = Inches(7.5)


def new_deck():
    prs = Presentation()
    prs.slide_width = W
    prs.slide_height = H
    return prs


def blank(prs):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    bg = slide.shapes.add_shape(1, 0, 0, W, H)
    bg.fill.solid()
    bg.fill.fore_color.rgb = BG
    bg.line.fill.background()
    bg.shadow.inherit = False
    return slide


def text(slide, x, y, w, h, s, size=15, color=WHITE, bold=False, font=FONT,
         align=PP_ALIGN.LEFT, line=1.35, anchor=MSO_ANCHOR.TOP):
    box = slide.shapes.add_textbox(x, y, w, h)
    tf = box.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    lines = s.split("\n")
    for i, ln in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.line_spacing = line
        r = p.add_run()
        r.text = ln
        r.font.size = Pt(size)
        r.font.bold = bold
        r.font.name = font
        r.font.color.rgb = color
    return box


def head(slide, kicker, title, sub=""):
    """页眉：节标记 + 主标题 + 一条冷青细线。"""
    if kicker:
        text(slide, Inches(0.85), Inches(0.52), Inches(11.5), Inches(0.3),
             kicker, 11, CYAN)
    text(slide, Inches(0.85), Inches(0.86), Inches(11.6), Inches(0.75),
         title, 27, WHITE, True)
    if sub:
        text(slide, Inches(0.85), Inches(1.59), Inches(11.6), Inches(0.34),
             sub, 13, RGBColor(0xC2, 0xCE, 0xD0))
    bar = slide.shapes.add_shape(1, Inches(0.85), Inches(1.50), Inches(0.62), Inches(0.035))
    bar.fill.solid()
    bar.fill.fore_color.rgb = CYAN
    bar.line.fill.background()
    bar.shadow.inherit = False
    return Inches(2.02)


def card(slide, x, y, w, h):
    box = slide.shapes.add_shape(1, x, y, w, h)
    box.fill.solid()
    box.fill.fore_color.rgb = CARD
    box.line.color.rgb = RGBColor(0x22, 0x30, 0x35)
    box.line.width = Pt(0.75)
    box.shadow.inherit = False
    return box


def table(slide, x, y, w, cols, rows, data, header=True, size=11.5, row_h=Inches(0.42)):
    total_h = Inches(0.42) * len(data)
    shape = slide.shapes.add_table(len(data), len(cols), x, y, w, total_h)
    tbl = shape.table
    for i, cw in enumerate(cols):
        tbl.columns[i].width = cw
    for r, row in enumerate(data):
        tbl.rows[r].height = row_h
        for c, val in enumerate(row):
            cell = tbl.cell(r, c)
            cell.margin_left = Inches(0.10)
            cell.margin_right = Inches(0.08)
            cell.margin_top = Inches(0.03)
            cell.margin_bottom = Inches(0.03)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            cell.fill.solid()
            if header and r == 0:
                cell.fill.fore_color.rgb = RGBColor(0x18, 0x24, 0x2A)
            else:
                cell.fill.fore_color.rgb = RGBColor(0x0F, 0x17, 0x1B) if r % 2 else RGBColor(0x13, 0x1C, 0x21)
            tf = cell.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.line_spacing = 1.0
            run = p.add_run()
            run.text = str(val)
            run.font.size = Pt(size)
            run.font.name = FONT
            run.font.bold = header and r == 0
            if header and r == 0:
                run.font.color.rgb = CYAN
            else:
                run.font.color.rgb = WHITE if c == 0 else MUTED
    return shape


def code(slide, x, y, w, h, s, size=11):
    box = card(slide, x, y, w, h)
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.18)
    tf.margin_top = Inches(0.14)
    tf.vertical_anchor = MSO_ANCHOR.TOP
    for i, ln in enumerate(s.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.line_spacing = 1.15
        r = p.add_run()
        r.text = ln
        r.font.size = Pt(size)
        r.font.name = MONO
        r.font.color.rgb = RGBColor(0xA8, 0xC6, 0xC8) if not ln.strip().startswith("#") else DIM
    return box


def big(slide, x, y, w, number, unit, label, color=BONE):
    text(slide, x, y, w, Inches(0.72), number, 40, color, True)
    if unit:
        text(slide, x + Inches(0.02), y + Inches(0.66), w, Inches(0.3), unit, 11, MUTED)
    text(slide, x, y + Inches(1.0), w, Inches(0.4), label, 12, MUTED)


# ---------------------------------------------------------------- 1 封面
def s_cover(prs):
    slide = blank(prs)
    line = slide.shapes.add_shape(1, Inches(0.9), Inches(2.06), Inches(1.1), Inches(0.05))
    line.fill.solid()
    line.fill.fore_color.rgb = CYAN
    line.line.fill.background()
    line.shadow.inherit = False

    text(slide, Inches(0.9), Inches(1.32), Inches(11.5), Inches(0.35),
         "2 组　软件工程课程设计　2026 年 11 月", 12, CYAN)
    text(slide, Inches(0.9), Inches(2.28), Inches(11.6), Inches(1.5),
         "Web 访问安全中的应用代理与负载均衡", 34, WHITE, True, line=1.25)
    text(slide, Inches(0.9), Inches(3.62), Inches(11.6), Inches(0.42),
         "以《共生之缚》的 Web 入口为例", 17, BONE)
    text(slide, Inches(0.9), Inches(5.55), Inches(11.0), Inches(1.1),
         "", 13, MUTED, line=1.55)
    return slide


# ---------------------------------------------------------------- 2 架构
def s_topology(prs):
    slide = blank(prs)
    head(slide, "现状", "我们的入口现在长这样",
         "")

    y = Inches(2.34)
    boxes = [
        (Inches(0.85),  "浏览器", "玩家打开的页面\n和游戏包", BONE),
        (Inches(3.35),  "网关 80 / 443", "TLS 终止　限流\n静态托管　反代", CYAN),
        (Inches(6.35),  "后端 ×3", "无状态 REST\n等价副本", WHITE),
        (Inches(9.05),  "MySQL", "账号　存档\n排行榜", MUTED),
    ]
    for x, name, desc, col in boxes:
        box = card(slide, x, y, Inches(2.05), Inches(1.55))
        text(slide, x + Inches(0.16), y + Inches(0.16), Inches(1.75), Inches(0.34),
             name, 15, col, True)
        text(slide, x + Inches(0.16), y + Inches(0.62), Inches(1.8), Inches(0.8),
             desc, 11, MUTED, line=1.4)

    for x in (Inches(2.95), Inches(5.95), Inches(8.55)):
        arrow = slide.shapes.add_shape(1, x, y + Inches(0.72), Inches(0.34), Inches(0.06))
        arrow.fill.solid()
        arrow.fill.fore_color.rgb = CYAN
        arrow.line.fill.background()
        arrow.shadow.inherit = False

    text(slide, Inches(0.85), Inches(4.35), Inches(11.6), Inches(0.9),
         "对外只开 80 和 443。后端 8000、数据库 3306 都不映射宿主机，从公网够不到它们。",
         15, WHITE, line=1.5)
    text(slide, Inches(0.85), Inches(4.95), Inches(11.6), Inches(0.9),
         "改造前不是这样：后端和数据库直接 publish 到宿主机，nginx 只有 22 行，只做了同源转发。",
         13, RED, line=1.5)
    text(slide, Inches(0.85), Inches(6.35), Inches(11.6), Inches(0.5),
         "三台后端是可选叠加层，默认部署只有一台；副本数是部署决策，不是代码。",
         12, DIM, line=1.4)
    return slide


# ---------------------------------------------------------------- 3 出发点
def s_why(prs):
    slide = blank(prs)
    head(slide, "出发点", "把后端直接开到公网上会发生什么")

    items = [
        ("明文", "HTTP 自己不加密，请求行、请求头、请求正文在链路上都是可读的。"
                 "登录请求带着账号密码，存档请求带着进度，经过任何一个中间节点都可能被留下记录。"),
        ("源站可被绕过", "很多部署把后端端口直接映射到宿主机。代理在不在都无关紧要，"
                       "攻击者绕开代理打后端，代理上的策略就全部失效。数据库端口一起暴露时风险更大。"),
        ("单点", "只有一台后端，它重启、升级，或者仅仅被一个慢请求拖住，服务就中断。"
                "这个问题跟访问量无关，哪怕一天只有三个用户。"),
    ]
    y = Inches(2.15)
    for i, (name, desc) in enumerate(items):
        box = card(slide, Inches(0.85), y, Inches(11.55), Inches(1.34))
        text(slide, Inches(1.05), y + Inches(0.17), Inches(2.1), Inches(0.34),
             name, 15, CYAN, True)
        text(slide, Inches(3.05), y + Inches(0.17), Inches(9.1), Inches(1.05),
             desc, 12.5, WHITE, line=1.45)
        y += Inches(1.52)

    text(slide, Inches(0.85), Inches(6.72), Inches(11.6), Inches(0.42),
         "这三件事对应两层不同的东西：前两个靠入口那一层解决，第三个才轮到负载均衡。",
         13, BONE, line=1.4)
    return slide


# ---------------------------------------------------------------- 4 七步
def s_seven_steps(prs):
    slide = blank(prs)
    head(slide, "原理", "一次请求穿过网关要经过七步",
         "写一个能转发的脚本，一百多行就够了。差距在第五步、第六步和超时体系上。")

    steps = [
        ("1", "接连接", "接受 TCP 连接，建立 TLS 会话", "listen 8443 ssl，TLSv1.2 与 1.3"),
        ("2", "解析报文", "方法、路径、Host、请求头", "七层代理才有这一步，四层看不到"),
        ("3", "决定路由", "按路径或主机名选处理方式", "根路径走静态，/api/ 走上游"),
        ("4", "改写头部", "补上游需要的来源信息", "X-Real-IP、X-Forwarded-For、X-Forwarded-Proto"),
        ("5", "建上游连接", "从地址池挑一台并连接", "upstream 加 least_conn 加 keepalive"),
        ("6", "转发与回传", "边收边转，不等响应结束", "默认流式，适合几十 MB 的 wasm 和 pck"),
        ("7", "收尾", "记耗时，处理超时与断连", "access_log，connect 5s / read 30s"),
    ]
    y = 2.04
    for num, name, desc, cfg in steps:
        text(slide, Inches(0.85), Inches(y), Inches(0.5), Inches(0.32), num, 16, CYAN, True)
        text(slide, Inches(1.4), Inches(y + 0.03), Inches(1.9), Inches(0.3), name, 13, WHITE, True)
        text(slide, Inches(3.3), Inches(y + 0.05), Inches(4.3), Inches(0.3), desc, 11.5, MUTED)
        text(slide, Inches(7.8), Inches(y + 0.06), Inches(4.6), Inches(0.3), cfg, 10.5, DIM, font=MONO)
        y += 0.64
    return slide

# ---------------------------------------------------------------- 5 连接复用
def s_keepalive(prs):
    slide = blank(prs)
    head(slide, "原理", "第五步和第六步是分水岭")

    text(slide, Inches(0.85), Inches(1.95), Inches(5.35), Inches(0.34),
         "连接复用", 14, CYAN, True)
    text(slide, Inches(0.85), Inches(2.36), Inches(5.35), Inches(1.5),
         "每个请求都重新和后端握手，握手开销会随并发升高迅速变大，"
         "还会在操作系统里留下大量等待关闭的连接。"
         "keepalive 让网关保持一组到后端的长连接，请求直接复用。",
         12, WHITE, line=1.55)

    text(slide, Inches(0.85), Inches(4.05), Inches(5.35), Inches(0.34),
         "超时要分层", 14, CYAN, True)
    text(slide, Inches(0.85), Inches(4.46), Inches(5.35), Inches(1.6),
         "连接超时、读超时、写超时分开设，才能区分“后端连不上”和“后端算得慢”。"
         "我们把连接压到五秒，读留三十秒：慢接口不该被当成故障，连不上才该立刻换一台。",
         12, WHITE, line=1.55)

    code(slide, Inches(6.55), Inches(1.95), Inches(5.9), Inches(2.95),
         "upstream symbiont_backend {\n"
         "    zone symbiont_backend 64k;\n"
         "    least_conn;\n"
         "    server server-1:8000 max_fails=2 fail_timeout=10s;\n"
         "    server server-2:8000 max_fails=2 fail_timeout=10s;\n"
         "    server server-3:8000 max_fails=2 fail_timeout=10s;\n"
         "    keepalive 16;\n"
         "}", 11)

    text(slide, Inches(6.55), Inches(5.12), Inches(5.9), Inches(1.4),
         "proxy_http_version 1.1 和 Connection 空值这两行不能少，"
         "否则 nginx 会退回短连接，keepalive 形同没写。",
         12, BONE, line=1.55)
    text(slide, Inches(0.85), Inches(6.55), Inches(11.6), Inches(0.6),
         "",
         12.5, DIM, line=1.4)
    return slide


# ---------------------------------------------------------------- 6 流式
def s_stream(prs):
    slide = blank(prs)
    head(slide, "原理", "96 MB 的包和网关内存",
         "把响应整体缓冲下来再发，意味着网关内存要装得下响应体。")

    big(slide, Inches(0.85), Inches(2.05), Inches(2.6), "58.3", "MB　游戏数据包 index.pck", "Godot 导出产物")
    big(slide, Inches(3.65), Inches(2.05), Inches(2.6), "37.7", "MB　引擎 index.wasm", "同一份导出")
    big(slide, Inches(6.45), Inches(2.05), Inches(2.6), "96.0", "MB　首屏要过的总量", "两个文件加起来", CYAN)
    big(slide, Inches(9.25), Inches(2.05), Inches(2.4), "0", "MB　网关内存增量", "docker stats 观察", GREEN)

    text(slide, Inches(0.85), Inches(3.55), Inches(5.35), Inches(0.34),
         "整块缓冲", 13, RED, True)
    text(slide, Inches(0.85), Inches(3.93), Inches(5.35), Inches(0.8),
         "内存要能装下整个响应体，包越大顶得越紧，首屏期间最容易出事。",
         12, WHITE, line=1.5)

    text(slide, Inches(6.75), Inches(3.55), Inches(5.6), Inches(0.34),
         "边收边转", 13, GREEN, True)
    text(slide, Inches(6.75), Inches(3.93), Inches(5.6), Inches(0.8),
         "占用的只是一块转发缓冲区，和文件大小无关。",
         12, WHITE, line=1.5)

    text(slide, Inches(0.85), Inches(4.45), Inches(11.6), Inches(1.2),
         "所以这个包里最重要的不是 96 MB 这个数，而是它过去的时候网关内存没有变化。"
         "如果网关先缓冲整个响应，这个包会把容器内存顶到上限，玩家看到的是首屏一直转圈。",
         14, WHITE, line=1.55)
    return slide


# ---------------------------------------------------------------- 7 zone
def s_zone(prs):
    slide = blank(prs)
    head(slide, "踩坑", "地址池要共享状态")

    text(slide, Inches(0.85), Inches(1.95), Inches(11.6), Inches(1.1),
         "upstream 不写 zone，每个 worker 会各算各的轮询计数。请求量小的时候，"
         "看起来就是全打在第一台上，明明三台都在跑。这个问题不加日志很难发现，"
         "因为服务本身一直是正常的。",
         14, WHITE, line=1.55)

    code(slide, Inches(0.85), Inches(3.2), Inches(5.65), Inches(1.5),
         "upstream symbiont_backend {\n"
         "    zone symbiont_backend 64k;   # 共享计数\n"
         "    least_conn;\n"
         "}", 11.5)

    code(slide, Inches(6.9), Inches(3.2), Inches(5.55), Inches(1.5),
         "# 观感上的差别\n"
         "无 zone：10 次请求可能 8 次落在第一台\n"
         "有 zone：10 次接近 4 / 3 / 3", 11.5)

    text(slide, Inches(0.85), Inches(5.1), Inches(5.6), Inches(1.5),
         "另一个跟 zone 无关但同类的问题：compose 项目名。两份编排放在同一个目录下，"
         "不写 name 会被当成同一个项目，起对照栈的时候把网关那套容器顶掉了。",
         12, MUTED, line=1.55)
    text(slide, Inches(6.9), Inches(5.1), Inches(5.55), Inches(1.5),
         "判断配置有没有生效，别看“服务是否可用”，看“三台的命中次数是否接近”。"
         "可用性永远是对的，分布才是配置在说话的证据。",
         12, BONE, line=1.55)
    return slide


# ---------------------------------------------------------------- 8 安全职责
def s_security(prs):
    slide = blank(prs)
    head(slide, "应用", "网关实际承担的职责",
         "")

    items = [
        ("传输加密", "TLS 在网关终止，同链路改走 443 之后中继只看到十六进制"),
        ("藏住源站", "后端与数据库改 expose，docker port 查过去输出为空"),
        ("收敛指纹", "server_tokens off，网关只报 nginx 且不带版本"),
        ("限流", "每秒八个、突发二十，四十个并发里二十一个通过"),
        ("防大包", "请求体上限四兆，超出直接 413"),
        ("防慢连接", "头部与正文各十五秒，半开连接会被断开"),
        ("提供真实来源", "覆盖写入转发头，后端能读到最左一个地址"),
        ("少泄漏信息", "nosniff、X-Frame-Options、Referrer-Policy，三项都在"),
    ]
    for i, (name, evidence) in enumerate(items):
        col = i // 4
        row = i % 4
        x = 0.85 + col * 6.1
        y = 2.12 + row * 1.2
        text(slide, Inches(x), Inches(y), Inches(5.4), Inches(0.3), name, 13.5, CYAN, True)
        text(slide, Inches(x), Inches(y + 0.4), Inches(5.4), Inches(0.6), evidence, 11, WHITE, line=1.45)
    return slide

# ---------------------------------------------------------------- 8.5 代码
def code_slide(path, title, sub):
    """一页一张编辑器截图。裁掉了活动栏和标签栏，正文才放得大。"""
    def build(prs):
        slide = blank(prs)
        head(slide, "代码", title, sub)
        w = Inches(10.3)
        h = Inches(5.24)
        slide.shapes.add_picture(str(ROOT / path), Inches((13.333 - 10.3) / 2), Inches(1.95),
                                 width=w, height=h)
        return slide
    return build


def s_code_limit(prs):
    return code_slide("img/code_limit_crop.png", "限流与状态码",
                      "deploy/nginx/templates/default.conf.template　第 9 到 17 行")(prs)


def s_code_proxy(prs):
    return code_slide("img/code_proxy_crop.png", "反代与转发头",
                      "同文件　第 96 到 115 行")(prs)


def s_code_expose(prs):
    return code_slide("img/code_expose_crop.png", "端口不外露",
                      "deploy/docker-compose.yml　第 13 行与第 31 行")(prs)


# ---------------------------------------------------------------- 9 两个细节
def s_details(prs):
    slide = blank(prs)
    head(slide, "应用", "两个容易被漏掉的细节")

    text(slide, Inches(0.85), Inches(1.95), Inches(5.5), Inches(0.34),
         "限流的状态码", 14, CYAN, True)
    text(slide, Inches(0.85), Inches(2.36), Inches(5.5), Inches(2.4),
         "nginx 的 limit_req 默认返回 503。503 的语义是服务不可用，客户端会以为后端坏了，"
         "重试策略也跟着变。真正要表达的是“你请求太多了”，那是 429。"
         "第一次实测出来的就是十九个 503，显式写 limit_req_status 429 之后才是现在的结果。",
         12, WHITE, line=1.55)

    text(slide, Inches(6.75), Inches(1.95), Inches(5.6), Inches(0.34),
         "转发头的信任链", 14, CYAN, True)
    text(slide, Inches(6.75), Inches(2.36), Inches(5.6), Inches(2.4),
         "网关看到的才是真实客户端地址，所以限流键用 binary_remote_addr 是准的。"
         "后端看到的是网关自己的地址，想按用户限流就得读 X-Forwarded-For，"
         "而这个头可以被伪造，只有由我们自己的网关覆盖写入时才可信。",
         12, WHITE, line=1.55)

    code(slide, Inches(6.75), Inches(4.75), Inches(5.6), Inches(1.2),
         "limit_req_status  429;\n"
         "limit_conn_status 429;", 11.5)
    text(slide, Inches(0.85), Inches(4.75), Inches(5.5), Inches(1.5),
         "如果以后前面再加一层 CDN，这里必须改用 realip 模块，"
         "否则所有用户会被当成同一个 IP 一起限流。这是一个现在不必做、但必须提前知道的边界。",
         12, BONE, line=1.55)
    return slide


# ---------------------------------------------------------------- 10 两个门槛
def s_threshold(prs):
    slide = blank(prs)
    head(slide, "负载均衡", "容量和可用性不是同一件事",
         "")

    text(slide, Inches(0.85), Inches(1.98), Inches(5.4), Inches(0.3), "容量", 13.5, CYAN, True)
    text(slide, Inches(0.85), Inches(2.38), Inches(5.4), Inches(1.1),
         "单台算不过来才需要扩。压测把请求量和延迟画出来，找曲率突变的拐点，"
         "并发长期超过拐点六成左右再考虑加机器。", 11.5, WHITE, line=1.5)

    text(slide, Inches(6.75), Inches(1.98), Inches(5.6), Inches(0.3), "可用性", 13.5, CYAN, True)
    text(slide, Inches(6.75), Inches(2.38), Inches(5.6), Inches(1.1),
         "不能因为一台故障就停。这件事跟流量无关，哪怕一天只有三个用户，"
         "只要服务不允许中断，就该有第二台。", 11.5, WHITE, line=1.5)

    rungs = [
        ("单机跑通", "初始状态", ""),
        ("单机优化", "延迟随并发上升，资源没用满", "优化有上限，改动可能影响正确性"),
        ("多副本加代理", "单机打满，或服务不许中断", "会话保持、日志分散、配置一致性"),
        ("多代理加外层均衡", "代理自己成了单点", "多一层转发，链路更难排查"),
    ]
    y = 4.0
    for i, (name, when, cost) in enumerate(rungs):
        x = 0.85 + i * 0.5
        bar = slide.shapes.add_shape(1, Inches(x), Inches(y + 0.12), Inches(0.22), Inches(0.05))
        bar.fill.solid()
        bar.fill.fore_color.rgb = CYAN if i == 2 else DIM
        bar.line.fill.background()
        bar.shadow.inherit = False
        text(slide, Inches(x + 0.4), Inches(y), Inches(2.2), Inches(0.3), name, 12.5, WHITE, True)
        text(slide, Inches(x + 2.7), Inches(y + 0.02), Inches(4.0), Inches(0.3), when, 11, MUTED)
        if cost:
            text(slide, Inches(x + 6.9), Inches(y + 0.02), Inches(4.6), Inches(0.3), cost, 10.5, DIM)
        y += 0.68
    return slide

# ---------------------------------------------------------------- 11 算法
def s_algo(prs):
    slide = blank(prs)
    head(slide, "负载均衡", "算法取舍与无状态",
         "")

    cards = [
        ("轮询", "后端同构、耗时相近时最简单", "有慢请求时会堆在固定几台上"),
        ("最少连接", "按当前连接数挑一台，抗慢请求", "长连接场景下计数会失真"),
        ("IP 哈希", "需要会话保持时用", "用户分布不均会倾斜"),
    ]
    x = 0.85
    for name, fit, fail in cards:
        box = card(slide, Inches(x), Inches(2.0), Inches(3.6), Inches(2.2))
        text(slide, Inches(x + 0.28), Inches(2.2), Inches(3.0), Inches(0.32), name, 15, BONE, True)
        text(slide, Inches(x + 0.28), Inches(2.68), Inches(3.05), Inches(0.6), fit, 11, WHITE, line=1.45)
        text(slide, Inches(x + 0.28), Inches(3.45), Inches(3.05), Inches(0.6), fail, 11, RED, line=1.45)
        x += 4.0

    text(slide, Inches(0.85), Inches(4.62), Inches(5.5), Inches(0.3),
         "我们选最少连接", 13.5, CYAN, True)
    text(slide, Inches(0.85), Inches(5.02), Inches(5.5), Inches(1.5),
         "健康检查和探测请求耗时接近，但真实业务里存档上传和排行榜查询差很多。"
         "最少连接比轮询更抗慢请求，也不像加权轮询那样依赖人工估权重。",
         11.5, WHITE, line=1.55)

    text(slide, Inches(6.75), Inches(4.62), Inches(5.6), Inches(0.3),
         "为什么不需要会话保持", 13.5, CYAN, True)
    text(slide, Inches(6.75), Inches(5.02), Inches(5.6), Inches(1.5),
         "后端是无状态 REST，账号、存档、排行榜都在 MySQL 里，任何一台都能处理任何请求。"
         "这是加副本不用改代码的前提，粘性会话那套问题也就不会出现。",
         11.5, WHITE, line=1.55)
    return slide

# ---------------------------------------------------------------- 12 健康检查
def s_health(prs):
    slide = blank(prs)
    head(slide, "负载均衡", "被动检查的代价是五秒")

    big(slide, Inches(0.85), Inches(2.0), Inches(2.9), "9 / 9", "", "停掉一台后的请求成功率", GREEN)
    big(slide, Inches(4.35), Inches(2.0), Inches(2.9), "5020", "ms　最慢一次", "正好打到死实例的那个", RED)
    big(slide, Inches(7.85), Inches(2.0), Inches(2.9), "10", "s　fail_timeout", "之后放回地址池", MUTED)

    text(slide, Inches(0.85), Inches(3.55), Inches(11.6), Inches(1.1),
         "百分百成功和五秒延迟要一起报。只报成功率，等于把被动健康检查的代价藏起来了。",
         14, WHITE, line=1.5)

    text(slide, Inches(0.85), Inches(4.35), Inches(5.5), Inches(0.34),
         "被动检查", 14, CYAN, True)
    text(slide, Inches(0.85), Inches(4.76), Inches(5.5), Inches(1.8),
         "开源 nginx 只有被动检查：某台连续失败 max_fails 次后标为不可用，"
         "fail_timeout 之后重新放回。那个五秒，就是请求正好落在已死实例上、"
         "等连接超时到点再重试下一台的时间。",
         12, WHITE, line=1.55)

    text(slide, Inches(6.75), Inches(4.35), Inches(5.6), Inches(0.34),
         "主动检查", 14, CYAN, True)
    text(slide, Inches(6.75), Inches(4.76), Inches(5.6), Inches(1.8),
         "想消除这个等待，要么把连接超时调短，代价是慢后端更容易被误判；"
         "要么换有主动探测的实现，NGINX Plus 和 Envoy 都支持周期性探活。"
         "这是成熟方案之间真正的差距，不在配置写法上。",
         12, WHITE, line=1.55)
    return slide


# ---------------------------------------------------------------- 13 前后对照
def s_before_after(prs):
    slide = blank(prs)
    head(slide, "改造", "改造前后",
         "")

    rows = [
        ("对外端口", "8000、3306、8080", "80、443"),
        ("传输", "明文 HTTP", "80 跳 443，TLS 1.2 与 1.3"),
        ("后端数量", "1", "3，least_conn 调度"),
        ("故障处理", "没有", "max_fails 摘除，重试下一台"),
        ("限流", "没有", "每秒八个，超出发 429"),
        ("版本指纹", "没有安全头，docs 敞开", "只报 nginx，不带版本"),
        ("请求体上限", "没有", "4 MB"),
    ]
    y = 2.02
    for label, before, after in rows:
        text(slide, Inches(0.85), Inches(y + 0.03), Inches(2.1), Inches(0.3), label, 11.5, MUTED)
        text(slide, Inches(3.0), Inches(y), Inches(3.4), Inches(0.34), before, 12, DIM)
        arrow = slide.shapes.add_shape(1, Inches(6.5), Inches(y + 0.15), Inches(0.42), Inches(0.035))
        arrow.fill.solid()
        arrow.fill.fore_color.rgb = RGBColor(0x35, 0x4A, 0x4D)
        arrow.line.fill.background()
        arrow.shadow.inherit = False
        text(slide, Inches(7.1), Inches(y), Inches(5.2), Inches(0.34), after, 12.5, BONE)
        y += 0.66

    text(slide, Inches(0.85), Inches(6.86), Inches(11.6), Inches(0.34),
         "最后还有一行：数据库与后端从 ports 改成 expose。源站不出内网，前面所有策略才成立。",
         11.5, WHITE, line=1.4)
    return slide

# ---------------------------------------------------------------- 14 实测
def s_measure(prs):
    slide = blank(prs)
    head(slide, "实测", "本机实测结果",
         "Windows 11，Docker 29.7.2，nginx 1.31.8，FastAPI 0.115.14，MySQL 8.4.13。")

    big(slide, Inches(0.85), Inches(1.98), Inches(2.9), "4 / 4 / 4", "次　三台分到的请求", "12 次依次请求，全部成功")
    big(slide, Inches(4.05), Inches(1.98), Inches(2.9), "21 / 19", "个　200 与 429", "40 并发，超出直接被拒")
    big(slide, Inches(7.25), Inches(1.98), Inches(2.7), "5007", "ms　最慢一次", "停一台后九次仍全成功", RED)
    big(slide, Inches(10.15), Inches(1.98), Inches(2.3), "10", "秒　自愈", "重启后重新均匀", MUTED)

    lines = [
        "限流那个二十一不是巧合：每秒八个加突发二十，一瞬间最多放过二十一个。",
        "明文对照，中继打印出完整请求行、请求头和 JSON。",
        "密文对照，同一段链路走 443，只剩十六进制。",
        "源站隐藏，docker port 查后端与数据库，两条都空。",
        "分流与自愈看的是命中次数，不看成功率，可用是默认。",
    ]
    y = 3.6
    for line in lines:
        text(slide, Inches(0.85), Inches(y), Inches(11.6), Inches(0.3), line, 11.5,
             MUTED if line.startswith("限流") else WHITE, line=1.4)
        y += 0.5
    return slide

# ---------------------------------------------------------------- 15 判断
def s_judgement(prs):
    slide = blank(prs)
    head(slide, "判断", "我们这个项目到底需不需要负载均衡")

    text(slide, Inches(0.85), Inches(2.0), Inches(11.6), Inches(1.0),
         "结论是：入口这一层必须存在，负载均衡这一层现在还不需要。",
         20, BONE, True, line=1.4)

    text(slide, Inches(0.85), Inches(3.2), Inches(5.5), Inches(2.2),
         "访问量很小，一门课的作品不会有并发压力。后端是无状态 REST，真要扩也只是加副本，"
         "不需要改代码。更关键的是，就算扩了，瓶颈也会立刻转移到 MySQL，而不是 uvicorn。"
         "现在加副本，是给错的地方扩容。",
         12.5, WHITE, line=1.6)

    text(slide, Inches(6.75), Inches(3.2), Inches(5.6), Inches(2.2),
         "所以这次做的改造，重点是把入口的安全职责补齐，这部分跟流量无关，是必须有。"
         "负载均衡那部分按第三级的样子搭好并做了验证：三台确实能跑通、能分流、"
         "能在故障时绕开。验证的目的是确认这条路可行，不是声称我们现在需要它。",
         12.5, WHITE, line=1.6)

    text(slide, Inches(0.85), Inches(5.7), Inches(11.6), Inches(0.34),
         "局限", 13, RED, True)
    text(slide, Inches(0.85), Inches(6.05), Inches(11.6), Inches(0.9),
         "证书是自签的，只适合演示与本机验收。网关自身是新的单点，要消除得在外层再做一次均衡。"
         "主动健康检查需要 Plus 或 Envoy，开源版做不到。",
         12, MUTED, line=1.45)
    return slide


# ---------------------------------------------------------------- 15.5 真跑
def s_game_browser(prs):
    slide = blank(prs)
    head(slide, "实测", "先看一眼它真的在浏览器里跑",
         "")
    w = Inches(10.4)
    h = Inches(5.41)
    slide.shapes.add_picture(str(ROOT / "img/game_browser_crop.png"),
                             Inches((13.333 - 10.4) / 2), Inches(1.98),
                             width=w, height=h)
    return slide


# ---------------------------------------------------------------- 16 演示
def s_demo(prs):
    slide = blank(prs)
    head(slide, "演示", "现场跑这几步")

    left = [
        ("裸奔对照", "curl 直连 18081", "http、无安全头、docs 敞开"),
        ("明文可见", "中继转发明文端口", "打印出完整请求行与 JSON"),
        ("密文对照", "中继转发 443", "只剩十六进制"),
        ("源站隐藏", "docker port 查后端", "输出为空"),
        ("大包流式", "拉一遍 96 MB 首屏包", "网关内存不跟着涨"),
    ]
    right = [
        ("分流", "依次请求 12 次", "三台各 4 次"),
        ("限流", "40 并发", "21 个 200，19 个 429"),
        ("故障转移", "停一台再请求 9 次", "全成功，最慢 5020 ms"),
        ("自愈", "启回来等 10 秒", "又均匀了"),
    ]
    y = Inches(1.98)
    for name, cmd, expect in left:
        text(slide, Inches(0.85), y, Inches(1.85), Inches(0.34), name, 12.5, CYAN, True)
        text(slide, Inches(2.7), y, Inches(3.05), Inches(0.34), cmd, 11.5, MUTED)
        text(slide, Inches(2.7), y + Inches(0.32), Inches(3.05), Inches(0.34), expect, 11, WHITE, line=1.3)
        y += Inches(0.94)

    y = Inches(1.98)
    for name, cmd, expect in right:
        text(slide, Inches(6.6), y, Inches(1.75), Inches(0.34), name, 12.5, CYAN, True)
        text(slide, Inches(8.3), y, Inches(4.1), Inches(0.34), cmd, 11.5, MUTED)
        text(slide, Inches(8.3), y + Inches(0.32), Inches(4.1), Inches(0.34), expect, 11, WHITE, line=1.3)
        y += Inches(0.94)

    text(slide, Inches(0.85), Inches(6.68), Inches(11.6), Inches(0.5),
         "",
         11.5, DIM, line=1.4)
    return slide


def build(path):
    prs = new_deck()
    for fn in (s_cover, s_topology, s_why, s_seven_steps, s_keepalive, s_stream,
               s_zone, s_security, s_code_limit, s_code_proxy, s_code_expose,
               s_details, s_threshold, s_algo,
               s_health, s_before_after, s_measure, s_judgement, s_game_browser, s_demo):
        fn(prs)
    prs.save(path)
    return path


if __name__ == "__main__":
    out = build("share/技术分享-应用代理与负载均衡.pptx")
    print("saved", out)
