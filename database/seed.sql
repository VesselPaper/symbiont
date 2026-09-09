-- =====================================================================
-- Symbiont 共生之缚 · 初始数据
-- 《软件工程》课程设计 · 交付文档 7
-- 说明：
--   1) 管理员账号由后端启动引导（scripts/create_admin.py）创建，
--      密码经 bcrypt 哈希，不在此明文写入。
--   2) 示例关卡 data_json 为占位骨架，真实关卡由关卡编辑器/AI 生成后入库。
-- =====================================================================

USE symbiont;

-- ---------------------------------------------------------------------
-- 示例关卡：主地牢入口（占位）
-- ---------------------------------------------------------------------
INSERT INTO levels (level_key, name, type, difficulty, data_json, ai_generated, enabled)
VALUES
  ('dungeon_entrance', '烬渊入口', 'main', 'easy',
   JSON_OBJECT('rooms', JSON_ARRAY(), 'player_start', JSON_OBJECT('x', 0, 'y', 0), 'theme', 'dungeon'),
   0, 1),
  ('parkour_01', '跑酷挑战 · 一环', 'parkour', 'easy',
   JSON_OBJECT('rooms', JSON_ARRAY(), 'time_limit', 60, 'star_thresholds', JSON_ARRAY(20, 35, 50)),
   0, 1),
  ('boss_01', '心核守卫', 'boss', 'normal',
   JSON_OBJECT('rooms', JSON_ARRAY(), 'boss_id', 'symbiont_guardian', 'theme', 'dungeon'),
   0, 1);

-- ---------------------------------------------------------------------
-- 示例公告
-- ---------------------------------------------------------------------
INSERT INTO announcements (title, content, enabled, created_by)
VALUES
  ('欢迎来到烬渊', '欢迎进入《共生之缚》！本版本为课程设计开发版，祝你好运。', 1, NULL),
  ('公告发布规则', '管理后台可在此发布公告，客户端登录后将拉取最新公告。', 1, NULL);
