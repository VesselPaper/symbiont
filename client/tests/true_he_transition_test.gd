extends SceneTree
## 第三层→起点货梯回归（M3-03）
## 反向：Boss 没死时不能回；正向：死后回教学关并生成骨片。

const FLOOR3 := "res://scenes/world/floor3.tscn"

var _gm: Node
var _floor: Node
var _elapsed := 0.0
var _phase := 0
var _failed := false

func _process(delta: float) -> bool:
	if _floor == null:
		_gm = root.get_node("/root/GameManager")
		_gm.set("flags", {})
		_gm.set("current_floor", "floor_3")
		_gm.set("sacrifice_count", 2)
		_gm.set("state", 2)
		_floor = load(FLOOR3).instantiate()
		root.add_child(_floor)
		return false
	_elapsed += delta
	if _phase == 0 and _elapsed >= 0.3:
		# 反向：没打守门者，货梯不该动
		_floor.call("return_to_start")
		_phase = 1
	elif _phase == 1 and _elapsed >= 0.8:
		_check(root.get_node_or_null("Floor3") != null, "Boss 没死就切走了")
		_check(not bool(_gm.call("has_flag", "true_he_return")), "Boss 没死就写了回头旗标")
		_gm.call("set_flag", "boss_defeated")
		_floor.call("return_to_start")
		_phase = 2
	elif _phase == 2 and _elapsed >= 2.2:
		_check_transition()
		print("[true_he_transition] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[true_he_transition] " + msg)
		_failed = true

func _check_transition() -> void:
	_check(root.get_node_or_null("TestArena") != null, "货梯没回到教学关")
	_check(bool(_gm.call("has_flag", "true_he_return")), "回起点没写 true_he_return")
	_check(str(_gm.get("current_floor")) == "start", "current_floor 没写成 start")
	_check(bool(_gm.call("has_flag", "boss_defeated")), "回起点把 Boss 旗标清了")
	var arena := root.get_node_or_null("TestArena")
	if arena == null:
		return
	_check(arena.get_node_or_null("TrueHEProps/OriginRelic") != null, "回起点没生成骨片")
	var tutorial := arena.get_node("Tutorial")
	_check(tutorial.process_mode == Node.PROCESS_MODE_DISABLED, "回起点没停用旧教学")
