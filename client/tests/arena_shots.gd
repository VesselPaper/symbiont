extends SceneTree
## 教学关美术巡图（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/arena_shots.gd
## 站位跟着 test_arena.gd 的 STAGE 表走（M4-19 拉宽后每个教学环一个停点）。

const SCENE := "res://scenes/world/test_arena.tscn"
const OUT_DIR := "res://shots"
const SLIME := preload("res://scenes/entities/slime.tscn")

var _elapsed := 0.0
var _started := false
var _warmup := 0
var _index := 0
var _arena: Node
var _player: Node2D
var _dbox: CanvasLayer
var _last_t := 0.0

const STOPS := [
	{"move": 0.20, "shot": 0.75, "pos": Vector2(300.0, 647.0), "name": "arena_entry"},
	{"move": 1.15, "shot": 1.70, "pos": Vector2(1360.0, 555.0), "name": "arena_combat"},
	{"move": 1.90, "shot": 2.45, "pos": Vector2(2560.0, 646.0), "name": "arena_hollow"},
	{"move": 2.85, "shot": 3.40, "pos": Vector2(3050.0, 558.0), "name": "arena_altar"},
	{"move": 3.65, "shot": 4.05, "pos": Vector2(3600.0, 646.0), "name": "arena_chest"},
	{"move": 4.35, "shot": 4.90, "pos": Vector2(3820.0, 646.0), "name": "arena_causeway"},
	{"move": 5.35, "shot": 5.95, "pos": Vector2(4320.0, 646.0), "name": "arena_gallery"},
	{"move": 6.40, "shot": 7.00, "pos": Vector2(4830.0, 646.0), "name": "arena_door"},
]

var _moved: Array[bool] = [false, false, false, false, false, false, false, false]

func _process(delta: float) -> bool:
	if not _started:
		# --script 模式下 EventBus 等 autoload 要等几帧才进入脚本编译域；
		# 过早 load 场景会让 slime/limb 的脚本报 "Identifier not found: EventBus"
		_warmup += 1
		if _warmup < 10:
			return false
		_started = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		_arena = load(SCENE).instantiate()
		root.add_child(_arena)
		_player = _arena.get_node("Player") as Node2D
		_dbox = _arena.get_node("DialogueBox") as CanvasLayer
		var slime := SLIME.instantiate()
		slime.position = Vector2(1550, 646)
		_arena.add_child(slime)
		return false
	_elapsed += delta
	if _index >= STOPS.size():
		quit(0)
		return true
	var stop: Dictionary = STOPS[_index]
	if not _moved[_index] and _elapsed >= stop["move"]:
		_player.global_position = stop["pos"]
		_moved[_index] = true
		return false
	if _elapsed >= stop["shot"]:
		if _dbox != null:
			_dbox.visible = false
		_save(str(stop["name"]) + ".png")
		var cam: Camera2D = _arena.get_node("Camera2D")
		print("[arena] cam=%s zoom=%s" % [cam.global_position, cam.zoom])
		_index += 1
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[arena] t=%.2fs %s player=%s" % [_elapsed, path, _player.global_position])
