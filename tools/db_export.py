#!/usr/bin/env python3
"""把 SQLite 游戏内容库导出为 client/data/<表>/ 下的 JSON，供 Godot 运行时读取。

每个表导出:
    <table>/<id>.json          一行一条（id 取自主键）
    <table>/<table>_index.json 索引（id -> 常用字段，便于 UI/调试）

用法:
    python tools/build_game_data.py   # 先构建 .db（如已存在可跳过）
    python tools/db_export.py
"""
from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "database" / "game_data" / "game_data.db"
DEFAULT_DATA_DIR = ROOT / "client" / "data"

# 与 database/game_data/schema.sql 同步；新增表须同时更新 DataDB（client/autoload/data_db.gd）
TABLES = ["items", "enemies", "npc", "dialogues", "endings", "sacrifices"]
INDEX_SUFFIX = "_index"

# 这些列存 JSON 字符串，导出时解析为对象
JSON_COLUMNS = {"stats", "flags", "drops", "lines", "effect", "payload", "meta"}
# 索引里保留的常用字段
INDEX_FIELDS = ("name", "type", "faction", "part", "behavior")


def _parse_json_cell(value: str | None) -> object:
    if value is None or value == "":
        return {}
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return {"_raw": value}


def row_to_dict(row: tuple, cols: list[str]) -> dict:
    out: dict = {}
    for col, val in zip(cols, row):
        out[col] = _parse_json_cell(val) if col in JSON_COLUMNS else val
    return out


def export_table(conn: sqlite3.Connection, table: str, data_dir: Path) -> dict:
    cur = conn.execute(f"SELECT * FROM {table}")
    cols = [c[0] for c in cur.description]
    out_dir = data_dir / table
    out_dir.mkdir(parents=True, exist_ok=True)

    index: dict = {}
    for row in cur.fetchall():
        rec = row_to_dict(row, cols)
        pk = str(rec.get(cols[0], "")) or f"row_{len(index)}"
        (out_dir / f"{pk}.json").write_text(
            json.dumps(rec, ensure_ascii=False, indent=2),
            encoding="utf-8",
            newline="\n",
        )
        index[pk] = {k: rec[k] for k in INDEX_FIELDS if k in rec}

    (out_dir / f"{table}{INDEX_SUFFIX}.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )
    return index


def export_all(db_path: Path | str | None = None, data_dir: Path | str | None = None) -> dict:
    db_path = Path(db_path) if db_path else DEFAULT_DB
    data_dir = Path(data_dir) if data_dir else DEFAULT_DATA_DIR
    if not db_path.exists():
        raise FileNotFoundError(
            f"未找到 {db_path}，请先运行: python tools/build_game_data.py"
        )

    conn = sqlite3.connect(db_path)
    try:
        stats: dict = {}
        for table in TABLES:
            index = export_table(conn, table, data_dir)
            stats[table] = len(index)
        return stats
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=str(DEFAULT_DB), help="源 SQLite 路径")
    parser.add_argument("--out", default=str(DEFAULT_DATA_DIR), help="输出 data 目录")
    args = parser.parse_args()

    try:
        stats = export_all(args.db, args.out)
    except FileNotFoundError as exc:
        print(f"[db_export] {exc}")
        return 2

    for table, count in stats.items():
        print(f"[db_export] {table}: {count} 条")
    print(f"[db_export] OK -> {args.out} | 共 {sum(stats.values())} 条")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
