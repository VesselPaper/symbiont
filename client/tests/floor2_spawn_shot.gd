extends SceneTree
## 临时排查图：第二层复活点画面（手动跑，不加 --headless）
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/floor2_spawn_shot.gd

const SCENE := "res://scenes/world/floor2.tscn"
const OUT := "res://shots/_debug_floor2_spawn.png"

var _warmup := 0
var _elapsed := 0.0
var _level: Node

func _process(delta: float) -> bool:
	if _level == null:
		_warmup += 1
		if _warmup < 10:
			return false
		var gm := root.get_node_or_null("/root/GameManager")
		if gm != null:
			gm.set("has_weapon", true)
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if _elapsed < 1.2:
		return false
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("[floor2_spawn_shot] saved %s player=%s" % [
		ProjectSettings.globalize_path(OUT),
		(_level.get_node("Player") as Node2D).global_position,
	])
	quit(0)
	return true
