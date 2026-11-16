"""生成技术分享 PPT：Web 访问安全中的应用代理与负载均衡。

结构按五段走：原理、代码、演示、项目应用、总结。
版式规则见 AGENTS.md 第八节：章节页分章、标题写清楚这页讲什么、标题下不放小字、
能不用表格就不用、白底纸纹配一个主色。字号不小于 11，正文以 13 为主。
"""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

ROOT = Path(__file__).resolve().parent

INK = RGBColor(0x1B, 0x1F, 0x1D)
MUTED = RGBColor(0x55, 0x5E, 0x59)
DIM = RGBColor(0x8A, 0x92, 0x8D)
FAINT = RGBColor(0xC4, 0xCA, 0xC4)
ACCENT = RGBColor(0x1F, 0x5C, 0x54)
WARN = RGBColor(0xA8, 0x44, 0x2F)
LINE = RGBColor(0xD5, 0xD9, 0xD2)
CARD = RGBColor(0xF2, 0xF2, 0xEC)

FONT = "微软雅黑"
MONO = "Consolas"

W, H = Inches(13.333), Inches(7.5)
LEFT = Inches(0.9)
BODY_W = Inches(11.5)


def new_deck() -> Presentation:
    prs = Presentation()
    prs.slide_width = W
    prs.slide_height = H
    return prs


def blank(prs):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    bg = slide.shapes.add_picture(str(ROOT / "img/bg_paper.png"), 0, 0, width=W, height=H)
    bg.shadow.inherit = False
    return slide


def text(slide, x, y, w, h, s, size=13, color=INK, bold=False, font=FONT,
         align=PP_ALIGN.LEFT, line=1.4):
    box = slide.shapes.add_textbox(x, y, w, h)
    tf = box.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.TOP
    for attr in ("margin_left", "margin_right", "margin_top", "margin_bottom"):
        setattr(tf, attr, 0)
    for i, ln in enumerate(s.split("\n")):
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


def rule(slide, x, y, w, h, color=ACCENT):
    shape = slide.shapes.add_shape(1, x, y, w, h)
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()
    shape.shadow.inherit = False
    return shape


def head(slide, title):
    """页眉：竖线加一句说清这页讲什么的标题。"""
    t = title
    size = 34
    if len(title) > 14:
        size = 30
    rule(slide, LEFT, Inches(0.62), Inches(0.05), Inches(0.56))
    text(slide, Inches(1.16), Inches(0.5), Inches(11.0), Inches(0.8), t, size, INK, True, line=1.15)
    return Inches(1.62)


def card(slide, x, y, w, h, fill=CARD):
    box = slide.shapes.add_shape(1, x, y, w, h)
    box.fill.solid()
    box.fill.fore_color.rgb = fill
    box.line.color.rgb = LINE
    box.line.width = Pt(0.75)
    box.shadow.inherit = False
    return box


