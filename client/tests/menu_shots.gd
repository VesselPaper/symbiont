extends SceneTree
## 主菜单截图（开发用）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/menu_shots.gd

const MAIN := "res://scenes/main/main.tscn"

var _warmup := 0
var _frames := 0
var _menu: Node

func _process(_delta: float) -> bool:
	if _menu == null:
		_warmup += 1
		if _warmup < 10:
			return false
		_menu = load(MAIN).instantiate()
		root.add_child(_menu)
		return false
	_frames += 1
	if _frames >= 20:
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://shots/main_menu.png")
		img.save_png(path)
		print("[menu_shots] %s" % path)
		quit(0)
		return true
	return false
