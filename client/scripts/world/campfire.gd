extends Area2D
## 篝火（休息点）
##
## 每张地图中段放一座：走累了在火边坐下，血回满。
## 和祭坛不同，篝火不推进剧情、不消耗任何东西，纯补给点 ——
## 玩家不用为了补血专门跑回起点。
##
## 视觉全部用代码画（石圈 + 柴堆 + 跳动火焰 + 火星 + 暖光），和场景里其它物件同一套画法。
## 交互：站进范围按 K 休息；对话/过场锁定输入时不响应。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const INTERACT_ACTION := "interact"
const InteractionPrompt := preload("res://components/interaction_prompt.gd")

const PROMPT_TEXT := "在火边休息（K）"
const RESTED_TEXT := "生命已恢复"
const FEEDBACK_TIME := 1.6

var _prompt: Label
var _glow: PointLight2D
var _flames: Array[Polygon2D] = []
var _embers: CPUParticles2D
var _time := 0.0
var _player_near := false
var _feedback_timer := 0.0
var _flare := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	z_index = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CircleShape2D.new()
	shape.radius = 78.0
	var col := CollisionShape2D.new()
	col.position = Vector2(0, -24)
	col.shape = shape
	add_child(col)
	_build_stones()
	_build_logs()
	_build_fire()
	_build_embers()
	_build_light()
	_build_prompt()
	_prompt.visible = false

## 石圈：一圈深浅不一的小石头，把火围起来
func _build_stones() -> void:
	var ring := Node2D.new()
	ring.name = "Stones"
	add_child(ring)
	for i in range(9):
		var a := TAU * float(i) / 9.0
		var stone := Polygon2D.new()
		stone.color = Color(0.24, 0.25, 0.26).lightened(0.03 * float(i % 3))
		var w := 9.0 + float(i % 3) * 2.0
		var h := 6.0 + float((i + 1) % 3) * 1.5
		var c := Vector2(cos(a) * 34.0, 6.0 + sin(a) * 9.0)
		stone.polygon = PackedVector2Array([
			c + Vector2(-w, -h * 0.4), c + Vector2(-w * 0.4, -h),
			c + Vector2(w * 0.6, -h * 0.7), c + Vector2(w, h * 0.2),
			c + Vector2(w * 0.2, h * 0.7), c + Vector2(-w * 0.7, h * 0.5),
		])
		ring.add_child(stone)
		var rim := Line2D.new()
		rim.width = 1.0
		rim.default_color = Color(0.42, 0.44, 0.45, 0.35)
		rim.points = PackedVector2Array([c + Vector2(-w, -h * 0.4), c + Vector2(-w * 0.4, -h)])
		ring.add_child(rim)

## 柴堆：三根交叉的干柴，端口烧黑
func _build_logs() -> void:
	var logs := Node2D.new()
	logs.name = "Logs"
	add_child(logs)
	for spec in [
		{"a": -0.35, "len": 40.0},
		{"a": 0.42, "len": 36.0},
		{"a": 0.02, "len": 30.0},
	]:
		var log_node := Node2D.new()
		log_node.rotation = float(spec["a"])
		logs.add_child(log_node)
		var length := float(spec["len"])
		var body := Polygon2D.new()
		body.color = Color(0.21, 0.15, 0.10)
		body.polygon = PackedVector2Array([
			Vector2(-length, -3), Vector2(length, -3.5),
			Vector2(length, 3.5), Vector2(-length, 3),
		])
		log_node.add_child(body)
		var charred := Polygon2D.new()
		charred.color = Color(0.06, 0.05, 0.05, 0.9)
		charred.polygon = PackedVector2Array([
			Vector2(-6, -3.2), Vector2(6, -3.2), Vector2(6, 3.2), Vector2(-6, 3.2),
		])
		log_node.add_child(charred)

## 火焰：三层不同颜色的火舌，靠时间各自抖动，叠在一起像在烧
func _build_fire() -> void:
	var fire := Node2D.new()
	fire.name = "Fire"
	add_child(fire)
	var layers := [
		# 最外层暗红火舌：比内焰矮胖，负责把火的轮廓撑开
		{"color": Color(0.45, 0.10, 0.04, 0.70), "w": 17.0, "h": 34.0, "speed": 4.6, "phase": 2.1},
		{"color": Color(0.72, 0.20, 0.06, 0.95), "w": 13.0, "h": 30.0, "speed": 6.0, "phase": 0.0},
		{"color": Color(0.95, 0.46, 0.10, 0.95), "w": 9.0, "h": 22.0, "speed": 8.0, "phase": 1.4},
		{"color": Color(1.0, 0.82, 0.42, 0.95), "w": 5.0, "h": 13.0, "speed": 11.0, "phase": 2.6},
	]
	for spec in layers:
		var flame := Polygon2D.new()
		flame.color = spec["color"]
		flame.set_meta("w", float(spec["w"]))
		flame.set_meta("h", float(spec["h"]))
		flame.set_meta("speed", float(spec["speed"]))
		flame.set_meta("phase", float(spec["phase"]))
		flame.position = Vector2(0, -4)
		fire.add_child(flame)
		_flames.append(flame)
	_update_flames(0.0)

