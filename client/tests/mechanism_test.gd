extends SceneTree
## 第一层机关回归（M2-06）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/mechanism_test.gd
##
## 验收：骨门初始挡路；拉钟绳后旗标、骨门碰撞、守钟人状态一起变化；
## 守钟人的 K 对话可重复；重复拉钟不会二次开演出。

var _frames := 0
var _level: Node = null
var _failed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		var scene: PackedScene = load("res://scenes/world/floor1.tscn")
		_level = scene.instantiate()
		root.add_child(_level)
		return false
	if _frames < 90:
		return false
	_run_checks()
	print("[mechanism] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[mechanism] " + message)
		_failed = true

func _make_k() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_K
	event.keycode = KEY_K
	event.pressed = true
	return event

func _run_checks() -> void:
	if _level == null:
		push_error("[mechanism] 场景加载失败")
		_failed = true
		return
	var gm := root.get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set("flags", {})
		gm.set("state", 2)
	var dialogue := _level.get_node_or_null("Dialogue")
	if dialogue != null and bool(dialogue.call("is_playing")):
		dialogue.call("_finish")

	var gate := _level.get_node_or_null("Mechanisms/BoneGate") as StaticBody2D
	var bell := _level.get_node_or_null("Mechanisms/BellMechanism")
	var watchman := _level.get_node_or_null("Mechanisms/Watchman")
	_check(gate != null and bell != null and watchman != null, "机关节点不齐")
	if gate == null or bell == null or watchman == null:
		return
	_check(gate.collision_layer == 1, "骨门初始没有挡住玩家")
	_check(not gate.call("is_open"), "骨门初始不应是打开的")

	# 守钟人：第一次 K 开 floor1_watchman，结束之后再按还能开（关键提示可重复）
	watchman.set("_in_range", true)
	watchman.call("_unhandled_input", _make_k())
	_check(dialogue != null and bool(dialogue.call("is_playing")), "守钟人第一次对话没有打开")
	if dialogue != null:
		dialogue.call("_finish")
	watchman.call("_unhandled_input", _make_k())
	_check(dialogue != null and bool(dialogue.call("is_playing")), "守钟人第二次对话不能重复打开")
	if dialogue != null:
		dialogue.call("_finish")

	# 钟绳：K 只应触发一次 ring_bell；骨门打开，旗标记住
	bell.set("_in_range", true)
	bell.call("_input", _make_k())
	_check(gate.collision_layer == 0, "拉钟后骨门碰撞没有关闭")
	_check(bool(gate.call("is_open")), "拉钟后骨门没有进入打开状态")
	_check(gm != null and bool(gm.call("has_flag", "floor1_bell_rung")), "拉钟后没有设置 floor1_bell_rung")
	_check(bool(watchman.get("_after")), "拉钟后守钟人没有切到钟响之后")
	_check(bool(bell.get("_rung")), "钟绳没有记住已拉过")
	if dialogue != null:
		dialogue.call("_finish")

	# 反向：已拉过再按 K，不应重复播放钟声/再次开骨门
	var second: bool = bool(_level.call("ring_bell"))
	_check(second == false, "重复 ring_bell 不应再返回 true")
	_check(dialogue != null and not bool(dialogue.call("is_playing")), "重复拉钟不应再次播钟声对话")
