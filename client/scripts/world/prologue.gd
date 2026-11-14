extends Node2D
## 序章 · 虚无里的苏醒（M4-24 / M4-25）
##
## 剧情：没有视觉、没有听觉、没有身体的一小团灰白，浮在无边的黑里。
## 前方有个和黑暗同色的身影在唤它；它飘过去、碰到它、接受它、融进它，才换来一具躯体。
## 可躯体到手后视野仍旧很窄：想看见、听见、走得动，只能献祭。
##
## 组长两次反馈都落在这一版：
##   M4-24：环境/建模/移动/叙事全部重做 —— 无底虚空、会呼吸的灵魂、按距离显形的身影、
##          带惯性的漂浮移动、贴着角色出现的耳语（不是屏幕中央通告），节奏放慢一倍。
##   M4-25：① 结尾要有一个“从虚空落到地面”的过渡演出，不能一切场景人就站在地上；
##          ② 旁白别写成一句一顿的短句（太 AI），改用更长、更迂回的说法，
##             不直接把事实讲完，让玩家自己往下猜。
##
## 对外保留：节点名 Soul / Heart、`_fuse()`。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const NEXT_SCENE := "res://scenes/world/test_arena.tscn"

const SOUL_START := Vector2(250, 560)
const HEART_POS := Vector2(1120, 520)
const WALK_MIN := 120.0
const WALK_MAX := 1270.0
const TOUCH_DISTANCE := 74.0
const REVEAL_DISTANCE := 520.0
const CALL_DISTANCE := 430.0

# 漂浮手感
const DRIFT_ACCEL := 520.0
const DRIFT_MAX_SPEED := 150.0
const DRIFT_DAMP := 3.4
const TILT_PER_SPEED := 0.0011

## 开场三段独白：不写“看不见听不见动不了”这种一句一顿的短句，
## 改成慢慢铺开的长句 —— 说的是同一件事，但让人自己意识到“我什么都没有”。
const BEATS := [
	{"at": 2.8, "text": "你在没有边界的地方醒着。什么也抓不住，连自己的形状都只能靠猜。", "hold": 5.2},
	{"at": 9.4, "text": "只有一层灰白的光还附在你身上，像别人遗落下来的一件旧衣裳。", "hold": 5.4},
	{"at": 16.6, "text": "左边是空的，右边也是空的。可很远的地方，有什么在反复叫你的名字。", "hold": 5.6},
]
## 融合后的独白：同样避开“它进来了”这种直白结论，写成身体上发生的事
const AFTER_FUSE := [
	{"delay": 1.4, "text": "有什么顺着掌心钻进来，凉得像井水。", "hold": 3.2},
	{"delay": 5.2, "text": "你的形状开始被别的东西填满，一点一点，从胸口往外。", "hold": 3.6},
	{"delay": 9.2, "text": "现在你有一具身体了。它还不是你的。", "hold": 3.6},
]

var _soul: Node2D
var _heart: Node2D
var _soul_core: Polygon2D
var _soul_haze: Polygon2D
var _soul_tendrils: Array[Line2D] = []
var _soul_reflection: Polygon2D
var _soul_glow: PointLight2D
var _heart_core: Polygon2D
var _heart_outline: Line2D
var _heart_cloak: Polygon2D
var _soul_label: Label
var _heart_label: Label
var _vignette: TextureRect
var _fade: ColorRect
var _camera: Camera2D
var _pulse: Sprite2D
var _fog_layers: Array[Dictionary] = []
## M4-27：体积光 / 雾柱 / 远景碎影这三层的动画数据
var _depth_glows: Array[Dictionary] = []
var _mist_columns: Array[Dictionary] = []
var _far_shards: Array[Dictionary] = []

var _time := 0.0
var _beat_index := 0
var _can_move := false
var _fused := false
var _descending := false
var _leaving := false
var _called_out := false
var _drift := 0.0
var _tilt := 0.0
var _bob := 0.0
var _note_tween: Tween
var _heart_note_tween: Tween

