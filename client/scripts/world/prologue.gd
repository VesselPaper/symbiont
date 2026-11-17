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
	{"at": 2.8, "text": "无垠之间，你缓缓苏醒。万般皆不可触及，连自我，都难以辨认。", "hold": 5.2},
	{"at": 9.4, "text": "一份根植于灵魂的渴望被唤醒，你向着虚无前进。", "hold": 5.4},
	{"at": 16.6, "text": "到这来，迷途的旅人，到这来。", "hold": 5.6},
]
## 融合后的独白：同样避开“它进来了”这种直白结论，写成身体上发生的事
const AFTER_FUSE := [
	{"delay": 1.4, "text": "过来，再靠近些，不必踌躇脚下的道路，到我这来。", "hold": 3.2},
	{"delay": 5.2, "text": "迷途的旅人，到这来。触碰我……感受我……吞噬我……", "hold": 3.6},
	{"delay": 9.2, "text": "刺痛穿过掌心，你再次感受到自我。胸膛、四肢，连脸庞都逐渐清晰。", "hold": 3.6},
	{"delay": 13.6, "text": "感知接踵而至，直到下坠感充满全身。你不再迷茫，任由自己坠入深渊。", "hold": 4.2},
]

var _soul: Node2D
var _heart: Node2D
var _soul_core: Polygon2D
var _soul_haze: Polygon2D
var _soul_tendrils: Array[Line2D] = []
var _soul_reflection: Polygon2D
var _soul_glow: PointLight2D
var _heart_core: Sprite2D
## M4-54：黑影的"体"换成着色器画的烟（components/shadow_mass.gd），不再有折线外框
var _shadow: Node2D
var _heart_cloak: Node2D
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
## 黑幕挖洞参数（M4-54 起黑火的火舌已并入烟体着色器，不再有单独的火舌节点）
## 胸口那点紫的默认尺寸：贴图 256px，scale = 半径(px) / 128
const CORE_BASE := Vector2(0.062, 0.070)
const CAVITY_BASE := Vector2(0.19, 0.21)
## 心跳脉冲的乘数：由 _fuse 的 tween 写，_update_heart 每帧读它来算最终尺寸。
## 这么绕是因为 scale 只能有一个写者，否则脉冲会被逐帧覆盖（见 _update_heart 注释）
var _core_pulse := 1.0

