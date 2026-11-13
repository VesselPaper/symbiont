extends Node2D
## 序章 · 虚无里的苏醒
##
## 剧情：最初什么都看不见 —— 灰白的轮廓、一小圈勉强够用的视野，其余全是黑的。
## 前方有个和黑暗同色的身影在唤你；走过去触碰它、接受它、融入它，你才有了躯体。
## 躯体到手后视野仍然很窄：想看见、听见、走得动，只能献祭。
##
## 实现：整张图靠 CanvasModulate 压到近黑，灵魂身上挂一盏 PointLight2D，
## 于是"看得见的地方"就是那一圈光 —— 不需要额外做视野遮罩。
## 操作只有左右移动；走近身影即触发融合，播完自动进教学关。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const SOUL_FLAME := preload("res://components/soul_flame.gd")
const NEXT_SCENE := "res://scenes/world/test_arena.tscn"
const SOUL_START := Vector2(250, 604)
const HEART_POS := Vector2(1090, 548)
const WALK_MIN := 90.0
const WALK_MAX := 1210.0
const TOUCH_DISTANCE := 78.0

## 每一句旁白的出现时间（秒）与文案；时间从进入场景开始算
const BEATS := [
	{"at": 0.8, "text": "看不见。听不见。动不了。"},
	{"at": 3.4, "text": "你在一片全然的虚无里醒来，只有灰白的轮廓，" },
	{"at": 5.8, "text": "和一小圈勉强够用的视野。"},
	{"at": 8.2, "text": "……前面，有什么在叫你。"},
]

var _soul: Node2D
var _heart: Node2D
var _soul_flame: Node2D
var _soul_glow: PointLight2D
var _label: Label
var _label_tween: Tween
var _fade: ColorRect
var _time := 0.0
var _beat_index := 0
var _can_move := false
var _fused := false
var _leaving := false
var _called_out := false

func _ready() -> void:
	GameManager.mark_floor_start("prologue")
	GameManager.current_floor = "start"
	EventBus.log_event("prologue_enter", {})
	_build_world()
	_build_ui()
	# 二周目/读档重进时不必再演一遍
	if GameManager.has_flag("prologue_seen"):
		_can_move = true
		_beat_index = BEATS.size()
		_show_text("……又是这里。", 1.6)

## 虚无的背景：冷水色渐变天空 + 远处塌了一半的拱门 + 贴地冷雾 + 漂浮尘埃。
## 只为了"看得见的边缘依然是地牢"，而不是一块纯黑画布。
func _build_backdrop() -> void:
	var sky := Polygon2D.new()
	sky.name = "Sky"
	sky.polygon = PackedVector2Array([
		Vector2(-200, -200), Vector2(1480, -200),
		Vector2(1480, 760), Vector2(-200, 760),
	])
	sky.vertex_colors = PackedColorArray([
		Color(0.072, 0.084, 0.108), Color(0.072, 0.084, 0.108),
		Color(0.020, 0.024, 0.033), Color(0.020, 0.024, 0.033),
	])
	add_child(sky)

	for spec in [
		{"x": 380.0, "w": 150.0, "h": 250.0, "a": 0.55},
		{"x": 720.0, "w": 190.0, "h": 300.0, "a": 0.42},
		{"x": 1080.0, "w": 160.0, "h": 220.0, "a": 0.34},
	]:
		var x := float(spec["x"])
		var w := float(spec["w"])
		var h := float(spec["h"])
		var alpha := float(spec["a"])
		var base_y := 618.0
		var arch := Line2D.new()
		arch.width = 2.0
		arch.default_color = Color(0.16, 0.21, 0.25, alpha)
		var pts := PackedVector2Array()
		pts.append(Vector2(x - w * 0.5, base_y))
		pts.append(Vector2(x - w * 0.5, base_y - h))
		for k in range(13):
			var a := PI * (1.0 - float(k) / 12.0)
			pts.append(Vector2(x + cos(a) * w * 0.5, base_y - h - sin(a) * w * 0.5))
		pts.append(Vector2(x + w * 0.5, base_y))
		arch.points = pts
		add_child(arch)

	for i in range(3):
		var fog := Polygon2D.new()
		fog.color = Color(0.30, 0.40, 0.44, 0.035 - float(i) * 0.008)
		fog.polygon = PackedVector2Array([
			Vector2(-200, 560 + i * 26), Vector2(1480, 552 + i * 26),
			Vector2(1480, 600 + i * 26), Vector2(-200, 608 + i * 26),
		])
		add_child(fog)

	var dust := CPUParticles2D.new()
	dust.name = "Dust"
	dust.amount = 26
	dust.lifetime = 9.0
	dust.preprocess = 4.0
	dust.position = Vector2(640, 680)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(760, 30)
	dust.direction = Vector2(0, -1)
	dust.spread = 20.0
	dust.gravity = Vector2(0, -4)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 9.0
	dust.scale_amount_min = 0.3
	dust.scale_amount_max = 1.0
	dust.color = Color(0.62, 0.74, 0.82, 0.22)
	dust.texture = _radial_texture()
	add_child(dust)