func _ready() -> void:
	GameManager.mark_floor_start("prologue")
	GameManager.current_floor = "start"
	EventBus.log_event("prologue_enter", {})
	_build_void()
	_build_soul()
	_build_heart()
	_build_ui()
	if GameManager.has_flag("prologue_seen"):
		_can_move = true
		_beat_index = BEATS.size()
		_soul_glow.texture_scale = 2.9
		_heart_outline.modulate.a = 0.9
		_whisper_soul("……又是这里。地板还是冷的。", 2.0)

# ---------- 环境 ----------

func _build_void() -> void:
	var sky := Polygon2D.new()
	sky.name = "Sky"
	sky.z_index = -20
	sky.polygon = PackedVector2Array([Vector2(-400, -400), Vector2(1900, -400), Vector2(1900, 1300), Vector2(-400, 1300)])
	sky.vertex_colors = PackedColorArray([
		Color(0.032, 0.040, 0.058), Color(0.032, 0.040, 0.058),
		Color(0.012, 0.015, 0.024), Color(0.012, 0.015, 0.024),
	])
	add_child(sky)

	# M4-27 组长反馈：原来天空里那块横向冷光带（Dome）和下半边的黑之间形成一条
	# 又直又硬的“灰黑分割线”，虚空看着像一张贴图。这里把横向带全部去掉，改成
	# 三团互相叠着的球状冷光（体积光），再补纵向的雾柱和远景碎影 —— 有纵深，没有分界线。
	_depth_glows.clear()
	for spec in [
		{"pos": Vector2(1120, 430), "scale": 7.4, "a": 0.20, "speed": 0.055, "phase": 0.0},
		{"pos": Vector2(300, 300), "scale": 5.2, "a": 0.13, "speed": 0.041, "phase": 1.9},
		{"pos": Vector2(760, 640), "scale": 6.0, "a": 0.10, "speed": 0.033, "phase": 3.3},
	]:
		var glow := Sprite2D.new()
		glow.z_index = -19
		glow.texture = _radial_texture()
		glow.position = spec["pos"]
		glow.scale = Vector2(float(spec["scale"]), float(spec["scale"]))
		glow.modulate = Color(0.52, 0.66, 0.82, float(spec["a"]))
		add_child(glow)
		_depth_glows.append({"node": glow, "a": float(spec["a"]), "speed": float(spec["speed"]), "phase": float(spec["phase"])})

	# 雾柱：竖着立起来的几缕烟，边缘全用顶点 alpha 化开。
	# 横向雾带会画出水平线，竖着的不会 —— 这一层专门用来打散“地平线”的感觉。
	_mist_columns.clear()
	for i in range(5):
		var col := Polygon2D.new()
		col.z_index = -17
		var x := 160.0 + float(i) * 240.0
		var w := 90.0 + float(i % 3) * 40.0
		var top := -120.0
		var bottom := 820.0
		col.polygon = PackedVector2Array([
			Vector2(x - w * 0.5, top), Vector2(x + w * 0.5, top),
			Vector2(x + w * 0.30, bottom), Vector2(x - w * 0.35, bottom),
		])
		var a := 0.055 + float(i % 3) * 0.018
		col.vertex_colors = PackedColorArray([
			Color(0.40, 0.50, 0.62, 0.0), Color(0.40, 0.50, 0.62, 0.0),
			Color(0.34, 0.44, 0.56, a), Color(0.34, 0.44, 0.56, a),
		])
		add_child(col)
		_mist_columns.append({"node": col, "phase": float(i) * 1.4, "speed": 0.6 + float(i % 3) * 0.25})

	# 远景碎影：几块几乎看不见的暗形，慢慢左右偏一点，制造“远处还有东西”的错觉
	_far_shards.clear()
	for i in range(6):
		var shard := Polygon2D.new()
		shard.z_index = -18
		var x := 120.0 + float(i) * 210.0
		var h := 120.0 + float(i % 3) * 70.0
		shard.color = Color(0.028, 0.034, 0.046, 0.85)
		shard.polygon = PackedVector2Array([
			Vector2(x, 760), Vector2(x + 26.0, 760 - h * 0.45),
			Vector2(x + 12.0, 760 - h), Vector2(x - 18.0, 760 - h * 0.5),
		])
		add_child(shard)
		_far_shards.append({"node": shard, "phase": float(i) * 0.9, "x": x})

	var motes := _make_motes(46, 26.0, 0.10, 0.55)
	motes.name = "Motes"
	motes.z_index = -16
	add_child(motes)
	var far := _make_motes(70, 14.0, 0.06, 0.28)
	far.name = "MotesFar"
	far.z_index = -18
	add_child(far)

	_pulse = Sprite2D.new()
	_pulse.name = "Pulse"
	_pulse.z_index = -15
	_pulse.texture = _radial_texture()
	_pulse.position = Vector2(760, 470)
	_pulse.modulate = Color(0.42, 0.52, 0.60, 0.0)
	_pulse.scale = Vector2(6.0, 6.0)
	add_child(_pulse)

	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position = Vector2(640, 360)
	add_child(_camera)
	_camera.make_current()

