extends SceneTree
## 拒绝结局截图（开发用）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/refuse_shots.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _warmup := 0
var _frames := 0
var _level: Node
var _started := false
var _finished_dialogue := false

func _process(_delta: float) -> bool:
	if _level == null:
		_warmup += 1
		if _warmup < 10:
			return false
		var gm := root.get_node("/root/GameManager")
		gm.set("flags", {})
		gm.set("sacrifice_count", 0)
		gm.set("monster_limb_count", 1)
		gm.set("state", 2)
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_frames += 1
	if not _started and _frames >= 40:
		_level.get_node("Dialogue").call("_finish")
		var altar := _level.get_node("Altar")
		altar.set("_player_in_range", true)
		var r := InputEventKey.new()
		r.keycode = KEY_R
		r.pressed = true
		altar.call("_unhandled_input", r)
		_started = true
		return false
	if _started and not _finished_dialogue and _frames >= 48:
		_level.get_node("Dialogue").call("_finish")
		_finished_dialogue = true
	if _finished_dialogue and _frames >= 600:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://shots/refuse_die.png"))
		print("[refuse_shots] saved")
		quit(0)
		return true
	return false