var _time := 0.0
var _beat_index := 0
var _can_move := false
var _fused := false
var _descending := false
## 下落演出的节拍与脉冲：鼓点从 5s 一拍渐快到 1s 一拍，明暗与它同拍
const BEAT_START := 5.0
const BEAT_END := 1.0
const MIST_TIME := 10.0     # 黑雾钻进身体的过程
## M4-64（组长定的新节奏）：灵魂保持原样一直往下掉，掉够一段时间后，
## 在某一次"暗 → 亮"的拍点上**直接**变成主角（不是慢慢长），然后继续全速下落。
const DESCENT_TIME := 30.0       # 下坠总时长（原来 20 秒，组长要再加 10 秒）
const TRANSFORM_AT := 8.0        # 掉这么久之后遇到的下一个"暗→亮"拍点就变身
const VOID_BLACK_TIME := 3.0     # 结尾全黑 3 秒（鼓照打）
## 虚空里长成的主角是教学关的两倍大（镜头没动，动的是角色自身缩放）
const KNIGHT_VOID_SCALE := 2.0
const TERMINAL_FALL_SPEED := 1500.0 # 演出用：比角色正常下落更快，才有坠落感
const FALL_GRAVITY := 2550.0        # 与 player.gd 的 GRAVITY 一致
const REVEAL_TIME := 2.0
var _desc_phase := 0            # 0 静止 / 1 下落 / 2 结尾全黑
var _desc_t := 0.0
var _form_t := 0.0
## 已经变成主角了吗（M4-64 改成拍点上一瞬间切换，不再按进度生长）
var _transformed := false
## 变身那一拍按的黑屏（等下一拍"亮"才撤），这段时间不要按明暗拍写 alpha
## 变身那一拍按的黑屏（等下一拍"亮"才撤），这段时间不要按明暗拍写 alpha
var _transform_black := false
## M4-66：虚空下坠时斗篷的两片布（序章没有 player.gd，布料得自己驱）
var _k_cloak_tail: Node2D
var _k_cloak_hem: Node2D
var _k_cape: Node2D
var _void_wind_t := 0.0
## 结尾那一拍：等下一次鼓点到了才砸黑（组长要求"最后一下也要进鼓"）
var _final_pending := false
var _black_t := 0.0
var _fall_vy := 0.0
var _beat_accum := 0.0
var _beat_interval := BEAT_START
var _beat_flash := 0.0
var _beat_dark := false
var _desc_zoom_from := 1.42
## M4-64：镜头保持原样（1.42 → 0.80），否则灵魂会跟着一起变大。
## "主角变大两倍"改成角色自己缩放（KNIGHT_VOID_SCALE），灵魂、光核、背景都不受影响。
var _desc_zoom_to := 0.80
## 亮起阶段接管黑幕半径（-1 表示仍用呼吸值）
var _dark_radius_override := -1.0
## 全屏忽明忽暗用的遮罩（暗角只压边缘，这里压整屏）
var _pulse_rect: ColorRect
var _ui_layer: CanvasLayer
var _descent_bg: Node2D
var _bg_scroll := 0.0
var _bg_nodes: Array = []
var _cam_following := false
var _leaving := false
var _called_out := false
var _drift := 0.0
var _tilt := 0.0
var _bob := 0.0
var _note_tween: Tween
var _heart_note_tween: Tween
## M4-55：坠落时长出来的"玩家正常样子"。直接实例化主角的身体美术
## （scenes/player/knight_body.tscn，player.tscn 自己也用这一份），
## 所以"灵魂长成的角色"和"教学关里操控的角色"永远是同一副，不会各画一份后漂移。
const KNIGHT_SCENE := preload("res://scenes/player/knight_body.tscn")
## 生长起点：小到一个点，读起来是"从核心里长出来"而不是"放大一张画"
const GROW_SCALE_FROM := 0.16
## 各部件依次成形的区间（0~1，对应 _grow）：身前斗篷 → 黑身 → 头盔 → 盔壳细节。
## M4-64 起 _grow 只有 0 和 1 两个值（拍点上一瞬间变身），所以这张表实际只在
## "0 → 1 那一下"被用一次；留着是因为以后若要恢复"慢慢长"，改一行调用就回来了。
## 分先后是画面的全部看头：一起淡入就是"图层变亮了"，依次长出来才是"长成一个人"。
## 眼睛不单独列：它是头盔贴图里的像素，末尾那一下"亮起来"交给 EyeGlow
## （_apply_growth 里 0.82~0.98 那段）。
## 路径必须和 knight_body.tscn 里的节点名一致（M4-61 换成第二版渲染图分层后重新接的）。
const GROW_PARTS := [
	["Cape", 0.00, 0.30], ["CloakTail", 0.04, 0.34], ["Silhouette", 0.10, 0.40],
	["Head", 0.12, 0.42], ["Head/Skull", 0.16, 0.44],
]
var _knight: Node2D
## 部件缓存：路径 → 节点。每帧按 GROW_PARTS 的区间算 alpha，不再逐个 get_node
var _k_parts: Dictionary = {}
## 生长进度 0~1（_update_descent_pulse 写）与魂体让位系数 0~1（_update_soul 读）
var _grow := 0.0
var _soul_fade := 1.0
## 身体自带的光与兜帽里的眼灯：都按生长进度点亮，让"长出来"看得见（M4-55）
var _k_body_glow: PointLight2D
var _k_eye_glow: PointLight2D
var _k_eye_energy_base := 0.35
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
		# 二周目已经见过它了：一进场就显形，不用再走近才看清
		if _shadow != null and is_instance_valid(_shadow):
			_shadow.call("set_reveal", 1.0)
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

	# 雾柱：竖着立起来的几缕烟。
	# M4-54：原来是四点多边形 + 顶点 alpha，竖直边是硬的，透光时能看出一道直边。
	# 现在用径向渐变的椭圆拉成柱，透明度全交给贴图 —— 边缘自己化开，没有边线。
	_mist_columns.clear()
	for i in range(5):
		var col := Sprite2D.new()
		col.z_index = -17
		var x := 160.0 + float(i) * 240.0
		var w := 90.0 + float(i % 3) * 40.0
		col.texture = _radial_texture()
		col.position = Vector2(x, 350.0)
		col.scale = Vector2(w / 256.0, 940.0 / 256.0)
		col.modulate = Color(0.34, 0.44, 0.56, 0.055 + float(i % 3) * 0.018)
		add_child(col)
		_mist_columns.append({"node": col, "phase": float(i) * 1.4, "speed": 0.6 + float(i % 3) * 0.25})

	# 远景碎影：远处几团几乎看不见的暗形，慢慢左右偏一点，制造"远处还有东西"的错觉。
	# M4-54：同样换成柔边椭圆。原来那四个尖角多边形在黑底上就是一排黑纸片，
	# 光圈照到时边缘一根直线，比不做还出戏。
	_far_shards.clear()
	for i in range(6):
		var shard := Sprite2D.new()
		shard.z_index = -18
		var x := 120.0 + float(i) * 210.0
		var h := 120.0 + float(i % 3) * 70.0
		shard.texture = _radial_texture()
		shard.position = Vector2(x, 760.0 - h * 0.5)
		shard.scale = Vector2(46.0 / 256.0, h / 256.0)
		shard.modulate = Color(0.028, 0.034, 0.046, 0.62)
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

	# M4-55：玩家正常样子 = 主角的身体美术本体（knight_body.tscn），先缩成一个点、
	# 部件全透明地藏在灵魂里，坠落时按 GROW_PARTS 依次长出来。
	_knight = KNIGHT_SCENE.instantiate()
	_knight.name = "Knight"
	_knight.position = Vector2(0, -6)
	_knight.scale = Vector2.ONE * GROW_SCALE_FROM
	_soul.add_child(_knight)
	_k_parts.clear()
	for entry in GROW_PARTS:
		var path := str(entry[0])
		var node := _knight.get_node_or_null(path) as CanvasItem
		if node == null:
			push_warning("prologue: 主角身体上找不到部件 %s，这一段会缺一块" % path)
			continue
		_k_parts[path] = node
		var col := node.modulate
		col.a = 0.0
		node.modulate = col
	# 生长表里没列到的部件也必须先藏起来：
	# 列漏一个，那个部件就会从第一帧起一直挂在魂体上（M4-58 加鼻梁条时就漏过一次）。
	# 灯和挥砍弧线不算：灯要靠 energy 控制，弧线本来 visible=false。
	for child in _knight.get_children():
		var ci := child as CanvasItem
		if ci == null:
			continue
		if _k_parts.has(str(ci.name)) or str(ci.name) in ["EyeGlow", "SlashArc", "SlashDown"]:
			continue
		var col2 := ci.modulate
		col2.a = 0.0
		ci.modulate = col2
	# 这时候还没拿到铁剑，而且角色手里本来就不挂剑（M4-56）：剑节点已经不存在了，
	# 这里只保留"如果有剑就藏起来"的兼容分支，防止以后又把剑加回来时忘了藏。
	var sword := _knight.get_node_or_null("ArmPivot/SwordPivot") as Node2D
	if sword != null:
		sword.visible = false
	# M4-66：虚空下坠时斗篷要飘（组长：幅度和角度都要比教学关更大）。
	# 这里把两片布的节点先拿到手，逐帧写角度 —— 序章里的角色是"展示用"的，
	# 没有 player.gd 那套布料逻辑，所以只能由序章自己驱。
	_k_cloak_tail = _knight.get_node_or_null("CloakTail") as Node2D
	_k_cloak_hem = _knight.get_node_or_null("CloakTail/CloakHem") as Node2D
	_k_cape = _knight.get_node_or_null("Cape") as Node2D
	# M4-71：虚空里的人**没有眼睛**（组长定的）。眼睛是单独一层，
	# 这里直接把它压成透明，一直压到切教学关为止 —— 那边是另一份玩家实例，默认就是亮的。
	var eyes := _knight.get_node_or_null("Head/Eyes") as CanvasItem
	if eyes != null:
		eyes.modulate.a = 0.0


	# 身体自带一盏冷光：主角美术是深色的（0.03~0.2），在虚空里没有光照就是一团黑。
	# 魂光褪下去以后，光要跟着身体走，否则"长出来"这件事根本看不见（M4-55）。
	var body_glow := PointLight2D.new()
	body_glow.name = "BodyGlow"
	body_glow.texture = _radial_texture()
	body_glow.texture_scale = 1.8
	body_glow.color = Color(0.72, 0.82, 0.98)
	body_glow.energy = 0.0
	body_glow.position = Vector2(0, -6)
	_knight.add_child(body_glow)
	_k_body_glow = body_glow
	# 兜帽里那只眼睛的光也跟着生长进度走：它一亮，人物才算"活了"
	_k_eye_glow = _knight.get_node_or_null("EyeGlow") as PointLight2D
	if _k_eye_glow != null:
		_k_eye_energy_base = _k_eye_glow.energy
		_k_eye_glow.energy = 0.0

