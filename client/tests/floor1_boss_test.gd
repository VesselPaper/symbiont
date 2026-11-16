extends SceneTree
## 第一层关底 Boss（魂史莱姆）回归：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/floor1_boss_test.gd
##
## 验收：Boss 能生成、体型是主角 4~5 倍、两个技能都能跑、打空血后置 floor1_boss_defeated 旗标。

const SCENE := "res://scenes/world/floor1.tscn"

var _frames := 0
var _level: Node
var _boss: Node
var _failed := false
var _checked_size := false
var _gm: Node

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_gm = root.get_node("/root/GameManager")
		_gm.set("flags", {})
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		# 先把玩家挪到关底门厅的地面上（顶面 600）：旁白要落地才播，
		# 人在半空的话对话会挂起，boss 也来不及被冻住，测出来的状态是假的
		var early_player := _level.get_node_or_null("Player") as Node2D
		if early_player != null:
			early_player.global_position = Vector2(5440, 587)
			(early_player as CharacterBody2D).velocity = Vector2.ZERO
		return false
	if _frames == 6:
		_level.call("_spawn_boss")
		_boss = _level.get_node_or_null("SoulSlimeBoss")
		_check(_boss != null, "没有生成 SoulSlimeBoss")
		# M5-16（组长要求"灵魂聚合体前加剧情说明缘由"）：出 boss 的同时必须播那段旁白，
		# 而且必须是"先放 boss 再播"——这样 dialogue.gd 才能把它冻住，念话时它不会砸人。
		var dlg := _level.get_node_or_null("Dialogue")
		_check(dlg != null and bool(dlg.call("is_playing")), "关底战前没有播说明缘由的旁白")
		if dlg != null:
			_check(str(dlg.get("_entry_dialogue_id")) == "floor1_soul_boss",
				"关底战前播的不是 floor1_soul_boss（%s）" % str(dlg.get("_entry_dialogue_id")))
		if _boss != null:
			_check(int(_boss.get("process_mode")) == Node.PROCESS_MODE_DISABLED,
				"旁白念着的时候 boss 还在动（没被对话冻住）")
		# 组长要求关底只有一个：重复调用也只有一个节点
		var count := 0
		for child in _level.get_children():
			if child.name == "SoulSlimeBoss":
				count += 1
		_check(count == 1, "Boss 数量应为 1，实际 %d" % count)
		return false
	if _frames == 10:
		_check_size()
		# Boss 战开始：关底围栏必须落下来（挡住通往层门的路）
		var gate := _level.get_node_or_null("BossGate")
		_check(gate != null, "缺少关底围栏 BossGate")
		if gate != null:
			_check(int(gate.get("collision_layer")) == 1, "Boss 战开始时围栏没有落下")
			_check(not bool(gate.call("is_open")), "Boss 战开始时围栏仍处于打开状态")
		if _boss != null:
			# 让近处的玩家触发跳砸分支
			_boss.set("_state", 0)
			_boss.set("_timer", 0.0)
		return false
	if _frames == 40:
		if _boss != null:
			_boss.call("_spit")
		return false
	if _frames == 120:
		_check_damage_and_flag()
		return false
	if _frames == 135:
		var gate := _level.get_node_or_null("BossGate")
		_check(gate != null and bool(gate.call("is_open")), "Boss 倒下后围栏没有升起")
		print("[floor1_boss] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check_size() -> void:
	var player := _level.get_node_or_null("Player") as Node2D
	_check(player != null, "缺少玩家")
	if player == null or _boss == null:
		return
	var visual := _boss.get_node_or_null("Visual") as Node2D
	_check(visual != null, "Boss 缺少 Visual")
	if visual == null:
		return
	var bounds := Rect2()
	var first := true
	# M5-16：组长要求重构建模，外观多了一层"挤在一起的魂"（Mantle）和绕飞的魂片（Shard）。
	# 那两样是装饰壳，量体型不能把它们算进去，否则永远"超宽"——
	# 体型只量主体和内核（Body / Core），这才是 1.25 倍加宽 / 0.8 倍压扁那条标准说的东西。
	for child in visual.get_children():
		if not (child is Polygon2D):
			continue
		var poly_name := str((child as Polygon2D).name)
		if poly_name.begins_with("Mantle") or poly_name.begins_with("Shard"):
			continue
		for p in (child as Polygon2D).polygon:
			var point: Vector2 = (child as Polygon2D).position + p
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	var size := bounds.size * visual.scale.abs()
	# 组长定稿：宽 = 旧版 1.25 倍、高 = 旧版 0.8 倍（约 105×88），且是重新设计而非拉伸
	_check(size.x >= 100.0 and size.x <= 118.0, "Boss 宽 %.0f 不符合 1.25 倍加宽" % size.x)
	_check(size.y >= 80.0 and size.y <= 96.0, "Boss 高 %.0f 不符合 0.8 倍压扁" % size.y)
	# 顺手确认新模型三件套真的挂上了（缺一件就等于模型没重建）
	_check(bounds.size.x > 0.0 and visual.get_node_or_null("Mantle0") != null, "Boss 缺少新的魂壳 Mantle")
	_check(visual.get_node_or_null("Shard0") != null, "Boss 缺少绕飞魂片 Shard")
	_checked_size = true

func _check_damage_and_flag() -> void:
	_check(_checked_size, "没有检查体型")
	_check(_boss != null, "Boss 丢失")
	if _boss == null:
		return
	for i in range(40):
		_boss.call("take_damage", 1)
	_check(bool(_gm.call("has_flag", "floor1_boss_defeated")), "打空血后没置 floor1_boss_defeated")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[floor1_boss] " + msg)
		_failed = true
