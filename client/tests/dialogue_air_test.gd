extends SceneTree
## 回归测试：开场对话在玩家腾空时触发，必须先挂起；落地后才开始播。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/dialogue_air_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _player: CharacterBody2D
var _dialogue: Node
var _time := 0.0
var _jumped := false
var _released := false
var _checked_air := false
var _checked_land := false

func _process(delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_dialogue = _level.get_node("Dialogue")
		_time = 0.0
		return false
	_time += delta
	# 0.42s 起跳：开场对话 0.6s 触发时玩家应该还在空中
	if not _jumped and _time >= 0.42:
		_jumped = true
		Input.action_press("jump")
	if _jumped and not _released and _time >= 0.50:
		_released = true
		Input.action_release("jump")
	if not _checked_air and _time >= 0.62:
		_checked_air = true
		var active: bool = bool(_dialogue.get("_active"))
		print("[dialogue_air] t=%.2f 空中触发：active=%s pending=%s floor=%s" % [
			_time, str(active), str(_dialogue.call("is_playing")), str(_player.is_on_floor())])
		if _player.is_on_floor():
			print("[dialogue_air] 已落地，本次样本不成立（跳过空中断言）")
		elif active:
			push_error("[dialogue_air] FAIL 空中就直接开始对话了")
			quit(1)
			return true
	if not _checked_land and _time >= 1.15:
		_checked_land = true
		var active: bool = bool(_dialogue.get("_active"))
		print("[dialogue_air] t=%.2f 落地后：active=%s floor=%s" % [
			_time, str(active), str(_player.is_on_floor())])
		if active and _player.is_on_floor():
			print("[dialogue_air] PASS")
			quit(0)
		else:
			push_error("[dialogue_air] FAIL 落地后对话没有开始")
			quit(1)
		return true
	return false
