extends SceneTree
## 回归：对话期间敌人必须冻结，对话结束恢复；玩家不会被怪物攻击。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/dialogue_freeze_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _dialogue: Node
var _enemies: Node
var _time := 0.0
var _frozen_pos := Vector2.ZERO
var _checked_frozen := false
var _finish_time := 0.0
var _checked_resumed := false

func _process(delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_dialogue = _level.get_node("Dialogue")
		_enemies = _level.get_node("Enemies")
		_time = 0.0
		return false
	_time += delta
	if not _checked_frozen and _time >= 0.8:
		_checked_frozen = true
		if not bool(_dialogue.get("_active")):
			push_error("[dialogue_freeze] FAIL 开场对话没有开始")
			quit(1)
			return true
		var slime := _enemies.get_child(0) as Node
		_frozen_pos = (slime as Node2D).global_position
		print("[dialogue_freeze] 对话中 slime mode=%d pos=%s" % [
			slime.process_mode, str(_frozen_pos)])
		if slime.process_mode != Node.PROCESS_MODE_DISABLED:
			push_error("[dialogue_freeze] FAIL 敌人没有被冻结")
			quit(1)
			return true
	if _checked_frozen and not _checked_resumed and _time >= 1.3 and _finish_time == 0.0:
		var slime := _enemies.get_child(0) as Node2D
		var moved := slime.global_position.distance_to(_frozen_pos)
		if moved > 1.0:
			push_error("[dialogue_freeze] FAIL 冻结期间敌人移动了 %.1fpx" % moved)
			quit(1)
			return true
		_dialogue.call("_finish")
		_finish_time = _time
		return false
	if _finish_time > 0.0 and not _checked_resumed and _time - _finish_time >= 0.15:
		var slime := _enemies.get_child(0) as Node
		var resumed := slime.process_mode != Node.PROCESS_MODE_DISABLED
		print("[dialogue_freeze] 结束后 slime mode=%d resumed=%s" % [
			slime.process_mode, str(resumed)])
		if resumed:
			print("[dialogue_freeze] PASS")
			quit(0)
		else:
			push_error("[dialogue_freeze] FAIL 对话结束后敌人没有恢复")
			quit(1)
		_checked_resumed = true
		return true
	return false
