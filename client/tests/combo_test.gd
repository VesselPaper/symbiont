extends SceneTree
## 三连击回归（M4-34）：横劈 → 反手上撩 → 前刺，窗口内接段、窗口外回第一段。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/combo_test.gd
##
## 喂的是真实按键（Input.action_press），不直接调 _start_side_slash，
## 这样连招窗口、最短间隔、段落切换的判定都在同一条路径上被测到。

const SCENE := "res://scenes/world/test_arena.tscn"
const TOL := 0.05

var _level: Node2D
var _player: CharacterBody2D
var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.25).timeout
	_level = load(SCENE).instantiate() as Node2D
	root.add_child(_level)
	_player = _level.get_node("Player") as CharacterBody2D

	await create_timer(0.4).timeout
	_player.set("has_weapon", true)
	var dialogue := _level.get_node_or_null("Dialogue")
	if dialogue != null:
		if bool(dialogue.get("_active")):
			dialogue.call("_finish")
		dialogue.call("abort")
	_player.set("_input_locked", false)
	await _frames(6)

	# ---- 第一段：横劈 ----
	await _press_attack()
	_check(_step() == 0, "第一次按 J 不是第一段（实际 %d）" % _step())
	_check(absf(_timer() - 0.42) < TOL, "第一段动作时长不是 0.42（实际 %.2f）" % _timer())
	_check(_arc_radius() >= 40.0 and _arc_radius() <= 44.0, "第一段刀弧半径不对（%.1f）" % _arc_radius())

	# ---- 第二段：反手上撩（过了最短间隔、还在窗口里）----
	await _wait(0.30)
	await _press_attack()
	_check(_step() == 1, "第二下没接上 step=%d win=%.2f cd=%.2f floor=%s lock=%s timer=%.2f" % [_step(), float(_player.get("_combo_window")), float(_player.get("_attack_cooldown_timer")), str(_player.is_on_floor()), str(_player.get("_input_locked")), _timer()])
	_check(absf(_timer() - 0.40) < TOL, "第二段动作时长不是 0.40（实际 %.2f）" % _timer())
	_check(_arc_radius() < 40.0, "第二段该用它自己的刀弧（%.1f）" % _arc_radius())

	# ---- 第三段：前刺 ----
	await _wait(0.30)
	await _press_attack()
	_check(_step() == 2, "窗口内第三下没有接成第三段（实际 %d）" % _step())
	_check(absf(_timer() - 0.55) < TOL, "第三段动作时长不是 0.55（实际 %.2f）" % _timer())
	var shape := _hitbox_size()
	_check(absf(shape.x - 84.0) < 1.0 and absf(shape.y - 40.0) < 1.0,
			"第三段判定框不是 84×40（实际 %.0f×%.0f）" % [shape.x, shape.y])
	# 前刺要往前踏：站在地上时该有向前的速度（空中不补冲量，跳过）
	if _player.is_on_floor():
		_check(absf(_player.velocity.x) > 40.0, "前刺没有向前踏出（vx=%.0f）" % _player.velocity.x)

	# ---- 窗口过期后回到第一段 ----
	await _wait(1.2)
	await _press_attack()
	_check(_step() == 0, "窗口过期后没有回到第一段（实际 %d）" % _step())

	# ---- 反向：间隔不足 0.25s 的连按不该跳段 ----
	await _wait(1.2)
	await _press_attack()
	await _wait(0.06)
	await _press_attack()
	_check(_step() == 0, "0.06s 内连按竟然跳了段（实际 %d）" % _step())
	# 没重新起手的话，动作时钟是接着走的（>0.09）；重新起手会被清回 ~0.05
	_check(absf(_timer() - 0.42) > 0.02, "0.06s 内连按把动作重新起手了（timer=%.2f）" % _timer())

	print("[combo] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

# ---- 取玩家内部状态 ----
func _step() -> int:
	return int(_player.get("_combo_step"))

func _timer() -> float:
	return float(_player.get("_attack_anim_timer"))

func _arc_radius() -> float:
	var slash := _player.get_node_or_null("Body/SlashArc") as Line2D
	if slash == null or slash.points.size() < 2:
		return 0.0
	# 取弧线中段到原点的距离，就是这一刀的半径
	return slash.points[slash.points.size() / 2].length()

func _hitbox_size() -> Vector2:
	var cs := _player.get_node_or_null("HitboxSide/CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return Vector2.ZERO
	return (cs.shape as RectangleShape2D).size

func _press_attack() -> void:
	# 关卡里的旁白会把输入锁住（lock=true），测试只关心连招，先解锁
	var dlg := _level.get_node_or_null("Dialogue")
	if dlg != null and bool(dlg.get("_active")):
		dlg.call("abort")
	_player.set("_input_locked", false)
	Input.action_press("attack")
	# 必须跨过物理帧：is_action_just_pressed 只在按下那一帧为真，
	# 只等 idle 帧可能整个物理滴答都没看到这次按下
	await physics_frame
	await physics_frame
	Input.action_release("attack")
	await physics_frame

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await physics_frame
		t += 1.0 / 60.0

func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[combo] " + msg)
		_failed = true
