extends Node2D
## 主场景（M0 占位）。M1 将替换为真正的主菜单（继续 / 新游戏 / 设置）。

func _ready() -> void:
	EventBus.log_event("boot", {"state": "main_menu"})
	print("[Symbiont] main scene ready | autoloads: EventBus/GameManager/DataDB/SaveSystem/Settings/Network")
