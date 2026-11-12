extends SceneTree
## 二段跳真实输入回归（M4-06）
## 走真实 Input.action_press，不直接调 try_air_jump，防止“方法对但按键路径没接上”。
##
## 正向：站在地上按跳 → 空中再按一次 → 只多跳一次；
## 反向：第三段不能再跳；落地后第二段重新可用；没有靴子时空中按跳不改变上升速度。

const SCENE := "res://scenes/world/test_arena.tscn"

var _level: Node
var _player: CharacterBody2D
var _gm: Node
var _t := 0.0
var _stage := 0
var _failed := false
var _first_jump_seen := false
var _second_jump_seen := false
var _landed := false

func _process(delta: float) -> bool:
	_t += delta
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_gm.set("has_steam_boots", true)
		_gm.set("flags", {})
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as CharacterBody2D
		_player.set("has_steam_boots", true)
		_player.call("_on_item_picked", "steam_boots", 1)
		_player.global_position = Vector2(2500, 600)
		_t = 0.0
		return false

	# 等落地稳定
	if _stage == 0:
		if _t > 0.8:
			_stage = 1
			_t = 0.0
			# 这里只验证跳跃输入；教学关祭坛后的对话会锁输入，测试不需要走对话
			_player.set("_input_locked", false)
			Input.action_press("jump")
		return false

	if _stage == 1:
		if _t > 0.12:
			Input.action_release("jump")
			_stage = 2
			_t = 0.0
			_first_jump_seen = _player.velocity.y < -200.0
			_check(_first_jump_seen, "第一段没有起跳")
		return false

	if _stage == 2:
		# 第一段上升到约 0.2s 时按第二段
		if _t > 0.08:
			Input.action_press("jump")
			_stage = 3
			_t = 0.0
		return false

	if _stage == 3:
		if _t > 0.05:
			Input.action_release("jump")
			_second_jump_seen = _player.velocity.y < -300.0
			_check(_second_jump_seen, "空中按跳没有第二段")
			_check(int(_player.get("_air_jumps_left")) == 0, "第二段后次数没扣")
			Input.action_press("jump")
			_stage = 4
			_t = 0.0
		return false

	if _stage == 4:
		if _t > 0.05:
			Input.action_release("jump")
			# 第三段按下后不该再有 -640 的初速；只检查次数仍为 0
			_check(int(_player.get("_air_jumps_left")) == 0, "第三段被错误允许")
			_stage = 5
			_t = 0.0
		return false

	if _stage == 5:
		if _player.is_on_floor():
			_landed = true
			# 落地帧的 _update_jump_timers 可能还没跑，等两帧再查重置
			_stage = 6
			_t = 0.0
		elif _t > 3.0:
			_check(false, "3 秒内没有落地")
			_stage = 6
			_t = 0.0
		return false

	if _stage == 6:
		if _t > 0.12:
			_check(int(_player.get("_air_jumps_left")) == 1, "落地后二段跳没有重置")
			_stage = 7
			_t = 0.0
		return false

	if _stage == 7:
		if _t > 0.2:
			print("[double_jump_flow] %s first=%s second=%s landed=%s left=%d" % [
				"PASS" if not _failed else "FAIL", _first_jump_seen,
				_second_jump_seen, _landed, int(_player.get("_air_jumps_left"))])
			_gm.set("has_steam_boots", false)
			_gm.set("flags", {})
			quit(0 if not _failed else 1)
			return true
		return false
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[double_jump_flow] " + msg)
		_failed = true
