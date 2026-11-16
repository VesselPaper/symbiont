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

## 从云端拉回落档后要不要立刻读档（按槽位记）
var _pull_then_load: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

## 从云端拉存档并写成本地文件；load_after=true 时顺带读档。
## 用于换机器或本地存档丢失的情况：本地永远优先，这条只在本地没有时用。
func pull_remote(slot: int, load_after: bool = false) -> void:
	if not Network.save_pulled.is_connected(_on_save_pulled):
		Network.save_pulled.connect(_on_save_pulled)
		Network.save_conflict.connect(_on_save_conflict)
		Network.save_pull_failed.connect(_on_save_pull_failed)
	_pull_then_load[slot] = load_after
	Network.pull_save(slot)


func _on_save_pulled(slot: int, data: Dictionary) -> void:
	var f := FileAccess.open(_save_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: 云端存档写入本地失败 %s" % _save_path(slot))
		EventBus.save_failed.emit(slot, "write_failed")
		return
	f.store_string(JSON.stringify(data, "\t"))

	var should_load: bool = _pull_then_load.get(slot, false)
	_pull_then_load.erase(slot)
	if should_load:
		# 必须写 self.：裸 load() 会解析成 Godot 内置的资源加载函数
		self.load(slot)


## 云端与本地的同一槽位都改过：把云端那份另存成 .conflict 副本（不丢），
## 再用云端的新版本号把本地这份重推上去，保证当前进度胜出。
func _on_save_conflict(slot: int, rev: int, cloud: Dictionary) -> void:
	if not cloud.is_empty():
		var path := "%s/slot_%d.conflict.json" % [SAVE_DIR, slot]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(cloud, "\t"))
			f.close()
	EventBus.log_event("save_conflict", {"slot": slot, "cloud_rev": rev})
	var mine := _read_slot(slot)
	if not mine.is_empty():
		Network.push_save(slot, mine, rev)

func _on_save_pull_failed(slot: int, reason: String) -> void:
	_pull_then_load.erase(slot)
	EventBus.save_failed.emit(slot, "remote_" + reason)

## 新游戏用哪个槽：优先空槽，全满就覆盖最旧的一个，别把旧档直接盖掉
## M5-06：单存档默认开（只用槽位 1），多存档可选。
## 槽位数由 Settings.multi_save 决定：关的时候外面只看到 1 个槽，
## 这样"选存档"这件事在默认设置下根本不存在，玩家不用挑。
func slot_count() -> int:
	return MAX_SLOTS if Settings.multi_save else 1

func pick_new_slot() -> int:
	for slot in range(slot_count()):
		if not has_save(slot):
			return slot
	var oldest := 0
	var oldest_time := 0
	for slot in range(slot_count()):
		var t := FileAccess.get_modified_time(_save_path(slot))
		if oldest_time == 0 or t < oldest_time:
			oldest_time = t
			oldest = slot
	return oldest

func _save_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_save_path(slot))

## 只读主档、不碰备份、不打日志的小读取：给"显示名字/摘要"和"自动存档保留名字"用。
## 正式读档还是走 _read_slot（那条路会回退 .bak 并告警）。
func _peek(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_save_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

func _peek_name(slot: int) -> String:
	return str(_peek(slot).get("name", ""))

## 槽位显示名：优先用玩家起的名字，没起就用"存档 N"
func slot_name(slot: int) -> String:
	var given := _peek_name(slot).strip_edges()
	if given != "":
		return given
	return "存档 %d" % (slot + 1)

## 一行摘要（名字 + 时间），暂停菜单/主菜单都用它，不用各自拼字符串
func slot_summary(slot: int) -> String:
	if not has_save(slot):
		return "空槽位"
	var stamp := str(_peek(slot).get("saved_at", ""))
	# 只留到分钟，秒对玩家没意义
	if stamp.length() >= 16:
		stamp = stamp.substr(0, 16)
	return "%s  %s" % [slot_name(slot), stamp]

## 原子写：先写 .tmp，落盘成功再改名成正式档；旧档先转成 .bak。
## 直接覆盖写在断电/关页面时会留下半个 JSON，读档就废了。
func _write_atomic(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(path + ".bak")
		)
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path)
	) == OK

## 读档：主档坏了就回退 .bak，而不是当成"没有存档"
func _read_slot(slot: int) -> Dictionary:
	for candidate in [_save_path(slot), _save_path(slot) + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if parsed is Dictionary:
			if candidate.ends_with(".bak"):
				push_warning("SaveSystem: 主档损坏，已回退备份 %s" % candidate)
				EventBus.log_event("save_recovered", {"slot": slot})
			return parsed
	return {}

## 存一个存档名（玩家自己起的名）进档里，跟着档走 —— 不另开配置文件，
## 换机器/发存档码的时候名字也在。
func save(slot: int, display_name: String = "") -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		EventBus.save_failed.emit(slot, "invalid_slot")
		return
	var data := _collect()
	data["version"] = SAVE_VERSION
	data["saved_at"] = Time.get_datetime_string_from_system()
	if display_name.strip_edges() != "":
		data["name"] = display_name.strip_edges()
	else:
		# 没起名就沿用这个槽位原来的名字，别因为这次自动存档把名字洗掉。
		# 这里特意不走 _read_slot：那条路遇到坏档会打"回退备份"的告警，
		# 自动存档每次路过都刷一条日志太吵；名字读不到就算了。
		data["name"] = _peek_name(slot)
	if not _write_atomic(_save_path(slot), JSON.stringify(data, "\t")):
		push_error("SaveSystem: 无法写入存档 %s" % _save_path(slot))
		EventBus.save_failed.emit(slot, "write_failed")
		return
	save_completed.emit(slot)
	EventBus.log_event("save", {"slot": slot})
	Network.push_save(slot, data)   # 异步远程同步（离线自动忽略）

## 导出存档码：base64(JSON)，可以抄走，到别的浏览器/机器上导入。
## 这是不用账号也能跨端搬档的最小方案，很多单机游戏都这么做。
func export_code(slot: int) -> String:
	var data := _read_slot(slot)
	if data.is_empty():
		return ""
	return Marshalls.utf8_to_base64(JSON.stringify(data))

## 导入存档码：校验能解析、带 version 才写；返回是否成功
func import_code(code: String) -> bool:
	var raw := Marshalls.base64_to_utf8(code.strip_edges())
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary) or not parsed.has("version"):
		return false
	var slot := int(parsed.get("slot_hint", 0))
	return _write_atomic(_save_path(slot), JSON.stringify(parsed, "\t"))

func load(slot: int) -> void:
	if not has_save(slot) and not FileAccess.file_exists(_save_path(slot) + ".bak"):
		push_warning("SaveSystem: 存档不存在 slot=%d" % slot)
		EventBus.save_failed.emit(slot, "not_found")
		return
	var parsed := _read_slot(slot)
	if parsed.is_empty():
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