# ---------- 身影 ----------

func _build_heart() -> void:
	_heart = Node2D.new()
	_heart.name = "Heart"
	_heart.position = HEART_POS
	_heart.z_index = 1
	add_child(_heart)

	# M4-54 组长："黑影太幼稚了，改得真实一点、质量高一点"。
	# 原版是 15 个顶点的折线剪影 + 4 个三角形火舌 + 2 个三角尖刺 + 一圈 Line2D 外框；
	# 镜头推到 1.4~1.7 倍时每条边都有几十像素长，看到的就是一堆直线。
	# 现在整团交给 components/shadow_mass.gd：密度逐像素算，边缘连续化到 0、
	# 被噪声推着缓慢翻滚、朝灵魂那一侧有一道冷色背光 —— 用体本身把轮廓读出来。
	_shadow = preload("res://components/shadow_mass.gd").new()
	_shadow.name = "Body"
	_heart.add_child(_shadow)
	# 变量名沿用 _heart_cloak：_fuse 里按 modulate:a 淡出、_update_heart 里左右微摆，
	# 这两件事对烟体一样成立，指过去即可，不必再动那两处。
	_heart_cloak = _shadow

	# 胸口那点紫：整团黑影里唯一"看得见的器官"，心跳和说话都落在它身上。
	# M4-54：原来是两个多边形椭圆，贴到 1.7 倍镜头下就是一个硬边圆饼；
	# 现在用径向渐变贴图（边缘自己化开），才像是"从烟里透出来的光"。
	# 凹坑半径约 24px、核心约 8px（贴图 256px，scale = 半径/128）
	var cavity := Sprite2D.new()
	cavity.name = "Cavity"
	cavity.texture = _radial_texture()
	cavity.position = Vector2(0, -18)
	cavity.scale = CAVITY_BASE
	cavity.modulate = Color(0.020, 0.014, 0.026, 0.95)
	_heart.add_child(cavity)
	# M4-54：胸口那点紫改成 Sprite2D + 径向渐变，尺寸语义跟着变了：
	# 贴图是 256px，scale = 半径(px)/128，所以 7.5px 的核心是 0.06 这一档。
	# 这两个常量就是"默认大小"，动画只写乘数，不去动 scale 本身。
	_heart_core = Sprite2D.new()
	_heart_core.name = "Core"
	_heart_core.texture = _radial_texture()
	_heart_core.position = Vector2(0, -18)
	_heart_core.scale = CORE_BASE
	_heart_core.modulate = Color(0.66, 0.50, 0.78, 0.62)
	_heart.add_child(_heart_core)

