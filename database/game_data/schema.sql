-- ============================================================
-- 共生之缚 Symbiont —— 游戏内容库 Schema（SQLite）
-- 版本: v1（M0）
--
-- 用途: 游戏静态数据源（物品/敌人/NPC/对话/结局/献祭改造）。
-- 工作流:
--   database/game_data/*.sql
--     └─ tools/build_game_data.py  →  game_data.db
--        └─ tools/db_export.py     →  client/data/<表>/*.json
--           └─ Godot DataDB 运行时加载
--
-- 约定: 表结构变化会改变导出的 JSON 结构，必须同步更新
--   docs/02-系统接口设计文档.md 与 client/scripts/autoload/data_db.gd。
-- ============================================================

PRAGMA foreign_keys = ON;

-- 物品 / 道具
CREATE TABLE IF NOT EXISTS items (
  id      TEXT PRIMARY KEY,                 -- 如 iron_sword
  name    TEXT NOT NULL,                    -- 显示名
  type    TEXT NOT NULL,                    -- weapon/shield/consumable/upgrade/quest/body_part
  desc    TEXT NOT NULL DEFAULT '',
  icon    TEXT NOT NULL DEFAULT '',         -- res://assets/ui/...（M2 填）
  stats   TEXT NOT NULL DEFAULT '{}',       -- JSON: {"atk":10,"def":0}
  obtain  TEXT NOT NULL DEFAULT '',         -- 获取方式：map_pickup / sacrifice / faction_engineer ...
  flags   TEXT NOT NULL DEFAULT '{}'        -- JSON: {"faction":"engineer","movement":"double_jump"}
);

-- 敌人（behavior: patrol 巡逻 / ranged 远程 / dive 俯冲 / boss）
CREATE TABLE IF NOT EXISTS enemies (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  hp            INTEGER NOT NULL DEFAULT 10,
  speed         REAL    NOT NULL DEFAULT 60,
  behavior      TEXT    NOT NULL DEFAULT 'patrol',
  attack_damage INTEGER NOT NULL DEFAULT 1,
  drops         TEXT    NOT NULL DEFAULT '{}',   -- JSON: {"sacrifice_part":"monster_limb","soul":2}
  desc          TEXT    NOT NULL DEFAULT ''
);

-- NPC（faction: heretic 异教徒 / engineer 工程师）
CREATE TABLE IF NOT EXISTS npc (
  id       TEXT PRIMARY KEY,
  name     TEXT NOT NULL,
  faction  TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  desc     TEXT NOT NULL DEFAULT ''
);

-- 对话（lines 为 JSON 数组，元素 {speaker, text, pause?}）
CREATE TABLE IF NOT EXISTS dialogues (
  id       TEXT PRIMARY KEY,
  npc_id   TEXT NOT NULL DEFAULT '',
  title    TEXT NOT NULL DEFAULT '',
  lines    TEXT NOT NULL DEFAULT '[]',
  next_id  TEXT NOT NULL DEFAULT '',   -- 顺序对话的下一段；空表示结束
  branch   TEXT NOT NULL DEFAULT ''    -- 分支触发条件（M2 细化）
);

-- 结局（condition 为结算条件说明；权重用于调试统计）
CREATE TABLE IF NOT EXISTS endings (
  id        TEXT PRIMARY KEY,           -- refuse_die / human / transformed / true_he
  name      TEXT NOT NULL,
  condition TEXT NOT NULL,
  weight    INTEGER NOT NULL DEFAULT 1,
  desc      TEXT NOT NULL DEFAULT ''
);

-- 献祭改造（route: heretic 献祭线 / both 通用）
CREATE TABLE IF NOT EXISTS sacrifices (
  id     TEXT PRIMARY KEY,
  part   TEXT NOT NULL,                 -- arm 手臂 / leg 腿部
  route  TEXT NOT NULL DEFAULT '',
  desc   TEXT NOT NULL DEFAULT '',
  effect TEXT NOT NULL DEFAULT '{}'     -- JSON: {"attack_mode":"arm_claw"} / {"jump":"big_jump"}
);
