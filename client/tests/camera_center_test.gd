extends SceneTree
## 镜头构图回归（试玩反馈：跳上高台后角色会停在画面上半屏，前方下面的平台看不到）：
##   1. 角色默认必须在中线偏下（720 高里约 y=456）；
##   2. 从高台落地/传送后，镜头要重新把角色放回默认位置，不能永久偏上；
##   3. 站在高台上时，正前下方的低台必须进入画面（屏幕 y < 700）。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/camera_center_test.gd

const FLOOR1 := "res://scenes/world/floor1.tscn"
const ARENA := "res://scenes/world/test_arena.tscn"
const BASE_SCREEN_Y := 720.0 * 0.5 + 56.0 * (720.0 / 420.0)  # 456

var _phase := 0
var _wait := 0
var _level: Node
var _player: CharacterBody2D
var _camera: Camera2D
var _failed := false

func _process(_delta: float) -> bool:
	if _level == null:
		_level = load(FLOOR1).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_camera = _level.get_node("Camera2D") as Camera2D
		_wait = 0
		return false
	_wait += 1
	# 先等角色落地、镜头吸附完成
	if _phase == 0 and _wait >= 50:
		_check_screen("出生点", 40.0)
		_phase = 1
		_wait = 0
		return false
	# 直接放到层门厅高台（顶 600），镜头必须回正
	if _phase == 1:
		_player.global_position = Vector2(5360, 587)
		_phase = 2
		_wait = 0
		return false
	if _phase == 2 and _wait >= 60:
		_check_screen("层门厅高台", 24.0)
		_phase = 3
		_wait = 0
		return false
	# 再落回钟厅低台（顶 760），镜头下跟后仍要回正
	if _phase == 3:
		_player.global_position = Vector2(1240, 747)
		_phase = 4
		_wait = 0
		return false
	if _phase == 4 and _wait >= 60:
		_check_screen("钟厅低台", 24.0)
		_level.queue_free()
		_level = null
		_phase = 5
		_wait = 0
		return false
	# 教学关：站在祭坛高台，前方下面的浅坑底必须能看到
	if _phase == 5:
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_camera = _level.get_node("Camera2D") as Camera2D
		# 祭坛在站位表里会挪（M4-19 拉宽了教学关），站位取自场景里的祭坛节点
		var altar := _level.get_node("Altar") as Node2D
		_player.global_position = Vector2(altar.global_position.x, 559)
		_phase = 6
		_wait = 0
		return false
	if _phase == 6 and _wait >= 60:
		_check_screen("祭坛高台", 24.0)
		var pit_screen := _screen_y(659.0)
		print("[camera_center] 前方浅坑底屏幕 y=%.1f（应 <700，能看见）" % pit_screen)
		_check(pit_screen < 700.0, "浅坑底被画面底边切掉 y=%.1f" % pit_screen)
		print("[camera_center] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check_screen(label: String, tolerance: float) -> void:
	var y := _screen_y(_player.global_position.y)
	print("[camera_center] %s 角色屏幕 y=%.1f 相机 y=%.1f" % [label, y, _camera.global_position.y])
	_check(absf(y - BASE_SCREEN_Y) <= tolerance, "%s 角色没回到中线偏下 y=%.1f" % [label, y])

func _screen_y(world_y: float) -> float:
	return (world_y - _camera.global_position.y) * _camera.zoom.y + 360.0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[camera_center] " + msg)
		_failed = true