# ---------- UI ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_ui_layer = layer
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
	# M4-44：融合阶段就开始把镜头往角色身上靠，黑雾钻进来时人才在画面正中
	if _desc_phase == 0 and _fused:
		_camera.position = _camera.position.lerp(_soul.global_position, 1.0 - exp(-4.0 * delta))
	_update_descent_pulse(delta)
	_update_void_cloth(delta)
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
	# M4-55：魂体的透明度一律乘上 _soul_fade。生长一开始它就得让位给长出来的身体，
	# 这里若直接写死 alpha，_apply_growth 算出来的让位会被这一行每帧盖掉。
	_soul_haze.modulate.a = (0.85 + sin(_bob * 1.1) * 0.15) * _soul_fade
	_soul_core.modulate.a = _soul_fade
	if _soul_glow != null and is_instance_valid(_soul_glow):
		_soul_glow.energy = (1.15 + sin(_bob * 1.4) * 0.12) * _soul_fade
	for t in _soul_tendrils:
		if t != null and is_instance_valid(t):
			var col := t.modulate
			col.a = _soul_fade
			t.modulate = col
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
	# 胸口的紫：尺寸只由这里写（M4-54 踩过的坑 —— 换 Sprite2D 后 scale=1.9 不再是
	# "1.9 倍"，而是 1.9×256px 的大白团；另外 _fuse 的心跳脉冲如果也去 tween scale，
	# 就成了一个属性两个写者，脉冲会被这一行逐帧盖掉。改成写乘数 _core_pulse）
	_heart_core.scale = Vector2(CORE_BASE.x, CORE_BASE.y) * (0.9 + beat * 0.35) * _core_pulse
	_heart_core.modulate.a = (0.45 + beat * 0.35) * clampf(_core_pulse, 0.0, 1.6)
	# 走近才显形：远的时候只剩一层很淡的黑（0.25），贴到跟前才压实。
	# 显形靠烟体自己的密度，不再画外框 —— 一画外框就又变回"贴纸"。
	if _shadow != null and is_instance_valid(_shadow) and _soul != null and is_instance_valid(_soul):
		var dist := _soul.global_position.distance_to(_heart.global_position)
		var reveal := clampf((REVEAL_DISTANCE - dist) / REVEAL_DISTANCE, 0.0, 1.0)
		_shadow.call("set_reveal", 0.25 + reveal * 0.75 + beat * 0.03)
		# 灵魂在哪一侧，背光就落在哪一侧（着色器要的是体的局部坐标）
		_shadow.call("set_light_local", to_local(_soul.global_position) - _heart.position)
	# 整团被气流推着左右晃，不是钉在地上一动不动的剪影
	if _heart_cloak != null and is_instance_valid(_heart_cloak):
		_heart_cloak.position.x = sin(_time * 0.7) * 3.2
	_heart.scale = Vector2(1.0 + sin(_time * 0.5) * 0.012, 1.0 + sin(_time * 0.5 + 1.2) * 0.014)

