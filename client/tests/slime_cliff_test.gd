extends SceneTree
## 怪物悬崖行为回归（M5-15）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/slime_cliff_test.gd
##
## 组长反馈：「怪物遇悬崖不自动走过也不追对面玩家。」
## 史莱姆是蹦着走的，以前只有巡逻会探落点，追击时不管前面有没有地就朝玩家跳，
## 玩家站在断口对面，它就一趟趟跳进坑里。这条钉两件事：
##   ① 玩家站在断口对面（水平距离仍在追击范围内）时，史莱姆不能跳过断口；
##   ② 它也不能掉进断口（y 一直在断口这一侧的地面上）。
## 反向：同一套场景里把玩家挪到史莱姆同侧近处，它必须照常追过来（不能因为怕悬崖就不追了）。

const SLIME := "res://scenes/entities/slime.tscn"
const PLAYER := "res://scenes/player/player.tscn"
## 断口：左岸 0..620，右岸 760 起，和第一层那两个断口的尺寸一致
const GAP_LEFT := 620.0
const GAP_RIGHT := 760.0
const TOP_Y := 620.0

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var level := Node2D.new()
	level.name = "CliffLevel"
	root.add_child(level)
	_add_ground(level, 0.0, GAP_LEFT, TOP_Y)
	_add_ground(level, GAP_RIGHT, 1400.0, TOP_Y)

	var player: CharacterBody2D = load(PLAYER).instantiate()
	player.position = Vector2(GAP_RIGHT + 30.0, TOP_Y - 20.0)
	level.add_child(player)
	player.set("_input_locked", true)

	var slime: Node2D = load(SLIME).instantiate()
	slime.position = Vector2(GAP_LEFT - 20.0, TOP_Y - 12.0)
	level.add_child(slime)

	# 让双方先落地站稳，再开始数（史莱姆是蹦着走的，固定帧数可能正好在空中，所以轮询）
	var both_grounded := false
	for _i in range(160):
		await physics_frame
		if player.is_on_floor() and slime.is_on_floor():
			both_grounded = true
			break
	_check(both_grounded, "双方没能在两岸站稳，测试场景不成立（player=%s slime=%s）" % [
		str(player.is_on_floor()), str(slime.is_on_floor())])
	var dx := absf(player.global_position.x - slime.global_position.x)
	var chase := float(slime.get_script().get_script_constant_map()["CHASE_DISTANCE"])
	_check(dx <= chase, "两人距离 %.0f 超出追击范围 %.0f，测不到追击" % [dx, chase])

	# ① 追 400 帧（约 6.7 秒，够跳七八次）
	var left_further := 0.0
	for _i in range(400):
		await physics_frame
		left_further = maxf(left_further, slime.global_position.x)
		_check(slime.global_position.y < TOP_Y + 40.0,
			"史莱姆掉进断口了（y=%.1f）" % slime.global_position.y)
		if slime.global_position.x > GAP_RIGHT:
			_check(false, "史莱姆跳过断口追人对岸玩家（x=%.1f）" % slime.global_position.x)
			break
	print("[slime_cliff] 最远跳到 x=%.1f（断口右边线 %.0f）" % [left_further, GAP_RIGHT])
	_check(left_further < GAP_LEFT + 20.0, "史莱姆越过断口边缘了（x=%.1f）" % left_further)

	# ② 反向：把玩家放到同一侧近处，它必须照常追过来
	player.position = Vector2(GAP_LEFT - 160.0, TOP_Y - 20.0)
	player.velocity = Vector2.ZERO
	await physics_frame
	var start_dx := absf(player.global_position.x - slime.global_position.x)
	var closed := false
	for _i in range(240):
		await physics_frame
		if absf(player.global_position.x - slime.global_position.x) < start_dx - 20.0:
			closed = true
			break
	_check(closed, "玩家就在同一侧，史莱姆却不追了（距离没缩短）")

	level.queue_free()
	await process_frame
	print("[slime_cliff] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 一块地面：顶面 TOP_Y，厚 90
func _add_ground(parent: Node, from_x: float, to_x: float, top_y: float) -> void:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(to_x - from_x, 90)
	col.shape = shape
	body.add_child(col)
	body.position = Vector2((from_x + to_x) * 0.5, top_y + 45.0)
	parent.add_child(body)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[slime_cliff] " + msg)
		_failed = true