def code(slide, x, y, w, h, s, size=11.5):
    box = card(slide, x, y, w, h)
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.2)
    tf.margin_top = Inches(0.16)
    for i, ln in enumerate(s.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.line_spacing = 1.2
        r = p.add_run()
        r.text = ln
        r.font.size = Pt(size)
        r.font.name = MONO
        r.font.color.rgb = DIM if ln.strip().startswith("#") else INK
    return box


def num(slide, x, y, value, unit, label, color=INK, w=Inches(2.7)):
    text(slide, x, y, w, Inches(0.8), value, 40, color, True, line=1.0)
    text(slide, x, y + Inches(0.66), w, Inches(0.3), unit, 11.5, DIM)
    text(slide, x, y + Inches(0.98), w, Inches(0.4), label, 12.5, MUTED, line=1.3)


# ---------------------------------------------------------------- 封面
def s_cover(prs):
    slide = blank(prs)
    rule(slide, Inches(1.0), Inches(2.02), Inches(0.9), Inches(0.05))
    text(slide, Inches(1.0), Inches(2.28), Inches(10.6), Inches(1.3),
         "Web 访问安全中的应用代理与负载均衡", 38, INK, True, line=1.2)
    text(slide, Inches(1.0), Inches(3.44), Inches(10.6), Inches(0.44),
         "以《共生之缚》的 Web 入口为例", 18, MUTED)
    text(slide, Inches(1.0), Inches(6.3), Inches(10.6), Inches(0.34),
         "2 组　软件工程课程设计　2026 年 11 月", 12, DIM)
    return slide


# ---------------------------------------------------------------- 章节页
def chapter(prs, index, title):
    slide = blank(prs)
    text(slide, LEFT, Inches(2.5), Inches(3.0), Inches(1.2), index, 64, FAINT, True, line=1.0)
    text(slide, Inches(2.5), Inches(2.62), Inches(9.6), Inches(1.0), title, 44, INK, True, line=1.1)
    rule(slide, Inches(2.55), Inches(3.86), Inches(1.1), Inches(0.04), ACCENT)
    return slide


# ---------------------------------------------------------------- 原理：七步
def s_steps(prs):
    slide = blank(prs)
    head(slide, "一次请求穿过网关的七个步骤")

    steps = [
        ("1", "接连接", "接受 TCP 连接，建立 TLS 会话", "listen 8443 ssl，TLSv1.2 与 1.3"),
        ("2", "解析报文", "方法、路径、Host 与请求头", "七层代理才有这一步"),
        ("3", "决定路由", "按路径或主机名选处理方式", "根路径走静态，/api/ 走上游"),
        ("4", "改写头部", "补上游需要的来源信息", "X-Real-IP、X-Forwarded-For、Proto"),
        ("5", "建上游连接", "从地址池挑一台并连上去", "least_conn 加 keepalive"),
        ("6", "转发与回传", "边收边转，不等响应结束", "默认流式，适合几十 MB 的包"),
        ("7", "收尾", "记耗时，处理超时与断连", "access_log，connect 5s，read 30s"),
    ]
    y = 1.86
    for n, name, desc, cfg in steps:
        text(slide, LEFT, Inches(y), Inches(0.4), Inches(0.34), n, 15, ACCENT, True)
        text(slide, Inches(1.36), Inches(y + 0.02), Inches(1.9), Inches(0.32), name, 14, INK, True)
        text(slide, Inches(3.4), Inches(y + 0.04), Inches(4.2), Inches(0.32), desc, 13.5, MUTED)
        text(slide, Inches(7.75), Inches(y + 0.05), Inches(4.6), Inches(0.32), cfg, 12, MUTED, font=MONO)
        y += 0.7
    return slide


# ---------------------------------------------------------------- 原理：转发
def s_forward(prs):
    slide = blank(prs)
    head(slide, "连接复用与流式转发")

    text(slide, LEFT, Inches(1.82), Inches(5.4), Inches(0.34), "连接复用", 14, ACCENT, True)
    text(slide, LEFT, Inches(2.24), Inches(5.4), Inches(1.5),
         "每个请求重新握手，开销随并发升高迅速放大，还会留下大量等待关闭的连接。"
         "网关保持一组到后端的长连接，请求直接复用。", 13, INK, line=1.55)

    text(slide, LEFT, Inches(3.98), Inches(5.4), Inches(0.34), "超时分层", 14, ACCENT, True)
    text(slide, LEFT, Inches(4.4), Inches(5.4), Inches(1.6),
         "连接、读、写三个超时分开设，才能区分后端连不上和后端算得慢。"
         "连接压到五秒，读留三十秒，慢接口不被当成故障。", 13, INK, line=1.55)

    text(slide, Inches(6.6), Inches(1.82), Inches(5.8), Inches(0.34), "流式转发", 14, ACCENT, True)
    text(slide, Inches(6.6), Inches(2.24), Inches(5.8), Inches(1.6),
         "整块缓冲意味着网关内存要装得下整个响应体。边收边转只占一块固定缓冲区，"
         "几十兆的 wasm 和 pck 过去，内存曲线是平的。", 13, INK, line=1.55)

    code(slide, Inches(6.6), Inches(4.05), Inches(5.8), Inches(2.05),
         "upstream symbiont_backend {\n"
         "    zone symbiont_backend 64k;\n"
         "    least_conn;\n"
         "    server server-1:8000 max_fails=2 fail_timeout=10s;\n"
         "    keepalive 16;\n"
         "}", 11.5)
    return slide


# ---------------------------------------------------------------- 原理：上游池
def s_upstream(prs):
    slide = blank(prs)
    head(slide, "上游地址池要共享状态")

    text(slide, LEFT, Inches(1.82), Inches(11.4), Inches(1.0),
         "upstream 不写 zone，每个 worker 各算各的轮询计数。请求量小时看起来全落在第一台，"
         "另外两台闲着，服务本身却一直正常。", 14, INK, line=1.55)

    code(slide, Inches(0.9), Inches(3.0), Inches(5.5), Inches(1.6),
         "upstream symbiont_backend {\n"
         "    zone symbiont_backend 64k;\n"
         "    least_conn;\n"
         "}", 12)

    text(slide, Inches(6.9), Inches(3.0), Inches(5.5), Inches(1.6),
         "命中次数才说明配置生效。\n"
         "没有 zone：十次请求可能八次落在第一台。\n"
         "有 zone：十次接近四比三比三。", 13, INK, line=1.75)

    text(slide, LEFT, Inches(5.3), Inches(11.4), Inches(0.34), "同一类问题还有一个", 14, ACCENT, True)
    text(slide, LEFT, Inches(5.72), Inches(11.4), Inches(1.0),
         "两份编排都放在 deploy 目录，compose 默认拿目录名当项目名，于是被当成同一个项目，"
         "起对照栈时把网关那套容器顶掉。修法是文件里显式写 name。", 13, INK, line=1.55)
    return slide


# ---------------------------------------------------------------- 原理：算法
def s_algo(prs):
    slide = blank(prs)
    head(slide, "调度算法各自的失效场景")

    cards = [
        ("轮询", "后端同构、耗时相近时最简单", "有慢请求时会堆在固定几台上"),
        ("最少连接", "按当前连接数挑一台，抗慢请求", "长连接场景下计数会失真"),
        ("IP 哈希", "需要会话保持时用", "用户分布不均会倾斜"),
    ]
    x = 0.9
    for name, fit, fail in cards:
        card(slide, Inches(x), Inches(1.86), Inches(3.6), Inches(2.1))
        text(slide, Inches(x + 0.28), Inches(2.04), Inches(3.0), Inches(0.34), name, 16, INK, True)
        text(slide, Inches(x + 0.28), Inches(2.52), Inches(3.05), Inches(0.64), fit, 12.5, INK, line=1.45)
        text(slide, Inches(x + 0.28), Inches(3.26), Inches(3.05), Inches(0.64), fail, 12.5, WARN, line=1.45)
        x += 4.0

    text(slide, LEFT, Inches(4.42), Inches(11.4), Inches(0.34), "我们选最少连接", 14, ACCENT, True)
    text(slide, LEFT, Inches(4.84), Inches(11.4), Inches(1.4),
         "健康检查和探测请求耗时接近，但存档上传和排行榜查询差很多。最少连接比轮询更抗慢请求，"
         "也不像加权轮询那样依赖人工估权重。后端是无状态 REST，任何一台都能处理任何请求，"
         "所以粘性会话那套问题不会出现。", 13, INK, line=1.6)
    return slide


# ---------------------------------------------------------------- 原理：健康检查
def s_health(prs):
    slide = blank(prs)
    head(slide, "被动健康检查的切换代价")

    num(slide, Inches(0.9), Inches(1.82), "9 / 9", "停一台后的成功率", "九次请求全部成功")
    num(slide, Inches(3.9), Inches(1.82), "5007", "ms　最慢一次", "正好落在已死实例上", WARN)
    num(slide, Inches(6.9), Inches(1.82), "10", "s　fail_timeout", "之后重新放回地址池")
    num(slide, Inches(9.9), Inches(1.82), "2", "次　max_fails", "连续失败才摘除", MUTED)

    text(slide, LEFT, Inches(3.95), Inches(5.4), Inches(0.34), "被动检查", 14, ACCENT, True)
    text(slide, LEFT, Inches(4.38), Inches(5.4), Inches(1.9),
         "开源 nginx 只有被动检查：某台连续失败 max_fails 次后标为不可用，fail_timeout 之后放回。"
         "那个五秒就是请求落在死实例上、等连接超时到点再重试的代价。", 13, INK, line=1.55)

    text(slide, Inches(6.6), Inches(3.95), Inches(5.8), Inches(0.34), "主动检查", 14, ACCENT, True)
    text(slide, Inches(6.6), Inches(4.38), Inches(5.8), Inches(1.9),
         "想消除这个等待，要么把连接超时调短，代价是慢后端更容易被误判；"
         "要么换带周期性探活的实现，NGINX Plus 和 Envoy 都支持。", 13, INK, line=1.55)
    return slide


# ---------------------------------------------------------------- 代码页
def code_slide(path, title):
    def build(prs):
        slide = blank(prs)
        head(slide, title)
        pic = slide.shapes.add_picture(str(ROOT / path), Inches(0.9), Inches(1.72),
                                       width=Inches(11.5), height=Inches(5.85))
        pic.line.color.rgb = LINE
        pic.line.width = Pt(0.75)
        return slide
    return build


def s_code_limit(prs):
    return code_slide("img/code_limit_crop.png", "限流配置与状态码")(prs)


def s_code_proxy(prs):
    return code_slide("img/code_proxy_crop.png", "反向代理与转发头配置")(prs)


def s_code_expose(prs):
    return code_slide("img/code_expose_crop.png", "编排里的端口收口")(prs)


# ---------------------------------------------------------------- 演示步骤
def s_demo(prs):
    slide = blank(prs)
    head(slide, "现场演示的九个步骤")

    left = [
        ("裸奔对照", "curl 直连 18081", "http、无安全头、docs 敞开"),
        ("明文可见", "中继转发明文端口", "打印完整请求行与 JSON"),
        ("密文对照", "中继转发 443", "只剩十六进制"),
        ("源站隐藏", "docker port 查后端", "输出为空"),
        ("大包流式", "拉一遍 96 MB 首屏包", "网关内存不跟着涨"),
    ]
    right = [
        ("分流", "依次请求 12 次", "三台各 4 次"),
        ("限流", "40 并发", "21 个 200，19 个 429"),
        ("故障转移", "停一台再请求 9 次", "全成功，最慢 5007 ms"),
        ("自愈", "启回来等 10 秒", "又均匀了"),
    ]
    y = Inches(1.82)
    for name, cmd, expect in left:
        text(slide, LEFT, y, Inches(1.7), Inches(0.32), name, 13.5, ACCENT, True)
        text(slide, Inches(2.65), y, Inches(3.1), Inches(0.32), cmd, 12.5, MUTED)
        text(slide, Inches(2.65), y + Inches(0.3), Inches(3.1), Inches(0.32), expect, 12.5, INK)
        y += Inches(0.95)

    y = Inches(1.82)
    for name, cmd, expect in right:
        text(slide, Inches(6.5), y, Inches(1.6), Inches(0.32), name, 13.5, ACCENT, True)
        text(slide, Inches(8.2), y, Inches(4.2), Inches(0.32), cmd, 12.5, MUTED)
        text(slide, Inches(8.2), y + Inches(0.3), Inches(4.2), Inches(0.32), expect, 12.5, INK)
        y += Inches(0.95)
    return slide


# ---------------------------------------------------------------- 实测
def s_measure(prs):
    slide = blank(prs)
    head(slide, "本机实测的四个数字")

    num(slide, Inches(0.9), Inches(1.8), "4 / 4 / 4", "次　三台分到的请求", "12 次依次请求，全部成功")
    num(slide, Inches(3.9), Inches(1.8), "21 / 19", "个　200 与 429", "40 并发，超出直接被拒")
    num(slide, Inches(6.9), Inches(1.8), "5007", "ms　最慢一次", "停一台后九次仍全成功", WARN)
    num(slide, Inches(9.9), Inches(1.8), "10", "秒　自愈", "重启后重新均匀", MUTED)

    lines = [
        "限流那个二十一不是巧合：每秒八个加突发二十，一瞬间最多放过二十一个。",
        "明文对照，中继打印出完整请求行、请求头和 JSON。",
        "密文对照，同一段链路走 443，只剩十六进制。",
        "源站隐藏，docker port 查后端与数据库，两条都空。",
    ]
    y = 3.62
    for ln in lines:
        text(slide, LEFT, Inches(y), Inches(11.4), Inches(0.34), ln, 13.5, INK, line=1.4)
        y += 0.78
    return slide


# ---------------------------------------------------------------- 项目：拓扑
def s_topology(prs):
    slide = blank(prs)
    head(slide, "项目的入口拓扑")

    y = Inches(1.9)
    boxes = [
        (Inches(0.9), "浏览器", "玩家打开的页面\n和游戏包", MUTED),
        (Inches(3.55), "网关 80 / 443", "TLS 终止　限流\n静态托管　反向代理", ACCENT),
        (Inches(6.85), "后端 ×3", "无状态 REST\n等价副本", INK),
        (Inches(9.85), "MySQL", "账号　存档\n排行榜", MUTED),
    ]
    for x, name, desc, col in boxes:
        card(slide, x, y, Inches(2.3), Inches(1.75))
        text(slide, x + Inches(0.2), y + Inches(0.2), Inches(1.95), Inches(0.34), name, 15, col, True)
        text(slide, x + Inches(0.2), y + Inches(0.7), Inches(1.95), Inches(0.9), desc, 12, MUTED, line=1.45)

    for x in (Inches(3.2), Inches(6.5), Inches(9.5)):
        rule(slide, x, y + Inches(0.82), Inches(0.3), Inches(0.05))

    text(slide, LEFT, Inches(4.1), Inches(11.4), Inches(0.7),
         "后端 8000 与数据库 3306 都不映射宿主机，从公网够不到它们。", 15, INK, line=1.5)
    text(slide, LEFT, Inches(4.85), Inches(11.4), Inches(0.7),
         "源站只要还能被直连，入口上配的限流、转发头和超时都可以被绕过。", 13, MUTED, line=1.5)
    return slide


# ---------------------------------------------------------------- 项目：问题
def s_problem(prs):
    slide = blank(prs)
    head(slide, "改造前的三个暴露面")

    items = [
        ("明文链路", "HTTP 自己不加密，请求行、请求头、正文在链路上都是可读的。"
                     "登录请求带账号密码，存档请求带进度，中间节点都能留下记录。"),
        ("源站可被绕过", "后端端口直接映射宿主机。代理在不在都无所谓，攻击者绕开代理打后端，"
                       "代理上的策略全部失效。数据库端口一起暴露时风险更大。"),
        ("单点", "只有一台后端，重启、升级，或者被一个慢请求拖住，服务就断。"
                "这个问题跟访问量无关，一天三个用户也一样。"),
    ]
    y = Inches(1.86)
    for name, desc in items:
        card(slide, LEFT, y, Inches(11.5), Inches(1.42))
        text(slide, Inches(1.14), y + Inches(0.2), Inches(2.2), Inches(0.34), name, 15, ACCENT, True)
        text(slide, Inches(3.5), y + Inches(0.2), Inches(8.6), Inches(1.05), desc, 13, INK, line=1.55)
        y += Inches(1.62)
    return slide


# ---------------------------------------------------------------- 项目：职责
def s_duty(prs):
    slide = blank(prs)
    head(slide, "网关承担的八项职责")

    items = [
        ("传输加密", "TLS 在网关终止，同链路改走 443 之后中继只看到十六进制"),
        ("藏住源站", "后端与数据库改 expose，docker port 查过去输出为空"),
        ("收敛指纹", "server_tokens off，网关只报 nginx 且不带版本"),
        ("流量限制", "每秒八个、突发二十，四十个并发里二十一个通过"),
        ("请求体上限", "四兆，超出直接返回 413"),
        ("慢连接防护", "头部与正文各十五秒，半开连接会被断开"),
        ("真实来源", "覆盖写入转发头，后端能读到最左一个地址"),
        ("响应头", "nosniff、X-Frame-Options、Referrer-Policy 三项都在"),
    ]
    for i, (name, ev) in enumerate(items):
        x = 0.9 + (i // 4) * 6.0
        y = 1.86 + (i % 4) * 1.22
        text(slide, Inches(x), Inches(y), Inches(5.3), Inches(0.32), name, 14, ACCENT, True)
        text(slide, Inches(x), Inches(y + 0.42), Inches(5.3), Inches(0.62), ev, 12.5, INK, line=1.5)
    return slide


# ---------------------------------------------------------------- 项目：体积
def s_size(prs):
    slide = blank(prs)
    head(slide, "首屏九十六兆过网关")

    num(slide, Inches(0.9), Inches(1.82), "58.3", "MB　游戏数据包 index.pck", "Godot 导出产物")
    num(slide, Inches(3.6), Inches(1.82), "37.7", "MB　引擎 index.wasm", "同一份导出")
    num(slide, Inches(6.3), Inches(1.82), "96.0", "MB　首屏要过的总量", "两个文件相加", ACCENT)
    num(slide, Inches(9.0), Inches(1.82), "0.8", "MB　网关内存波动", "35.13 到 35.93 MiB", WARN)

    text(slide, LEFT, Inches(4.15), Inches(5.4), Inches(0.34), "整块缓冲", 14, WARN, True)
    text(slide, LEFT, Inches(4.6), Inches(5.4), Inches(1.0),
         "内存要装下整个响应体，包越大顶得越紧。", 13, INK, line=1.5)

    text(slide, Inches(6.6), Inches(4.15), Inches(5.6), Inches(0.34), "边收边转", 14, ACCENT, True)
    text(slide, Inches(6.6), Inches(4.6), Inches(5.6), Inches(1.0),
         "只占一块转发缓冲区，和文件大小无关。", 13, INK, line=1.5)
    return slide


# ---------------------------------------------------------------- 项目：前后
def s_before_after(prs):
    slide = blank(prs)
    head(slide, "改造前后的六项差异")

    rows = [
        ("对外端口", "8000、3306、8080", "80、443"),
        ("传输", "明文 HTTP", "80 跳 443，TLS 1.2 与 1.3"),
        ("后端数量", "1", "3，least_conn 调度"),
        ("故障处理", "没有", "max_fails 摘除，重试下一台"),
        ("限流", "没有", "每秒八个，超出发 429"),
        ("版本指纹", "没有安全头，docs 敞开", "只报 nginx，不带版本"),
    ]
    y = Inches(1.86)
    for label, before, after in rows:
        text(slide, LEFT, y + 0.04, Inches(2.0), Inches(0.3), label, 12.5, MUTED)
        text(slide, Inches(3.0), y, Inches(3.3), Inches(0.32), before, 13, DIM)
        rule(slide, Inches(6.45), y + Inches(0.16), Inches(0.4), Inches(0.03), FAINT)
        text(slide, Inches(7.0), y, Inches(5.3), Inches(0.32), after, 13, INK)
        y += Inches(0.72)

    text(slide, LEFT, Inches(6.55), Inches(11.4), Inches(0.4),
         "改动最大的一行在编排里：数据库与后端从 ports 改成 expose。", 13, ACCENT, line=1.4)
    return slide


# ---------------------------------------------------------------- 项目：实景
def s_browser(prs):
    slide = blank(prs)
    head(slide, "Web 版在网关后面运行")
    pic = slide.shapes.add_picture(str(ROOT / "img/game_browser_crop.png"),
                                   Inches(0.9), Inches(1.72), width=Inches(11.5), height=Inches(5.85))
    pic.line.color.rgb = LINE
    pic.line.width = Pt(0.75)
    return slide


# ---------------------------------------------------------------- 总结
def s_summary(prs):
    slide = blank(prs)
    head(slide, "这次分享的四句话")

    points = [
        ("代理解决的是入口问题", "安全策略只有在唯一入口上才成立，分散到每台后端就无从统一。"),
        ("成熟度不在转发本身", "连接复用、流式转发、超时分层、共享状态、健康检查，才是与原型脚本的差距。"),
        ("负载均衡解决两件事", "可用性跟流量无关，容量要等流量到位，两者的门槛不能合并判断。"),
        ("代价要一起报", "被动检查换来百分之百成功率，代价是那一次五秒。"),
    ]
    y = 1.9
    for i, (name, desc) in enumerate(points):
        text(slide, LEFT, Inches(y), Inches(0.5), Inches(0.34), str(i + 1), 15, ACCENT, True)
        text(slide, Inches(1.36), Inches(y), Inches(4.6), Inches(0.34), name, 16, INK, True)
        text(slide, Inches(1.36), Inches(y + 0.46), Inches(10.6), Inches(0.4), desc, 13.5, MUTED, line=1.45)
        y += 1.26
    return slide


def build(path):
    prs = new_deck()
    s_cover(prs)

    chapter(prs, "01", "原理")
    s_steps(prs)
    s_forward(prs)
    s_upstream(prs)
    s_algo(prs)
    s_health(prs)

    chapter(prs, "02", "代码")
    s_code_limit(prs)
    s_code_proxy(prs)
    s_code_expose(prs)

    chapter(prs, "03", "演示")
    s_demo(prs)
    s_measure(prs)

    chapter(prs, "04", "项目应用")
    s_topology(prs)
    s_problem(prs)
    s_duty(prs)
    s_size(prs)
    s_before_after(prs)
    s_browser(prs)

    chapter(prs, "05", "总结")
    s_summary(prs)

    prs.save(path)
    return path


if __name__ == "__main__":
    print("saved", build("share/技术分享-应用代理与负载均衡.pptx"))