func _make_motes(amount: int, speed: float, alpha: float, size: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(760, 380)
	p.position = Vector2(700, 380)
	p.direction = Vector2(1, 0)
	p.spread = 20.0
	p.gravity = Vector2(0, -1.5)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.color = Color(0.78, 0.84, 0.92, alpha)
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	for y in range(3):
		for x in range(3):
			var d := Vector2(x - 1, y - 1).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	p.texture = ImageTexture.create_from_image(img)
	return p

# ---------- 灵魂 ----------

func _build_soul() -> void:
	_soul = Node2D.new()
	_soul.name = "Soul"
	_soul.position = SOUL_START
	_soul.z_index = 2
	add_child(_soul)

	_soul_reflection = Polygon2D.new()
	_soul_reflection.name = "Reflection"
	_soul_reflection.color = Color(0.62, 0.70, 0.80, 0.10)
	_soul_reflection.polygon = _ellipse(38.0, 7.0, 20)
	_soul_reflection.position = Vector2(0, 96)
	_soul.add_child(_soul_reflection)

	_soul_haze = Polygon2D.new()
	_soul_haze.name = "Haze"
	_soul_haze.polygon = _blob_points(30.0, 16, 0.22)
	var colors := PackedColorArray()
	for i in range(_soul_haze.polygon.size()):
		colors.append(Color(0.80, 0.86, 0.94, 0.13 if i % 2 == 0 else 0.20))
	_soul_haze.vertex_colors = colors
	_soul.add_child(_soul_haze)

	_soul_core = Polygon2D.new()
	_soul_core.name = "Core"
	_soul_core.color = Color(0.96, 0.98, 1.0, 1.0)
	_soul_core.polygon = _blob_points(10.0, 14, 0.10)
	_soul_core.position = Vector2(0, -4)
	_soul.add_child(_soul_core)

	for i in range(3):
		var t := Line2D.new()
		t.name = "Tendril%d" % i
		t.width = 2.4 - float(i) * 0.5
		t.default_color = Color(0.72, 0.78, 0.86, 0.42 - float(i) * 0.10)
		t.points = PackedVector2Array([Vector2(0, 12), Vector2(0, 30), Vector2(0, 46)])
		_soul.add_child(t)
		_soul_tendrils.append(t)

	_soul_glow = PointLight2D.new()
	_soul_glow.name = "SoulGlow"
	_soul_glow.texture = _radial_texture()
	_soul_glow.texture_scale = 2.1
	_soul_glow.energy = 1.15
	_soul_glow.color = Color(0.86, 0.92, 1.0)
	_soul_glow.position = Vector2(0, -4)
	_soul.add_child(_soul_glow)

# ---------- 身影 ----------

func _build_heart() -> void:
	_heart = Node2D.new()
	_heart.name = "Heart"
	_heart.position = HEART_POS
	_heart.z_index = 1
	add_child(_heart)

	_heart_cloak = Polygon2D.new()
	_heart_cloak.name = "Cloak"
	_heart_cloak.color = Color(0.010, 0.012, 0.017, 1.0)
	_heart_cloak.polygon = PackedVector2Array([
		Vector2(-40, 78), Vector2(-52, 40), Vector2(-46, 2), Vector2(-34, -40),
		Vector2(-18, -74), Vector2(0, -92), Vector2(16, -76), Vector2(32, -44),
		Vector2(40, -8), Vector2(50, 30), Vector2(44, 74), Vector2(24, 92),
		Vector2(6, 84), Vector2(-12, 94), Vector2(-28, 84),
	])
	_heart.add_child(_heart_cloak)

	var hood := Polygon2D.new()
	hood.color = Color(0.004, 0.005, 0.008, 1.0)
	hood.polygon = PackedVector2Array([
		Vector2(-16, -60), Vector2(0, -84), Vector2(16, -60), Vector2(11, -42), Vector2(-11, -42),
	])
	_heart.add_child(hood)

	for side in [-1.0, 1.0]:
		var spike := Polygon2D.new()
		spike.color = Color(0.008, 0.010, 0.014, 1.0)
		spike.polygon = PackedVector2Array([
			Vector2(side * 30, -52), Vector2(side * 58, -66), Vector2(side * 40, -34),
		])
		_heart.add_child(spike)
	for i in range(5):
		var t := Line2D.new()
		t.width = 2.0
		t.default_color = Color(0.014, 0.017, 0.022, 0.95)
		var bx := -26.0 + float(i) * 13.0
		t.points = PackedVector2Array([
			Vector2(bx, 70), Vector2(bx + 5.0, 92.0 + float(i % 2) * 9.0), Vector2(bx - 3.0, 108.0 + float(i % 3) * 8.0),
		])
		_heart.add_child(t)

	_heart_outline = Line2D.new()
	_heart_outline.name = "Outline"
	_heart_outline.width = 1.6
	_heart_outline.default_color = Color(0.40, 0.46, 0.56, 1.0)
	_heart_outline.modulate = Color(1, 1, 1, 0.0)
	_heart_outline.points = PackedVector2Array([
		Vector2(-40, 78), Vector2(-52, 40), Vector2(-46, 2), Vector2(-34, -40),
		Vector2(-18, -74), Vector2(0, -92), Vector2(16, -76), Vector2(32, -44),
		Vector2(40, -8), Vector2(50, 30), Vector2(44, 74),
	])
	_heart.add_child(_heart_outline)

	var cavity := Polygon2D.new()
	cavity.color = Color(0.030, 0.020, 0.036, 1.0)
	cavity.polygon = _ellipse(19.0, 22.0, 18)
	cavity.position = Vector2(0, -18)
	_heart.add_child(cavity)
	_heart_core = Polygon2D.new()
	_heart_core.name = "Core"
	_heart_core.color = Color(0.66, 0.50, 0.78, 0.62)
	_heart_core.polygon = _ellipse(7.5, 8.5, 12)
	_heart_core.position = Vector2(0, -18)
	_heart.add_child(_heart_core)

# ---------- UI ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 3
	add_child(layer)

	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.texture = _radial_texture(false)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.size = Vector2(1280, 720)
	_vignette.modulate = Color(0, 0, 0, 0.74)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_vignette)

	# M4-26 组长定稿：虚无阶段的话直接摆在屏幕正中央 —— 这段是“旁白/内心”，
	# 人物本身几乎没有形体，字跟着角色飘反而像标签。
	# 放在 UI 层且铺满屏幕：不吃镜头缩放，位置永远是正中；仍用慢淡入淡出保持节奏。
	_soul_label = _make_label("Narration", 22, Color(0.80, 0.84, 0.88, 0.95))
	_soul_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_soul_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(_soul_label)
	# 身影说的话仍复用这一枚，只是换成偏冷的紫色，说的瞬间同位置换色，不另起一块
	_heart_label = _soul_label

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 2.4)

