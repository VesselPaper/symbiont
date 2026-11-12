extends Node2D
## 美术展示台（开发用，按场景跑，不是 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --path client res://tests/art_stage.tscn
## 摆一排模型，相机左右移两次，分别拍怪物组和祭坛/光点/剑。

const OUT_DIR := "res://shots"

@onready var _player: Node2D = $Player
@onready var _marker: Node2D = $QuestMarker
@onready var _slime: Node2D = $Slime
@onready var _dummy: Node2D = $Dummy
@onready var _altar: Node2D = $Altar
@onready var _cam: Camera2D = $Camera2D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_player.set("has_weapon", true)
	_player.set("_facing", 1)
	_marker.call("activate")
	# 展示台补一盏柔光：模型本身颜色偏暗，没有环境光拍出来像剪影
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	for px in [340.0, 800.0]:
		var light := PointLight2D.new()
		light.texture = tex
		light.color = Color(0.90, 0.95, 1.0)
		light.energy = 0.85
		light.texture_scale = 3.4
		light.position = Vector2(px, 600)
		add_child(light)
	await get_tree().create_timer(0.9).timeout
	_cam.position = Vector2(340, 600)
	await get_tree().create_timer(0.25).timeout
	_shot("stage_monsters")
	_cam.position = Vector2(770, 600)
	await get_tree().create_timer(0.30).timeout
	_shot("stage_items")
	# 献祭演出：给一个肢体，拍肢体飞进石碗和触须收拢的瞬间
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and _altar != null:
		gm.set("monster_limb_count", 1)
		_altar.call("try_sacrifice")
		await get_tree().create_timer(0.34).timeout
		_shot("stage_sacrifice")
		# 寄生组织：把镜头拉回玩家，拍献祭后肩后长出的东西
		_cam.position = Vector2(220, 600)
		_player.call("_show_corruption", 1)
		await get_tree().create_timer(0.30).timeout
		_shot("stage_corruption")
		_cam.position = Vector2(770, 600)
	# 顺手验证怪物死亡表现：压扁淡出后掉肢体、节点销毁，不报错
	_dummy.call("activate")
	_dummy.call("take_damage", 1)
	_slime.call("take_damage", 99)
	await get_tree().create_timer(0.55).timeout
	_shot("stage_corpse")
	var limbs := 0
	for child in get_tree().current_scene.get_children():
		if child.scene_file_path.ends_with("limb_pickup.tscn"):
			limbs += 1
	print("[stage] slime freed=%s limbs=%d dummy_hp=%d" % [
		not is_instance_valid(_slime), limbs, _dummy.get("hp")
	])
	get_tree().quit(0)

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	img.save_png(path)
	print("[stage] %s" % path)
