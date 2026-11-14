extends SceneTree
## 虚空 → 地图的过渡回归（M4-25）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/void_transition_test.gd
##
## 组长反馈：「从虚空到正式的地图，做一个动画，中间过渡一下，而不是人物之间就在地面上站着了。」
## 这条钉两件事：
##   ① 序章结尾确实播了“下坠”演出（地板亮起、速度线出现、灵魂被拉长往下掉）；
##   ② 教学关收到“刚从虚空掉下来”的旗标时，玩家先出现在半空、之后落到地面；
##      没有这个旗标时（读档/直接进关）必须老实站在出生点 —— 反向验证。

const PROLOGUE := "res://scenes/world/prologue.tscn"
const ARENA := "res://scenes/world/test_arena.tscn"

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.25).timeout
	# ① 序章的下坠演出
	var pro: Node2D = load(PROLOGUE).instantiate()
	root.add_child(pro)
	await process_frame
	await process_frame
	pro.call("_begin_descent")
	await process_frame
	_check(bool(pro.get("_descending")), "序章没有进入下坠状态")
	_check(pro.get_node_or_null("FallStreaks") != null, "下坠演出里没有速度线")
	_check(pro.get_node_or_null("VoidFloor") != null, "下坠演出里没有实体化的地板")
	pro.queue_free()
	await process_frame

	# ② 从虚空掉进教学关：先在半空
	var gm := root.get_node("GameManager")
	gm.call("set_flag", "enter_from_void")
	var arena: Node2D = load(ARENA).instantiate()
	root.add_child(arena)
	await process_frame
	var player := arena.get_node("Player") as CharacterBody2D
	var stage: Dictionary = arena.get_script().get_script_constant_map()["STAGE"]
	var spawn: Vector2 = stage["spawn"]
	var start_y := player.global_position.y
	print("[void] 落地前 y=%.1f（出生点 %.1f，高出 %.1fpx）" % [start_y, spawn.y, spawn.y - start_y])
	_check(spawn.y - start_y >= 150.0, "进关时人还站在地上（只高出 %.1fpx）" % (spawn.y - start_y))
	_check(not bool(gm.call("has_flag", "enter_from_void")), "旗标没被消费，下次进关又会掉一次")
	var landed := false
	for _i in range(180):
		await physics_frame
		if player.is_on_floor() and absf(player.global_position.y - spawn.y) <= 2.0:
			landed = true
			break
	print("[void] 落地后 y=%.1f on_floor=%s" % [player.global_position.y, player.is_on_floor()])
	_check(landed, "没有落到地面（y=%.1f）" % player.global_position.y)
	arena.queue_free()
	await process_frame

	# ③ 反向：没有旗标时，玩家必须老实站在出生点
	var arena2: Node2D = load(ARENA).instantiate()
	root.add_child(arena2)
	await process_frame
	var p2 := arena2.get_node("Player") as CharacterBody2D
	var stage2: Dictionary = arena2.get_script().get_script_constant_map()["STAGE"]
	var spawn2: Vector2 = stage2["spawn"]
	print("[void] 普通进关 y=%.1f（应≈%.1f）" % [p2.global_position.y, spawn2.y])
	_check(absf(p2.global_position.y - spawn2.y) <= 2.0, "普通进关也从天上掉下来了")
	arena2.queue_free()

	print("[void] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[void] " + msg)
		_failed = true
