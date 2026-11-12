extends SceneTree
## 镜头跳跃回归：平地正常跳跃时镜头不要上下抽；落地后角色必须回到屏幕中线偏下，
## 不能跳一次就永久停在画面上半屏（会看不到前方下面的平台）。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/camera_jump_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _player: CharacterBody2D
var _camera: Camera2D
var _time := 0.0
var _jumped := false
var _released := false
var _start_cam_y := 0.0
var _start_screen_y := 0.0
var _end_screen_y := 0.0
var _min_cam_y := 999999.0
var _max_cam_y := -999999.0
var _min_screen_y := 999999.0
var _max_screen_y := -999999.0
var _done := false

func _process(delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_camera = _level.get_node("Camera2D") as Camera2D
		# 标记开场对话已播过，否则 0.6s 后玩家输入被锁，跳跃根本不会发生（测试会假通过）
		_level.set("_played", {"intro": true})
		_player.set("_input_locked", false)
		_time = 0.0
		return false
	_time += delta
	if not _jumped and _time >= 0.9:
		_jumped = true
		_start_cam_y = _camera.global_position.y
		_start_screen_y = _screen_y()
		Input.action_press("jump")
		print("[camera_jump] 起跳 cam_y=%.1f 角色屏幕 y=%.1f" % [_start_cam_y, _start_screen_y])
	if _jumped and not _released and _time >= 1.0:
		_released = true
		Input.action_release("jump")
	if _jumped and _time < 2.2:
		_min_cam_y = minf(_min_cam_y, _camera.global_position.y)
		_max_cam_y = maxf(_max_cam_y, _camera.global_position.y)
		var screen_y := (_player.global_position.y - _camera.global_position.y) * _camera.zoom.y + 360.0
		_min_screen_y = minf(_min_screen_y, screen_y)
		_max_screen_y = maxf(_max_screen_y, screen_y)
	if _jumped and not _done and _time >= 2.2:
		_done = true
		var travel := _max_cam_y - _min_cam_y
		_end_screen_y = _screen_y()
		print("[camera_jump] 镜头 y 行程 %.1f px（应接近 0），角色屏幕 y %.1f~%.1f，落地后 %.1f" % [
			travel, _min_screen_y, _max_screen_y, _end_screen_y])
		# 默认构图：720 高里角色在中线偏下（56px*1.714+360≈456），允许 40px 浮动
		if travel < 2.0 and _min_screen_y > 120.0 and _max_screen_y < 660.0 \
				and absf(_start_screen_y - 456.0) < 40.0 \
				and absf(_end_screen_y - 456.0) < 24.0:
			print("[camera_jump] PASS")
			quit(0)
		else:
			push_error("[camera_jump] FAIL 平地跳镜头仍在动，或角色没回到中线偏下")
			quit(1)
		return true
	return false

func _screen_y() -> float:
	return (_player.global_position.y - _camera.global_position.y) * _camera.zoom.y + 360.0
