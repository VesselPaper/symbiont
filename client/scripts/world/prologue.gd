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
## M4-29：只给角色周围一小圈光，其余全黑（屏幕空间挖洞，而不是整屏压暗）
var _darkness: ColorRect
var _dark_mat: ShaderMaterial
var _fade: ColorRect
var _camera: Camera2D
var _pulse: Sprite2D
var _fog_layers: Array[Dictionary] = []
## M4-27：体积光 / 雾柱 / 远景碎影这三层的动画数据
var _depth_glows: Array[Dictionary] = []
var _mist_columns: Array[Dictionary] = []
var _far_shards: Array[Dictionary] = []
## 黑火的火舌（M4-29）与黑幕挖洞参数
var _heart_licks: Array[Dictionary] = []

var _time := 0.0
var _beat_index := 0
var _can_move := false
var _fused := false
var _descending := false
## 下落演出的节拍与脉冲：鼓点从 5s 一拍渐快到 1s 一拍，明暗与它同拍
const BEAT_START := 5.0
const BEAT_END := 1.0
const FALL_TIME := 35.0
const HOLD_DARK := 1.0
const REVEAL_TIME := 2.0
var _desc_phase := 0            # 0 静止 / 1 下落 / 2 停在暗拍 / 3 从玩家亮起
var _desc_t := 0.0
var _beat_accum := 0.0
var _beat_interval := BEAT_START
var _beat_flash := 0.0
var _desc_zoom_from := 1.0
var _desc_zoom_to := 0.80
## 亮起阶段接管黑幕半径（-1 表示仍用呼吸值）
var _dark_radius_override := -1.0
var _leaving := false
var _called_out := false
var _drift := 0.0
var _tilt := 0.0
var _bob := 0.0
var _note_tween: Tween
var _heart_note_tween: Tween
## M4-28：融合后要显出的“玩家正常样子”（先做好藏在灵魂里，坠落时淡入）
var _knight: Node2D
var _shake_timer := 0.0
var _shake_strength := 0.0

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

	# 玩家正常样子：兜帽骑士的剪影。先藏起来（透明），等融合后往下坠时淡入，
	# 让“灵魂变成人形”这件事是渐变出来的，而不是切场景时突然换了个角色。
	_knight = Node2D.new()
	_knight.name = "Knight"
	_knight.position = Vector2(0, -6)
	_knight.scale = Vector2(0.62, 0.62)
	_knight.modulate = Color(1, 1, 1, 0.0)
	_soul.add_child(_knight)

	var cloak := Polygon2D.new()
	cloak.color = Color(0.150, 0.164, 0.186, 1.0)
	cloak.polygon = PackedVector2Array([
		Vector2(-13, 22), Vector2(-16, 8), Vector2(-13, -6), Vector2(-9, -16),
		Vector2(-4, -24), Vector2(0, -27), Vector2(4, -24), Vector2(9, -16),
		Vector2(13, -6), Vector2(16, 8), Vector2(13, 22), Vector2(5, 25), Vector2(-5, 25),
	])
	_knight.add_child(cloak)

	var hood := Polygon2D.new()
	hood.color = Color(0.100, 0.110, 0.128, 1.0)
	hood.polygon = PackedVector2Array([
		Vector2(-10, -14), Vector2(-7, -26), Vector2(0, -30),
		Vector2(7, -26), Vector2(10, -14), Vector2(6, -8), Vector2(-6, -8),
	])
	_knight.add_child(hood)

	# 兜帽里是空的：一团比斗篷更深的黑，只有一点眼白
	var face := Polygon2D.new()
	face.color = Color(0.020, 0.024, 0.030, 1.0)
	face.polygon = _ellipse(6.5, 8.0, 12)
	face.position = Vector2(0, -17)
	_knight.add_child(face)

	var eye := Polygon2D.new()
	eye.color = Color(0.90, 0.94, 0.86, 0.95)
	eye.polygon = _ellipse(1.8, 2.6, 10)
	eye.position = Vector2(1.6, -18)
	_knight.add_child(eye)

	var rim := Line2D.new()
	rim.width = 1.2
	rim.default_color = Color(0.42, 0.48, 0.54, 0.55)
	rim.points = PackedVector2Array([
		Vector2(-13, 22), Vector2(-16, 8), Vector2(-13, -6),
		Vector2(-9, -16), Vector2(-4, -24), Vector2(0, -27),
	])
	_knight.add_child(rim)

