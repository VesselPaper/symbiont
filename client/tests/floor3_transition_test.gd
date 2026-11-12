extends SceneTree
## 第二层→第三层黑场转场回归（M3-02）
## 真的把玩家放到第二层门缝里，等黑场走完，检查场景、当前楼层和旗标。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/floor3_transition_test.gd

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
		gm.set("current_floor", "floor_2")
		_level = load("res://scenes/world/floor2.tscn").instantiate()
		root.add_child(_level)
		# 让 change_scene_to_file 释放旧场景，避免旧玩家被新场景入口重复判定
		current_scene = _level
		return false
	_elapsed += delta
	if not _entered:
		# 真的把玩家放到门缝判定里，跟着 M4-09 右移后的 Floor3Entry 走
		var player := _level.get_node("Player") as Node2D
		player.global_position = Vector2(5122, 535)
		_entered = true
	if _elapsed < 1.4:
		return false
	var gm := root.get_node("/root/GameManager")
	_check(root.get_node_or_null("Floor3") != null, "1.4 秒后没有切到 Floor3")
	_check(str(gm.get("current_floor")) == "floor_3", "current_floor 没写成 floor_3")
	_check(bool(gm.call("has_flag", "floor3_unlocked")), "缺少 floor3_unlocked 旗标")
	print("[floor3_transition] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[floor3_transition] " + msg)
		_failed = true
