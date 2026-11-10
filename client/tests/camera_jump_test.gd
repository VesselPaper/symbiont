extends SceneTree
## 镜头跳跃回归：起跳后镜头必须向上跟，且角色不能跑出安全画面。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/camera_jump_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _player: CharacterBody2D
var _camera: Camera2D
var _time := 0.0
var _jumped := false
var _released := false
var _start_cam_y := 0.0
var _min_cam_y := 999999.0
var _min_screen_y := 999999.0
var _max_screen_y := -999999.0
var _done := false

func _process(delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_camera = _level.get_node("Camera2D") as Camera2D
		_time = 0.0
		return false
	_time += delta
	if not _jumped and _time >= 0.35:
		_jumped = true
		_start_cam_y = _camera.global_position.y
		Input.action_press("jump")
		print("[camera_jump] 起跳 cam_y=%.1f" % _start_cam_y)
	if _jumped and not _released and _time >= 0.45:
		_released = true
		Input.action_release("jump")
	if _jumped and _time < 1.7:
		_min_cam_y = minf(_min_cam_y, _camera.global_position.y)
		var screen_y := (_player.global_position.y - _camera.global_position.y) * _camera.zoom.y + 360.0
		_min_screen_y = minf(_min_screen_y, screen_y)
		_max_screen_y = maxf(_max_screen_y, screen_y)
	if _jumped and not _done and _time >= 1.7:
		_done = true
		var rise := _start_cam_y - _min_cam_y
		print("[camera_jump] 镜头上升 %.1f px，角色屏幕 y %.1f~%.1f" % [
			rise, _min_screen_y, _max_screen_y])
		if rise >= 12.0 and _min_screen_y > 120.0 and _max_screen_y < 660.0:
			print("[camera_jump] PASS")
			quit(0)
		else:
			push_error("[camera_jump] FAIL 镜头没跟跳或角色跑出安全区")
			quit(1)
		return true
	return false