# ---------- 身影 ----------

func _build_heart() -> void:
	_heart = Node2D.new()
	_heart.name = "Heart"
	_heart.position = HEART_POS
	_heart.z_index = 1
	add_child(_heart)

	# M4-29 组长：寄生体的黑影改成“黑色的火焰”。
	# 轮廓照着一团往上舔的火：底宽、腰收、顶端分几股尖，边缘故意不对齐。
	_heart_cloak = Polygon2D.new()
	_heart_cloak.name = "Flame"
	_heart_cloak.color = Color(0.006, 0.007, 0.010, 1.0)
	_heart_cloak.polygon = PackedVector2Array([
		Vector2(-34, 92), Vector2(-46, 54), Vector2(-30, 20), Vector2(-40, -18),
		Vector2(-18, -52), Vector2(-24, -96), Vector2(0, -124), Vector2(10, -88),
		Vector2(24, -104), Vector2(20, -60), Vector2(38, -26), Vector2(30, 18),
		Vector2(44, 56), Vector2(30, 94), Vector2(0, 104),
	])
	_heart.add_child(_heart_cloak)

	# 火舌：几条会飘的细长舌头，让“黑火”是会动的，而不是一块剪影
	_heart_licks.clear()
	for i in range(4):
		var lick := Polygon2D.new()
		lick.color = Color(0.010, 0.011, 0.016, 0.85)
		lick.position = Vector2(-24.0 + float(i) * 16.0, -70.0 - float(i % 2) * 10.0)
		lick.polygon = PackedVector2Array([
			Vector2(-5, 6), Vector2(-2, -26 - float(i) * 8.0), Vector2(3, -10), Vector2(6, 6),
		])
		_heart.add_child(lick)
		_heart_licks.append({"node": lick, "phase": float(i) * 1.3})

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
	# 轮廓要贴着黑火的形状走，否则会在火焰外面画出一个旧版斗篷的人形
	_heart_outline.points = PackedVector2Array([
		Vector2(-34, 92), Vector2(-46, 54), Vector2(-30, 20), Vector2(-40, -18),
		Vector2(-18, -52), Vector2(-24, -96), Vector2(0, -124), Vector2(10, -88),
		Vector2(24, -104), Vector2(20, -60), Vector2(38, -26), Vector2(44, 56),
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

	# M4-29 组长：一开始只有角色周围一点点有光，别的地方全都看不见。
	# 做法是一整块黑幕挖一个柔和的小洞（洞心跟着灵魂走），而不是把整屏压暗 ——
	# 压暗只是“变灰”，挖洞才是真的“看不见”。
	_dark_mat = ShaderMaterial.new()
	_dark_mat.shader = _make_dark_shader()
	_dark_mat.set_shader_parameter("hole", Vector2(250, 560))
	_dark_mat.set_shader_parameter("radius", 108.0)
	_dark_mat.set_shader_parameter("softness", 118.0)
	_darkness = ColorRect.new()
	_darkness.name = "Darkness"
	_darkness.material = _dark_mat
	_darkness.color = Color(0.0, 0.0, 0.0, 1.0)
	_darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darkness.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_darkness)

	# M4-26 组长定稿：虚无阶段的话直接摆在屏幕正中央 —— 这段是“旁白/内心”，
	# 人物本身几乎没有形体，字跟着角色飘反而像标签。
	# 放在 UI 层且铺满屏幕：不吃镜头缩放，位置永远是正中；仍用慢淡入淡出保持节奏。
	_soul_label = _make_label("Narration", 22, Color(0.80, 0.84, 0.88, 0.95))
	_soul_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_soul_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# M4-39：虚无前半段是内心独白（居中），附身开始后改成字幕位（底部），
	# 让画面中央留给"寄生体化雾钻进来"这件事。位置由 _set_subtitle_mode 切换。
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
	_update_shake(delta)
	_update_darkness()
	_update_descent_pulse(delta)
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

## 屏幕抖动：给 camera.offset 加随机偏移，逐帧衰减
func _shake(duration: float, strength: float) -> void:
	_shake_timer = maxf(_shake_timer, duration)
	_shake_strength = maxf(_shake_strength, strength)

## 黑幕的洞心跟着灵魂走：世界坐标 → 屏幕坐标（相机 zoom 一起算进去）
func _update_darkness() -> void:
	if _dark_mat == null or _soul == null or not is_instance_valid(_soul):
		return
	var cam_pos := Vector2(640, 360)
	var cam_zoom := Vector2.ONE
	if _camera != null and is_instance_valid(_camera):
		cam_pos = _camera.global_position
		cam_zoom = _camera.zoom
	var view := get_viewport().get_visible_rect().size
	var screen := (_soul.global_position - cam_pos) * cam_zoom + view * 0.5
	_dark_mat.set_shader_parameter("hole", screen)
	_dark_mat.set_shader_parameter("screen_size", view)
	# 落地亮起阶段由外部接管半径；平时才是"还活着的一小圈视野"的轻微搏动
	if _dark_radius_override >= 0.0:
		_dark_mat.set_shader_parameter("radius", _dark_radius_override)
	else:
		_dark_mat.set_shader_parameter("radius", 104.0 + sin(_time * 1.5) * 7.0)

func _update_shake(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _shake_timer <= 0.0:
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, 0.35)
		_shake_strength = 0.0
		return
	_shake_timer -= delta
	var k := clampf(_shake_timer / 0.4, 0.0, 1.0)
	_camera.offset = Vector2(
		randf_range(-1.0, 1.0) * _shake_strength * k,
		randf_range(-1.0, 1.0) * _shake_strength * k
	)

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
	# 黑火：火舌各自飘、长度一起一伏，像在往上舔
	for item in _heart_licks:
		var lick := item["node"] as Polygon2D
		if lick == null or not is_instance_valid(lick):
			continue
		var ph := _time * (1.6 + float(item["phase"]) * 0.3) + float(item["phase"])
		lick.rotation = sin(ph) * 0.14
		lick.scale = Vector2(1.0 + sin(ph * 0.7) * 0.18, 1.0 + sin(ph) * 0.22)
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

# ---------- 融合：要有“被夺舍”的张力 ----------
#
# M4-28 组长要求：融入时动画要有张力；融入后一边往下掉，一边变成玩家正常的样子。
#
# 张力靠四件事堆出来：① 镜头猛推 + 屏幕抖动；② 身影不再匀速飘过来，而是分三段“扑”，
# 每扑一次闪一圈冲击环、抖一次；③ 斗篷被扯成几条流线吸进胸口；④ 全程心跳加速。

func _fuse() -> void:
	if _fused:
		return
	_fused = true
	_can_move = false
	_drift = 0.0
	GameManager.set_flag("prologue_seen")

	# 镜头：先猛地推近，压得人喘不过气
	var cam_tw := create_tween()
	cam_tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	cam_tw.tween_property(_camera, "zoom", Vector2(1.42, 1.42), 0.7)
	cam_tw.tween_property(_camera, "position", Vector2(880, 400), 1.2)
	_shake(1.2, 9.0)
	_whisper_heart("……你碰到我了。", 2.2)

	# 心跳加速：越靠近越快、越亮
	var pulse_tw := create_tween()
	pulse_tw.set_loops(6)
	pulse_tw.tween_property(_heart_core, "scale", Vector2(1.9, 1.9), 0.24)
	pulse_tw.parallel().tween_property(_heart_core, "modulate:a", 1.0, 0.24)
	pulse_tw.tween_property(_heart_core, "scale", Vector2(1.2, 1.2), 0.24)
	pulse_tw.parallel().tween_property(_heart_core, "modulate:a", 0.6, 0.24)

	var start := _heart.position
	var target := _soul.position + Vector2(0, -14)
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_callback(func() -> void: _whisper_heart("别急着明白。先把这只手接过去。", 2.2))
	# 三段逼近：每一段都“先缩一下再扑上来”
	for i in range(3):
		var step := float(i + 1) / 3.0
		tw.tween_property(_heart, "scale", Vector2(0.86, 1.06), 0.10)
		tw.parallel().tween_property(_heart, "position", start.lerp(target, step - 0.12 * step), 0.10)
		tw.tween_property(_heart, "scale", Vector2(1.0, 1.0), 0.16)
		tw.parallel().tween_property(_heart, "position", start.lerp(target, step), 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: _punch(i))
		tw.tween_interval(0.20)
	# 吞没：斗篷被扯成流线，整团黑影压进胸口
	tw.tween_callback(_tear_cloak)
	tw.tween_property(_heart, "scale", Vector2(0.22, 0.22), 0.85)
	tw.parallel().tween_property(_heart, "position", target, 0.85)
	tw.parallel().tween_property(_heart_cloak, "modulate:a", 0.0, 0.85)
	tw.tween_callback(_after_fuse)

## 每一次扑击的反馈：冲击环 + 抖动 + 灵魂被“撞歪”一下
func _punch(step: int) -> void:
	_shake(0.30, 7.0 + float(step) * 3.0)
	_ring(_heart.global_position, 40.0 + float(step) * 26.0, Color(0.78, 0.62, 0.92, 0.55))
	var tw := create_tween()
	tw.tween_property(_soul, "scale", Vector2(1.18, 0.86), 0.08)
	tw.tween_property(_soul, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_ELASTIC)

## 冲击环：一圈迅速胀开、变淡的线，读完就自己删掉
func _ring(at: Vector2, radius: float, color: Color) -> void:
	var ring := Line2D.new()
	ring.width = 2.2
	ring.default_color = color
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * 8.0, sin(a) * 8.0))
	ring.points = pts
	ring.closed = true
	ring.position = to_local(at)
	ring.z_index = 4
	add_child(ring)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector2(radius / 8.0, radius / 8.0), 0.35)
	tw.parallel().tween_property(ring, "default_color:a", 0.0, 0.35)
	tw.tween_callback(ring.queue_free)

