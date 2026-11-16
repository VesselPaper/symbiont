extends SceneTree
## 虚空 → 地图的过渡回归（M4-25）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/void_transition_test.gd
##
## 组长反馈：「从虚空到正式的地图，做一个动画，中间过渡一下，而不是人物之间就在地面上站着了。」
## 这条钉两件事：
##   ① 序章结尾确实播了“下坠”演出（地板亮起、速度线出现、灵魂被拉长往下掉）；
##   ② 教学关收到“刚从虚空掉下来”的旗标时，玩家先出现在半空 → 砸到地上 → 压扁站起 → 交还操作；
##      没有这个旗标时（读档/直接进关）必须老实站在出生点 —— 反向验证。
## M4-62：原来那段"先躺在地上、灵魂入体、10 秒慢慢爬起来"被组长否掉了，改成直接砸下来站起。

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
	# M4-39 换成了一镜到底的演出：不再有速度线与实体地板，
	# 改成"镜头锁玩家 + 鼓点收紧 + 明暗同拍"，这里钉住新的骨架
	_check(int(pro.get("_desc_phase")) == 1, "下坠演出没有进入第 1 阶段")
	# M4-44：镜头改成平滑跟随，第一帧不该瞬移到位（那正是"闪现"的来源）
	var cam: Camera2D = pro.get("_camera")
	var soul: Node2D = pro.get("_soul")
	_check(cam != null and soul != null and cam.global_position.distance_to(soul.global_position) > 20.0,
			"镜头一帧就瞬移到角色身上（应该是平滑跟随）")
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
	var arena_cam := arena.get_node("Camera2D") as Camera2D
	await process_frame
	await process_frame
	var start_y := player.global_position.y
	print("[void] 进关位置 y=%.1f（出生点 %.1f），rotation=%.2f" % [start_y, spawn.y, player.rotation])
	# M4-62（组长定的新开场）：人从上方砸下来 —— 进关时必须在半空、不是躺在地上，
	# 而且姿态是正的（躺倒那一套已经删了）。
	# 阈值给 100 而不是"离出生点 150"：跑测试时机器的帧率不一致，两帧之内他已经掉下来一截了。
	_check(player.global_position.y < spawn.y - 100.0,
		"进关时人不在半空（y=%.1f，出生点 %.1f）" % [player.global_position.y, spawn.y])
	_check(absf(player.rotation) < 0.2, "进关时人是躺着的（rotation=%.2f）" % player.rotation)
	_check(not player.is_on_floor(), "进关时人已经站在地上了，没有下坠过程")
	# M4-67：进关时人必须在**画面 X 轴正中**（虚空的最后也是一晃人在正中掉下去，
	# 两幕要接得上）。这里按屏幕坐标算，不管地图 limit 怎么夹。
	var screen_x := (player.global_position.x - arena_cam.global_position.x) * arena_cam.zoom.x + 640.0
	print("[void] 进关时角色屏幕 x=%.1f（应≈640）" % screen_x)
	_check(absf(screen_x - 640.0) < 40.0, "进关时人不在画面正中（屏幕 x=%.1f）" % screen_x)
	# M5-01（组长反馈「角色并没有在蒙版的中间」）：亮圈必须钉在**角色身体**上，
	# 不是钉在屏幕正中。逐帧跟着人算，落地那一下的镜头下压也得算进去。
	var hole = arena.get("_intro_shader").get_shader_parameter("center_px")
	var body_screen := (player.global_position + Vector2(0, -6) - arena_cam.global_position
		- arena_cam.offset) * arena_cam.zoom + Vector2(640, 360)
	print("[void] 亮圈中心=%s 角色屏幕位置=%s" % [hole, body_screen])
	# 纵向允许 40px：读参数和物理推进差一帧，坠落时一帧就差这么多（终速 900px/s × 2.679）
	_check(Vector2(hole).distance_to(body_screen) < 40.0,
		"亮圈没有套在角色身上（圈心 %s，角色 %s）" % [hole, body_screen])
	_check(absf(float(hole.x) - 640.0) < 8.0, "亮圈横向不在屏幕正中（x=%.1f）" % float(hole.x))
	# 下坠 → 落地 → 站起来（落地压扁那一下由 player.gd 的 _intro_land_timer 结算）
	var landed := false
	for _i in range(1200):
		await physics_frame
		if player.is_on_floor():
			landed = true
			break
	_check(landed, "从虚空掉下来没有落到地面（y=%.1f）" % player.global_position.y)
	_check(absf(player.global_position.y - spawn.y) < 12.0,
		"落地的位置不是出生点（y=%.1f）" % player.global_position.y)
	var land_anim := float(player.get("_intro_land_timer"))
	_check(land_anim > 0.0, "落地没有播「压扁站起」（_intro_land_timer=%.2f）" % land_anim)
	# M4-67：落地之后先黑着缓冲 2 秒、再用 5 秒慢慢照亮，照完才进正式教学关。
	# M5-01：组长要求开场放慢到 10 多秒，缓冲改成 3.5 秒、照亮 6.5 秒（合计 10 秒）。
	# 不能用 _input_locked 判断（开场低语也会锁输入），改看"那层黑幕有没有撤掉"。
	# 用 create_timer 而不是数帧：无头模式帧率不受限，数帧会随机翻车。
	var lit := false
	var waited_lit := 0.0
	while waited_lit < 30.0:
		await create_timer(0.25).timeout
		waited_lit += 0.25
		if arena.get("_intro_blackout") == null:
			lit = true
			break
	print("[void] 落地后 y=%.1f on_floor=%s 照亮完=%s（等了 %.1fs）" % [
		player.global_position.y, player.is_on_floor(), lit, waited_lit])
	_check(lit, "落地后黑暗一直没照亮")
	# 3.5 秒缓冲 + 6.5 秒照亮，不能被压缩
	_check(waited_lit >= 9.5, "缓冲 3.5 秒 + 照亮 6.5 秒被压缩了（只等了 %.1fs）" % waited_lit)
	_check(absf(player.rotation) < 0.1, "站起后姿态没有回正（rotation=%.2f）" % player.rotation)
	_check(arena_cam.zoom.x < 2.9, "亮起来之后镜头没有拉回常规（zoom=%.2f）" % arena_cam.zoom.x)
	_check(not bool(player.get("_input_locked")) or arena.get("_playing_dialogue") != null,
		"照亮结束后没有交还操作权")
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
