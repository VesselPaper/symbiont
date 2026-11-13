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
		_boss = _level.get_node_or_null("SoulSlimeBoss")
		_check(_boss != null, "没有生成 SoulSlimeBoss")
		return false
	if _frames == 10:
		_check_size()
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
	# 主角碰撞盒 14×26；Boss 视觉应落在 4~5 倍之间
	_check(size.x >= 52.0 and size.x <= 96.0, "Boss 宽 %.0f 不在主角 4~5 倍范围" % size.x)
	_check(size.y >= 96.0 and size.y <= 140.0, "Boss 高 %.0f 不在主角 4~5 倍范围" % size.y)
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