## 生长进度（0~1）：一次写完"身体到哪一步"和"魂体让了多少位"。
## 只让这一个函数写 scale 与 alpha，_update_soul 只读 _soul_fade —— 一个属性一个写者，
## 否则呼吸的逐帧赋值会把生长结果盖掉（黑影那边刚踩过同一个坑）。
func _apply_growth(k: float) -> void:
	_grow = clampf(k, 0.0, 1.0)
	# 先慢后快再收：前半段在"攒形体"，后半段一口气站起来，末尾减速免得定格太硬
	var e := _grow * _grow * (3.0 - 2.0 * _grow)
	if _knight != null and is_instance_valid(_knight):
		# M4-64：虚空里长成的角色是教学关的两倍大（镜头没动，灵魂也就没变大）
		_knight.scale = Vector2.ONE * lerpf(GROW_SCALE_FROM, KNIGHT_VOID_SCALE, e)
		for entry in GROW_PARTS:
			var node: CanvasItem = _k_parts.get(str(entry[0]))
			if node == null or not is_instance_valid(node):
				continue
			var from := float(entry[1])
			var to := float(entry[2])
			var a := clampf((_grow - from) / maxf(to - from, 0.001), 0.0, 1.0)
			var col := node.modulate
			if not is_equal_approx(col.a, a):
				col.a = a
				node.modulate = col
	# 魂体让位：前半段就褪干净，别和刚长出来的身体抢画面。
	# 1.6 而不是 2.4：褪得太快会出现"魂没了、身体才长了一半"的空档
	_soul_fade = clampf(1.0 - _grow * 1.6, 0.0, 1.0)
	# 光跟着身体走：魂光褪下去时，身体自己带的光接上来，否则深色美术在虚空里等于隐形
	if _k_body_glow != null and is_instance_valid(_k_body_glow):
		_k_body_glow.energy = 0.95 * e
	if _k_eye_glow != null and is_instance_valid(_k_eye_glow):
		var eye_a := clampf((_grow - 0.82) / 0.16, 0.0, 1.0)
		_k_eye_glow.energy = _k_eye_energy_base * eye_a


## 化雾进度（0~1）：从外缘往里被抽走。用 tween_method 推，是为了让"被抽干"
## 有一个连续的过程，而不是到点整团消失。
func _set_shadow_dissolve(v: float) -> void:
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.call("set_dissolve", v)

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
	# 注意：这里只推 zoom，不动 position —— 位置由 _process 里的跟随统一负责，
	# 两边同时写位置会互相拉扯，表现就是"人一会儿在中间、一会儿被甩到右下角"
	var cam_tw := create_tween()
	cam_tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	cam_tw.tween_property(_camera, "zoom", Vector2(1.42, 1.42), 0.7)
	_shake(1.2, 9.0)
	_whisper_heart("……你碰到我了。", 2.2)

	# 心跳加速：越靠近越快、越亮。
	# M4-54：不再 tween _heart_core.scale —— 尺寸归 _update_heart 写，
	# 这里只推乘数 _core_pulse，否则两处写同一个属性，脉冲会被逐帧盖掉。
	var pulse_tw := create_tween()
	pulse_tw.set_loops(6)
	pulse_tw.tween_property(self, "_core_pulse", 1.45, 0.24)
	pulse_tw.tween_property(self, "_core_pulse", 0.95, 0.24)

	var start := _heart.position
	var target := _soul.position + Vector2(0, -14)
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_callback(func() -> void: _whisper_heart("别急着明白。先把这只手接过去。", 2.2))
	# M4-41：不再"扑过来三次、每次放大缩小"。本心在原地直接化成黑烟，
	# 由烟自己收进胸口（视觉交给 components/shadow_mass.gd + dark_swarm.gd）。
	tw.tween_callback(_heart_scatter)
	# 黑雾钻进身体的过程放慢到 10 秒。
	# M4-54：不再把整团缩成一个点（那是"贴纸缩小"，不是被抽干），
	# 改成外缘一路往里被抽走；位置仍然慢慢被拽向胸口，留下"被拖过去"的感觉。
	tw.tween_method(_set_shadow_dissolve, 0.0, 1.0, MIST_TIME)
	tw.parallel().tween_property(_heart, "scale", Vector2(0.62, 0.62), MIST_TIME)
	# M4-54：前 3.6 秒就压到身上，之后停在那儿被慢慢抽干。
	# 原本用满 10 秒挪过去，结果整段时间它都停在光圈外，玩家只看见几粒黑点，
	# 根本看不见"有个东西在吃你"—— 这段演出真正要看的就是这一下。
	tw.parallel().tween_property(_heart, "position", target, 3.6)
	tw.parallel().tween_property(_heart_cloak, "modulate:a", 0.0, MIST_TIME)
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

## 化雾：本心炸成一大片黑雾，收成漏斗钻进胸口，人跟着抖
func _heart_scatter() -> void:
	# 换成大量黑色粒子持续涌进身体
	var swarm = preload("res://components/dark_swarm.gd").new()
	swarm.name = "DarkSwarm"
	swarm.z_index = 3
	add_child(swarm)
	swarm.play(_heart.global_position, _soul.global_position + Vector2(0, -12), MIST_TIME)
	_shake(1.4, 6.0)
	# 身体抖动：不是整体平移，是高频小幅缩放 + 左右微摆，读起来像"有东西钻进来"
	var jitter := create_tween()
	jitter.set_loops(34)
	jitter.tween_property(_soul, "scale", Vector2(1.04, 0.97), 0.06)
	jitter.tween_property(_soul, "scale", Vector2(0.97, 1.03), 0.06)
	jitter.tween_property(_soul, "scale", Vector2(1.0, 1.0), 0.08)
	EventBus.log_event("parasite_enter", {})

