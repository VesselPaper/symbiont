extends SceneTree
## 火堆前那一战回归（M5-18）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/tutorial_beast_test.gd
##
## 组长定的教学节奏：走到火堆前方 → 过一段剧情 → 剧情末尾怪物扑上来咬一口（固定掉 1 颗心）
## → 这时候才交还操作、开始打 → 打完回火边歇一下学会回血。
## 这条钉住四个环节：
##   ① 火堆前方有触发区，走进去会播 tutorial_beast 这段旁白；
##   ② 旁白念完会放出一只加厚血的史莱姆（CaveBeast），并且玩家**正好掉 1 颗心**；
##   ③ 怪死了（打死或自己掉进悬崖）会在火堆上方挂"回火边歇一下"的提示；
##   ④ 回火边按 K 休息，回 1 颗心 —— 正好把刚才掉的那颗补回来。

const ARENA := "res://scenes/world/test_arena.tscn"
const TRIGGER := Vector2(4520, 640)
const CAMPFIRE := Vector2(4820, 659)

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var arena: Node2D = load(ARENA).instantiate()
	root.add_child(arena)
	await create_timer(0.5).timeout
	_check(arena.get_node_or_null("BeastTrigger") != null, "火堆前方没有剧情触发区")

	var player := arena.get_node("Player") as CharacterBody2D
	var max_hp := int(player.get_script().get_script_constant_map()["MAX_HP"])
	# 开场低语会先播（0.5 秒后），它和这一战无关：先把它翻完，免得两条对话撞在一起
	var dialogue := arena.get_node_or_null("Dialogue")
	await create_timer(0.9).timeout
	if dialogue != null and bool(dialogue.call("is_playing")):
		for _i in range(20):
			if not bool(dialogue.call("is_playing")):
				break
			dialogue.call("_finish")
			await physics_frame
	# 开场那层黑幕会锁输入；这里只测战斗段落，直接把锁解开
	player.set("_input_locked", false)
	player.set("hp", max_hp)
	player.global_position = TRIGGER
	player.velocity = Vector2.ZERO

	var playing := false
	# 走到触发区之后，这一战的旁白要等别的旁白念完才轮到它，所以这里等到"那条是 tutorial_beast"为止
	for _i in range(400):
		await physics_frame
		if dialogue != null and bool(dialogue.call("is_playing")) \
				and str(dialogue.get("_entry_dialogue_id")) == "tutorial_beast":
			playing = true
			break
	_check(playing, "走进火堆前方没有播 tutorial_beast 这段剧情")
	if playing:
		_check(str(dialogue.get("_entry_dialogue_id")) == "tutorial_beast",
			"播的不是 tutorial_beast（%s）" % str(dialogue.get("_entry_dialogue_id")))
		# 把这段旁白翻完（玩家按 K 的行为）
		for _i in range(20):
			if not bool(dialogue.call("is_playing")):
				break
			dialogue.call("_finish")
			await physics_frame
	_check(not bool(dialogue.call("is_playing")), "旁白翻不完")

	# ② 念完之后才放怪、才掉血
	var beast: Node2D = null
	for _i in range(180):
		await physics_frame
		beast = arena.get_node_or_null("CaveBeast") as Node2D
		if beast != null:
			break
	_check(beast != null, "剧情演完没有放出怪物")
	if beast != null:
		_check(int(beast.get("hp")) == 14, "怪物不是加厚血的小 boss（hp=%d）" % int(beast.get("hp")))
	var hp_after_bite := -1
	for _i in range(180):
		await physics_frame
		hp_after_bite = int(player.get("hp"))
		if hp_after_bite < max_hp:
			break
	print("[beast] 咬完 hp=%d / %d" % [hp_after_bite, max_hp])
	_check(hp_after_bite == max_hp - 1, "怪物咬完没有正好掉 1 颗心（hp=%d）" % hp_after_bite)

	# ③ 打死它 → 火堆上方出现提示
	if beast != null and is_instance_valid(beast):
		beast.call("take_damage", 999)
	for _i in range(180):
		await physics_frame
		if arena.get_node_or_null("CaveBeast") == null:
			break
	await physics_frame
	await physics_frame
	_check(arena.get_node_or_null("CampfireHint") != null, "怪死了没有在火堆上方提示回血")

	# ④ 回火边休息：正好把掉的那颗补回来
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