## 斗篷被扯成几条流线，往灵魂胸口里流
func _tear_cloak() -> void:
	_shake(0.45, 10.0)
	for i in range(5):
		var strip := Line2D.new()
		strip.width = 2.6
		strip.default_color = Color(0.22, 0.20, 0.30, 0.85)
		var from := _heart.global_position + Vector2(float(i) * 9.0 - 18.0, -30.0 + float(i) * 10.0)
		strip.points = PackedVector2Array([to_local(from), to_local(from)])
		strip.z_index = 3
		add_child(strip)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# Line2D 的 points 是 PackedVector2Array，不能被单点补间；直接整体平移这条流线
		tw.tween_property(strip, "position", _soul.global_position - from, 0.5 + float(i) * 0.06)
		tw.parallel().tween_property(strip, "modulate:a", 0.0, 0.5 + float(i) * 0.06)
		tw.tween_callback(strip.queue_free)

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

# ---------- 从虚空落到地面：边坠边变身 ----------
#
# M4-28：融入之后不是“淡出 + 切场景”，而是 —— 脚下的虚空托不住你了，
# 你一边往下坠，身上那层灰白的魂光一边褪掉、显出兜帽骑士的轮廓，
# 最后带着速度砸进教学关（教学关那边 _drop_in 接住，落地扬尘）。

