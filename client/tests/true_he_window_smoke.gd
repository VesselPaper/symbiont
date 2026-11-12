extends SceneTree
## 真 HE 二周目窗口冒烟（开发用）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/true_he_window_smoke.gd
## 打开真实窗口跑 300 帧，确认二周目场景无 SCRIPT ERROR。

const ARENA := "res://scenes/world/test_arena.tscn"
var _level: Node
var _frames := 0

func _process(_delta: float) -> bool:
	if _level == null:
		var gm := root.get_node("/root/GameManager")
		gm.set("flags", {})
		gm.set("sacrifice_count", 2)
		gm.set("monster_limb_count", 0)
		gm.set("state", 2)
		gm.call("set_flag", "boss_defeated")
		gm.call("set_flag", "true_he_return")
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_frames += 1
	if _frames >= 300:
		print("[true_he_window] frames=%d scene=%s" % [_frames, _level.name])
		quit(0)
		return true
	return false
