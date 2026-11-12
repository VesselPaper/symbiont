extends SceneTree
## 第二层巡视图（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/floor2_shots.gd
## 抓入口、铸炉、圣坛、封印门、第三层门五张，检查暖色铸炉和紫色圣坛的构图。

const SCENE := "res://scenes/world/floor2.tscn"
const OUT_DIR := "res://shots"
const STOPS := [
	{"move": 0.05, "shot": 0.95, "pos": Vector2(180.0, 606.0), "shot_name": "floor2_entry"},
	{"move": 1.35, "shot": 2.05, "pos": Vector2(1180.0, 626.0), "shot_name": "floor2_forge"},
	{"move": 2.55, "shot": 3.25, "pos": Vector2(2200.0, 586.0), "shot_name": "floor2_chapel"},
	{"move": 3.75, "shot": 4.45, "pos": Vector2(3560.0, 586.0), "shot_name": "floor2_seal"},
	{"move": 4.75, "shot": 5.35, "pos": Vector2(4620.0, 586.0), "shot_name": "floor2_corridor"},
	{"move": 5.65, "shot": 6.35, "pos": Vector2(5040.0, 546.0), "shot_name": "floor2_gate"},
]

var _elapsed := 0.0
var _started := false
var _warmup := 0
var _index := 0
var _level: Node
var _player: Node2D
var _dbox: CanvasLayer

func _process(delta: float) -> bool:
	if not _started:
		_warmup += 1
		if _warmup < 10:
			return false
		_started = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as Node2D
		_dbox = _level.get_node("DialogueBox") as CanvasLayer
		return false
	_elapsed += delta
	if _index >= STOPS.size():
		quit(0)
		return true
	var stop: Dictionary = STOPS[_index]
	if _elapsed >= stop["move"]:
		_player.global_position = stop["pos"]
		if _dbox != null:
			_dbox.visible = false
	if _elapsed >= stop["shot"]:
		_save(str(stop["shot_name"]) + ".png")
		_index += 1
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[floor2_shots] %s" % path)
