extends SceneTree
## 自动存档回归（M4-36）：进层自动写盘、新游戏挑空槽不覆盖旧档。
##
## 背景：之前游戏只在暂停菜单点"保存"才写档，玩家直接关掉网页就什么都没有，
## 下次只能从虚空重玩。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/autosave_test.gd

const SCENE := "res://scenes/world/test_arena.tscn"

var _level: Node2D
var _save: Node
var _gm: Node
var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	_gm = root.get_node("/root/GameManager")
	_save = root.get_node("/root/SaveSystem")
	# M5-06：单存档是默认设置（只认 1 号槽），这条测试要验"多槽挑空槽"，
	# 得先把多存档打开，跑完再恢复
	var settings := root.get_node("/root/Settings")
	var was_multi := bool(settings.get("multi_save"))
	settings.call("set_multi_save", true)
	for slot in range(int(_save.get("MAX_SLOTS"))):
		_save.call("delete_slot", slot)

	# 新游戏挑空槽：三个空槽时应该拿 0
	_check(int(_save.call("pick_new_slot")) == 0, "空槽时新游戏没拿到 slot 0")

	# 反向：单存档模式下无论 0 号有没有档，都只认 0 号（不会去占 2 号）
	settings.call("set_multi_save", false)
	_check(int(_save.call("pick_new_slot")) == 0, "单存档模式挑槽没落回 1 号槽")
	settings.call("set_multi_save", true)

	_level = load(SCENE).instantiate() as Node2D
	root.add_child(_level)
	_gm.set("state", 2)  # PLAYING
	_gm.set("active_slot", 1)
	var dialogue := _level.get_node_or_null("Dialogue")
	if dialogue != null:
		dialogue.call("abort")
	await create_timer(0.3).timeout

	_gm.call("autosave")
	_check(bool(_save.call("has_save", 1)), "自动存档没写到 active_slot=1")
	_check(not bool(_save.call("has_save", 0)), "自动存档写错了槽位（slot 0 不该有）")

	# 已有 slot 1 时，新游戏应该避开它
	_save.call("save", 0)
	_check(int(_save.call("pick_new_slot")) == 2, "已有 0/1 时新游戏没用 slot 2")

	var parsed = JSON.parse_string(FileAccess.get_file_as_string("user://saves/slot_1.json"))
	_check(parsed != null and str(parsed.get("saved_at", "")) != "", "存档里没有 saved_at")
	var progress: Dictionary = parsed.get("game_progress", {}) if parsed != null else {}
	_check(str(progress.get("current_floor", "")) != "", "存档里没有 current_floor")

	for slot in range(int(_save.get("MAX_SLOTS"))):
		_save.call("delete_slot", slot)
	settings.call("set_multi_save", was_multi)
	print("[autosave] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[autosave] " + msg)
		_failed = true