func _build_world() -> void:
	_build_backdrop()
	# 冷色的全局压暗：真正"看得见"的范围由灵魂身上的灯决定
	var dark := CanvasModulate.new()
	dark.name = "Dark"
	dark.color = Color(0.052, 0.060, 0.082, 1.0)
	add_child(dark)

	# 灰白的地面：灵魂踩在上面，能看出一点方向
	var ground := Polygon2D.new()
	ground.name = "Ground"
	ground.color = Color(0.30, 0.31, 0.33, 1.0)
	ground.polygon = PackedVector2Array([
		Vector2(-200, 618), Vector2(1480, 618), Vector2(1480, 900), Vector2(-200, 900),
	])
	add_child(ground)
	var rim := Line2D.new()
	rim.width = 2.0
	rim.default_color = Color(0.55, 0.56, 0.58, 0.75)
	rim.points = PackedVector2Array([Vector2(-200, 618), Vector2(1480, 618)])
	add_child(rim)

	# 灵魂：一点灰白的雾团，没有手脚
	_soul = Node2D.new()
	_soul.name = "Soul"
	_soul.position = SOUL_START
	add_child(_soul)
	var wisp := Polygon2D.new()
	wisp.color = Color(0.78, 0.80, 0.82, 0.92)
	wisp.polygon = PackedVector2Array([
		Vector2(0, -26), Vector2(9, -14), Vector2(12, 4),
		Vector2(6, 16), Vector2(0, 20), Vector2(-6, 16),
		Vector2(-12, 4), Vector2(-9, -14),
	])
	_soul.add_child(wisp)
	var tail := Polygon2D.new()
	tail.color = Color(0.62, 0.66, 0.70, 0.55)
	tail.polygon = PackedVector2Array([
		Vector2(-6, 18), Vector2(0, 34), Vector2(4, 41), Vector2(6, 18),
	])
	_soul.add_child(tail)

	# 灵魂上方像火焰一样向上消逝的白色火舌（见 components/soul_flame.gd）
	_soul_flame = SOUL_FLAME.new()
	_soul_flame.name = "SoulFlame"
	_soul_flame.position = Vector2(0, -20)
	_soul.add_child(_soul_flame)

	# 灵魂自带的一小圈视野
	_soul_glow = PointLight2D.new()
	_soul_glow.name = "SoulGlow"
	_soul_glow.texture = _radial_texture()
	_soul_glow.texture_scale = 2.6
	_soul_glow.energy = 1.35
	_soul_glow.color = Color(0.96, 0.97, 1.0)
	_soul_glow.position = Vector2(0, -6)
	_soul.add_child(_soul_glow)

	# 身影：和黑暗同一种黑，只有一圈极淡的轮廓，靠近才看得出是人形
	_heart = Node2D.new()
	_heart.name = "Heart"
	_heart.position = HEART_POS
	add_child(_heart)
	# 斗篷：宽下摆、收肩、尖头兜帽，人形但比例不对，像"披着人形的什么东西"
	var cloak := Polygon2D.new()
	cloak.color = Color(0.017, 0.019, 0.024, 1.0)
	cloak.polygon = PackedVector2Array([
		Vector2(-38, 52), Vector2(-44, 20), Vector2(-38, -18),
		Vector2(-28, -44), Vector2(-12, -62), Vector2(0, -74),
		Vector2(12, -62), Vector2(28, -44), Vector2(34, -16),
		Vector2(40, 22), Vector2(34, 52), Vector2(18, 60),
		Vector2(4, 52), Vector2(-10, 62), Vector2(-24, 54),
	])
	_heart.add_child(cloak)

	# 兜帽内侧更黑一层，做出"脸是空的"的感觉
	var hood := Polygon2D.new()
	hood.color = Color(0.008, 0.009, 0.012, 1.0)
	hood.polygon = PackedVector2Array([
		Vector2(-13, -48), Vector2(0, -66), Vector2(13, -48),
		Vector2(9, -34), Vector2(-9, -34),
	])
	_heart.add_child(hood)

	# 肩上的尖刺 + 下摆垂下的触须
	for side in [-1.0, 1.0]:
		var spike := Polygon2D.new()
		spike.color = Color(0.013, 0.015, 0.019, 1.0)
		spike.polygon = PackedVector2Array([
			Vector2(side * 26, -40), Vector2(side * 46, -52), Vector2(side * 34, -26),
		])
		_heart.add_child(spike)
	for i in range(4):
		var t := Line2D.new()
		t.width = 2.0
		t.default_color = Color(0.020, 0.023, 0.028, 0.9)
		var bx := -22.0 + float(i) * 14.0
		t.points = PackedVector2Array([
			Vector2(bx, 52), Vector2(bx + 4.0, 66 + float(i % 2) * 8.0),
			Vector2(bx - 2.0, 78 + float(i % 3) * 6.0),
		])
		_heart.add_child(t)

	# 极淡的轮廓光，只在边缘勾一下，靠近才看得出是人形
	var outline := Line2D.new()
	outline.width = 1.4
	outline.default_color = Color(0.38, 0.43, 0.50, 0.30)
	outline.points = PackedVector2Array([
		Vector2(-38, 52), Vector2(-44, 20), Vector2(-38, -18),
		Vector2(-28, -44), Vector2(-12, -62), Vector2(0, -74),
		Vector2(12, -62), Vector2(28, -44), Vector2(34, -16),
	])
	_heart.add_child(outline)

	# 胸腔是空的：一圈暗色腔体，中间一点心跳般的微光（寄生物的本心）
	var cavity := Polygon2D.new()
	cavity.color = Color(0.045, 0.030, 0.045, 1.0)
	cavity.polygon = _ring_points(17.0, 18)
	cavity.position = Vector2(0, -14)
	_heart.add_child(cavity)
	var core := Polygon2D.new()
	core.name = "Core"
	core.color = Color(0.62, 0.46, 0.72, 0.75)
	core.polygon = _ring_points(6.5, 12)
	core.position = Vector2(0, -14)
	_heart.add_child(core)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 3
	add_child(layer)

	_label = Label.new()
	_label.name = "Narration"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.position = Vector2(140, 120)
	_label.size = Vector2(1000, 120)
	_label.modulate = Color(1, 1, 1, 0.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.80, 0.82, 0.84, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	var font := load(FONT_PATH) as Font
	if font != null:
		_label.add_theme_font_override("font", font)
	layer.add_child(_label)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.4)

