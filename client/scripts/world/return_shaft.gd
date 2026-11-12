extends Area2D
## 第三层入口的旧货梯（M3-03）
##
## Boss 死后才亮，K 坐它回教学关起点，走真 HE 的回头路。
## 之前是坏的：没打赢守门者，按 K 不会有反应。

const INTERACT_ACTION := "interact"
const DialogueLocator := preload("res://components/dialogue_locator.gd")
const InteractionPrompt := preload("res://components/interaction_prompt.gd")

var controller: Node

var _dialogue: Node
var _in_range := false
var _prompt: Label
var _glow: Sprite2D
var _cage: Node2D
var _time := 0.0
var _activated := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_dialogue = DialogueLocator.resolve(self, controller)
	_build_visual()
	_build_prompt()
	_prompt.visible = false

func _build_visual() -> void:
	var cage := Node2D.new()
	cage.name = "Cage"
	cage.position = Vector2(0, 0)
	add_child(cage)
	_cage = cage
	# 两根生锈导轨，顶部接一条断链：这是“还能动”的唯一理由
	for dx in [-30.0, 30.0]:
		var post := Polygon2D.new()
		post.color = Color(0.095, 0.100, 0.105, 1)
		post.polygon = PackedVector2Array([
			Vector2(dx - 4, -126), Vector2(dx + 4, -126), Vector2(dx + 5, 34), Vector2(dx - 5, 34),
		])
		cage.add_child(post)
		var rim := Line2D.new()
		rim.width = 1.2
		rim.default_color = Color(0.36, 0.44, 0.42, 0.45)
		rim.points = PackedVector2Array([Vector2(dx - 3, -120), Vector2(dx - 4, 28)])
		cage.add_child(rim)
	var beam := Polygon2D.new()
	beam.color = Color(0.075, 0.080, 0.085, 1)
	beam.polygon = PackedVector2Array([
		Vector2(-44, -140), Vector2(44, -140), Vector2(40, -126), Vector2(-40, -126),
	])
	cage.add_child(beam)
	var chain := Line2D.new()
	chain.width = 3.0
	chain.default_color = Color(0.06, 0.06, 0.065, 1)
	chain.points = PackedVector2Array([
		Vector2(0, -132), Vector2(5, -80), Vector2(-2, -28), Vector2(0, 6),
	])
	cage.add_child(chain)
	# 笼底踏板：站上去就想到“货梯”
	var plate := Polygon2D.new()
	plate.color = Color(0.14, 0.15, 0.15, 1)
	plate.polygon = PackedVector2Array([
		Vector2(-38, 30), Vector2(38, 30), Vector2(33, 38), Vector2(-33, 38),
	])
	cage.add_child(plate)
	var rail := Line2D.new()
	rail.width = 2.0
	rail.default_color = Color(0.52, 0.58, 0.52, 0.35)
	rail.points = PackedVector2Array([Vector2(-30, 8), Vector2(30, 8)])
	cage.add_child(rail)
	# 井口冷光：没打 Boss 前是暗的，激活后变亮
	_glow = Sprite2D.new()
	_glow.name = "Glow"
	_glow.texture = _radial_texture()
	_glow.position = Vector2(0, -36)
	_glow.scale = Vector2(0.9, 1.3)
	_glow.modulate = Color(0.38, 0.66, 0.68, 0.06)
	cage.add_child(_glow)

func _radial_texture() -> GradientTexture2D:
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
	return tex

func _build_prompt() -> void:
	_prompt = InteractionPrompt.create(
		self, "K 回起点", Vector2(-90, -176), Vector2(180, 24),
		14, Color(0.86, 0.90, 0.78, 0.96), 2, 5
	)

func _process(delta: float) -> void:
	_time += delta
	_activated = _boss_is_dead()
	if _activated:
		_glow.modulate.a = 0.14 + sin(_time * 2.0) * 0.04
		_cage.visible = true
	else:
		_glow.modulate.a = 0.035
	if _prompt == null:
		return
	_prompt.visible = _in_range and _activated and not _dialogue_playing()
	_prompt.text = "K 回起点"

func _boss_is_dead() -> bool:
	var gm := get_node_or_null("/root/GameManager")
	return gm != null and bool(gm.call("has_flag", "boss_defeated"))

func _dialogue_playing() -> bool:
	return DialogueLocator.is_playing(_dialogue)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = false
		if _prompt != null:
			_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _in_range or not _activated:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if _dialogue_playing():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and bool(player.get("_input_locked")):
		return
	if controller != null and controller.has_method("return_to_start"):
		controller.call("return_to_start")
