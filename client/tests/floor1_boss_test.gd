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
		return false
	if _frames == 6:
		_level.call("_spawn_boss")
		_level.call("_spawn_boss")
		_boss = _level.get_node_or_null("SoulSlimeBoss")
		_check(_boss != null, "没有生成 SoulSlimeBoss")
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
	for child in visual.get_children():
		if child is Polygon2D:
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
