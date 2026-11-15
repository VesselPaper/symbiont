extends SceneTree
## 开场演出逐秒采样（M4-53）：每秒存一张 PNG 到 shots/intro/，用来判断
##  ① 相邻两秒之间"变化大不大"（静止/拖沓会一堆帧几乎一样）
##  ② 细节动作有没有发生（起身阶段的身高/轮廓变化）
##
## 跑法（要窗口，不用 --headless）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/intro_shots.gd

const ARENA := "res://scenes/world/test_arena.tscn"
const OUT_DIR := "user://intro_shots"
const SECONDS := 30

var _arena: Node2D
var _shot := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var gm := root.get_node_or_null("/root/GameManager")
	if gm != null:
		gm.call("set_flag", "enter_from_void")
	_arena = load(ARENA).instantiate() as Node2D
	root.add_child(_arena)
	for i in range(SECONDS):
		await create_timer(1.0).timeout
		_capture(i)
	print("[shots] 存了 %d 张到 %s" % [_shot, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)

func _capture(second: int) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := "%s/t%02d.png" % [OUT_DIR, second]
	img.save_png(path)
	_shot += 1
	var player: Node2D = _arena.get_node("Player")
	print("[shots] t=%02ds player=(%.0f,%.0f) rot=%.2f" % [second, player.global_position.x, player.global_position.y, player.rotation])
