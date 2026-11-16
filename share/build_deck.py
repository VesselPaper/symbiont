"""用 powerpoint-deck-designer 这个 skill 来渲染分享材料。

skill 本身提供主题系统、九种版式和校验器，但没有图片页和大数字页；
这份内容里有代码截图、浏览器截图和几组关键数字，所以在它的 LayoutEngine
上加了三种版式（picture、stats、ledger），其余全部沿用 skill 的规则。

用法：
    python share/build_deck.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from pptx import Presentation
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

ROOT = Path(__file__).resolve().parent
SKILL = Path.home() / ".agents" / "skills" / "powerpoint-deck-designer"

sys.path.insert(0, str(SKILL / "scripts"))

from layout_engine import LayoutEngine  # noqa: E402
from theme_engine import ThemeEngine  # noqa: E402

SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)
MARGIN = Inches(0.7)
CONTENT_TOP = Inches(1.75)


class DeckEngine(LayoutEngine):
    """在 skill 的基础上补三种版式，其余规则不动。"""

    # 一张大图，标题在上。用于代码截图和浏览器截图。
    def _layout_picture(self, slide, spec):
        self._layout_heading(slide, spec)
        path = ROOT / spec["image"]
        box_w = self.slide_w - MARGIN * 2
        box_top = Inches(1.62)
        box_h = self.slide_h - box_top - Inches(0.62)
        pic = slide.shapes.add_picture(str(path), MARGIN, box_top, width=box_w)
        if pic.height > box_h:
            ratio = box_h / pic.height
            pic.width = int(pic.width * ratio)
            pic.height = box_h
        pic.left = int((self.slide_w - pic.width) / 2)
        pic.line.color.rgb = self.theme.rgb("secondary")
        pic.line.width = Pt(0.75)

    # 四个大数字横排，下面一行说明。
    def _layout_stats(self, slide, spec):
        self._layout_heading(slide, spec)
        items = spec.get("stats", [])[:4]
        gap = Inches(0.3)
        cell = int((self.slide_w - MARGIN * 2 - gap * (len(items) - 1)) / max(1, len(items)))
        for i, item in enumerate(items):
            x = MARGIN + (cell + gap) * i
            self._raw_text(slide, x, Inches(1.9), cell, Inches(0.85),
                           item["value"], 40, "primary", bold=True)
            self._raw_text(slide, x, Inches(2.72), cell, Inches(0.32),
                           item.get("unit", ""), 13, "muted")
            self._raw_text(slide, x, Inches(3.08), cell, Inches(0.62),
                           item.get("label", ""), 14, "text")
        note = spec.get("body") or ""
        if note:
            self._raw_text(slide, MARGIN, Inches(4.4), self.slide_w - MARGIN * 2,
                           Inches(1.4), note, 18, "text", line=1.55)

    # 左右两栏对照，每行一条，中间一个箭头。用于改造前后。
    def _layout_ledger(self, slide, spec):
        self._layout_heading(slide, spec)
        rows = spec.get("rows", [])
        left_w = Inches(4.0)
        right_x = MARGIN + left_w + Inches(1.0)
        right_w = self.slide_w - right_x - MARGIN
        y = CONTENT_TOP + Inches(0.1)
        step = Inches(0.72)
        for before, after in rows:
            self._raw_text(slide, MARGIN, y, left_w, Inches(0.36), before, 15, "muted")
            self._accent_bar(slide, MARGIN + left_w + Inches(0.2),
                             int(y + Inches(0.16)), Inches(0.45), Inches(0.03), "secondary")
            self._raw_text(slide, right_x, y, right_w, Inches(0.36), after, 15, "text")
            y += step

    # -------- 内部：标题与文字 ------
    # 章节页：skill 原版用一条整宽主色带，太抢眼；换成深色面板加左侧竖线。
    def _layout_section(self, slide, spec):
        band_top = Inches(2.5)
        band_h = Inches(2.3)
        panel = slide.shapes.add_shape(1, 0, band_top, self.slide_w, band_h)
        panel.line.fill.background()
        panel.fill.solid()
        panel.fill.fore_color.rgb = self.theme.rgb("surface")
        panel.shadow.inherit = False
        self._accent_bar(slide, MARGIN, band_top + Inches(0.85),
                         Inches(0.06), Inches(0.6), "primary")
        self._raw_text(slide, MARGIN + Inches(0.3), band_top + Inches(0.72),
                       self.slide_w - MARGIN * 2, Inches(0.9),
                       spec.get("title", ""), 40, "text", bold=True, font_key="heading")
        self._raw_text(slide, MARGIN + Inches(0.3), band_top + band_h + Inches(0.35),
                       self.slide_w - MARGIN * 2, Inches(0.5),
                       spec.get("subtitle", ""), 16, "muted")

    # 正文页：skill 原版把条目顶在最上面，下半页空一大块；这里改成整块垂直居中。
    def _layout_content(self, slide, spec):
        self._layout_heading(slide, spec)
        top = CONTENT_TOP + Inches(0.1)
        height = self.slide_h - top - Inches(0.7)
        bullets = spec.get("bullets") or []
        if bullets:
            self._bullet_block(slide, MARGIN, top, self.slide_w - MARGIN * 2, height, bullets, 20)
        elif spec.get("body"):
            self._raw_text(slide, MARGIN, top, self.slide_w - MARGIN * 2, height,
                           spec["body"], 20, "text", line=1.6, anchor=MSO_ANCHOR.MIDDLE)

    def _layout_two_column(self, slide, spec):
        self._layout_heading(slide, spec)
        cols = spec.get("columns", [])[:2]
        col_w = int((self.slide_w - MARGIN * 2 - Inches(0.5)) / 2)
        top = CONTENT_TOP + Inches(0.1)
        height = self.slide_h - top - Inches(0.7)
        for i, col in enumerate(cols):
            x = MARGIN + (col_w + Inches(0.5)) * i
            self._raw_text(slide, x, top, col_w, Inches(0.42),
                           col.get("title", ""), 20, "primary", bold=True)
            body_top = top + Inches(0.62)
            body_h = height - Inches(0.62)
            if col.get("bullets"):
                self._bullet_block(slide, x, body_top, col_w, body_h, col["bullets"], 16)
            elif col.get("body"):
                self._raw_text(slide, x, body_top, col_w, body_h, col["body"], 16, "text", line=1.6)

    # 卡片页：原版卡片撑满整页，字只在最上面；这里按内容定高并居中。
    def _layout_cards(self, slide, spec):
        self._layout_heading(slide, spec)
        cards = spec.get("cards", [])[:6]
        n = len(cards)
        gap = Inches(0.25)
        card_w = int((self.slide_w - MARGIN * 2 - gap * (n - 1)) / max(1, n))
        card_h = Inches(2.5)
        top = int((self.slide_h - card_h) / 2 + Inches(0.35))
        for i, c in enumerate(cards):
            x = MARGIN + (card_w + gap) * i
            box = slide.shapes.add_shape(1, x, top, card_w, card_h)
            box.line.color.rgb = self.theme.rgb("secondary")
            box.line.width = Pt(0.75)
            box.fill.solid()
            box.fill.fore_color.rgb = self.theme.rgb("surface")
            box.shadow.inherit = False
            self._raw_text(slide, x + Inches(0.24), top + Inches(0.22),
                           card_w - Inches(0.48), Inches(0.42), c.get("title", ""),
                           19, "primary", bold=True)
            self._raw_text(slide, x + Inches(0.24), top + Inches(0.78),
                           card_w - Inches(0.48), card_h - Inches(1.0), c.get("body", ""),
                           15, "text", line=1.6)

    def _bullet_block(self, slide, left, top, width, height, bullets, size):
        tb = slide.shapes.add_textbox(left, top, width, height)
        tf = tb.text_frame
        tf.word_wrap = True
        tf.vertical_anchor = MSO_ANCHOR.MIDDLE
        tf.margin_left = tf.margin_right = 0
        tf.margin_top = tf.margin_bottom = 0
        for i, b in enumerate(bullets):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            p.alignment = PP_ALIGN.LEFT
            p.line_spacing = 1.35
            p.space_after = Pt(size * 0.7)
            run = p.add_run()
            run.text = "·  " + str(b)
            run.font.name = self.theme.fonts["body"]
            run.font.size = Pt(size)
            run.font.color.rgb = self.theme.rgb("text")

    def _layout_heading(self, slide, spec):
        self._accent_bar(slide, MARGIN, Inches(0.62), Inches(0.05), Inches(0.5), "primary")
        self._raw_text(slide, MARGIN + Inches(0.24), Inches(0.52),
                       self.slide_w - MARGIN * 2 - Inches(0.3), Inches(0.7),
                       spec.get("title", ""), 30, "text", bold=True, font_key="heading",
                       line=1.15)

    def _raw_text(self, slide, left, top, width, height, text, size, color_key,
                  bold=False, font_key="body", line=1.35, anchor=MSO_ANCHOR.TOP):
        if not text:
            return
        tb = slide.shapes.add_textbox(left, top, width, height)
        tf = tb.text_frame
        tf.word_wrap = True
        tf.vertical_anchor = anchor
        tf.margin_left = tf.margin_right = 0
        tf.margin_top = tf.margin_bottom = 0
        for i, ln in enumerate(str(text).split("\n")):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            p.alignment = PP_ALIGN.LEFT
            p.line_spacing = line
            run = p.add_run()
            run.text = ln
            run.font.name = self.theme.fonts[font_key]
            run.font.size = Pt(size)
            run.font.bold = bold
            run.font.color.rgb = self.theme.rgb(color_key)


def build(spec_path: Path, out_path: Path) -> Path:
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    themes = json.loads((SKILL / "assets" / "themes.json").read_text(encoding="utf-8"))
    theme = ThemeEngine(themes).get(spec.get("theme", "modern-slate"))

    # 这套材料是中文正文，Verdana 没有中文字形，换成雅黑保证字形一致
    theme.fonts["heading"] = "微软雅黑"
    theme.fonts["body"] = "微软雅黑"

    prs = Presentation()
    prs.slide_width = SLIDE_W
    prs.slide_height = SLIDE_H

    engine = DeckEngine(prs, theme)
    slides = spec["slides"]
    for idx, slide_spec in enumerate(slides, start=1):
        engine.render(slide_spec.get("layout", "content"), slide_spec,
                      slide_number=idx, total=len(slides))

    prs.save(out_path)
    return out_path


if __name__ == "__main__":
    out = build(ROOT / "spec_share.json", ROOT / "技术分享-应用代理与负载均衡.pptx")
    print("saved", out)
