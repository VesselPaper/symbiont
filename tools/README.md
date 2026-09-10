# 工具集 tools/

数据管道（游戏内容库 → 运行时 JSON）：

```
database/game_data/*.sql
      │  python tools/build_game_data.py
      ▼
database/game_data/game_data.db   (SQLite，.gitignore 忽略)
      │  python tools/db_export.py
      ▼
client/data/<表>/*.json           (Godot 运行时由 DataDB 加载)
```

- `build_game_data.py`：执行 schema.sql + seed.sql 生成 SQLite。
- `db_export.py`：按表导出 JSON（每主键一个文件 + `*_index.json` 索引）。
- `tests/test_db_export.py`：链路测试（pytest）。

**铁律**：`client/data/` 下的 JSON 是生成物，禁止手改。改数据 = 改 SQL → 重新导出。

后续可在此增加：`asset_audit.py`（素材引用完整性检查）、AI 精灵图处理脚本等。
