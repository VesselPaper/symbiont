#!/usr/bin/env python3
"""从 database/game_data/*.sql 构建 SQLite 游戏内容库 game_data.db。

用法:
    python tools/build_game_data.py
    python tools/build_game_data.py --out path/to/game_data.db
"""
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "database" / "game_data" / "game_data.db"


def build(db_path: Path | str | None = None) -> sqlite3.Connection:
    """执行 schema.sql + seed.sql 生成数据库，返回连接。"""
    db_path = Path(db_path) if db_path else DEFAULT_DB
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(db_path)
    try:
        for sql_file in (ROOT / "database/game_data/schema.sql", ROOT / "database/game_data/seed.sql"):
            conn.executescript(sql_file.read_text(encoding="utf-8"))
        conn.commit()
    except Exception:
        conn.close()
        raise
    return conn


def _list_tables(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    ).fetchall()
    return [r[0] for r in rows]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(DEFAULT_DB), help="输出 .db 路径")
    args = parser.parse_args()

    conn = build(args.out)
    try:
        tables = _list_tables(conn)
        print(f"[build_game_data] OK -> {args.out}")
        print(f"[build_game_data] tables: {', '.join(tables)}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