func _after_fuse() -> void:
	if _heart != null and is_instance_valid(_heart):
		_heart.queue_free()
	# M4-40：不再先站定把话说完再掉。附身一结束立刻开始下坠，
	# 后面的旁白在坠落途中作为字幕逐条出现（与下落并行，不额外占时间）。
	_begin_descent()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_soul_glow, "texture_scale", 2.9, 2.0)
	tw.parallel().tween_property(_soul_glow, "color", Color(0.92, 0.95, 0.90), 2.0)
	for item in AFTER_FUSE:
		tw.tween_interval(float(item["delay"]))
		tw.tween_callback(func() -> void: _whisper_soul(str(item["text"]), float(item["hold"])))
	tw.tween_interval(4.0)
	tw.tween_callback(func() -> void: _whisper(1, "想看见的话，就把身上多余的部分交出来。我不急，我等得起。", 4.6, true))

# ---------- 从虚空落到地面：边坠边变身 ----------
#
# M4-28：融入之后不是“淡出 + 切场景”，而是 —— 脚下的虚空托不住你了，
# 你一边往下坠，身上那层灰白的魂光一边褪掉、显出兜帽骑士的轮廓，
# 最后带着速度砸进教学关（教学关那边 _drop_in 接住，落地扬尘）。

## M4-39：附身之后是一镜到底的下落演出。
## M4-64（组长定的新节奏）：灵魂保持原样一直往下掉；掉够 TRANSFORM_AT 之后，
## 在某一次"暗 → 亮"的拍点上**直接**变成主角（不是慢慢长出来），然后继续全速下落；
## 掉满 DESCENT_TIME 之后的**下一拍**把画面砸成全黑（"最后一下也进鼓"），
## 全黑维持 VOID_BLACK_TIME 秒、鼓照打，再切教学关（那边一开始也靠鼓接住）。
func _begin_descent() -> void:
	if _descending:
		return
	_descending = true
	_can_move = false
	_set_subtitle_mode(true)
	_desc_phase = 1
	_desc_t = 0.0
	_form_t = 0.0
	_transformed = false
	_transform_black = false
	_final_pending = false
	_black_t = 0.0
	_fall_vy = 0.0
	_cam_following = false
	# 镜头从融合时的位置接着拉远（1.42 → 0.80）。灵魂、光核、背景都保持原来的大小，
	# "主角两倍大"由角色自己的 scale 负责 —— 这样灵魂不会被镜头一起放大（组长点名要的）。
	_desc_zoom_from = _camera.zoom.x
	_beat_accum = _beat_interval
	_build_pulse_rect()
	_build_descent_bg()
	# 拉远后会把虚空里那些装饰（体积光/雾柱/远影）露出来，看着像"左边冒出地图"，一并收掉
	for arr in [_depth_glows, _mist_columns, _far_shards]:
		for item in arr:
			var n = item.get("node", null)
			if n != null and is_instance_valid(n):
				n.visible = false

	# 魂光褪掉、身体长出来，都由 _apply_growth 按同一进度推进（不再各自 tween：
	# 一个属性两个写者，表现就是"有时长出来、有时卡住"）
	_apply_growth(0.0)



## 下落期间的节拍器：鼓点间隔从 5s 收紧到 1s，音量渐强，明暗与它同拍。
## 速度按角色正常物理下落（重力加速到终端速度 900），不再用固定时长的 tween。
func _update_descent_pulse(delta: float) -> void:
	if _desc_phase == 0:
		return
	_beat_flash = maxf(_beat_flash - delta * 3.2, 0.0)

	# 结尾全黑那 3 秒：人不再往下掉，只有鼓还在打，打满就切场景。
	# 鼓必须一直响到教学关接手为止（组长："鼓不要停，在教学关时停"）。
	if _desc_phase == 2:
		_black_t += delta
		_tick_beat(delta, 1.0)
		if _black_t >= VOID_BLACK_TIME:
			_leave()
		return

	_form_t += delta

	# 物理下落：重力加速到终端速度
	_fall_vy = minf(_fall_vy + FALL_GRAVITY * delta, TERMINAL_FALL_SPEED)
	_soul.position.y += _fall_vy * delta

	# 变身之前灵魂保持原样（_grow 一直是 0），变身后直接满格 —— 没有中间态
	_apply_growth(1.0 if _transformed else 0.0)

	# 鼓点：从 5s 一拍线性收紧到 1s 一拍，之后一直保持 1s 一拍
	var ramp_span := maxf(DESCENT_TIME - 5.0, 0.1)
	_beat_interval = lerpf(BEAT_START, BEAT_END, clampf(_form_t / ramp_span, 0.0, 1.0))
	_tick_beat(delta, clampf(_form_t / DESCENT_TIME, 0.0, 1.0))

	# 镜头：先平滑靠过去（避免一帧瞬移=闪现），再用"速度前馈 + 残差修正"紧跟。
	# 只用 lerp 会恒定落后 v/rate（900px/s 时差 180px），人就被甩到画面上方。
	var ff := clampf(_form_t / 0.6, 0.0, 1.0)
	_camera.position.y += _fall_vy * ff * delta
	var err := _soul.global_position - _camera.position
	_camera.position += err * (1.0 - exp(-12.0 * delta))
	_camera.offset = Vector2.ZERO
	_camera.zoom = Vector2.ONE * lerpf(_desc_zoom_from, _desc_zoom_to,
		clampf(_form_t / DESCENT_TIME, 0.0, 1.0))

	# 背景：以镜头为中心循环滚动，落下多久都不会露底
	if _descent_bg != null:
		_descent_bg.position = _camera.position - Vector2(0, 360)
		_bg_scroll += _fall_vy * 0.45 * delta
		for it in _bg_nodes:
			var span := 2800.0
			var y := fposmod(float(it["y0"]) - _bg_scroll + 1400.0, span) - 1400.0
			(it["node"] as Node2D).position.y = y

	_dark_radius_override = 104.0 + 300.0 * clampf(_form_t / DESCENT_TIME, 0.0, 1.0)
	# 注意：_tick_beat 里可能已经把画面砸成全黑了（phase 翻成 2，或正在变身那一拍的黑屏），
	# 这时候再按明暗拍写 alpha 会把它改回 0.62 —— 黑就"闪了一下"。
	if _pulse_rect != null and _desc_phase == 1 and not _transform_black:
		_pulse_rect.color.a = 0.62 if _beat_dark else 0.0

	# 掉满之后不立刻砸黑：等下一次鼓点（_tick_beat 里处理），这样"最后一下"是踩着鼓的
	if _form_t >= DESCENT_TIME:
		_final_pending = true

