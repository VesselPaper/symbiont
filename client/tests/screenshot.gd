extends SceneTree
## 截图脚本（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/screenshot.gd
## 载入第一层，等画面稳定后抓两张图，存到 client/shots/，然后退出。
## 注意：必须带渲染跑（不加 --headless），否则视口没有画面。
##
## 按「真实秒数」计时，不按帧数：--script 模式下主循环不锁帧，95 帧可能只有 0.05 秒，
## 0.6 秒的入场对话永远等不到（第一次截图两张一模一样就是这个坑）。

const SCENE := "res://scenes/world/floor1.tscn"
const OUT_DIR := "res://shots"
## 抓图时间点（秒）：A 抓开场空镜，B 抓入场对话打出字之后
const SHOT_A_AT := 0.45
const SHOT_B_AT := 1.60

var _elapsed := 0.0
var _started := false
var _shot_a := false
var _shot_b := false
var _level: Node

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if not _shot_a and _elapsed >= SHOT_A_AT:
		_shot_a = true
		_save("floor1_a.png")
	elif not _shot_b and _elapsed >= SHOT_B_AT:
		_shot_b = true
		_save("floor1_b.png")
		_report()
		quit(0)
		return true
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[shot] t=%.2fs %s" % [_elapsed, path])

## 截完把对话状态打出来：看得见/看不见时都能从日志判断，不用猜
func _report() -> void:
	if _level == null:
		return
	var dlg := _level.get_node_or_null("Dialogue")
	var dbox := _level.get_node_or_null("DialogueBox")
	var panel := dbox.get_node_or_null("Panel") if dbox != null else null
	print("[shot] dialogue playing=%s panel_visible=%s text_len=%d" % [
		dlg.call("is_playing") if dlg != null else "n/a",
		panel.visible if panel != null else "n/a",
		dbox.get_node("Panel/Margin/VBox/TextLabel").text.length() if dbox != null else 0,
	])
	var cam := _level.get_node_or_null("Camera2D")
	var player := _level.get_node_or_null("Player")
	var backdrop := _level.get_node_or_null("Backdrop")
	if cam != null and player != null:
		print("[shot] cam=%s zoom=%s player=%s" % [
			cam.global_position, cam.zoom, player.global_position,
		])
	if backdrop != null:
		var landmark := backdrop.get_node_or_null("Landmark")
		var far := backdrop.get_node_or_null("Far")
		var mid := backdrop.get_node_or_null("Mid")
		print("[shot] landmark=%s far=%s mid=%s vines=%s" % [
			landmark.global_position if landmark != null else "n/a",
			far.global_position if far != null else "n/a",
			mid.global_position if mid != null else "n/a",
			backdrop.get_node("Vines").global_position if backdrop.get_node_or_null("Vines") != null else "n/a",
		])
