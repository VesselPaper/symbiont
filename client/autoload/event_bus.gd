extends Node
## 全局事件总线（EventBus，autoload 单例）
##
## 所有跨模块通信通过这里广播，模块间不直接引用对方节点，避免硬耦合。
## 命名规范：<主体>_<过去式/完成式>，如 enemy_killed、sacrifice_done。
## 新增信号请同步更新 docs/02-系统接口设计文档.md 的信号表。

# ---- 玩家 ----
signal player_hurt(amount: int, source: Node)
signal player_healed(amount: int)
signal player_died
signal player_moved_between_floors(floor_id: String)

# ---- 战斗 ----
signal enemy_spawned(enemy: Node)
signal enemy_killed(enemy: Node, position: Vector2)
signal boss_defeated(boss_id: String)

# ---- 物品 / 献祭 ----
signal item_picked(item_id: String, count: int)
signal sacrifice_done(sacrifice_id: String, total_count: int)
signal body_part_modified(part: String, route: String)

# ---- 任务光点 / 教程 ----
signal marker_triggered(marker_id: String)

# ---- 存档 / 流程 ----
signal save_requested(slot: int)
signal save_loaded(slot: int)
signal save_failed(slot: int, reason: String)
signal dialogue_started(dialogue_id: String)
signal dialogue_finished(dialogue_id: String)
signal ending_reached(ending_id: String)
signal game_over

## 统计埋点统一入口：事件进 Network 的离线队列，可联网时上报服务器。
func log_event(event_name: String, data: Dictionary = {}) -> void:
	Network.report_event(event_name, data)
