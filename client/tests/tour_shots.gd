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
## move 时瞬移，shot 时抓图，中间留时间让相机吸附/落稳。
const STOPS := [
	{"move": 0.05, "shot": 0.40, "pos": Vector2(80.0, 646.0), "shot_name": "floor1_a"},
	{"move": 0.55, "shot": 1.25, "pos": Vector2(80.0, 646.0), "shot_name": "floor1_b", "show_dialogue": true},
	{"move": 1.60, "shot": 2.10, "pos": Vector2(900.0, 557.0), "shot_name": "floor1_shelf"},
	{"move": 2.55, "shot": 3.05, "pos": Vector2(1600.0, 746.0), "shot_name": "floor1_bell"},
	{"move": 3.50, "shot": 4.00, "pos": Vector2(2260.0, 646.0), "shot_name": "floor1_steps"},
	{"move": 4.45, "shot": 4.95, "pos": Vector2(2600.0, 586.0), "shot_name": "floor1_altar"},
	{"move": 5.40, "shot": 5.90, "pos": Vector2(2950.0, 586.0), "shot_name": "floor1_bridge"},
	{"move": 6.35, "shot": 6.85, "pos": Vector2(3560.0, 626.0), "shot_name": "floor1_relic"},
	{"move": 7.30, "shot": 7.80, "pos": Vector2(3900.0, 606.0), "shot_name": "floor1_foyer"},
	{"move": 8.25, "shot": 8.75, "pos": Vector2(4390.0, 586.0), "shot_name": "floor1_gate"},
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
		# 等 autoload 进入 --script 编译域，避免场景里的 EventBus 引用编译失败
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
		# UI 显隐要提前一帧以上设置，直接 set + 立刻抓图会抓到上一帧
		if _dbox != null:
			_dbox.visible = bool(stop.get("show_dialogue", false))
	if _elapsed >= stop["shot"]:
		_save(str(stop["shot_name"]) + ".png")
		_index += 1
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[tour] t=%.2fs %s player=%s" % [_elapsed, path, _player.global_position])