## 虚空下坠时的斗篷（M4-66）：风是从下往上灌的，所以布不是"轻轻摆"，
## 而是被整片掀起来、还在抖。组长要求幅度和角度都比教学关大一截，具体是：
##   角度基线：上段 +0.85 rad、下摆 +1.25 rad（约 49°/72°，布几乎被吹平）
##   抖动：上段 ±0.28、下摆 ±0.42（两块错开相位，不然像一块硬板）
##   斜切：上段 ±0.12、下摆 ±0.26（布被风推着横向走）
##   横移：下摆再整体往后错一点，读作"布被甩到身后"
## 变身之前角色是隐形的，这段动画只在变身后才看得见，所以直接跟着 _transformed 走。
func _update_void_cloth(delta: float) -> void:
	if _knight == null or not is_instance_valid(_knight):
		return
	if _k_cloak_tail == null or _k_cloak_hem == null:
		return
	# 布在风里要有"自己的节奏"：频率和鼓点无关，否则每一下都像被鼓抽了一下
	_void_wind_t += delta
	var t := _void_wind_t
	var fade := clampf(_grow, 0.0, 1.0)   # 没变身时布还是坏的，不用管
	var swing_a := sin(t * 2.6) * 0.25 + sin(t * 4.3 + 1.1) * 0.08
	var swing_b := sin(t * 3.1 - 0.9) * 0.22 + sin(t * 5.2 + 0.5) * 0.06
	var gust_a := sin(t * 2.2 + 0.7) * 0.10
	var gust_b := sin(t * 2.2 - 0.5) * 0.16
	_k_cloak_tail.rotation = (0.85 + swing_a) * fade
	_k_cloak_tail.skew = gust_a * fade
	# 下摆现在是上段节点的**子节点**：上段转多少它就跟多少，这里只加"自己多甩一点"，
	# 所以接缝处永远是连着的（组长要的"下面那节接在上面那节上"）。
	_k_cloak_hem.rotation = (0.18 + swing_b) * fade
	_k_cloak_hem.skew = gust_b * fade
	# 身后那片斗篷也是布，跟着一起掀；幅度小一点，免得把黑影露缝
	if _k_cape != null:
		_k_cape.rotation = (0.75 + swing_b) * fade
		_k_cape.skew = gust_b * 0.6

## 鼓点推进：到点就换一次明暗、放一声鼓，并顺手办两件"必须卡在鼓点上"的事 ——
## ① 变身为主角（在"暗 → 亮"的那一下，亮起来时人已经是骑士了）
## ② 结尾砸黑（掉满 DESCENT_TIME 之后的第一拍）
func _tick_beat(delta: float, k: float) -> void:
	_beat_accum += delta
	if _beat_accum < _beat_interval:
		return
	_beat_accum = 0.0
	_beat_dark = not _beat_dark
	_beat_flash = 1.0 if _beat_dark else 0.0
	GameManager.play_sfx("drum", lerpf(-16.0, -2.0, k), 1.0)

	# 变身那一拍：直接按成全黑，黑着的时候把灵魂换成主角；等下一拍"亮"的时候再撤黑，
	# 所以人是"在全黑里换的"，亮起来那一下已经在画面里的是骑士。
	# M4-65（组长原话：那一拍就是全屏直接按，然后亮的时候再出来）。
	if not _transformed and _form_t >= TRANSFORM_AT and _beat_dark:
		_transformed = true
		_apply_growth(1.0)
		_transform_black = true
		if _pulse_rect != null:
			_pulse_rect.color.a = 1.0
	elif _transform_black and not _beat_dark:
		# 下一拍"亮"：撤黑，画面里已经是换了人的骑士（黑着的这几拍完成了换人）
		_transform_black = false
		if _pulse_rect != null:
			_pulse_rect.color.a = 0.0
	if _desc_phase == 1 and _final_pending and _form_t >= DESCENT_TIME:
		_desc_final_hit()

