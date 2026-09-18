# -*- coding: utf-8 -*-
"""把需求分析文档 md 转成 Word(docx)，嵌入图片，采用正式中文文档样式。
用法: python tools/md_to_docx.py <input.md> <output.docx>
"""
import re
import sys
from pathlib import Path

from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

IMG_W = Cm(14.5)
EA_FONT = '微软雅黑'
EN_FONT = 'Microsoft YaHei'
DARK = RGBColor(0x1F, 0x38, 0x64)      # 标题深蓝
HEADER_FILL = 'D9E2F3'                 # 表头浅蓝底


def set_ea_font(style_or_run, ea=EA_FONT, en=EN_FONT):
    """同时设置中英文（eastAsia）字体。"""
    font = style_or_run.font
    font.name = en
    rpr = font.element.get_or_add_rPr()
    rfonts = rpr.find(qn('w:rFonts'))
    if rfonts is None:
        rfonts = OxmlElement('w:rFonts')
        rpr.append(rfonts)
    rfonts.set(qn('w:eastAsia'), ea)


def shade_cell(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill)
    tcPr.append(shd)


def add_hrule(doc):
    """标题下加一条细横线。"""
    p = doc.add_paragraph()
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement('w:pBdr')
    bottom = OxmlElement('w:bottom')
    bottom.set(qn('w:val'), 'single')
    bottom.set(qn('w:sz'), '8')
    bottom.set(qn('w:space'), '1')
    bottom.set(qn('w:color'), '1F3864')
    pBdr.append(bottom)
    pPr.append(pBdr)


def add_page_number(doc):
    """页脚居中页码。"""
    for sec in doc.sections:
        footer = sec.footer
        p = footer.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        # PAGE 域
        run = p.add_run()
        fldChar1 = OxmlElement('w:fldChar')
        fldChar1.set(qn('w:fldCharType'), 'begin')
        instrText = OxmlElement('w:instrText')
        instrText.set(qn('xml:space'), 'preserve')
        instrText.text = 'PAGE'
        fldChar2 = OxmlElement('w:fldChar')
        fldChar2.set(qn('w:fldCharType'), 'end')
        run._r.append(fldChar1)
        run._r.append(instrText)
        run._r.append(fldChar2)
        run.font.size = Pt(9)
        run.font.color.rgb = RGBColor(0x59, 0x59, 0x59)


def parse_table(lines):
    """解析连续表格行, 返回 (表格行列表, 剩余lines)。"""
    rows = []
    for line in lines:
        if not line.startswith('|'):
            break
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if all(re.fullmatch(r':?-{2,}:?', c) for c in cells):
            continue
        rows.append(cells)
    return rows


def add_table(doc, rows):
    if not rows:
        return
    ncols = max(len(r) for r in rows)
    nrows = len(rows)
    table = doc.add_table(rows=nrows, cols=ncols)
    table.style = 'Table Grid'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = True

    for i, r in enumerate(rows):
        for j in range(ncols):
            cell = table.cell(i, j)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            text = r[j] if j < len(r) else ''
            cell.text = ''
            p = cell.paragraphs[0]
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(2)
            run = p.add_run(text)
            set_ea_font(run)
            run.font.size = Pt(10.5)
            if i == 0:
                run.font.bold = True
                run.font.color.rgb = DARK
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                shade_cell(cell, HEADER_FILL)
    # 表格后加一个紧凑空段
    sp = doc.add_paragraph()
    sp.paragraph_format.space_before = Pt(2)
    sp.paragraph_format.space_after = Pt(2)