func _make_label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(1, 1, 1, 0.0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	var font := load(FONT_PATH) as Font
	if font != null:
		label.add_theme_font_override("font", font)
	return label

# ---------- 每帧 ----------

func _process(delta: float) -> void:
	_time += delta
	_update_void()
	_update_soul(delta)
	_update_heart(delta)
	if not _fused:
		while _beat_index < BEATS.size() and _time >= float(BEATS[_beat_index]["at"]):
			_whisper_soul(str(BEATS[_beat_index]["text"]), float(BEATS[_beat_index]["hold"]))
			_beat_index += 1
			if _beat_index == BEATS.size():
				_can_move = true
		_move_soul(delta)
		_check_touch()

func _update_void() -> void:
	# 体积光：三团各自缓慢呼吸（周期不同，画面就不会一起亮一起暗）
	for item in _depth_glows:
		var glow := item["node"] as Sprite2D
		if glow == null or not is_instance_valid(glow):
			continue
		var base := float(item["a"])
		glow.modulate.a = base * (0.82 + sin(_time * float(item["speed"]) + float(item["phase"])) * 0.18)
	# 雾柱：竖着往上慢慢飘，飘到头再从下面接回来（循环看不出断点）
	for item in _mist_columns:
		var col := item["node"] as Polygon2D
		if col == null or not is_instance_valid(col):
			continue
		col.position.y = -fmod(_time * float(item["speed"]) + float(item["phase"]), 260.0)
		col.position.x = sin(_time * 0.06 + float(item["phase"])) * 18.0
	# 远景碎影：几乎没有位移，只是左右偏一点，做“远处的东西”的暗示
	for item in _far_shards:
		var shard := item["node"] as Polygon2D
		if shard == null or not is_instance_valid(shard):
			continue
		shard.position.x = sin(_time * 0.035 + float(item["phase"])) * 14.0
	var t := fmod(_time, 6.0) / 6.0
	_pulse.modulate.a = sin(t * PI) * 0.22
	_pulse.scale = Vector2(6.0 + t * 3.2, 6.0 + t * 3.2)

func _update_soul(delta: float) -> void:
	if _soul == null or not is_instance_valid(_soul):
		return
	_bob += delta
	var breath := sin(_bob * 1.5) * 0.06
	_soul_core.scale = Vector2(1.0 + breath, 1.0 - breath * 0.6)
	_soul_haze.scale = Vector2(1.0 - breath * 0.5, 1.0 + breath * 0.8)
	_soul_haze.modulate.a = 0.85 + sin(_bob * 1.1) * 0.15
	if not _descending:
		_soul.position.y = SOUL_START.y + sin(_bob * 0.9) * 6.0
	_tilt = lerpf(_tilt, _drift * TILT_PER_SPEED, 0.12)
	_soul.rotation = _tilt
	var lean := clampf(_drift / DRIFT_MAX_SPEED, -1.0, 1.0)
	for i in range(_soul_tendrils.size()):
		var t := _soul_tendrils[i]
		var sway := sin(_bob * (1.6 + float(i) * 0.4) + float(i)) * (5.0 + float(i) * 2.5)
		var tip := 46.0 + float(i) * 6.0
		t.points = PackedVector2Array([
			Vector2(-lean * 4.0, 10.0),
			Vector2(-lean * 10.0 + sway * 0.4, tip * 0.55),
			Vector2(-lean * 18.0 + sway, tip),
		])
	if _soul_reflection != null and is_instance_valid(_soul_reflection):
		_soul_reflection.position = Vector2(-lean * 8.0, 96.0 + sin(_bob * 0.9 + PI) * 2.0)
		_soul_reflection.modulate.a = 0.10 - absf(lean) * 0.03

func _update_heart(_delta: float) -> void:
	if _heart == null or not is_instance_valid(_heart):
		return
	var beat := sin(_time * 1.85) * 0.5 + 0.5
	_heart_core.scale = Vector2(0.9 + beat * 0.35, 0.9 + beat * 0.35)
	_heart_core.modulate.a = 0.45 + beat * 0.35
	if _soul != null and is_instance_valid(_soul) and not _fused:
		var dist := _soul.global_position.distance_to(_heart.global_position)
		var reveal := clampf((REVEAL_DISTANCE - dist) / REVEAL_DISTANCE, 0.0, 1.0)
		_heart_outline.modulate.a = reveal * 0.35 + beat * 0.05
	_heart_cloak.position.x = sin(_time * 0.7) * 2.4
	_heart.scale = Vector2(1.0 + sin(_time * 0.5) * 0.012, 1.0 + sin(_time * 0.5 + 1.2) * 0.012)

# ---------- 移动 / 触碰 ----------

func _move_soul(delta: float) -> void:
	if not _can_move or _fused:
		return
	var dir := Input.get_axis("move_left", "move_right")
	if absf(dir) > 0.01:
		_drift = move_toward(_drift, dir * DRIFT_MAX_SPEED, DRIFT_ACCEL * delta)
	else:
		_drift -= _drift * minf(DRIFT_DAMP * delta, 1.0)
		if absf(_drift) < 1.0:
			_drift = 0.0
	var x := _soul.position.x + _drift * delta
	var d := absf(HEART_POS.x - x)
	if d < 180.0:
		x -= _drift * delta * 0.35 * (1.0 - d / 180.0)
	_soul.position.x = clampf(x, WALK_MIN, WALK_MAX)

func _check_touch() -> void:
	if _soul == null or _heart == null:
		return
	var distance := _soul.global_position.distance_to(_heart.global_position)
	if distance < CALL_DISTANCE and not _called_out:
		_called_out = true
		_whisper_heart("过来。这里没有路，可你踩得上来。", 3.6)
	if distance < TOUCH_DISTANCE:
		_fuse()

# ---------- 融合 ----------

func _fuse() -> void:
	if _fused:
		return
	_fused = true
	_can_move = false
	_drift = 0.0
	GameManager.set_flag("prologue_seen")
	var cam_tw := create_tween()
	cam_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam_tw.tween_property(_camera, "zoom", Vector2(1.26, 1.26), 2.6)
	cam_tw.parallel().tween_property(_camera, "position", Vector2(760, 360), 2.6)
	_whisper_heart("……你碰到我了。", 2.6)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(1.8)
	tw.tween_callback(func() -> void: _whisper_heart("别急着明白。先把这只手接过去。", 2.6))
	tw.tween_property(_heart_core, "modulate:a", 1.0, 1.6)
	tw.parallel().tween_property(_heart_core, "scale", Vector2(2.2, 2.2), 1.6)
	tw.tween_interval(0.6)
	tw.tween_property(_heart, "position", _soul.position + Vector2(0, -10), 2.2)
	tw.parallel().tween_property(_heart, "scale", Vector2(0.35, 0.35), 2.2)
	tw.parallel().tween_property(_heart_cloak, "modulate:a", 0.0, 2.2)
	tw.tween_callback(_after_fuse)

func _after_fuse() -> void:
	if _heart != null and is_instance_valid(_heart):
		_heart.queue_free()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_soul_glow, "texture_scale", 2.9, 2.0)
	tw.parallel().tween_property(_soul_glow, "color", Color(0.92, 0.95, 0.90), 2.0)
	tw.parallel().tween_property(_vignette, "modulate:a", 0.70, 2.0)
	for item in AFTER_FUSE:
		tw.tween_interval(float(item["delay"]))
		tw.tween_callback(func() -> void: _whisper_soul(str(item["text"]), float(item["hold"])))
	tw.tween_interval(5.2)
	tw.tween_callback(func() -> void: _whisper(1, "想看见的话，就把身上多余的部分交出来。我不急，我等得起。", 5.4, true))
	tw.tween_interval(5.6)
	tw.tween_callback(_begin_descent)