## M4-39：附身之后是一镜到底的 60 秒下落演出。
## 躯干从灵魂形长成主角模样，镜头始终把人放在画面中间并缓慢拉远，
## 环境明暗跟着鼓点走（5s 一拍渐快到 1s 一拍），落地前停在"暗"的那一拍，
## 静一秒后从玩家身上向外亮起，直接接教学关。
func _begin_descent() -> void:
	if _descending:
		return
	_descending = true
	_can_move = false
	_set_subtitle_mode(true)
	_desc_phase = 1
	_desc_t = 0.0
	_beat_accum = _beat_interval

	# 魂光褪掉、骑士显形（生长交给下面那条 tween，贯穿整个下落）
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_soul_core, "modulate:a", 0.0, 2.5)
	tw.tween_property(_soul_haze, "modulate:a", 0.0, 2.5)
	tw.tween_property(_knight, "modulate:a", 1.0, 4.0)
	tw.tween_property(_knight, "scale", Vector2(1.0, 1.0), FALL_TIME * 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 一直往下掉，镜头在 _update_descent_pulse 里始终锁住玩家
	var fall := create_tween()
	fall.tween_property(_soul, "position:y", SOUL_START.y + 4200.0, FALL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_callback(_desc_hold_dark)

## 下落期间的节拍器：鼓点间隔从 5s 收紧到 1s，明暗与它同拍
func _update_descent_pulse(delta: float) -> void:
	if _desc_phase == 0:
		return
	_beat_flash = maxf(_beat_flash - delta * 3.2, 0.0)
	if _desc_phase != 1:
		return

	_desc_t += delta
	var k := clampf(_desc_t / FALL_TIME, 0.0, 1.0)
	_beat_interval = lerpf(BEAT_START, BEAT_END, k * k)
	_beat_accum += delta
	if _beat_accum >= _beat_interval:
		_beat_accum = 0.0
		_beat_flash = 1.0
		# 鼓点先用现有的低频受击音顶位，音量压到底只留"咚"的质感
		GameManager.play_sfx("hit_flesh", -12.0, 0.55)

	_camera.position = Vector2(640.0, _soul.global_position.y)
	_camera.zoom = Vector2.ONE * lerpf(_desc_zoom_from, _desc_zoom_to, k)
	if _vignette != null:
		_vignette.modulate.a = clampf(0.62 + 0.34 * _beat_flash, 0.0, 1.0)

## 停在"暗"的那一拍：不闪、不动，等一秒
func _desc_hold_dark() -> void:
	_desc_phase = 2
	_beat_flash = 0.0
	_beat_accum = 0.0
	if _vignette != null:
		_vignette.modulate.a = 0.96
	await get_tree().create_timer(HOLD_DARK).timeout
	_desc_reveal()

## 从玩家向外亮：黑幕挖洞半径撑开，暗角褪到只剩一点，然后进教学关
func _desc_reveal() -> void:
	_desc_phase = 3
	var tw := create_tween()
	tw.set_parallel(true)
	if _vignette != null:
		tw.tween_property(_vignette, "modulate:a", 0.28, REVEAL_TIME)
	if _dark_mat != null:
		tw.tween_method(_set_dark_radius, 104.0, 1400.0, REVEAL_TIME)
	tw.chain().tween_interval(0.4)
	tw.chain().tween_callback(_leave)

func _set_dark_radius(r: float) -> void:
	_dark_radius_override = r

## 附身开始后旁白从画面中央降到字幕位，把中央让给"黑雾钻进来"
func _set_subtitle_mode(on: bool) -> void:
	if _soul_label == null:
		return
	_soul_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if on else VERTICAL_ALIGNMENT_CENTER
	_soul_label.offset_bottom = -84.0 if on else 0.0

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

## 黑幕挖洞：屏幕像素到洞心的距离落在 radius 内全透明，radius+softness 之外全黑，
## 中间用 smoothstep 过渡，所以边界是柔的，不会出现一个硬边圆。
const DARK_SHADER := """
shader_type canvas_item;
uniform vec2 hole = vec2(640.0, 360.0);
uniform float radius = 110.0;
uniform float softness = 120.0;
uniform vec2 screen_size = vec2(1280.0, 720.0);
void fragment() {
	vec2 px = UV * screen_size;
	float d = distance(px, hole);
	float a = smoothstep(radius, radius + softness, d);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

func _make_dark_shader() -> Shader:
	var shader := Shader.new()
	shader.code = DARK_SHADER
	return shader

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
