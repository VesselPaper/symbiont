extends SceneTree
## 真 HE 反向回归（M3-03）：普通周目不能被骨片逻辑劫持。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/true_he_reverse_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _level: Node
var _gm: Node
var _elapsed := 0.0
var _failed := false

func _process(delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_gm.set("flags", {})
		_gm.set("sacrifice_count", 0)
		_gm.set("monster_limb_count", 1)
		_gm.set("faction", "")
		_gm.set("state", 2)
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if _elapsed < 0.6:
		return false
	var tutorial := _level.get_node("Tutorial")
	_check(tutorial.process_mode != Node.PROCESS_MODE_DISABLED, "普通周目误停用了教学")
	var hud := _level.get_node("ObjectiveHUD") as Node2D
	_check(hud != null, "普通周目缺少教学目标文字节点")
	_check(_level.get_node_or_null("TrueHEProps/OriginRelic") == null, "普通周目错误生成骨片")
	var altar := _level.get_node("Altar")
	_check(not bool(altar.call("try_restore")), "没有骨片也能归还")
	var ok := bool(altar.call("try_sacrifice"))
	_check(ok, "普通周目有肢体时应能正常献祭")
	_check(int(_gm.get("sacrifice_count")) == 1, "普通献祭计数没 +1")
	_check(not bool(_gm.call("has_flag", "true_he_unlocked")), "普通献祭误开真 HE")
	_check(_level.get_node_or_null("EndingScreen") == null, "普通献祭误弹真 HE 结局")
	print("[true_he_reverse] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[true_he_reverse] " + msg)
		_failed = true
