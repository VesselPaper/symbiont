extends SceneTree
## 背景目标文字截图（开发用，手动跑，不加 --headless）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/world_hint_shots.gd

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
		# 直接摆到祭坛上方的 SACRIFICE 目标点：验证文字压在祭坛模型前面
		# 锚点从 Tutorial 生效的那份表读（M4-19 起由 STAGE 表推进来；M4-21 光点已删）
		# M4-22 起目标是“刻在地图上的句子”，所以调 show_objective 而不是临时气泡
		var target: Vector2 = tutorial.get("_anchors")[7]
		hud.call("show_objective", 6, "捡起肢体，献给我", tutorial.get("_anchors")[6])
		hud.call("set_active_step", 7)
		hud.call("show_objective", 7, "带到祭坛，按 K 献祭", target)
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