## 结尾那一拍：直接砸成全黑（不是渐变），然后开始计时 3 秒。
## 鼓不在这里停 —— 停鼓就等于"人还没进关，声音先没了"。
func _desc_final_hit() -> void:
	if _desc_phase != 1:
		return
	_desc_phase = 2
	_black_t = 0.0
	_final_pending = false
	_beat_flash = 0.0
	if _pulse_rect != null:
		_pulse_rect.color.a = 1.0
	_beat_accum = 0.0

## （M4-64 起结尾不再"亮回来再切"，而是砸黑 → 鼓打满 3 秒 → 直接切教学关。
## 这个函数留着给以后想恢复"从玩家向外亮"的版本用，目前没有调用点。）
func _desc_reveal() -> void:
	_desc_phase = 3
	var tw := create_tween()
	tw.set_parallel(true)
	if _pulse_rect != null:
		tw.tween_property(_pulse_rect, "color:a", 0.0, REVEAL_TIME)
	if _dark_mat != null:
		tw.tween_method(_set_dark_radius, 104.0, 1400.0, REVEAL_TIME)
	tw.chain().tween_interval(0.4)
	tw.chain().tween_callback(_leave)

func _set_dark_radius(r: float) -> void:
	_dark_radius_override = r

## 全屏明暗遮罩：铺在 UI 层最上面，盖住背景与角色一起闪
func _build_pulse_rect() -> void:
	if _pulse_rect != null and is_instance_valid(_pulse_rect):
		return
	_pulse_rect = ColorRect.new()
	_pulse_rect.name = "PulseShade"
	_pulse_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_pulse_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _ui_layer != null:
		_ui_layer.add_child(_pulse_rect)
		# 遮罩压在最底层：字幕/提示要浮在明暗之上，否则变暗时字也没了
		_ui_layer.move_child(_pulse_rect, 0)

## 下落时的背景：远处一片雾、两侧暗柱、飘落的尘埃。
## 之前是纯黑虚空，掉下去像掉进空文件，得有参照物才看得出在"往下"。
func _build_descent_bg() -> void:
	if _descent_bg != null and is_instance_valid(_descent_bg):
		return
	_descent_bg = Node2D.new()
	_descent_bg.name = "DescentBackdrop"
	_descent_bg.z_index = -4
	add_child(_descent_bg)
	_bg_nodes.clear()

	# 一整片暗雾，跟着镜头走，压住四周
	var mist := ColorRect.new()
	mist.color = Color(0.035, 0.040, 0.055, 0.90)
	# 铺得足够大：zoom 拉到 0.8 时可见范围约 1600×900，留一倍余量
	mist.position = Vector2(-1200, -2200)
	mist.size = Vector2(3200, 4400)
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_descent_bg.add_child(mist)

	# 两侧暗柱：在 ±1400 的带子里均匀铺开，配合循环滚动，落多久都不会露底
	for i in range(12):
		var col := Polygon2D.new()
		col.color = Color(0.055 + 0.012 * float(i % 3), 0.060, 0.078, 0.55)
		var w := 90.0 + float(i % 4) * 55.0
		var x := -300.0 + float(i % 8) * 210.0
		var h := 700.0 + float(i % 3) * 420.0
		col.polygon = PackedVector2Array([
			Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w * 0.82, h), Vector2(x + w * 0.10, h),
		])
		_descent_bg.add_child(col)
		var y0 := -1400.0 + float(i) * 235.0
		col.position.y = y0
		_bg_nodes.append({"node": col, "y0": y0})

	# 尘埃：细亮线，和柱子同一条带子里循环
	for i in range(30):
		var mote := Line2D.new()
		mote.width = 1.2
		mote.default_color = Color(0.52, 0.60, 0.72, 0.30)
		var mx := 60.0 + float(i % 10) * 120.0
		mote.points = PackedVector2Array([Vector2(mx, 0), Vector2(mx + 1.5, 26.0)])
		_descent_bg.add_child(mote)
		var my0 := -1400.0 + float(i) * 95.0
		mote.position.y = my0
		_bg_nodes.append({"node": mote, "y0": my0})

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
	# 先把透明度压到 0 再换字：否则上一句还没淡完，新句子会"闪现"出来
	label.modulate.a = 0.0
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
