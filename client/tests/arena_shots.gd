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

## 站位对着 test_arena.gd 的 STAGE 表现抄（M5-48 改成 3 秒一档之后）：出生 140、移动 890、
## 铁剑 2390、木桩甲 3140、下劈台 3900（顶 440）、战场 4750、火堆 6250、
## 悬崖 7000..8400、祭坛 9000、层门 9650。表一改这里就要跟着改，不然拍出来是过期画面。
const STOPS := [
	{"move": 0.20, "shot": 0.70, "pos": Vector2(300.0, 646.0), "name": "arena_entry"},
	{"move": 0.90, "shot": 1.40, "pos": Vector2(890.0, 646.0), "name": "arena_move"},
	{"move": 1.60, "shot": 2.10, "pos": Vector2(2390.0, 558.0), "name": "arena_weapon"},
	{"move": 2.30, "shot": 2.80, "pos": Vector2(3140.0, 558.0), "name": "arena_dummy"},
	{"move": 3.00, "shot": 3.50, "pos": Vector2(4000.0, 427.0), "name": "arena_pogo"},
	{"move": 3.70, "shot": 4.20, "pos": Vector2(4750.0, 646.0), "name": "arena_combat"},
	{"move": 4.40, "shot": 4.90, "pos": Vector2(6250.0, 646.0), "name": "arena_campfire"},
	{"move": 5.10, "shot": 5.60, "pos": Vector2(7782.0, 552.0), "name": "arena_chasm"},
	{"move": 5.80, "shot": 6.30, "pos": Vector2(9000.0, 646.0), "name": "arena_altar"},
	{"move": 6.50, "shot": 7.00, "pos": Vector2(9600.0, 646.0), "name": "arena_door"},
]

var _moved: Array[bool] = [false, false, false, false, false, false, false, false, false, false]

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
