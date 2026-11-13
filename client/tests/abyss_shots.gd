extends SceneTree
## 深渊终章截图（开发用）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/abyss_shots.gd

const SCENE := "res://scenes/world/abyss.tscn"

var _warmup := 0
var _frames := 0
var _level: Node

func _process(_delta: float) -> bool:
	if _level == null:
		_warmup += 1
		if _warmup < 10:
			return false
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_frames += 1
	if _frames == 55:
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://shots/abyss_heart.png")
		img.save_png(path)
		print("[abyss_shots] %s" % path)
		quit(0)
		return true
	return false
