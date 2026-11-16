extends SceneTree
## 火堆场景回归（M5-35 重定顺序）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/tutorial_beast_test.gd
##
## 组长定的走线：
##   ① 这个场景一开始场上就有史莱姆（不是走到触发区才刷出来）
##   ② 走到能看见它的时候触发剧情
##   ③ 剧情念完，它扑过来；**真咬到玩家（掉血）之后**剧情结束，提示"砍它"
##   ④ 打死它会在火堆上方挂"回火边歇一下"
##   ⑤ 火堆只在血不满时能用，回 1 颗心

const ARENA := "res://scenes/world/test_arena.tscn"
const TRIGGER := Vector2(13300, 640)
const CAMPFIRE := Vector2(16500, 637)

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var arena: Node2D = load(ARENA).instantiate()
	root.add_child(arena)
	await create_timer(0.6).timeout

	# ① 一开始场上就有史莱姆（还没走到它跟前）
	_check(arena.get_node_or_null("CaveBeast") != null, "场景开始时场上没有史莱姆")
	_check(arena.get_node_or_null("BeastTrigger") != null, "缺少剧情触发区")

	var player := arena.get_node("Player") as CharacterBody2D
	var max_hp := int(player.get_script().get_script_constant_map()["MAX_HP"])
	var dialogue := arena.get_node_or_null("Dialogue")
	# 开场低语先翻完，免得两条对话撞在一起
	await create_timer(0.9).timeout
	if dialogue != null and bool(dialogue.call("is_playing")):
		for _i in range(20):
			if not bool(dialogue.call("is_playing")):
				break
			dialogue.call("_finish")
			await physics_frame
	player.set("_input_locked", false)
	player.set("hp", max_hp)
	player.global_position = TRIGGER
	player.velocity = Vector2.ZERO

	# ② 走到触发区 → 播 tutorial_beast
	var playing := false
	for _i in range(400):
		await physics_frame
		if dialogue != null and bool(dialogue.call("is_playing")) \
				and str(dialogue.get("_entry_dialogue_id")) == "tutorial_beast":
			playing = true
			break
	_check(playing, "走到史莱姆跟前没有播 tutorial_beast")
	# ③ 念完这段旁白（玩家按 K 的行为），之后它才会扑上来
	if playing:
		for _i in range(40):
			if not bool(dialogue.call("is_playing")):
				break
			dialogue.call("_finish")
			await physics_frame
	_check(not bool(dialogue.call("is_playing")), "旁白翻不完")

	var hp_after_bite := max_hp
	for _i in range(600):
		await physics_frame
		hp_after_bite = int(player.get("hp"))
		if hp_after_bite < max_hp:
			break
	print("[beast] 被咬完 hp=%d / %d" % [hp_after_bite, max_hp])
	_check(hp_after_bite == max_hp - 1, "史莱姆咬完没有正好掉 1 颗心（hp=%d）" % hp_after_bite)
	await physics_frame
	_check(arena.get_node_or_null("BeastFightHint") != null, "被咬之后没有提示玩家还手")

	# ④ 打死它 → 火堆上方提示
	var beast := arena.get_node_or_null("CaveBeast")
	if beast != null:
		beast.call("take_damage", 999)
	for _i in range(180):
		await physics_frame
		if arena.get_node_or_null("CaveBeast") == null:
			break
	await physics_frame
	await physics_frame
	_check(arena.get_node_or_null("CampfireHint") != null, "怪死了没有在火堆上方提示回血")

	# ⑤ 火堆：血不满才能休息，正好补回掉的那颗
	var fire := arena.get_node_or_null("Campfire")
	_check(fire != null, "教学关没有火堆")
	if fire != null:
		player.global_position = CAMPFIRE + Vector2(24, -13)
		await physics_frame
		fire.call("_rest")
		await physics_frame
		_check(int(player.get("hp")) == hp_after_bite + 1,
			"火边休息没有把血补回来（hp=%d）" % int(player.get("hp")))

	arena.queue_free()
	await process_frame
	print("[beast] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[beast] " + msg)
		_failed = true
