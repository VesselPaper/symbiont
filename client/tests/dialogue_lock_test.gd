extends SceneTree
## 回归测试：走路时触发开场对话，玩家必须立刻停住，不能继续滑出平台。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/dialogue_lock_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _player: CharacterBody2D
var _dialogue: Node
var _time := 0.0
var _x_at_lock := 0.0
var _locked := false
var _checked := false

func _process(delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_dialogue = _level.get_node("Dialogue")
		# 开场前就一直往右走，模拟"走路时撞到剧情触发器"
		Input.action_press("move_right")
		_time = 0.0
		return false
	_time += delta
	if not _locked:
		if _time > 0.85 and _dialogue.call("is_playing"):
			_locked = true
			_x_at_lock = _player.global_position.x
			print("[dialogue_lock] 对话开始 t=%.2f x=%.1f vx=%.1f floor=%s" % [
				_time, _x_at_lock, _player.velocity.x, str(_player.is_on_floor())])
		return false
	if not _checked and _time > 1.65:
		_checked = true
		Input.action_release("move_right")
		var dx := absf(_player.global_position.x - _x_at_lock)
		print("[dialogue_lock] 锁后 0.8s x=%.1f dx=%.1f" % [_player.global_position.x, dx])
		if dx < 3.0:
			print("[dialogue_lock] PASS")
			quit(0)
		else:
			push_error("[dialogue_lock] FAIL 对话锁输入后仍在移动 dx=%.1f" % dx)
			quit(1)
		return true
	return false
