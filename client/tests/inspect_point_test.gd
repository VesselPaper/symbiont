extends SceneTree
## 可重复调查点回归（M2-05）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/inspect_point_test.gd
##
## 验收：第一层只保留祭坛 1 个调查点；靠近后按 K 能播；播完再按 K 还能再播（不是一次性）。
## 反向：抬起/长按 echo/其它键不触发。

const DIALOGUE_KEYS := ["AltarInspect"]

var _frames := 0
var _level: Node = null
var _failed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		var scene: PackedScene = load("res://scenes/world/floor1.tscn")
		if scene == null:
			push_error("[inspect] 场景加载失败")
			_failed = true
			quit(1)
			return true
		_level = scene.instantiate()
		root.add_child(_level)
		return false
	if _frames < 70:
		return false
	_run_checks()
	print("[inspect] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[inspect] " + message)
		_failed = true

func _run_checks() -> void:
	if _level == null:
		_failed = true
		return
	var holder := _level.get_node_or_null("InspectPoints")
	_check(holder != null, "缺少 InspectPoints")
	if holder == null:
		return
	_check(holder.get_child_count() == 1, "调查点应为 1 个（只留祭坛），实际 %d" % holder.get_child_count())
	for key in DIALOGUE_KEYS:
		_check(holder.get_node_or_null(key) != null, "缺少调查点 %s" % key)

	var point := holder.get_node_or_null("AltarInspect")
	var dialogue := _level.get_node_or_null("Dialogue")
	var player := _level.get_node_or_null("Player")
	_check(point != null and dialogue != null and player != null, "调查点/对话/玩家节点不全")
	if point == null or dialogue == null or player == null:
		return

	# 场景开场低语可能还在播；先收掉，测调查点自己的重复触发
	if bool(dialogue.call("is_playing")):
		dialogue.call("_finish")
	_check(not bool(dialogue.call("is_playing")), "开场对话未收尾")

	point.call("_on_body_entered", player)
	var key_event := _make_k()
	point.call("_unhandled_input", key_event)
	_check(bool(dialogue.call("is_playing")), "第一次按 K 没有打开对话")
	if bool(dialogue.call("is_playing")):
		dialogue.call("_finish")

	# 同一个点第二次按 K，必须还能打开（关键：没有一次性旗标）
	point.call("_unhandled_input", key_event)
	_check(bool(dialogue.call("is_playing")), "第二次按 K 不能重复打开对话")

	# 反向输入：抬起/echo/其它键不能推进或重开
	if bool(dialogue.call("is_playing")):
		dialogue.call("_finish")
	var release := InputEventKey.new()
	release.physical_keycode = KEY_K
	release.pressed = false
	point.call("_unhandled_input", release)
	_check(not bool(dialogue.call("is_playing")), "K 抬起不应打开对话")
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_K
	echo.pressed = true
	echo.echo = true
	point.call("_unhandled_input", echo)
	_check(not bool(dialogue.call("is_playing")), "K 长按 echo 不应打开对话")
	var other := InputEventKey.new()
	other.physical_keycode = KEY_J
	other.pressed = true
	point.call("_unhandled_input", other)
	_check(not bool(dialogue.call("is_playing")), "J 不应打开调查对话")

func _make_k() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_K
	event.keycode = KEY_K
	event.pressed = true
	return event
