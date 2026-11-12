extends SceneTree
## 暂停菜单截图（开发用）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/pause_shots.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _warmup := 0
var _frames := 0
var _level: Node
var _pause: Node

func _process(_delta: float) -> bool:
	if _level == null:
		_warmup += 1
		if _warmup < 10:
			return false
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	if _pause == null:
		_pause = _level.get_node_or_null("GameHUD/PauseMenu")
		if _pause == null:
			quit(1)
			return true
		_pause.call("open")
		return false
	_frames += 1
	if _frames >= 8:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://shots/pause.png"))
		print("[pause_shots] saved")
		_pause.call("close")
		quit(0)
		return true
	return false
