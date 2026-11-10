extends SceneTree
## 玩家建模特写（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/player_shot.gd
## 单独实例化玩家、关掉物理，用 6 倍相机拍一张，检查兜帽剪影/轮廓光/单眼。

const PLAYER := "res://scenes/player/player.tscn"
const OUT_DIR := "res://shots"

var _elapsed := 0.0
var _started := false
var _shot := false

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var bg := ColorRect.new()
		bg.color = Color(0.085, 0.105, 0.120, 1.0)
		bg.size = Vector2(1280, 720)
		root.add_child(bg)
		var player := load(PLAYER).instantiate() as Node2D
		root.add_child(player)
		player.position = Vector2(640, 380)
		player.set_physics_process(false)
		var cam := Camera2D.new()
		cam.zoom = Vector2(6.0, 6.0)
		cam.position = Vector2(640, 360)
		root.add_child(cam)
		cam.make_current()
		return false
	_elapsed += delta
	if not _shot and _elapsed >= 0.35:
		_shot = true
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("%s/player_model.png" % OUT_DIR)
		img.save_png(path)
		print("[player] %s" % path)
		quit(0)
		return true
	return false
