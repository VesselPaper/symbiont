extends SceneTree
## 教学关尾门截图（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/door_shot.gd
## 把教程状态直接推到完成，站到门前抓一张，检查门有没有立在地图右侧、亮没亮。

const SCENE := "res://scenes/world/test_arena.tscn"
const OUT_DIR := "res://shots"

var _elapsed := 0.0
var _started := false
var _opened := false
var _shot := false
var _arena: Node
var _player: Node2D

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		_arena = load(SCENE).instantiate()
		root.add_child(_arena)
		_player = _arena.get_node("Player") as Node2D
		return false
	_elapsed += delta
	if not _opened and _elapsed >= 0.20:
		_opened = true
		var tutorial := _arena.get_node("Tutorial")
		tutorial.set("_step", 8)  # 等价于献祭完成（DONE）
		_player.global_position = Vector2(2380, 645)
	if not _shot and _elapsed >= 1.00:
		_shot = true
		var dbox := _arena.get_node("DialogueBox") as CanvasLayer
		if dbox != null:
			dbox.visible = false
		_save("test_arena_door.png")
		quit(0)
		return true
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[door] %s" % path)
