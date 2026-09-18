# -*- coding: utf-8 -*-
"""把需求分析文档 md 转成 Word(docx)，嵌入图片。
用法: python tools/md_to_docx.py <input.md> <output.docx>
"""
import re
import sys
from pathlib import Path

from docx import Document
from docx.shared import Cm, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

IMG_W = Cm(15.0)


def parse_table(lines):
    """解析连续表格行, 返回 (表格行列表, 剩余lines)。"""
    rows = []
    for line in lines:
        if not line.startswith('|'):
            break
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        # 跳过分隔行 |---|
        if all(re.fullmatch(r':?-{2,}:?', c) for c in cells):
            continue
        rows.append(cells)
    return rows, lines[len(rows) + (len(lines) > len(rows)):]


def add_table(doc, rows):
    if not rows:
        return
    ncols = max(len(r) for r in rows)
    table = doc.add_table(rows=len(rows), cols=ncols)
    table.style = 'Table Grid'
    for i, r in enumerate(rows):
        for j in range(ncols):
            cell = table.cell(i, j)
            cell.text = r[j] if j < len(r) else ''
    # 表头加粗
    for j in range(ncols):
        table.cell(0, j).paragraphs[0].runs and [
            r.font.bold for r in table.cell(0, j).paragraphs[0].runs
        ]
    doc.add_paragraph()


def main(md_path, out_path):
    md_path = Path(md_path)
    out_path = Path(out_path)
    base = md_path.parent

    doc = Document()
    style = doc.styles['Normal']
    style.font.name = 'Microsoft YaHei'
    style.font.size = Pt(11)

    lines = md_path.read_text(encoding='utf-8').splitlines()
    i = 0
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
            i += 1
            continue

        if line.startswith('|'):
            rows, _ = parse_table(lines[i:])
            add_table(doc, rows)
            i += len(rows) + 1  # 跳过表格行和分隔行
            continue

        m = re.match(r'!\[([^\]]*)\]\(([^)]+)\)', line)
        if m:
            alt, rel = m.group(1), m.group(2)
            img_path = (base / rel).resolve()
            if img_path.exists():
                p = doc.add_paragraph()
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                p.add_run().add_picture(str(img_path), width=IMG_W)
                if alt:
                    cap = doc.add_paragraph()
                    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    run = cap.add_run(alt)
                    run.font.size = Pt(9)
                    run.font.color.rgb = None
            else:
                doc.add_paragraph(f'[图片缺失: {rel}]')
            i += 1
            continue

        if line.startswith('- '):
            p = doc.add_paragraph(style='List Bullet')
            p.add_run(line[2:].strip())
            i += 1
            continue

        if re.match(r'^\d+\.\s', line):
            p = doc.add_paragraph(style='List Number')
            p.add_run(re.sub(r'^\d+\.\s*', '', line).strip())
            i += 1
            continue

        doc.add_paragraph(line.strip())
        i += 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(out_path))
    print(f'OK -> {out_path}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
