extends SceneTree
## 屏幕目标提示截图（开发用，手动跑，不加 --headless）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/world_hint_shots.gd
## P0 改版后提示不再刻在世界坐标上，这里只验证底部提示条的字号/位置/换句行为。

const SCENE := "res://scenes/world/test_arena.tscn"
const OUT_DIR := "res://shots"

var _arena: Node
var _elapsed := 0.0
var _done := false

func _process(delta: float) -> bool:
	if _arena == null:
		_arena = load(SCENE).instantiate()
		root.add_child(_arena)
		var tutorial := _arena.get_node("Tutorial")
		tutorial.process_mode = Node.PROCESS_MODE_DISABLED
		var dbox := _arena.get_node_or_null("DialogueBox")
		if dbox != null:
			dbox.visible = false
		var hud := _arena.get_node("ObjectiveHUD")
		# 连推两句：验证换环时上一句直接消失、屏幕上只剩当前这句
		hud.call("show_objective", 6, "捡起肢体，献给我", Vector2.ZERO)
		hud.call("set_active_step", 7)
		hud.call("show_objective", 7, "带到祭坛，按 K 献祭", Vector2.ZERO)
		return false
	_elapsed += delta
	if not _done and _elapsed >= 0.8:
		_done = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://shots/world_hint.png")
		print("[world_hint_shots] saved 1280x720")
		quit(0)
		return true
	return false
