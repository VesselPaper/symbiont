extends SceneTree
## 教学关物理门回归（M2-08）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/tutorial_gates_test.gd
##
## 验收：五扇门存在且初始挡路；推进步骤只开对应的门；战斗门要等敌人清空才开。

var _frames := 0
var _level: Node = null
var _failed := false
var _phase := 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_level = load("res://scenes/world/test_arena.tscn").instantiate()
		root.add_child(_level)
		return false
	if _frames == 8:
		_run_initial()
		return false
	if _phase == 1 and _frames >= 180:
		_run_combat_kill()
		return false
	if _phase == 2 and _frames >= 420:
		_run_combat_clear()
		print("[gates] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[gates] " + message)
		_failed = true

func _run_initial() -> void:
	var holder := _level.get_node_or_null("TutorialGates")
	_check(holder != null, "缺少 TutorialGates")
	if holder == null:
		_failed = true
		return
	_check(holder.get_child_count() == 5, "教学门应为 5 扇，实际 %d" % holder.get_child_count())
	for gate_id in ["move", "jump", "attack", "pogo", "combat"]:
		var gate := holder.get_node_or_null("Gate_%s" % gate_id) as StaticBody2D
		_check(gate != null, "缺少 %s 门" % gate_id)
		if gate != null:
			_check(gate.collision_layer == 1, "%s 门初始应挡路" % gate_id)
	# 推进 MOVE 后只开 move 门，jump 门仍然关着
	_level.call("open_tutorial_gate", "move")
	var move_gate := holder.get_node_or_null("Gate_move") as StaticBody2D
	var jump_gate := holder.get_node_or_null("Gate_jump") as StaticBody2D
	_check(move_gate != null and move_gate.call("is_open"), "move 门没有打开")
	_check(jump_gate != null and not jump_gate.call("is_open"), "jump 门被提前打开了")
	# 为战斗门准备：手动生成敌人并杀死，确认 combat 门只在清空后打开
	# 先结束开场低语：对话会按 enemy 组冻结敌人，不结束的话史莱姆死亡动画不会走
	var dialogue := _level.get_node_or_null("Dialogue")
	if dialogue != null and bool(dialogue.call("is_playing")):
		dialogue.call("_finish")
	_level.call("spawn_enemies")
	_phase = 1

func _run_combat_kill() -> void:
	var dialogue := _level.get_node_or_null("Dialogue")
	if dialogue != null and bool(dialogue.call("is_playing")):
		dialogue.call("_finish")
	for enemy in get_nodes_in_group("enemy"):
		if enemy.has_method("take_damage"):
			enemy.call("take_damage", 99)
	_phase = 2

func _run_combat_clear() -> void:
	var combat_gate := _level.get_node_or_null("TutorialGates/Gate_combat") as StaticBody2D
	_check(combat_gate != null, "缺少 combat 门")
	if combat_gate != null:
		_check(bool(combat_gate.call("is_open")), "敌人清空后战斗门仍没开")
		_check(int(combat_gate.collision_layer) == 0, "战斗门打开后碰撞没关")
