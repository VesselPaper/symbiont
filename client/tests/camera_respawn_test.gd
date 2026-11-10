extends SceneTree
## 回归测试：死亡复活后相机必须回到出生点附近，不能停在旧尸体处。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/camera_respawn_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _player: CharacterBody2D
var _camera: Camera2D
var _time := 0.0
var _killed := false

func _process(delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_camera = _level.get_node("Camera2D") as Camera2D
		_time = 0.0
		return false
	_time += delta
	if not _killed and _time > 0.35:
		_killed = true
		# 把玩家扔到远处（模拟掉坑死亡），再走死亡→复活流程
		_player.global_position = Vector2(1600, 1000)
		_player.call("take_damage", 99)
		print("[camera_respawn] 死亡位置 player=(%.1f,%.1f) cam=(%.1f,%.1f)" % [
			_player.global_position.x, _player.global_position.y,
			_camera.global_position.x, _camera.global_position.y])
	if _killed and _time > 2.6:
		var dx := absf(_camera.global_position.x - _player.global_position.x)
		var dy := absf(_camera.global_position.y - _player.global_position.y)
		print("[camera_respawn] 复活后 player=(%.1f,%.1f) cam=(%.1f,%.1f) dx=%.1f dy=%.1f" % [
			_player.global_position.x, _player.global_position.y,
			_camera.global_position.x, _camera.global_position.y, dx, dy])
		if dx < 320.0 and dy < 260.0:
			print("[camera_respawn] PASS")
			quit(0)
		else:
			push_error("[camera_respawn] FAIL 相机没有回到出生点")
			quit(1)
		return true
	return false
