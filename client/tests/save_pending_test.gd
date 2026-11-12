extends SceneTree
## 跨层读档暂存回归（M1-05）：load 只暂存玩家数据，不套到当前即将释放的玩家。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/save_pending_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _level: Node
var _gm: Node
var _save: Node
var _elapsed := 0.0
var _failed := false

func _process(delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_save = root.get_node("/root/SaveSystem")
		_gm.set("flags", {})
		_gm.set("state", 2)
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if _elapsed < 0.35:
		return false
	var player := _level.get_node("Player") as Node2D
	player.global_position = Vector2(700, 646)
	_gm.set("current_floor", "floor_3")
	_save.call("save", 1)
	player.global_position = Vector2(100, 646)
	_save.call("load", 1)
	_check(player.global_position.distance_to(Vector2(100, 646)) < 2.0, "跨层读档提前套用了旧玩家位置")
	_check(not (_save.get("pending_player") as Dictionary).is_empty(), "跨层读档没有留下 pending_player")
	_save.call("apply_pending_player", player)
	_check(player.global_position.distance_to(Vector2(700, 646)) < 2.0, "pending_player 落地后位置不对")
	_save.call("delete_slot", 1)
	_check(not bool(_save.call("has_save", 1)), "测试存档没删干净")
	print("[save_pending] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[save_pending] " + msg)
		_failed = true
