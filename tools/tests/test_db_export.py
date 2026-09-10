"""数据管道测试：SQLite → JSON 导出链路。"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import build_game_data as bgd
import db_export as dbe


def test_build_then_export(tmp_path):
    db = tmp_path / "g.db"
    bgd.build(db)
    out = tmp_path / "data"
    stats = dbe.export_all(db_path=db, data_dir=out)

    for table in dbe.TABLES:
        assert table in stats, f"缺少表导出: {table}"
        index = json.loads((out / table / f"{table}_index.json").read_text(encoding="utf-8"))
        assert isinstance(index, dict)
        assert len(index) == stats[table]


def test_exports_parse_as_json(tmp_path):
    db = tmp_path / "g2.db"
    bgd.build(db)
    out = tmp_path / "data2"
    dbe.export_all(db_path=db, data_dir=out)

    # 每行 JSON 可解析且含主键字段
    item = json.loads((out / "items" / "iron_sword.json").read_text(encoding="utf-8"))
    assert item["id"] == "iron_sword"
    assert item["type"] == "weapon"
    assert item["stats"] == {"atk": 10}          # JSON 列已解析为对象


def test_canonical_data_contains_core_endings():
    # 使用仓库默认路径，验证正式导出的核心内容存在（同时也是实际导出结果自检）
    db = ROOT / "database/game_data/game_data.db"
    if not db.exists():
        bgd.build(db)
    out = ROOT / "client/data"
    dbe.export_all(db_path=db, data_dir=out)

    endings = json.loads((out / "endings" / "endings_index.json").read_text(encoding="utf-8"))
    for key in ("human", "transformed", "true_he", "refuse_die"):
        assert key in endings, f"结局缺失: {key}"
