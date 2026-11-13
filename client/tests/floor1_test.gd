extends SceneTree
## 第一层地板测试（无头）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/floor1_test.gd
## 检查：场景能加载、地形/触发器等节点生成、剧情数据在库里、关键子节点齐全。

var _frames := 0
var _level: Node = null
var _failed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		var scene: PackedScene = load("res://scenes/world/floor1.tscn")
		if scene == null:
			push_error("[floor1] 场景加载失败")
			_failed = true
			quit(1)
			return true
		_level = scene.instantiate()
		root.add_child(_level)
		return false
	if _frames < 20:
		return false

	_run_checks()
	print("[floor1] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[floor1] " + message)
		_failed = true

func _run_checks() -> void:
	if _level == null:
		_failed = true
		return

	# 地形：13 块平台/边界墙（M4-08 后段扩建：入口、钟厅、台阶、祭坛、断桥、遗物廊、层门厅两段 + 两墙）
	var terrain := _level.get_node_or_null("Terrain")
	_check(terrain != null, "缺少 Terrain 节点")
	if terrain != null:
		_check(terrain.get_child_count() == 13, "地形数量应为 13，实际 %d" % terrain.get_child_count())
		var first := terrain.get_child(0) as StaticBody2D
		_check(first != null, "地形子节点不是 StaticBody2D")
		if first != null:
			_check(first.get_node_or_null("CollisionShape2D") != null, "平台缺少碰撞")
			var rim := first.get_child(1) as Polygon2D
			_check(rim != null, "平台缺少顶面亮边")

	# 触发器：钟厅/祭坛/断桥/遗物廊/层门
	var triggers := _level.get_node_or_null("Triggers")
	_check(triggers != null, "缺少 Triggers")
	if triggers != null:
		_check(triggers.get_child_count() == 5, "触发器应为 5 个，实际 %d" % triggers.get_child_count())
		for trigger_name in ["BellTrigger", "AltarTrigger", "BridgeTrigger", "RelicTrigger", "GateTrigger"]:
			_check(triggers.get_node_or_null(trigger_name) != null, "缺少触发器 %s" % trigger_name)

	# 机关与守钟人（M2-06）：骨门初始挡路，钟绳/NPC 在骨门左侧
	var mechanisms := _level.get_node_or_null("Mechanisms")
	_check(mechanisms != null, "缺少 Mechanisms")
	if mechanisms != null:
		_check(mechanisms.get_node_or_null("BoneGate") != null, "缺少 BoneGate")
		_check(mechanisms.get_node_or_null("BellMechanism") != null, "缺少 BellMechanism")
		_check(mechanisms.get_node_or_null("Watchman") != null, "缺少 Watchman")
		var gate := mechanisms.get_node_or_null("BoneGate") as StaticBody2D
		if gate != null:
			_check(gate.collision_layer == 1, "骨门初始应挡住玩家")
			_check(gate.get_node_or_null("Shape") != null, "骨门缺少碰撞形状")

	# M4-04：层门只路过播一次，不再挂 K；只保留祭坛这个关键机制提示
	var inspect := _level.get_node_or_null("InspectPoints")
	_check(inspect != null, "缺少 InspectPoints")
	if inspect != null:
		_check(inspect.get_child_count() == 1, "调查点应为 1 个（只留祭坛），实际 %d" % inspect.get_child_count())
		_check(inspect.get_node_or_null("AltarInspect") != null, "缺少祭坛调查点")
		_check(inspect.get_node_or_null("GateInspect") == null, "层门不应再有重复 K 调查点")

	# 掉出地图的重伤区
	_check(_level.get_node_or_null("KillZone") != null, "缺少 KillZone")

	# M3-01：层门后接真正的第二层，门缝判定和黑场遮罩都要在
	_check(_level.get_node_or_null("Floor2Entry") != null, "缺少第二层入口判定")
	var transition := _level.get_node_or_null("Floor2Transition")
	_check(transition != null, "缺少第二层转场层")
	if transition != null:
		_check(transition.get_node_or_null("Fade") != null, "缺少转场黑幕")
		_check(transition.get_node_or_null("FloorName") != null, "缺少第二层层名")

	# 敌人：钟厅不给怪；钟厅之后沿路线铺 4 只史莱姆 + 1 只孢子射手
	var enemies := _level.get_node_or_null("Enemies")
	_check(enemies != null and enemies.get_child_count() == 5, "敌人应为 4 只史莱姆 + 1 只孢子射手")
	_check(enemies != null and enemies.get_node_or_null("SporeShooter") != null, "缺少 SporeShooter")
	# 剧情触发器周围不放怪：每个触发器和最近史莱姆至少隔 200px
	if enemies != null and triggers != null:
		for trigger in triggers.get_children():
			var trigger_pos: Vector2 = (trigger as Node2D).global_position
			for enemy in enemies.get_children():
				var enemy_pos: Vector2 = (enemy as Node2D).global_position
				_check(trigger_pos.distance_to(enemy_pos) >= 200.0,
					"%s 周围 %dpx 内有史莱姆 %s" % [trigger.name, int(trigger_pos.distance_to(enemy_pos)), enemy.name])

	# 场景物件：钟、灯、门
	var props := _level.get_node_or_null("Props")
	_check(props != null, "缺少 Props")
	if props != null:
		_check(props.get_node_or_null("Bell") != null, "缺少吊钟")
		_check(props.get_node_or_null("GateFrame") != null, "缺少层门")

	# 背景：天光与暗角两个 CanvasLayer
	var backdrop := _level.get_node_or_null("Backdrop")
	_check(backdrop != null, "缺少 Backdrop")
	if backdrop != null:
		_check(backdrop.get_node_or_null("Sky") != null, "缺少天光层")
		_check(backdrop.get_node_or_null("Vignette") != null, "缺少暗角层")
		_check(backdrop.get_node_or_null("Far") != null, "缺少远景剪影层")
		_check(backdrop.get_node_or_null("Vines") != null, "缺少前景藤蔓层")

	# 剧情：四段台词都在 DataDB 里，且进入段有台词
	var db := root.get_node_or_null("/root/DataDB")
	_check(db != null, "缺少 DataDB")
	if db != null:
		for dialogue_id in ["floor1_enter", "floor1_bell", "floor1_altar", "floor1_bridge", "floor1_relic", "floor1_gate", "floor1_watchman", "floor1_watchman_after", "floor1_bell_ring"]:
			var row: Dictionary = db.get_dialogue(dialogue_id)
			_check(not row.is_empty(), "对话 %s 不在数据表里" % dialogue_id)
			_check(row.has("lines") and (row["lines"] as Array).size() > 0, "对话 %s 没有台词" % dialogue_id)

	# 玩家出生在第一块平台上
	var player := _level.get_node_or_null("Player") as Node2D
	_check(player != null, "缺少 Player")
	if player != null:
		_check(player.global_position.x < 640.0, "玩家出生点不在入口平台范围内")
