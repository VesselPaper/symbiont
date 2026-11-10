extends SceneTree
## 教学关 → 第一层的门测试（无头）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/transition_test.gd
## 检查：门和进入判定生成、教程没完成时门是关的、教程完成后门点亮、
## F2 快捷键的反向输入（抬起 / 长按 echo / 其它键）不会切场景。

const SCENE := "res://scenes/world/test_arena.tscn"

var _frames := 0
var _arena: Node = null
var _failed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_arena = load(SCENE).instantiate()
		root.add_child(_arena)
		return false
	if _frames == 8:
		_check_door_nodes()
		_check_closed_by_default()
		_check_input_reverse()
		# 直接把教程状态推到 DONE（等价于献祭完成），验证门会亮
		var tutorial := _arena.get_node_or_null("Tutorial")
		if tutorial != null:
			tutorial.set("_step", 8)
		return false
	if _frames == 20:
		_check_door_opens()
		print("[transition] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[transition] " + message)
		_failed = true

func _check_door_nodes() -> void:
	var door := _arena.get_node_or_null("NextFloorDoor")
	_check(door != null, "缺少 NextFloorDoor")
	if door != null:
		_check(door.get_node_or_null("DoorArea") != null, "缺少 DoorArea 进入判定")
		_check(door.get_node_or_null("DoorArea/CollisionShape2D") != null, "DoorArea 缺少碰撞形状")

func _check_closed_by_default() -> void:
	var tutorial := _arena.get_node_or_null("Tutorial")
	_check(tutorial != null and not bool(tutorial.call("is_completed")), "教程初始不应算完成")
	_check(not bool(_arena.get("_door_open")), "教程没完成时门不应打开")

## 反向输入：只认 F2 按下沿，别的都不得触发进入第一层
func _check_input_reverse() -> void:
	var other := InputEventKey.new()
	other.keycode = KEY_F1
	other.pressed = true
	_arena.call("_unhandled_input", other)
	_check(not bool(_arena.get("_entering")), "F1 不应触发进第一层")

	var release := InputEventKey.new()
	release.keycode = KEY_F2
	release.pressed = false
	_arena.call("_unhandled_input", release)
	_check(not bool(_arena.get("_entering")), "F2 抬起不应触发")

	var echo := InputEventKey.new()
	echo.keycode = KEY_F2
	echo.pressed = true
	echo.echo = true
	_arena.call("_unhandled_input", echo)
	_check(not bool(_arena.get("_entering")), "F2 长按 echo 不应触发")

func _check_door_opens() -> void:
	var door := _arena.get_node_or_null("NextFloorDoor")
	_check(bool(_arena.get("_door_open")), "教程完成后门应打开")
	if door != null:
		var line := door.get_node_or_null("DoorSeam") as Line2D
		_check(line != null, "门缺少门缝")
		if line != null:
			_check(line.default_color.g > 0.6, "门打开后门缝应变亮（实际 g=%.2f）" % line.default_color.g)
