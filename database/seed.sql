-- ============================================================
-- 共生之缚 Symbiont —— 服务器初始数据（MySQL 8）
-- 执行: mysql -u root -p < database/seed.sql
-- 说明: 密码为演示用，正式环境务必更换并使用 bcrypt 等加盐哈希。
-- ============================================================

USE symbiont;

-- 演示账号（密码均为 symbiont-demo，正式实现时用 server 注册接口创建）
INSERT INTO users (username, password_hash) VALUES
  ('demo',  '$2b$12$PLACEHOLDER_DEMO_USER_HASH_CHANGE_ME'),
  ('player1', '$2b$12$PLACEHOLDER_PLAYER1_HASH_CHANGE_ME')
ON DUPLICATE KEY UPDATE username = VALUES(username);
