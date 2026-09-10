# 数据库工程 database/

本目录对应课程交付物 **7. 数据库脚本文件**，分两层：

| 子目录 / 文件 | 数据库 | 用途 | 交付定位 |
|---|---|---|---|
| `schema.sql` | MySQL 8 | 服务器：users / saves / events / leaderboard | 服务器数据库脚本 |
| `seed.sql` | MySQL 8 | 服务器初始数据 | 服务器数据库脚本 |
| `migrations/` | — | 增量变更（后续演进） | 版本管理 |
| `game_data/schema.sql` | SQLite | 游戏内容库：items/enemies/npc/dialogues/endings/sacrifices | 游戏数据库脚本 |
| `game_data/seed.sql` | SQLite | 游戏初始内容 | 游戏数据库脚本 |
| `game_data/game_data.db` | SQLite | 构建产物（.gitignore，不提交） | 生成物 |

## 数据流

**游戏内容库**（静态，数据驱动）：
`game_data/*.sql` → `tools/build_game_data.py` → `game_data.db` → `tools/db_export.py` → `client/data/*.json` → Godot `DataDB` 运行时读取。

**服务器**（动态）：FastAPI（`server/`）操作 MySQL，schema 与 `server/app/models.py` 保持一致；Docker 首次启动会自动执行 `schema.sql` + `seed.sql`（见 `deploy/docker-compose.yml`）。

## 常用命令

```powershell
# 重建游戏内容库并导出
python tools/build_game_data.py
python tools/db_export.py

# 初始化 MySQL（本地）
mysql -u root -p < database/schema.sql
mysql -u root -p < database/seed.sql
```

## 约定

- 表结构变更：改 schema.sql + 加 `migrations/` 增量 + 同步 `server/app/models.py` 或 `client/autoload/data_db.gd` + 更新 `docs/03-系统详细设计.md` 的 ER 图。
- 所有 SQL 文件保持 UTF-8 编码。
