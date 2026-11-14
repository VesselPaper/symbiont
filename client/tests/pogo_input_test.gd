extends SceneTree
## 空中按 J 到底反弹不反弹（M4-23 组长反馈：在稻草人头上砍一刀，人不弹反而往下掉）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/pogo_input_test.gd
##
## 这条不走内部函数，直接喂真实输入：空中只按攻击键（不按 S），
## 1) 必须进入下劈并命中脚下的木桩；2) 必须获得向上反弹速度；3) 人必须比出手点更高。
## 反向也要测：站在地上只按攻击 = 横砍，不该把自己弹起来。

const SCENE := "res://scenes/world/test_arena.tscn"
const MIN_UP_SPEED := 300.0     # 反弹初速 -650，扣掉几帧重力也该明显大于这个数
const MIN_RISE := 20.0          # 从出手点到最高点至少升这么多，肉眼能看出“弹起来了”

var _level: Node2D
var _player: CharacterBody2D
var _stage: Dictionary
var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.25).timeout
	_level = load(SCENE).instantiate() as Node2D
	root.add_child(_level)
	_player = _level.get_node("Player") as CharacterBody2D
	_stage = _level.get_script().get_script_constant_map()["STAGE"]
	await create_timer(0.4).timeout
	_player.set("has_weapon", true)
	var dialogue := _level.get_node_or_null("Dialogue")
	if dialogue != null:
		if bool(dialogue.get("_active")):
			dialogue.call("_finish")
		dialogue.call("abort")
	_player.set("_input_locked", false)
	await _frames(4)

	var dummy_b: Vector2 = _stage["dummy_b"]
	var start := Vector2(dummy_b.x, dummy_b.y - 70.0)
	_player.global_position = start
	_player.velocity = Vector2(0, 60.0)
	await _frames(3)
	await _press_attack()
	var best_vy := 999.0
	var highest := _player.global_position.y
	for _i in range(40):
		await physics_frame
		best_vy = minf(best_vy, _player.velocity.y)
		highest = minf(highest, _player.global_position.y)
	await _frames(2)
	print("[pogo_input] 空中按 J：最上冲速度 %.0f，比出手点高 %.1fpx" % [best_vy, start.y - highest])
	_check(best_vy <= -MIN_UP_SPEED, "空中按 J 没有向上反弹（最小 vy=%.0f）" % best_vy)
	_check(start.y - highest >= MIN_RISE, "弹起高度不够（%.1f < %.1f）" % [start.y - highest, MIN_RISE])

	# 反向：站在地上按 J 只该横砍，不该把自己弹起来
	await _frames(30)
	_player.global_position = Vector2(dummy_b.x - 40.0, _stage["ledge"].position.y - 13.0)
	_player.velocity = Vector2.ZERO
	await _frames(20)
	var ground_y := _player.global_position.y
	await _press_attack()
	var tops_ground := ground_y
	for _i in range(30):
		await physics_frame
		tops_ground = minf(tops_ground, _player.global_position.y)
	print("[pogo_input] 地面按 J：离地 %.1fpx（横砍不该跳起来）" % [ground_y - tops_ground])
	_check(ground_y - tops_ground <= 2.0, "地面横砍把自己弹起来了（%.1fpx）" % [ground_y - tops_ground])

	print("[pogo_input] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _press_attack() -> void:
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(1)

func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[pogo_input] " + msg)
		_failed = true
