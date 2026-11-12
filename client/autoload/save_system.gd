extends Node
## 存档系统（SaveSystem，autoload 单例）
##
## 本地存档：user://saves/slot_N.json（JSON，存档 Schema v1）。
## 可选：经 Network 同步到服务器（远程存档）。
## 存档格式见 docs/02-系统接口设计文档.md。

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const MAX_SLOTS := 3

signal save_completed(slot: int)
signal load_completed(slot: int)

## 读档时当前场景可能还没加载玩家（例如主菜单继续游戏）：
## 先把玩家数据存在这里，目标关卡 _ready 时调用 apply_pending_player() 落地。
var pending_player: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _save_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_save_path(slot))

func save(slot: int) -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		EventBus.save_failed.emit(slot, "invalid_slot")
		return
	var data := _collect()
	data["version"] = SAVE_VERSION
	data["saved_at"] = Time.get_datetime_string_from_system()
	var f := FileAccess.open(_save_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: 无法写入存档 %s" % _save_path(slot))
		EventBus.save_failed.emit(slot, "write_failed")
		return
	f.store_string(JSON.stringify(data, "\t"))
	save_completed.emit(slot)
	EventBus.log_event("save", {"slot": slot})
	Network.push_save(slot, data)   # 异步远程同步（离线自动忽略）

func load(slot: int) -> void:
	if not has_save(slot):
		push_warning("SaveSystem: 存档不存在 slot=%d" % slot)
		EventBus.save_failed.emit(slot, "not_found")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_save_path(slot)))
	if parsed == null:
		EventBus.save_failed.emit(slot, "corrupted")
		return
	_restore(parsed)
	load_completed.emit(slot)
	EventBus.save_loaded.emit(slot)

func _collect() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var player_data: Dictionary = {}
	if player != null:
		player_data = {
			"position": [player.global_position.x, player.global_position.y],
			"hp": int(player.get("hp")),
			"has_weapon": bool(player.get("has_weapon")),
			"has_steam_boots": bool(player.get("has_steam_boots")),
		}
	var scene := get_tree().current_scene
	if scene == null and player != null:
		scene = player.get_parent()
	return {
		"game_progress": GameManager.to_dict(),
		"player": player_data,
		"inventory": {"monster_limb_count": GameManager.monster_limb_count},
		"levels": {"scene": scene.scene_file_path if scene != null else ""},
	}

func _restore(data: Dictionary) -> void:
	GameManager.from_dict(data.get("game_progress", {}))
	# 只暂存，不在这里落地：跨层读档时当前场景的玩家马上会被释放，
	# 位置必须留给目标关卡的 _ready；同层读档由暂停菜单显式调用 apply_pending_player()。
	pending_player = data.get("player", {})

## 把暂存的玩家位置/血量/持剑状态落到当前场景玩家；只应用一次。
func apply_pending_player(player: Node2D) -> void:
	if pending_player.is_empty():
		return
	var pos: Array = pending_player.get("position", [])
	if pos.size() >= 2:
		player.global_position = Vector2(float(pos[0]), float(pos[1]))
	if pending_player.has("hp"):
		player.set("hp", int(pending_player["hp"]))
	if pending_player.has("has_weapon"):
		var weapon := bool(pending_player["has_weapon"])
		player.set("has_weapon", weapon)
		# 老存档没有 GameManager.has_weapon 字段；读档后同步，避免下一层又丢剑
		GameManager.has_weapon = weapon
	if pending_player.has("has_steam_boots"):
		var boots := bool(pending_player["has_steam_boots"])
		player.set("has_steam_boots", boots)
		GameManager.has_steam_boots = boots
	pending_player = {}

func delete_slot(slot: int) -> void:
	var path := _save_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