# ---------- 从虚空落到地面的过渡演出 ----------
#
# 组长反馈：“从虚空到正式的地图要有过渡，不能一切场景人就站在地上。”
# 这段做三件事：① 脚下那道极淡的倒影实体化成一块地板；② 视野圈收窄、四周压黑，
# 镜头随之往下沉；③ 灵魂被这层地板“漏”下去 —— 画面拉出竖直的速度线，
# 落地前后的黑场交给教学关那边接（见 test_arena 的 _drop_in）。

func _begin_descent() -> void:
	if _descending:
		return
	_descending = true
	_can_move = false
	# 地板实体化：一道冷光从脚下摊开，越摊越实，最后把整个画面托起来
	var floor_line := Line2D.new()
	floor_line.name = "VoidFloor"
	floor_line.width = 2.0
	floor_line.default_color = Color(0.62, 0.72, 0.82, 0.0)
	floor_line.points = PackedVector2Array([
		Vector2(SOUL_START.x - 240.0, SOUL_START.y + 96.0),
		Vector2(SOUL_START.x + 240.0, SOUL_START.y + 96.0),
	])
	floor_line.z_index = 0
	add_child(floor_line)

	# 速度线：一组竖直细线从下往上刷过，表现“在往下掉”
	var streaks := Node2D.new()
	streaks.name = "FallStreaks"
	streaks.z_index = 3
	add_child(streaks)
	var streak_nodes: Array[Line2D] = []
	for i in range(14):
		var line := Line2D.new()
		line.width = 1.0 + float(i % 3) * 0.6
		line.default_color = Color(0.70, 0.80, 0.90, 0.0)
		var x := 380.0 + float(i) * 60.0 + float(i % 4) * 9.0
		line.points = PackedVector2Array([Vector2(x, 0), Vector2(x + 2.0, 120.0 + float(i % 5) * 40.0)])
		streaks.add_child(line)
		streak_nodes.append(line)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# ① 地板亮起来，视野收窄（1.4s）
	tw.tween_property(floor_line, "default_color:a", 0.55, 1.2)
	tw.parallel().tween_property(_vignette, "modulate:a", 0.96, 1.6)
	tw.parallel().tween_property(_camera, "zoom", Vector2(0.92, 0.92), 1.6)
	tw.parallel().tween_property(_soul_glow, "energy", 0.55, 1.6)
	# ② 速度线出现，灵魂被拉长、往下坠（1.4s）
	tw.tween_callback(func() -> void:
		for line in streak_nodes:
			var st := create_tween()
			st.tween_property(line, "default_color:a", 0.55, 0.25)
			st.tween_property(line, "default_color:a", 0.0, 0.75)
	)
	tw.tween_property(_soul, "scale", Vector2(0.72, 1.9), 1.3)
	tw.parallel().tween_property(_soul, "position:y", SOUL_START.y + 460.0, 1.3)
	tw.parallel().tween_property(_soul, "modulate:a", 0.0, 1.3)
	tw.parallel().tween_property(floor_line, "default_color:a", 0.0, 1.1)
	# ③ 黑场吞掉，交给教学关那边“落地”
	tw.tween_property(_fade, "color:a", 1.0, 0.7)
	tw.tween_interval(0.15)
	tw.tween_callback(_leave)

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	# 告诉下一幕：这次是从虚空里掉下来的，别让角色一开始就老老实实站在地上
	GameManager.set_flag("enter_from_void")
	get_tree().change_scene_to_file(NEXT_SCENE)

