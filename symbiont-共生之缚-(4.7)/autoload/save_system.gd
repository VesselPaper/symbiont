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
	return {
		"game_progress": GameManager.to_dict(),
		"player": {},     # M1: 玩家状态（位置/血量/能力）
		"inventory": {},  # M1: 背包与已改造部位
		"levels": {},     # M2: 楼层进度（开关/已拾取/已击败）
	}

func _restore(data: Dictionary) -> void:
	GameManager.from_dict(data.get("game_progress", {}))
	# M1/M2: 恢复 player / inventory / levels
