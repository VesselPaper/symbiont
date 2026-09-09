-- =====================================================================
-- Symbiont 共生之缚 · 数据库脚本（建库建表）
-- 《软件工程》课程设计 · 交付文档 7
-- 目标数据库：MySQL 8.x（utf8mb4 / utf8mb4_unicode_ci）
-- =====================================================================

CREATE DATABASE IF NOT EXISTS symbiont
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE symbiont;

-- ---------------------------------------------------------------------
-- 1. 账号表 users
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(32)  NOT NULL COMMENT '登录名（唯一）',
  password_hash VARCHAR(255) NOT NULL COMMENT 'bcrypt 哈希',
  nickname      VARCHAR(32)  NOT NULL DEFAULT '' COMMENT '玩家昵称（排行榜展示）',
  role          ENUM('player','admin') NOT NULL DEFAULT 'player' COMMENT '角色',
  status        ENUM('active','banned') NOT NULL DEFAULT 'active' COMMENT '账号状态',
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_username (username)
) ENGINE=InnoDB COMMENT='账号';

-- ---------------------------------------------------------------------
-- 2. 用户扩展档案 user_profiles
-- ---------------------------------------------------------------------
CREATE TABLE user_profiles (
  user_id            BIGINT UNSIGNED PRIMARY KEY,
  avatar_url         VARCHAR(255) NOT NULL DEFAULT '' COMMENT '头像地址',
  total_play_seconds INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计游玩秒数',
  total_deaths       INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计死亡次数',
  last_login_at      DATETIME NULL COMMENT '最近登录时间',
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_profile_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='用户扩展档案';

-- ---------------------------------------------------------------------
-- 3. 云存档 saves（多存档位 + 版本号冲突检测 + 校验和防篡改）
-- ---------------------------------------------------------------------
CREATE TABLE saves (
  id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id   BIGINT UNSIGNED NOT NULL,
  slot      TINYINT UNSIGNED NOT NULL COMMENT '存档位 1-3',
  version   INT UNSIGNED NOT NULL DEFAULT 1 COMMENT '版本号（并发/冲突检测）',
  data_json JSON NOT NULL COMMENT '存档数据（角色/进度/能力/道具）',
  checksum  CHAR(64) NOT NULL COMMENT 'SHA-256 校验和（防篡改）',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_user_slot (user_id, slot),
  CONSTRAINT fk_save_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='云存档';

-- ---------------------------------------------------------------------
-- 4. 排行榜 leaderboard_entries（3 维度：通关时间/死亡数/完成度）
-- ---------------------------------------------------------------------
CREATE TABLE leaderboard_entries (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id     BIGINT UNSIGNED NOT NULL,
  metric_type ENUM('clear_time','deaths','completion') NOT NULL COMMENT '排行维度',
  level_id    BIGINT UNSIGNED NULL COMMENT 'NULL=总榜；否则按关卡分榜',
  value       DECIMAL(12,3) NOT NULL COMMENT '指标值（时间秒 / 死亡数 / 完成度%）',
  stars       TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '跑酷星级 0-3',
  achieved_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_user_metric_level (user_id, metric_type, level_id),
  KEY idx_metric_value (metric_type, value),
  CONSTRAINT fk_lb_user  FOREIGN KEY (user_id)  REFERENCES users(id)    ON DELETE CASCADE,
  CONSTRAINT fk_lb_level FOREIGN KEY (level_id) REFERENCES levels(id)   ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='排行榜条目';

-- ---------------------------------------------------------------------
-- 5. 关卡配置 levels（JSON 布局数据；AI 生成标记）
-- ---------------------------------------------------------------------
CREATE TABLE levels (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  level_key    VARCHAR(64) NOT NULL COMMENT '关卡标识（客户端引用）',
  name         VARCHAR(64) NOT NULL COMMENT '关卡名',
  type         ENUM('main','parkour','boss') NOT NULL DEFAULT 'main' COMMENT '类型',
  difficulty   ENUM('easy','normal','hard') NOT NULL DEFAULT 'normal' COMMENT '难度',
  data_json    JSON NOT NULL COMMENT '关卡布局数据（JSON）',
  ai_generated TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否 AI 生成',
  enabled      TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
  version      INT UNSIGNED NOT NULL DEFAULT 1 COMMENT '配置版本',
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_level_key (level_key)
) ENGINE=InnoDB COMMENT='关卡配置';

-- ---------------------------------------------------------------------
-- 6. 公告 announcements
-- ---------------------------------------------------------------------
CREATE TABLE announcements (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title      VARCHAR(128) NOT NULL COMMENT '标题',
  content    TEXT NOT NULL COMMENT '内容',
  enabled    TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
  created_by BIGINT UNSIGNED NULL COMMENT '发布管理员',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ann_admin FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='公告';

-- ---------------------------------------------------------------------
-- 7. 玩家行为事件 player_events（数据统计看板数据源）
-- ---------------------------------------------------------------------
CREATE TABLE player_events (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id      BIGINT UNSIGNED NOT NULL,
  event_type   VARCHAR(64) NOT NULL COMMENT '事件类型：session/level_clear/death/ability_get/item_choice/parkour_result 等',
  payload_json JSON NOT NULL COMMENT '事件详情（关卡/数值/耗时等）',
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_user_time (user_id, created_at),
  KEY idx_type_time (event_type, created_at)
) ENGINE=InnoDB COMMENT='玩家行为事件（埋点）';

-- ---------------------------------------------------------------------
-- 8. 管理日志 admin_logs
-- ---------------------------------------------------------------------
CREATE TABLE admin_logs (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  admin_id   BIGINT UNSIGNED NOT NULL,
  action     VARCHAR(64) NOT NULL COMMENT '操作类型（如 level.update/player.ban）',
  detail     VARCHAR(512) NOT NULL DEFAULT '' COMMENT '操作详情',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_admin_time (admin_id, created_at),
  CONSTRAINT fk_log_admin FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='管理操作日志';