func _process(delta: float) -> void:
	_time += delta
	if not _fused:
		# 旁白按时间轴推进
		while _beat_index < BEATS.size() and _time >= float(BEATS[_beat_index]["at"]):
			_show_text(str(BEATS[_beat_index]["text"]), 2.2)
			_beat_index += 1
			if _beat_index == BEATS.size():
				_can_move = true
		_move_soul(delta)
		_check_touch()
	# 身影与灵魂的呼吸
	var pulse := 1.0 + sin(_time * 1.6) * 0.05
	if _heart != null and is_instance_valid(_heart):
		_heart.scale = Vector2(pulse, pulse)
	if _soul != null and is_instance_valid(_soul) and not _fused:
		var wisp := _soul.get_child(0) as Node2D
		if wisp != null:
			wisp.position.y = sin(_time * 2.2) * 2.0

func _move_soul(delta: float) -> void:
	if not _can_move or _fused:
		return
	var dir := Input.get_axis("move_left", "move_right")
	if dir == 0.0:
		return
	_soul.position.x = clampf(_soul.position.x + dir * 150.0 * delta, WALK_MIN, WALK_MAX)

func _check_touch() -> void:
	if _soul == null or _heart == null:
		return
	var distance := _soul.global_position.distance_to(_heart.global_position)
	if distance < 420.0 and not _called_out:
		_called_out = true
		_show_text("它就在那里。和黑暗同一种黑，只有胸口一点微光。", 2.6)
	if distance < TOUCH_DISTANCE:
		_fuse()

func _fuse() -> void:
	if _fused:
		return
	_fused = true
	_can_move = false
	GameManager.set_flag("prologue_seen")
	if _soul_flame != null and _soul_flame.has_method("set_rise"):
		_soul_flame.call("set_rise", 1.9)
	_show_text("你伸出手，触碰了它。\n接受了它。融入了它。", 2.8)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# 身影缩进灵魂胸口
	tw.tween_property(_heart, "position", _soul.position + Vector2(0, -10), 1.1)
	tw.parallel().tween_property(_heart, "scale", Vector2(0.18, 0.18), 1.1)
	tw.parallel().tween_property(_heart, "modulate:a", 0.0, 1.1)
	tw.tween_callback(_after_fuse)

func _after_fuse() -> void:
	if _heart != null and is_instance_valid(_heart):
		_heart.queue_free()
	# 视野放大一点：有了躯体，但还看得不远
	if _soul_flame != null and _soul_flame.has_method("set_rise"):
		_soul_flame.call("set_rise", 0.55)
	var tw := create_tween()
	tw.tween_property(_soul_glow, "texture_scale", 3.2, 1.2)
	tw.parallel().tween_property(_soul_glow, "color", Color(0.86, 0.90, 0.92), 1.2)
	tw.tween_callback(func() -> void:
		_show_text("你有了躯体。", 2.2)
	)
	tw.tween_interval(2.6)
	tw.tween_callback(func() -> void:
		_show_text("可四周仍是黑的 —— 你还没有视觉，也还不太动得了。\n想看见、听见、走得动，就只能献祭。", 3.6)
	)
	tw.tween_interval(4.0)
	# 先让画面完整地沉下去，再切场景：不要在两幕之间留一帧硬切
	tw.tween_property(_fade, "color:a", 1.0, 1.0)
	tw.tween_interval(0.25)
	tw.tween_callback(_leave)

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(NEXT_SCENE)

func _show_text(text: String, hold: float) -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()
	_label.text = text
	_label_tween = create_tween()
	_label_tween.tween_property(_label, "modulate:a", 1.0, 0.45)
	_label_tween.tween_interval(maxf(hold, 0.4))
	_label_tween.tween_property(_label, "modulate:a", 0.0, 0.6)

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

func _ring_points(radius: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts
