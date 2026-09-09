extends Node
## 全局事件总线：玩家状态 / 战斗 / 死亡 / 统计埋点
## 供 HUD、主场景、关卡加载器与后续后台统计（player_events）连接

signal player_hp_changed(hp: int, max_hp: int)
signal player_energy_changed(energy: float, max_energy: int)
signal player_died
signal enemy_killed(pos: Vector2)
signal enemy_damaged
signal stats_event(event_type: String, payload: Dictionary)
