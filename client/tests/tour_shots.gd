extends SceneTree
## 关卡巡视图（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/tour_shots.gd
## 把玩家依次瞬移到几个关键位置，每个位置抓一张图，存到 client/shots/。
## 目的：不开游戏也能检查钟厅、台阶、祭坛、层门的构图和光照。
## 注意：必须带渲染跑（不加 --headless），并临时隐藏对话 UI，免得挡住画面。

const SCENE := "res://scenes/world/floor1.tscn"
const OUT_DIR := "res://shots"
const SETTLE := 0.55  # 瞬移后等相机跟上、物理落稳的时间

## 瞬移目标和抓图时间（秒）。y 取地面顶面减去半个角色高（14），避免穿地。
const STOPS := [
	{"t": 0.30, "pos": Vector2(900.0, 666.0), "shot": "floor1_shelf"},
	{"t": 1.15, "pos": Vector2(1600.0, 746.0), "shot": "floor1_bell"},
	{"t": 2.00, "pos": Vector2(2260.0, 646.0), "shot": "floor1_steps"},
	{"t": 2.85, "pos": Vector2(2600.0, 586.0), "shot": "floor1_altar"},
	{"t": 3.70, "pos": Vector2(2820.0, 586.0), "shot": "floor1_gate"},
]

var _elapsed := 0.0
var _started := false
var _index := 0
var _level: Node
var _player: Node2D
var _dbox: CanvasLayer

func _process(delta: float) -> bool:
	if not _started:
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
	if _elapsed >= stop["t"]:
		_player.global_position = stop["pos"]
		if _dbox != null:
			_dbox.visible = false
		_save(str(stop["shot"]) + ".png")
		_index += 1
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[tour] t=%.2fs %s player=%s" % [_elapsed, path, _player.global_position])