func _flame_polygon(w: float, h: float, sway: float, lean: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-w, 2),
		Vector2(-w * 0.72, -h * 0.32),
		Vector2(-w * 0.34 + sway * 0.4, -h * 0.68),
		Vector2(lean, -h),
		Vector2(w * 0.4 + sway * 0.6, -h * 0.62),
		Vector2(w * 0.78, -h * 0.26),
		Vector2(w, 2),
	])

## 火星：慢慢往上飘、逐颗熄灭
func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.name = "Embers"
	_embers.amount = 14
	_embers.lifetime = 1.9
	_embers.preprocess = 0.8
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 8.0
	_embers.direction = Vector2(0, -1)
	_embers.spread = 26.0
	_embers.gravity = Vector2(6, -26)
	_embers.initial_velocity_min = 16.0
	_embers.initial_velocity_max = 42.0
	_embers.scale_amount_min = 0.5
	_embers.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.72, 0.30, 0.95))
	ramp.set_color(1, Color(0.85, 0.22, 0.05, 0.0))
	_embers.color_ramp = ramp
	_embers.position = Vector2(0, -14)
	add_child(_embers)

## 暖光：随火焰呼吸，让周围地面亮一点
func _build_light() -> void:
	_glow = PointLight2D.new()
	_glow.name = "Glow"
	_glow.texture = _radial_texture()
	_glow.texture_scale = 1.6
	_glow.energy = 1.15
	_glow.color = Color(1.0, 0.62, 0.30)
	_glow.position = Vector2(0, -18)
	add_child(_glow)

func _build_prompt() -> void:
	_prompt = InteractionPrompt.create(
		self, PROMPT_TEXT, Vector2(-84, -104), Vector2(168, 26),
		14, Color(1.0, 0.86, 0.62, 0.96), 2, 5
	)

func _process(delta: float) -> void:
	_time += delta
	_flare = maxf(_flare - delta * 1.6, 0.0)
	_update_flames(delta)
	if _glow != null:
		var breathe := 1.0 + sin(_time * 3.1) * 0.06 + sin(_time * 7.7) * 0.03
		_glow.energy = (1.15 + _flare * 0.9) * breathe
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0 and _player_near:
			_prompt.text = PROMPT_TEXT

func _update_flames(delta: float) -> void:
	for flame in _flames:
		if flame == null or not is_instance_valid(flame):
			continue
		var w: float = flame.get_meta("w")
		var h: float = flame.get_meta("h")
		var speed: float = flame.get_meta("speed")
		var phase: float = flame.get_meta("phase")
		var sway := sin(_time * speed + phase) * 3.2 + sin(_time * speed * 2.3 + phase) * 1.1
		var lean := sin(_time * speed * 0.7 + phase) * 2.4
		var grow := 1.0 + _flare * 0.55 + sin(_time * 5.0 + phase) * 0.04
		flame.polygon = _flame_polygon(w, h * grow, sway, lean)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if _player_input_locked():
		return
	_rest()

## 休息：回满血 + 火焰窜一下 + 一行反馈
func _rest() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("heal_full"):
		return
	var healed := int(player.call("heal_full"))
	# 坐在火边：身体压低一会儿（玩家按方向键会立刻起身）
	if player.has_method("sit_rest"):
		player.call("sit_rest", 2.2)
	_flare = 1.0
	GameManager.play_sfx("heal", -2.0)
	EventBus.log_event("campfire_rest", {"healed": healed})
	_prompt.text = RESTED_TEXT if healed > 0 else "火光很暖。你歇了一会儿。"
	_feedback_timer = FEEDBACK_TIME

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_near = true
	_prompt.text = PROMPT_TEXT
	_prompt.visible = true

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_near = false
	_prompt.visible = false

func _player_input_locked() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	return bool(player.get("_input_locked"))

func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex
