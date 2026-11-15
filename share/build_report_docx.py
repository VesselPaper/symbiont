"""把技术报告 Markdown 排成 Word 文档。

只支持报告里用到的语法：标题、二级标题、段落、表格、代码块、图片、有序列表。
排版按中文报告的习惯：正文宋体小四、行距 1.5、首行缩进两字，标题黑体。
"""
from __future__ import annotations

import re
from pathlib import Path

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

HERE = Path(__file__).resolve().parent
SRC = HERE / "应用代理与负载均衡-技术报告.md"
OUT = HERE / "应用代理与负载均衡-技术报告.docx"

BODY_FONT = "宋体"
HEAD_FONT = "黑体"
MONO_FONT = "Courier New"


def set_fonts(style, name: str) -> None:
    """python-docx 只设 font.name 对中文不生效，必须同时写 w:eastAsia。"""
    style.font.name = name
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:ascii"), name)
    rfonts.set(qn("w:hAnsi"), name)
    rfonts.set(qn("w:eastAsia"), name)


def run_fonts(run, name: str) -> None:
    run.font.name = name
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:ascii"), name)
    rfonts.set(qn("w:hAnsi"), name)
    rfonts.set(qn("w:eastAsia"), name)


def shade(cell, hex_color: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:fill"), hex_color)
    tc_pr.append(shd)


def para_shade(paragraph, hex_color: str) -> None:
    p_pr = paragraph._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:fill"), hex_color)
    p_pr.append(shd)


def add_page_number(footer) -> None:
    p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    run._r.addnext(fld)


def setup_styles(doc: Document) -> None:
    normal = doc.styles["Normal"]
    set_fonts(normal, BODY_FONT)
    normal.font.size = Pt(12)
    pf = normal.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    pf.space_after = Pt(6)
    pf.first_line_indent = Pt(24)  # 小四字号下约两字符

    for name, size in (("Heading 1", 15), ("Heading 2", 13)):
        st = doc.styles[name]
        set_fonts(st, HEAD_FONT)
        st.font.size = Pt(size)
        st.font.color.rgb = RGBColor(0, 0, 0)
        st.paragraph_format.first_line_indent = Pt(0)
        st.paragraph_format.space_before = Pt(12 if name == "Heading 1" else 8)
        st.paragraph_format.space_after = Pt(6)
        st.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE


BOLD = re.compile(r"\*\*(.+?)\*\*")
CODE = re.compile(r"`(.+?)`")


def add_rich(paragraph, text: str, *, size: float | None = None, font: str | None = None) -> None:
    """处理 **加粗** 与 `行内代码`，其他按普通文本。"""
    base = size or 12
    for tok in re.split(r"(\*\*.+?\*\*|`.+?`)", text):
        if not tok:
            continue
        m_bold = BOLD.fullmatch(tok)
        m_code = CODE.fullmatch(tok)

        if m_code:
            run = paragraph.add_run(m_code.group(1))
            run_fonts(run, MONO_FONT)
            run.font.size = Pt(base - 1.5)
            continue

        run = paragraph.add_run(m_bold.group(1) if m_bold else tok)
        if m_bold:
            run.bold = True
        if font:
            run_fonts(run, font)
        if size:
            run.font.size = Pt(size)


def disp_len(text: str) -> int:
    """估算一格内容有多宽：中文按两个西文字符算，去掉 Markdown 标记。"""
    plain = text.replace("**", "").replace("`", "")
    return sum(2 if ord(ch) > 0x2E80 else 1 for ch in plain)


UNIT_CM = 0.19   # 五号西文一个字符大约占多少厘米
PAD_CM = 0.5     # 单元格左右内边距合计
MIN_CM = 1.8
ASCII_TOKEN = re.compile(r"[A-Za-z0-9_./:@%\-]+")


def col_widths(rows: list[list[str]], total_cm: float = 15.8) -> list[float]:
    """先保证每列放得下最长的英文/代码片段，再把剩余宽度按内容量分配。

    只按整格内容算会把"职责"列压到 1.6 cm，四个汉字就折行；
    连中文也当成不断词又会把"后端与数据库不映射宿主机端口"这种长句
    撑成 5.8 cm。中文可以逐字断行，所以只有英文和代码算硬约束。
    """
    n = len(rows[0])
    mins = []
    bulk = []
    for c in range(n):
        longest = 0
        for r in rows:
            for token in ASCII_TOKEN.findall(r[c].replace("**", "").replace("`", "")):
                longest = max(longest, len(token))
        mins.append(max(MIN_CM, longest * UNIT_CM + PAD_CM))
        bulk.append(max(2, max(disp_len(r[c]) for r in rows)))

    free = total_cm - sum(mins)
    if free <= 0:
        scale = total_cm / sum(mins)
        return [m * scale for m in mins]

    total_bulk = sum(bulk)
    return [mins[i] + free * bulk[i] / total_bulk for i in range(n)]


def mark_table(table) -> None:
    """表头跨页重复 + 单行不许被切开。

    表格一页放不下时会从中间断行，断掉的那半行很难看；跨页后没有表头，
    下一页那几行就不知道每列是什么意思。
    """
    header_pr = table.rows[0]._tr.get_or_add_trPr()
    hdr = OxmlElement("w:tblHeader")
    hdr.set(qn("w:val"), "true")
    header_pr.append(hdr)

    for row in table.rows:
        tr_pr = row._tr.get_or_add_trPr()
        tr_pr.append(OxmlElement("w:cantSplit"))


def fix_table_width(table, rows: list[list[str]], total_cm: float = 15.8) -> None:
    """锁成固定布局并逐格写宽度，否则 Word/LibreOffice 会自己重排。"""
    widths = col_widths(rows, total_cm)

    table.autofit = False
    tbl_pr = table._tbl.tblPr
    layout = OxmlElement("w:tblLayout")
    layout.set(qn("w:type"), "fixed")
    tbl_pr.append(layout)

    for i, w in enumerate(widths):
        table.columns[i].width = Cm(w)
    for row in table.rows:
        for i, w in enumerate(widths):
            row.cells[i].width = Cm(w)


def keep_table_together(table) -> None:
    """小表整体不许跨页。

    只靠"表头跨页重复"能救，但那会留下一个只有表头和半行的孤页开头。
    表本身不高时直接整张挪到下一页更干净。
    """
    if len(table.rows) > 8:
        return
    for row in table.rows[:-1]:
        for cell in row.cells:
            for p in cell.paragraphs:
                p.paragraph_format.keep_with_next = True


def add_table(doc: Document, rows: list[list[str]]) -> None:
    cols = len(rows[0])
    table = doc.add_table(rows=len(rows), cols=cols)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER

    for r, row in enumerate(rows):
        for c, text in enumerate(row):
            cell = table.cell(r, c)
            cell.text = ""
            p = cell.paragraphs[0]
            p.paragraph_format.first_line_indent = Pt(0)
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.space_before = Pt(2)
            add_rich(p, text, size=10.5)
            if r == 0:
                for run in p.runs:
                    run.bold = True
                shade(cell, "F2F4F8")

    fix_table_width(table, rows)
    mark_table(table)
    keep_table_together(table)
    doc.add_paragraph()


def add_code(doc: Document, lines: list[str], keep_with_next: bool = False) -> None:
    for i, line in enumerate(lines):
        p = doc.add_paragraph()
        pf = p.paragraph_format
        pf.first_line_indent = Pt(0)
        pf.left_indent = Pt(18)
        pf.space_after = Pt(0)
        pf.space_before = Pt(6) if i == 0 else Pt(0)
        pf.line_spacing_rule = WD_LINE_SPACING.SINGLE
        pf.keep_together = True
        # 整块代码不许被分页切开；只有最后一行之后允许断开
        if i < len(lines) - 1 or keep_with_next:
            pf.keep_with_next = True
        para_shade(p, "F5F6F8")
        run = p.add_run(line if line else " ")
        run_fonts(run, MONO_FONT)
        run.font.size = Pt(9.5)
    doc.add_paragraph().paragraph_format.space_after = Pt(6)


def parse(md: str):
    """切块：按行扫描，返回 (类型, 内容) 序列。"""
    blocks = []
    lines = md.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            i += 1
            buf = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            blocks.append(("code", buf))
            continue

        if stripped.startswith("# "):
            blocks.append(("title", stripped[2:].strip()))
            i += 1
            continue

        if stripped.startswith("## "):
            text = stripped[3:].strip()
            blocks.append(("subtitle" if text.startswith("——") else "h1", text))
            i += 1
            continue

        if stripped.startswith("### "):
            blocks.append(("h2", stripped[4:].strip()))
            i += 1
            continue

        img = re.fullmatch(r"!\[(.*?)\]\((.*?)\)", stripped)
        if img:
            blocks.append(("image", img.group(2)))
            i += 1
            continue

        if stripped.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                raw = lines[i].strip().strip("|")
                cells = [c.strip() for c in raw.split("|")]
                if not all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                    rows.append(cells)
                i += 1
            blocks.append(("table", rows))
            continue

        if re.match(r"^\d+\.\s", stripped):
            blocks.append(("numbered", stripped))
            i += 1
            continue

        if stripped == "":
            i += 1
            continue

        # 署名行
        if stripped.startswith("2 组"):
            blocks.append(("byline", stripped))
            i += 1
            continue

        blocks.append(("p", stripped))
        i += 1
    return blocks


def build() -> Path:
    doc = Document()
    setup_styles(doc)

    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21), Cm(29.7)
    sec.top_margin = sec.bottom_margin = Cm(2.54)
    sec.left_margin = sec.right_margin = Cm(2.5)
    add_page_number(sec.footer)

    blocks = parse(SRC.read_text(encoding="utf-8"))

    for i, (kind, content) in enumerate(blocks):
        nxt = blocks[i + 1][0] if i + 1 < len(blocks) else ""
        if kind == "title":
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(24)
            p.paragraph_format.space_after = Pt(6)
            p.paragraph_format.first_line_indent = Pt(0)
            run = p.add_run(content)
            run_fonts(run, HEAD_FONT)
            run.font.size = Pt(20)
            run.bold = True
        elif kind == "subtitle":
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Pt(0)
            p.paragraph_format.space_after = Pt(12)
            run = p.add_run(content)
            run_fonts(run, HEAD_FONT)
            run.font.size = Pt(14)
        elif kind == "byline":
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Pt(0)
            p.paragraph_format.space_after = Pt(18)
            run = p.add_run(content)
            run_fonts(run, BODY_FONT)
            run.font.size = Pt(11)
            run.font.color.rgb = RGBColor(0x55, 0x5F, 0x70)
        elif kind == "h1":
            doc.add_heading(content, level=1).paragraph_format.keep_with_next = True
        elif kind == "h2":
            doc.add_heading(content, level=2).paragraph_format.keep_with_next = True
        elif kind == "p":
            p = doc.add_paragraph()
            if content.startswith("**关键词**"):
                p.paragraph_format.first_line_indent = Pt(0)
            # "地址池部分："这类引出句必须和下面的代码块同页；
            # 表格同理，否则标题和"下表……"会孤独地留在上一页底部
            if nxt in ("code", "table"):
                p.paragraph_format.keep_with_next = True
            add_rich(p, content)
        elif kind == "numbered":
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Pt(24)
            p.paragraph_format.first_line_indent = Pt(0)
            add_rich(p, content)
        elif kind == "table":
            add_table(doc, content)
        elif kind == "code":
            add_code(doc, content)
        elif kind == "image":
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Pt(0)
            p.paragraph_format.space_before = Pt(6)
            p.paragraph_format.space_after = Pt(10)
            p.add_run().add_picture(str(HERE / content), width=Cm(15.5))

    doc.save(OUT)
    return OUT


if __name__ == "__main__":
    print(build())