def main(md_path, out_path):
    md_path = Path(md_path)
    out_path = Path(out_path)
    base = md_path.parent

    doc = Document()

    # 页面边距
    for sec in doc.sections:
        sec.top_margin = Cm(2.2)
        sec.bottom_margin = Cm(2.2)
        sec.left_margin = Cm(2.5)
        sec.right_margin = Cm(2.5)

    # Normal 正文
    normal = doc.styles['Normal']
    set_ea_font(normal)
    normal.font.size = Pt(10.5)
    normal.paragraph_format.space_after = Pt(4)
    normal.paragraph_format.line_spacing = 1.3

    # 标题样式：去默认丑蓝，用深蓝 + 微软雅黑
    h1 = doc.styles['Heading 1']
    set_ea_font(h1)
    h1.font.size = Pt(20)
    h1.font.bold = True
    h1.font.color.rgb = DARK
    h1.paragraph_format.space_before = Pt(6)
    h1.paragraph_format.space_after = Pt(6)

    h2 = doc.styles['Heading 2']
    set_ea_font(h2)
    h2.font.size = Pt(14)
    h2.font.bold = True
    h2.font.color.rgb = DARK
    h2.paragraph_format.space_before = Pt(10)
    h2.paragraph_format.space_after = Pt(4)

    h3 = doc.styles['Heading 3']
    set_ea_font(h3)
    h3.font.size = Pt(12)
    h3.font.bold = True
    h3.font.color.rgb = RGBColor(0x2E, 0x4E, 0x7E)
    h3.paragraph_format.space_before = Pt(6)
    h3.paragraph_format.space_after = Pt(2)

    add_page_number(doc)

    lines = md_path.read_text(encoding='utf-8').splitlines()
    i = 0
    first_heading_done = False
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue

        m = re.match(r'^(#{1,6})\s+(.*)$', line)
        if m:
            level = len(m.group(1))
            text = m.group(2).strip()
            doc.add_heading(text, level=min(level, 3))
            if level == 1 and not first_heading_done:
                add_hrule(doc)
                first_heading_done = True
            i += 1
            continue

        if line.startswith('|'):
            rows = parse_table(lines[i:])
            add_table(doc, rows)
            i += len(rows) + 1
            continue

        m = re.match(r'!\[([^\]]*)\]\(([^)]+)\)', line)
        if m:
            alt, rel = m.group(1), m.group(2)
            img_path = (base / rel).resolve()
            if img_path.exists():
                p = doc.add_paragraph()
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                p.add_run().add_picture(str(img_path), width=IMG_W)
                p.paragraph_format.space_before = Pt(4)
                p.paragraph_format.space_after = Pt(2)
                # 图片段落加细边框
                pPr = p._p.get_or_add_pPr()
                pBdr = OxmlElement('w:pBdr')
                for side in ('top', 'left', 'bottom', 'right'):
                    b = OxmlElement(f'w:{side}')
                    b.set(qn('w:val'), 'single')
                    b.set(qn('w:sz'), '4')
                    b.set(qn('w:space'), '4')
                    b.set(qn('w:color'), 'BFBFBF')
                    pBdr.append(b)
                pPr.append(pBdr)
                if alt:
                    cap = doc.add_paragraph()
                    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    run = cap.add_run(alt)
                    set_ea_font(run)
                    run.font.size = Pt(9)
                    run.font.color.rgb = RGBColor(0x59, 0x59, 0x59)
            else:
                doc.add_paragraph(f'[图片缺失: {rel}]')
            i += 1
            continue

        if line.startswith('- '):
            p = doc.add_paragraph(style='List Bullet')
            p.paragraph_format.space_after = Pt(2)
            run = p.add_run(line[2:].strip())
            set_ea_font(run)
            run.font.size = Pt(10.5)
            i += 1
            continue

        if re.match(r'^\d+\.\s', line):
            p = doc.add_paragraph(style='List Number')
            p.paragraph_format.space_after = Pt(2)
            run = p.add_run(re.sub(r'^\d+\.\s*', '', line).strip())
            set_ea_font(run)
            run.font.size = Pt(10.5)
            i += 1
            continue

        p = doc.add_paragraph()
        run = p.add_run(line.strip())
        set_ea_font(run)
        run.font.size = Pt(10.5)
        i += 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(out_path))
    print(f'OK -> {out_path}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
