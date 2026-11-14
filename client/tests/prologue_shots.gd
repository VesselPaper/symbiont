extends SceneTree
## 序章截图（开发用）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/prologue_shots.gd
## 抓三张：刚苏醒（黑场退完、第一句耳语还没散）、走近身影、融合之后。

const SCENE := "res://scenes/world/prologue.tscn"

var _warmup := 0
var _frames := 0
var _level: Node
var _shots := 0

func _process(_delta: float) -> bool:
	if _level == null:
		_warmup += 1
		if _warmup < 10:
			return false
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_frames += 1
	# 30fps 下 1 帧≈33ms：黑场 2.4s 退完，所以第一张等到第 90 帧
	if _frames == 90:
		_save("prologue_soul")
	elif _frames == 100:
		# 把灵魂挪到身影附近，看“走近才发现”的画面
		var soul := _level.get_node_or_null("Soul") as Node2D
		if soul != null:
			soul.position = Vector2(900, 560)
	elif _frames == 130:
		_save("prologue_near")
	elif _frames == 150:
		_level.call("_fuse")
	elif _frames == 330:
		_save("prologue_fused")
	elif _frames >= 340:
		quit(0)
		return true
	return false

func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://shots/%s.png" % name)
	img.save_png(path)
	_shots += 1
	print("[prologue_shots] %s" % path)
