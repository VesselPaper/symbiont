extends SceneTree
## 真 HE 巡视图（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/true_he_shots.gd
## 抓二周目起点骨片、祭坛归还后的结局画面。

const ARENA := "res://scenes/world/test_arena.tscn"
const OUT_DIR := "res://shots"

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
		gm.set("flags", {})
		gm.set("sacrifice_count", 2)
		gm.set("monster_limb_count", 0)
		gm.set("state", 2)
		gm.call("set_flag", "boss_defeated")
		gm.call("set_flag", "true_he_return")
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player") as Node2D
		_dbox = _level.get_node("DialogueBox") as CanvasLayer
		return false
	_elapsed += delta
	if _index == 0:
		_player.global_position = Vector2(255, 606)
		if _dbox != null:
			_dbox.visible = false
		if _elapsed >= 0.8:
			_save("true_he_start.png")
			_index = 1
	elif _index == 1:
		var relic := _level.get_node_or_null("TrueHEProps/OriginRelic")
		if relic != null:
			relic.call("_on_body_entered", _player)
		var altar := _level.get_node("Altar")
		altar.call("try_restore")
		if _elapsed >= 2.9:
			_save("true_he_ending.png")
			_index = 2
	else:
		quit(0)
		return true
	return false

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[true_he_shots] %s" % path)
