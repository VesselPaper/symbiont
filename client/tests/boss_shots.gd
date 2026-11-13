extends SceneTree
## 关底 Boss 截图（开发用）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/boss_shots.gd

const SCENE := "res://scenes/world/floor1.tscn"

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
	if _frames == 8:
		_level.call("_spawn_boss")
		var player := _level.get_node_or_null("Player") as Node2D
		if player != null:
			player.global_position = Vector2(5520, 560)
	if _frames == 40:
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://shots/floor1_boss.png")
		img.save_png(path)
		print("[boss_shots] %s" % path)
		quit(0)
		return true
	return false
