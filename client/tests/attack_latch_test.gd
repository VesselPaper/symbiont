extends SceneTree
## 攻击输入的反向回归（M5-07）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/attack_latch_test.gd
##
## 组长反馈：「空中一直按攻击会无限攻击，需加后摇防止。」
## 这里钉三件事（都是"不该发生"的反向验证）：
##   ① 按住攻击键不放时，只出第一刀，后面不再自动续刀；
##   ② 松开再按，才允许出下一刀；
##   ③ 空中攻击后摇（_air_attack_recovery）期间按下攻击，不出刀。
##
## 不用教学关整张地图：那张图开局会播低语对话、把输入锁住，测不出攻击门禁。
## 这里只搭一块地板 + 一个玩家，舞台最小化。

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var level := Node2D.new()
	level.name = "Level"
	root.add_child(level)
	# 地板：玩家出生点脚下一条长条（碰撞层 1，和正式关卡一致）
	var ground := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000, 60)
	col.shape = shape
	col.position = Vector2(0, 30)
	ground.add_child(col)
	ground.position = Vector2(0, 40)
	level.add_child(ground)

	var player: CharacterBody2D = load(PLAYER_SCENE).instantiate()
	player.position = Vector2(0, -13)
	level.add_child(player)
	await physics_frame
	await physics_frame
	player.set("has_weapon", true)
	# 等落地站稳，免得第一刀被"空中"判定成下劈
	for _i in range(20):
		await physics_frame
		if player.is_on_floor():
			break
	Input.action_release("attack")
	await physics_frame
	await physics_frame

	# ① 按下 → 出刀
	Input.action_press("attack")
	var started: int = await _attack_starts(player, 4)
	_check(started >= 1, "按下攻击键没有出刀（%d）" % started)

	# ② 一直按着（模拟键盘长按 echo）→ 不该再有新刀
	var held: int = await _attack_starts(player, 40)
	_check(held == 0, "按住攻击键还在自动连砍（多了 %d 刀）" % held)

	# ③ 松开再按 → 允许下一刀
	Input.action_release("attack")
	await physics_frame
	await physics_frame
	Input.action_press("attack")
	var again: int = await _attack_starts(player, 6)
	_check(again >= 1, "松开再按没有出下一刀（%d）" % again)
	Input.action_release("attack")
	await physics_frame

	# ④ 空中连劈：抬到半空，出第一刀之后马上松开再按，后摇内不该出第二刀。
	# （不能在地上测：后摇设计成"一落地立刻解除"，地上永远测不出这层门禁）
	# 先把上一刀的地面冷却等干净（0.25 秒），否则空中第一刀会被冷却吞掉，测出来的时序全是错的
	await create_timer(0.5).timeout
	player.position = Vector2(0, -280)
	player.velocity = Vector2.ZERO
	await physics_frame
	await physics_frame
	_check(not player.is_on_floor(), "没抬到半空，地面测试不算数")
	Input.action_press("attack")
	var air_first: int = await _attack_starts(player, 4)
	_check(air_first >= 1, "空中按下攻击没有出刀（%d）" % air_first)
	_check(float(player.get("_air_attack_recovery")) > 0.0, "空中出刀后没有进入后摇")
	Input.action_release("attack")
	await physics_frame
	Input.action_press("attack")
	var air_blocked: int = await _attack_starts(player, 6)
	_check(air_blocked == 0, "空中后摇期间还能连劈（多了 %d 刀）" % air_blocked)
	Input.action_release("attack")

	level.queue_free()
	await process_frame
	print("[attack_latch] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 数"新起手"的次数：攻击动画计时器只会往下走，只有重新出刀才会跳回高位。
func _attack_starts(player: Node, frames: int) -> int:
	var last := float(player.get("_attack_anim_timer"))
	var count := 0
	for _i in range(frames):
		await physics_frame
		var now := float(player.get("_attack_anim_timer"))
		if now > last:
			count += 1
		last = now
	return count

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[attack_latch] " + msg)
		_failed = true
