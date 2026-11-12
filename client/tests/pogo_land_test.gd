extends SceneTree
## 下劈跳跃能不能真的落上方台（M4-21）。
##
## 组长定稿：下劈成功的标志是**站上那块方台**，不是挥出下劈动作。既然判定改了，
## 就得证明这条路是走得通的：从跳台上起跳、落到木桩乙上踩一下、靠反弹的高度
## 飘到方台顶上。判定一旦改成“站上去”，方台高度/反弹初速配不上就会卡死整关，
## 所以这条测试用真实物理跑一遍，不看数值表。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/pogo_land_test.gd

const SCENE := "res://scenes/world/test_arena.tscn"

var _level: Node2D
var _player: CharacterBody2D
var _stage: Dictionary
var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	_level = load(SCENE).instantiate() as Node2D
	root.add_child(_level)
	_player = _level.get_node("Player") as CharacterBody2D
	_stage = _level.get_script().get_script_constant_map()["STAGE"]
	var pogo: Rect2 = _stage["pogo"]
	var dummy_b: Vector2 = _stage["dummy_b"]
	var ledge: Rect2 = _stage["ledge"]
	await create_timer(0.5).timeout
	_player.set("has_weapon", true)
	# 开场低语会把玩家输入锁住（_input_locked 期间水平速度直接归零），
	# 这条测的是物理够不够得着，所以先把对话掐掉、解锁输入
	var dialogue := _level.get_node_or_null("Dialogue")
	if dialogue != null:
		if bool(dialogue.get("_active")):
			dialogue.call("_finish")
		dialogue.call("abort")
	_player.set("_input_locked", false)
	await _frames(4)

	# 先把方台摆到“够得着”的距离逻辑上核对一遍：反弹高度减去方台顶面要留出余量。
	# （数字只用于打印，真正判定还是靠下面的真实物理）
	var bounce_height: float = pow(float(_player.get("POGO_BOUNCE_VELOCITY")), 2.0) / (2.0 * float(_player.get("GRAVITY")))
	print("[pogo] 反弹高度 %.0fpx，方台顶 %.0f，木桩顶约 %.0f" % [bounce_height, pogo.position.y, dummy_b.y - 15.0])

	# 站到跳台上，木桩乙左边一点
	await _stand(Vector2(dummy_b.x - 10.0, ledge.position.y - 13.0))
	# 起跳：给一个真正的一跳（和玩家按空格等价）
	_player.velocity = Vector2(0, float(_player.get("JUMP_VELOCITY")))
	await _frames(14)
	# 下落途中在木桩上方按 J：直接走下劈入口（输入映射由 double_jump_flow/战斗测试覆盖）
	_player.call("_start_pogo")
	# 一边下落一边往右飘，模拟玩家踩完木桩往方台那边推
	Input.action_press("move_right")
	var landed := false
	for _i in range(120):
		await physics_frame
		if bool(_level.call("player_on_platform", "pogo", _player)):
			landed = true
			break
	Input.action_release("move_right")

	var feet := _player.global_position.y + 13.0
	print("[pogo] 落点 x=%.1f feet=%.1f 判定=%s" % [_player.global_position.x, feet, str(landed)])
	_check(landed, "下劈反弹后没能站上方台（x=%.1f feet=%.1f，方台 %.0f..%.0f 顶 %.0f）" % [
		_player.global_position.x, feet, pogo.position.x, pogo.end.x, pogo.position.y])
	# 站稳之后再确认一次：判定不能只在落地那一帧为真
	await _frames(20)
	_check(bool(_level.call("player_on_platform", "pogo", _player)), "站上方台后判定又变假了（应该稳定为真）")
	print("[pogo] %s" % ("FAIL" if _failed else "PASS 下劈反弹能站上方台，判定稳定"))
	quit(1 if _failed else 0)

func _stand(target: Vector2) -> void:
	_player.global_position = target
	await _frames(90, true)

func _frames(count: int, wait_floor := false) -> void:
	for _i in range(count):
		await physics_frame
		if wait_floor and _player.is_on_floor():
			return

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[pogo] " + msg)
		_failed = true
