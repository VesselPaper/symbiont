"""生成报告用的两张架构图。

改造前（图 1）与改造后（图 2）对照，风格统一：浅底、细边框、蓝灰主色、红色标注问题。
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent / "img"
OUT.mkdir(parents=True, exist_ok=True)

FONT_REGULAR = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"

BG = (255, 255, 255)
INK = (32, 38, 48)
MUTED = (108, 120, 145)
BORDER = (196, 205, 220)
FILL = (246, 248, 252)
ACCENT = (63, 111, 212)
ACCENT_FILL = (232, 239, 253)
WARN = (198, 76, 64)
WARN_FILL = (253, 238, 236)
OK = (58, 138, 96)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size)


def box(d: ImageDraw.ImageDraw, xy, title: str, sub: str = "", *, fill=FILL, border=BORDER,
        accent=None, width=2) -> None:
    x0, y0, x1, y1 = xy
    d.rounded_rectangle(xy, radius=10, fill=fill, outline=accent or border, width=width)
    tf = font(26, bold=True)
    sf = font(19)
    title_w = d.textlength(title, font=tf)
    cx = (x0 + x1) / 2
    ty = (y0 + y1) / 2 - (26 if sub else 0)
    d.text((cx - title_w / 2, ty), title, font=tf, fill=INK)
    if sub:
        sub_w = d.textlength(sub, font=sf)
        d.text((cx - sub_w / 2, ty + 36), sub, font=sf, fill=MUTED)


def arrow(d: ImageDraw.ImageDraw, start, end, label: str = "", *, color=BORDER, dashed=False,
          labels_above=True) -> None:
    d.line([start, end], fill=color, width=3)
    ang = math.atan2(end[1] - start[1], end[0] - start[0])
    size = 12
    tip = end
    left = (tip[0] - size * math.cos(ang - 0.4), tip[1] - size * math.sin(ang - 0.4))
    right = (tip[0] - size * math.cos(ang + 0.4), tip[1] - size * math.sin(ang + 0.4))
    d.polygon([tip, left, right], fill=color)
    if label:
        f = font(18)
        w = d.textlength(label, font=f)
        mx = (start[0] + end[0]) / 2 - w / 2
        my = (start[1] + end[1]) / 2 - (30 if labels_above else -14)
        d.text((mx, my), label, font=f, fill=MUTED if color == BORDER else color)


def warn_tag(d: ImageDraw.ImageDraw, xy, text: str) -> None:
    x, y = xy
    f = font(19)
    w = d.textlength(text, font=f)
    d.rounded_rectangle((x, y, x + w + 26, y + 34), radius=6, fill=WARN_FILL, outline=WARN, width=1)
    d.text((x + 13, y + 6), text, font=f, fill=WARN)


def ok_tag(d: ImageDraw.ImageDraw, xy, text: str) -> None:
    x, y = xy
    f = font(19)
    w = d.textlength(text, font=f)
    d.rounded_rectangle((x, y, x + w + 26, y + 34), radius=6, fill=(236, 247, 241), outline=OK, width=1)
    d.text((x + 13, y + 6), text, font=f, fill=OK)


def before() -> Path:
    W, H = 1500, 560
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    d.text((60, 44), "图 1　改造前：后端与数据库直接对外", font=font(30, bold=True), fill=INK)

    box(d, (70, 190, 330, 330), "浏览器", "玩家")
    box(d, (520, 170, 880, 350), "FastAPI 单实例", "对外 0.0.0.0:8000")
    box(d, (1070, 190, 1410, 330), "MySQL", "对外 0.0.0.0:3306")

    arrow(d, (330, 260), (520, 260), "HTTP 明文")
    arrow(d, (880, 260), (1070, 260), "明文连接")

    warn_tag(d, (400, 400), "请求行与正文在链路上可见")
    warn_tag(d, (930, 400), "数据库端口暴露在宿主机")
    warn_tag(d, (520, 90), "只有一台，挂了就没有服务")

    d.text((60, 470), "三处问题：传输明文、源站可直接访问、后端无冗余。",
           font=font(21), fill=MUTED)
    p = OUT / "fig1-before.png"
    img.save(p)
    return p


def after() -> Path:
    W, H = 1600, 720
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    d.text((60, 40), "图 2　改造后：所有流量经过入口网关", font=font(30, bold=True), fill=INK)

    box(d, (60, 260, 290, 390), "浏览器", "玩家")

    # 网关这一块自己画：标题在左上角，下面列职责，不用居中标题（会和列表撞）
    d.rounded_rectangle((390, 130, 800, 520), radius=10, fill=ACCENT_FILL, outline=ACCENT, width=3)
    d.text((418, 156), "nginx 网关", font=font(28, bold=True), fill=INK)
    d.text((418, 200), "对外 80 / 443", font=font(20), fill=ACCENT)
    duties = [
        "TLS 终止（80 跳 443）",
        "限流 8 r/s，burst 20",
        "静态托管与缓存",
        "安全响应头、抹版本号",
        "把客户端 IP 传给后端",
        "按 least_conn 分给三台",
    ]
    for i, line in enumerate(duties):
        d.text((418, 240 + i * 34), "· " + line, font=font(19), fill=INK)

    ys = [100, 270, 440]
    for i, y in enumerate(ys, start=1):
        box(d, (930, y, 1240, y + 110), f"server-{i}", "内网 8000")

    box(d, (1340, 250, 1560, 380), "MySQL", "内网 3306")

    arrow(d, (290, 325), (390, 325), "HTTPS")
    for y in ys:
        arrow(d, (800, 325), (930, y + 55), "", color=ACCENT)
    for y in ys:
        arrow(d, (1240, y + 55), (1340, 300), "", color=BORDER)

    ok_tag(d, (60, 430), "只开放 80 / 443")
    ok_tag(d, (400, 556), "后端与数据库不出内网")
    ok_tag(d, (620, 612), "停一台不报错，10 秒后自动回池")

    d.text((60, 640), "网关同时负责四件事：加密、限流、藏源站、分发。",
           font=font(21), fill=MUTED)
    p = OUT / "fig2-after.png"
    img.save(p)
    return p


def trim(p: Path, pad: int = 18) -> None:
    """裁掉四周空白，图放进 Word 后字才不会显得小。"""
    img = Image.open(p).convert("RGB")
    bbox = ImageChops.difference(img, Image.new("RGB", img.size, BG)).getbbox()
    if not bbox:
        return
    x0, y0, x1, y1 = bbox
    img.crop((
        max(0, x0 - pad), max(0, y0 - pad),
        min(img.width, x1 + pad), min(img.height, y1 + pad),
    )).save(p)


if __name__ == "__main__":
    for path in (before(), after()):
        trim(path)
        print(path)
