extends SceneTree
## 第三层巡视图（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/floor3_shots.gd
## 抓入口、骑士像廊、守门者、结局画面四张。

const SCENE := "res://scenes/world/floor3.tscn"
const OUT_DIR := "res://shots"
const STOPS := [
	{"move": 0.05, "shot": 0.95, "pos": Vector2(180.0, 606.0), "shot_name": "floor3_entry"},
	{"move": 1.35, "shot": 2.05, "pos": Vector2(1280.0, 586.0), "shot_name": "floor3_gallery"},
	{"move": 2.25, "shot": 2.95, "pos": Vector2(2480.0, 606.0), "shot_name": "floor3_arms"},
	{"move": 3.15, "shot": 3.85, "pos": Vector2(3300.0, 586.0), "shot_name": "floor3_boss"},
	{"move": 4.30, "shot": 5.45, "pos": Vector2(3300.0, 586.0), "shot_name": "floor3_ending"},
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
		var gm := root.get_node("/root/GameManager")
		gm.set("sacrifice_count", 1)
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
		if str(stop["shot_name"]) == "floor3_boss":
			var boss := _level.get_node_or_null("BossHolder/Gatekeeper")
			if boss != null and boss.has_method("activate"):
				boss.call("activate")
		if str(stop["shot_name"]) == "floor3_ending":
			_level.call("_show_ending")
	if _elapsed >= stop["shot"]:
		_save(str(stop["shot_name"]) + ".png")
		_index += 1
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[floor3_shots] %s" % path)
