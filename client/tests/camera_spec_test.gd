extends SceneTree
## 摄像机规格回归（补 M1-09 验收里“zoom / limit”这一项）：
## 教学关和三层都必须用“垂直视野 = 15 个角色身高”的 zoom，并各自覆盖整张地图；
## 相机必须挂 camera_follow.gd，不能退回固定镜头。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/camera_spec_test.gd

const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
const EXPECTED_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)
const CASES := [
	{"label": "arena", "scene": "res://scenes/world/test_arena.tscn", "right": 6250, "top": -120, "bottom": 720},
	{"label": "floor1", "scene": "res://scenes/world/floor1.tscn", "right": 6160, "top": 0, "bottom": 1200},
	{"label": "floor2", "scene": "res://scenes/world/floor2.tscn", "right": 5300, "top": 0, "bottom": 1200},
	{"label": "floor3", "scene": "res://scenes/world/floor3.tscn", "right": 4300, "top": 0, "bottom": 1200},
]

var _phase := 0
var _wait := 0
var _level: Node
var _failed := false

func _process(_delta: float) -> bool:
	if _level == null:
		var case: Dictionary = CASES[_phase]
		_level = load(str(case["scene"])).instantiate()
		root.add_child(_level)
		_wait = 0
		return false
	_wait += 1
	if _wait < 5:
		return false
	var spec: Dictionary = CASES[_phase]
	_check_camera(str(spec["label"]), int(spec["right"]), int(spec["top"]), int(spec["bottom"]))
	_level.queue_free()
	_level = null
	_phase += 1
	_wait = 0
	if _phase >= CASES.size():
		print("[camera_spec] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check_camera(label: String, limit_right: int, limit_top: int, limit_bottom: int) -> void:
	var camera := _level.get_node("Camera2D") as Camera2D
	_check(camera != null, "%s 没有 Camera2D" % label)
	if camera == null:
		return
	_check(absf(camera.zoom.x - EXPECTED_ZOOM) < 0.001, "%s zoom_x=%.4f 应=%.4f" % [label, camera.zoom.x, EXPECTED_ZOOM])
	_check(absf(camera.zoom.y - EXPECTED_ZOOM) < 0.001, "%s zoom_y=%.4f 应=%.4f" % [label, camera.zoom.y, EXPECTED_ZOOM])
	_check(camera.limit_left == 0, "%s limit_left=%d 应=0" % [label, camera.limit_left])
	_check(camera.limit_right == limit_right, "%s limit_right=%d 应=%d" % [label, camera.limit_right, limit_right])
	_check(camera.limit_top == limit_top, "%s limit_top=%d 应=%d" % [label, camera.limit_top, limit_top])
	_check(camera.limit_bottom == limit_bottom, "%s limit_bottom=%d 应=%d" % [label, camera.limit_bottom, limit_bottom])
	_check(camera.has_method("shake"), "%s 相机没挂 camera_follow.gd" % label)
	print("[camera_spec] %s zoom=%.4f limits=(%d,%d,%d,%d)" % [
		label, camera.zoom.x, camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom])

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[camera_spec] " + msg)
		_failed = true
