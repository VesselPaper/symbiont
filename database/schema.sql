-- ============================================================
-- 共生之缚 Symbiont —— 服务器数据库 Schema（MySQL 8）
-- 版本: v1（M0）
-- 说明: 账号 / 远程存档 / 统计埋点 / 排行榜
-- 执行: mysql -u root -p < database/schema.sql
-- 对应: server/app/models.py（SQLAlchemy 模型与之一致）
-- ============================================================

CREATE DATABASE IF NOT EXISTS symbiont
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;
USE symbiont;

-- 玩家账号
CREATE TABLE IF NOT EXISTS users (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  username      VARCHAR(64)     NOT NULL,
  password_hash VARCHAR(255)    NOT NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_username (username)
) ENGINE=InnoDB;

-- 远程存档（按用户 × 槽位）
CREATE TABLE IF NOT EXISTS saves (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  slot       TINYINT UNSIGNED NOT NULL DEFAULT 1,
  save_data  JSON            NOT NULL,      -- 与客户端存档 Schema v1 一致
  updated_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_saves_user_slot (user_id, slot),
  CONSTRAINT fk_saves_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 统计埋点（游戏事件流：献祭/死亡/结局/时长……）
CREATE TABLE IF NOT EXISTS events (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NULL,
  event      VARCHAR(64)     NOT NULL,
  payload    JSON            NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_events_created (created_at),
  KEY idx_events_event (event),
  CONSTRAINT fk_events_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- 排行榜（如 最快通关 / 最少献祭通关 等，board 区分榜单）
CREATE TABLE IF NOT EXISTS leaderboard (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  board      VARCHAR(64)     NOT NULL,
  user_id    BIGINT UNSIGNED NOT NULL,
  score      DOUBLE          NOT NULL,
  meta       JSON            NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_leaderboard_board_score (board, score),
  CONSTRAINT fk_leaderboard_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;
