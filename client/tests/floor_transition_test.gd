extends SceneTree
## 第一层→第二层黑场转场回归（M3-01）
## 真的把玩家放到第一层门缝里，等黑场走完，检查场景、当前楼层和旗标。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/floor_transition_test.gd

var _level: Node
var _elapsed := 0.0
var _failed := false
var _entered := false
var _started := false

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		var gm := root.get_node("/root/GameManager")
		gm.set("flags", {})
		gm.set("current_floor", "floor_1")
		_level = load("res://scenes/world/floor1.tscn").instantiate()
		root.add_child(_level)
		# 让 change_scene_to_file 把旧场景释放掉，否则旧玩家还站在门缝里，
		# 新场景的 Floor2Entry 会被旧玩家重复判定。
		current_scene = _level
		# 跳过开场白和层门台词：门缝判定要等对话念完才切，测门位置不需要先看两段剧情
		_level.set("_played", {"intro": true, "gate": true})
		return false
	_elapsed += delta
	if not _entered:
		# 真的把玩家放到层门缝里，而不是直接置 _want_floor2：门/入口位置改了才能测出来。
		# 门的位置从关卡常量读，钟厅加长后不用在这里跟着改数字。
		var player := _level.get_node("Player") as Node2D
		var consts: Dictionary = _level.get_script().get_script_constant_map()
		var gate_x := float(consts.get("GATE_X", 5140.0))
		player.global_position = Vector2(gate_x + 20.0, 535)
		_entered = true
	if _elapsed < 1.4:
		return false
	var gm := root.get_node("/root/GameManager")
	var floor2 := root.get_node_or_null("Floor2")
	_check(floor2 != null, "1.4 秒后没有切到 Floor2")
	_check(str(gm.get("current_floor")) == "floor_2", "current_floor 没写成 floor_2")
	_check(bool(gm.call("has_flag", "floor2_unlocked")), "缺少 floor2_unlocked 旗标")
	print("[floor_transition] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[floor_transition] " + msg)
		_failed = true
