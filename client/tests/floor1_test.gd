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

	# 地形：12 块平台/边界墙（M2-04 扩建后：入口、钟厅、台阶、祭坛、断桥、遗物廊、层门厅 + 两墙）
	var terrain := _level.get_node_or_null("Terrain")
	_check(terrain != null, "缺少 Terrain 节点")
	if terrain != null:
		_check(terrain.get_child_count() == 12, "地形数量应为 12，实际 %d" % terrain.get_child_count())
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

	# 掉出地图的重伤区
	_check(_level.get_node_or_null("KillZone") != null, "缺少 KillZone")

	# 敌人
	var enemies := _level.get_node_or_null("Enemies")
	_check(enemies != null and enemies.get_child_count() == 3, "史莱姆应为 3 只")
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
		for dialogue_id in ["floor1_enter", "floor1_bell", "floor1_altar", "floor1_bridge", "floor1_relic", "floor1_gate"]:
			var row: Dictionary = db.get_dialogue(dialogue_id)
			_check(not row.is_empty(), "对话 %s 不在数据表里" % dialogue_id)
			_check(row.has("lines") and (row["lines"] as Array).size() > 0, "对话 %s 没有台词" % dialogue_id)

	# 玩家出生在第一块平台上
	var player := _level.get_node_or_null("Player") as Node2D
	_check(player != null, "缺少 Player")
	if player != null:
		_check(player.global_position.x < 640.0, "玩家出生点不在入口平台范围内")