# ---------- 耳语 ----------

func _whisper_soul(text: String, hold: float) -> void:
	_whisper(0, text, hold, true)

func _whisper_heart(text: String, hold: float) -> void:
	_whisper(1, text, hold, false)

## who: 0 = 旁白（偏白）；1 = 身影说的话（偏紫）。两者都摆在屏幕正中央，只换颜色。
func _whisper(who: int, text: String, hold: float, is_soul: bool) -> void:
	var label := _soul_label if who == 0 else _heart_label
	if label == null or not is_instance_valid(label):
		return
	var old := _note_tween if is_soul else _heart_note_tween
	if old != null and old.is_valid():
		old.kill()
	label.text = text
	label.add_theme_color_override("font_color",
		Color(0.80, 0.84, 0.88, 0.95) if who == 0 else Color(0.74, 0.66, 0.88, 0.96))
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(label, "modulate:a", 1.0, 1.1)
	tw.tween_interval(maxf(hold, 0.6))
	tw.tween_property(label, "modulate:a", 0.0, 1.7)
	if is_soul:
		_note_tween = tw
	else:
		_heart_note_tween = tw

# ---------- 小工具 ----------

func _radial_texture(soft: bool = true) -> GradientTexture2D:
	var gradient := Gradient.new()
	if soft:
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
	else:
		gradient.set_color(0, Color(1, 1, 1, 0))
		gradient.set_color(1, Color(1, 1, 1, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

func _blob_points(radius: float, steps: int, wobble: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		var r := radius * (1.0 + sin(a * 3.0) * wobble + sin(a * 5.0 + 1.2) * wobble * 0.6)
		pts.append(Vector2(cos(a) * r, sin(a) * r * 1.18))
	return pts

func _ellipse(rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts
