extends Node2D
## 第一层 · 锈钟回廊（M2 关卡）
##
## 教学关之后的第一张正式地图。地形全部由本脚本按 P L A T F O R M S 数据生成，
## 改关卡形状只改下面那几张表，不用在编辑器里拖节点。
##
## 路线：入口平台 → 断口 → 下沉台阶 → 钟厅（吊钟/锁链/史莱姆）→ 上行台阶 → 祭坛厅 → 层门
##
## 剧情三段各挂一个 Area2D 触发器，踩进去播对话，每个只播一次（靠 GameManager 旗标去重）：
##   钟厅 → floor1_bell    祭坛前 → floor1_altar    层门前 → floor1_gate
## 进场景 0.6 秒后播 floor1_enter。
##
## 视觉：背景交给 Backdrop（components/abyss_backdrop.gd），地形是石块 + 顶部亮边，
## 吊钟、锁链、灯火都在 _build_props 里生成。

## 地形：x, 顶面 y, 宽, 厚（顶面是玩家站的那条线）
const PLATFORMS: Array[Dictionary] = [
	{"rect": Rect2(0, 620, 620, 90), "stone": 0.0},        # 入口平台
	{"rect": Rect2(760, 680, 300, 90), "stone": 0.15},     # 断口对岸（低一级）
	{"rect": Rect2(1120, 760, 780, 130), "stone": 0.0},    # 钟厅地面
	{"rect": Rect2(1960, 720, 200, 90), "stone": 0.2},     # 上行台阶一
	{"rect": Rect2(2160, 660, 200, 90), "stone": 0.35},    # 上行台阶二
	{"rect": Rect2(2380, 600, 520, 120), "stone": 0.1},    # 祭坛厅
	{"rect": Rect2(-80, 300, 80, 900), "stone": 0.0},      # 左边界墙
	{"rect": Rect2(2900, 300, 80, 900), "stone": 0.0},     # 右边界墙
]

const SPAWN_POINT := Vector2(140, 560)
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const SLIME_SPAWNS: Array[Vector2] = [Vector2(1350, 720), Vector2(1780, 720)]

## 摄像机参数与教学关一致：垂直视野 = 15 倍角色身高
const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

const INTRO_DELAY := 0.6
const INTRO_ID := "floor1_enter"
## 层门目前没有下一张地图：播完对话给一句占位提示，别让玩家以为卡死
const GATE_NOTICE := "第二层 · 还在建（M3 落地）"

const STONE_COLOR := Color(0.165, 0.190, 0.210)
const STONE_DARK := Color(0.075, 0.090, 0.105)
const STONE_RIM := Color(0.380, 0.470, 0.480)

@onready var _dialogue: Node = $Dialogue
@onready var _player: Node2D = $Player
@onready var _camera: Camera2D = $Camera2D

var _played: Dictionary = {}
var _toast: Label

func _ready() -> void:
	_build_platforms()
	_build_props()
	_build_triggers()
	_build_kill_zone()
	_spawn_enemies()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	var timer := get_tree().create_timer(INTRO_DELAY)
	timer.timeout.connect(_play_intro)

func _play_intro() -> void:
	_play_once("intro", INTRO_ID)

## 同一段剧情只播一次：旗标记在 GameManager，死了重进也不会重复念
func _play_once(key: String, dialogue_id: String) -> void:
	if _played.get(key, false):
		return
	_played[key] = true
	_dialogue.call("play", dialogue_id)

# ---------- 地形 ----------

func _build_platforms() -> void:
	var holder := Node2D.new()
	holder.name = "Terrain"
	# 地形压在背景之上、角色之下：Backdrop 根节点 z=-3，Props z=-1，角色 0
	holder.z_index = -2
	add_child(holder)
	for i in range(PLATFORMS.size()):
		var spec: Dictionary = PLATFORMS[i]
		var rect: Rect2 = spec["rect"]
		var body := StaticBody2D.new()
		body.name = "Plat%02d" % i
		body.position = rect.position + rect.size * 0.5
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		col.shape = shape
		body.add_child(col)
		var visual := Polygon2D.new()
		visual.name = "Visual"
		visual.polygon = PackedVector2Array([
			Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
			Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
		])
		# 每块石头颜色略有差别，避免一整片死板的灰
		visual.color = STONE_COLOR.lightened(float(spec["stone"]) * 0.25)
		body.add_child(visual)
		# 顶面亮边：光从上面来，玩家一眼能看出哪儿能站
		var rim := Polygon2D.new()
		rim.name = "Rim"
		var rim_h := 5.0
		rim.polygon = PackedVector2Array([
			Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, -rect.size.y * 0.5 + rim_h),
			Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5 + rim_h),
		])
		rim.color = STONE_RIM
		body.add_child(rim)
		# 底部压暗，让石块有厚度
		var shade := Polygon2D.new()
		shade.name = "Shade"
		var shade_h := minf(18.0, rect.size.y * 0.25)
		shade.polygon = PackedVector2Array([
			Vector2(-rect.size.x * 0.5, rect.size.y * 0.5 - shade_h),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5 - shade_h),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
			Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
		])
		shade.color = STONE_DARK
		body.add_child(shade)
		# 石缝 / 苔痕 / 碎石：只在能站的大平台上加，边界墙不用
		if rect.size.x >= 120.0:
			_add_platform_detail(body, rect)
		holder.add_child(body)

## 平台表面装饰：竖向石缝 + 顶角苔痕 + 两块碎石
## 都是纯装饰，不参与碰撞，也不影响 PLATFORMS 数据
func _add_platform_detail(body: StaticBody2D, rect: Rect2) -> void:
	var top := -rect.size.y * 0.5
	var half_w := rect.size.x * 0.5
	var seam_color := Color(0.040, 0.052, 0.062, 0.55)
	var x := 70.0
	# 缝间距按平台长度自适应，短平台少几道，长平台多几道
	var step := maxf(80.0, rect.size.x / 6.0)
	while x < rect.size.x - 50.0:
		var seam := Line2D.new()
		seam.width = 1.4
		seam.default_color = seam_color
		seam.points = PackedVector2Array([
			Vector2(-half_w + x, top + 7.0),
			Vector2(-half_w + x + 4.0, top + 20.0),
		])
		body.add_child(seam)
		x += step
	# 顶角苔痕：一小撮偏绿的暗色，别让石头全是蓝灰
	for sx in [-half_w + 10.0, half_w - 26.0]:
		var moss := Polygon2D.new()
		moss.color = Color(0.085, 0.125, 0.105, 0.6)
		moss.polygon = PackedVector2Array([
			Vector2(sx, top + 5.0), Vector2(sx + 22.0, top + 5.0),
			Vector2(sx + 16.0, top + 12.0), Vector2(sx + 4.0, top + 14.0),
		])
		body.add_child(moss)
	# 碎石：贴着顶面几块大小不一的石头，破掉完美的直线
	for i in range(2):
		var r := Polygon2D.new()
		r.color = STONE_RIM.darkened(0.28)
		var rx := -half_w + rect.size.x * (0.32 + 0.28 * i)
		var rw := 10.0 + 5.0 * i
		r.polygon = PackedVector2Array([
			Vector2(rx, top + 1.0), Vector2(rx + rw, top - 3.0),
			Vector2(rx + rw + 6.0, top + 4.0), Vector2(rx + 3.0, top + 5.0),
		])
		body.add_child(r)

# ---------- 场景物件 ----------

func _build_props() -> void:
	var props := Node2D.new()
	props.name = "Props"
	# 物件在角色之后、地形之前：吊钟和门框不会挡住玩家
	props.z_index = -1
	add_child(props)
	_build_entry_props(props)

	# 吊钟：钟厅的视觉中心。钟要挂到镜头（地面探索时视野约 y 396~816）里，
	# 所以钟底离地 40 多像素，玩家正好从钟下走过。
	var bell := Node2D.new()
	bell.name = "Bell"
	bell.position = Vector2(1600, 620)
	props.add_child(bell)

	var bell_body := Polygon2D.new()
	bell_body.color = Color(0.045, 0.055, 0.065)
	bell_body.polygon = PackedVector2Array([
		Vector2(-46, -150), Vector2(46, -150),
		Vector2(74, 40), Vector2(60, 96),
		Vector2(-60, 96), Vector2(-74, 40),
	])
	bell.add_child(bell_body)

	var bell_rim := Polygon2D.new()
	bell_rim.color = Color(0.150, 0.180, 0.190)
	bell_rim.polygon = PackedVector2Array([
		Vector2(-60, 84), Vector2(60, 84), Vector2(64, 100), Vector2(-64, 100),
	])
	bell.add_child(bell_rim)

	var bell_highlight := Line2D.new()
	bell_highlight.width = 3.0
	bell_highlight.default_color = Color(0.36, 0.46, 0.48, 0.9)
	bell_highlight.points = PackedVector2Array([Vector2(-38, -140), Vector2(-52, 10), Vector2(-48, 78)])
	bell.add_child(bell_highlight)

	# 挂钟的横梁与锁链（横梁和链子都在镜头里，别挂到画面外）
	for x in [1500.0, 1600.0, 1700.0]:
		var chain := Line2D.new()
		chain.width = 4.0
		chain.default_color = Color(0.075, 0.085, 0.095)
		chain.points = PackedVector2Array([
			Vector2(x, 342.0), Vector2(x + 6.0, 420.0), Vector2(x, 470.0 if x == 1600.0 else 560.0)
		])
		props.add_child(chain)

	var beam := Polygon2D.new()
	beam.color = Color(0.070, 0.082, 0.092)
	beam.polygon = PackedVector2Array([
		Vector2(1430, 352), Vector2(1770, 352), Vector2(1770, 382), Vector2(1430, 382),
	])
	props.add_child(beam)

	# 灯火：祭坛暖光、钟厅冷光。没有贴图，用径向渐变纹理当光晕
	_add_light(props, Vector2(2600, 520), Color(1.0, 0.78, 0.52), 0.85, 2.6)
	_add_light(props, Vector2(1600, 560), Color(0.45, 0.78, 0.82), 0.5, 2.6)
	_add_light(props, Vector2(420, 585), Color(1.0, 0.70, 0.44), 0.35, 1.6)

	# 钟厅残旗：给冷灰的钟厅加一点暗紫布色，风一吹能看出这是"有人住过的地方"
	var banner := Polygon2D.new()
	banner.color = Color(0.150, 0.095, 0.170, 0.9)
	banner.polygon = PackedVector2Array([
		Vector2(1452, 372), Vector2(1502, 384), Vector2(1508, 560),
		Vector2(1492, 544), Vector2(1478, 582), Vector2(1462, 538), Vector2(1446, 566),
	])
	props.add_child(banner)
	var banner_rim := Line2D.new()
	banner_rim.width = 1.5
	banner_rim.default_color = Color(0.30, 0.20, 0.34, 0.7)
	banner_rim.points = PackedVector2Array([Vector2(1452, 372), Vector2(1502, 384)])
	props.add_child(banner_rim)

	# 层门：两根柱子 + 门楣 + 一条冷光缝
	var gate := Node2D.new()
	gate.name = "GateFrame"
	gate.position = Vector2(2835, 600)
	props.add_child(gate)
	for dx in [-58.0, 58.0]:
		var post := Polygon2D.new()
		post.color = Color(0.095, 0.110, 0.125)
		post.polygon = PackedVector2Array([
			Vector2(dx - 16, -185), Vector2(dx + 16, -185), Vector2(dx + 16, 0), Vector2(dx - 16, 0),
		])
		gate.add_child(post)
	var lintel := Polygon2D.new()
	lintel.color = Color(0.105, 0.122, 0.138)
	lintel.polygon = PackedVector2Array([
		Vector2(-84, -205), Vector2(84, -205), Vector2(84, -175), Vector2(-84, -175),
	])
	gate.add_child(lintel)
	var seam := Line2D.new()
	seam.width = 6.0
	seam.default_color = Color(0.42, 0.72, 0.76, 0.55)
	seam.points = PackedVector2Array([Vector2(0, -173), Vector2(0, -6)])
	gate.add_child(seam)

## 入口区装饰：头顶断链、一盏挂灯、脚边碎石。
## 这一片是玩家开局唯一看得到的画面，必须有东西可看，不能只有一块灰平台。
func _build_entry_props(parent: Node) -> void:
	for spec in [
		{"x": 236.0, "end_y": 470.0, "width": 2.6},
		{"x": 560.0, "end_y": 372.0, "width": 1.7},
	]:
		var chain := Line2D.new()
		chain.width = spec["width"]
		chain.default_color = Color(0.060, 0.070, 0.080)
		chain.points = PackedVector2Array([
			Vector2(spec["x"], -200.0),
			Vector2(spec["x"] + 10.0, 140.0),
			Vector2(spec["x"] + 2.0, spec["end_y"]),
		])
		parent.add_child(chain)

	# 挂灯：入口唯一的暖色点。灯罩用梯形剪影，里面一块暖玻璃，再加一圈光晕
	var lantern := Node2D.new()
	lantern.name = "EntryLantern"
	lantern.position = Vector2(238.0, 470.0)
	parent.add_child(lantern)
	# PointLight2D 只照亮别的面，自己不会发光；这里额外贴一张径向渐变当可见光晕
	var halo := Sprite2D.new()
	halo.texture = _radial_texture()
	halo.modulate = Color(1.0, 0.66, 0.34, 0.38)
	halo.scale = Vector2(0.35, 0.35)
	halo.position = Vector2(0, 18)
	lantern.add_child(halo)
	var outer_halo := Sprite2D.new()
	outer_halo.texture = _radial_texture()
	outer_halo.modulate = Color(1.0, 0.60, 0.30, 0.08)
	outer_halo.scale = Vector2(0.9, 0.9)
	outer_halo.position = Vector2(0, 18)
	lantern.add_child(outer_halo)
	var cap := Polygon2D.new()
	cap.color = Color(0.095, 0.108, 0.118)
	cap.polygon = PackedVector2Array([
		Vector2(-13, 0), Vector2(13, 0), Vector2(9, 6), Vector2(-9, 6),
	])
	lantern.add_child(cap)
	var glass := Polygon2D.new()
	glass.color = Color(0.92, 0.68, 0.38, 0.9)
	glass.polygon = PackedVector2Array([
		Vector2(-7, 5), Vector2(7, 5), Vector2(10, 26), Vector2(-10, 26),
	])
	lantern.add_child(glass)
	var cage := Polygon2D.new()
	cage.color = Color(0.075, 0.085, 0.095)
	cage.polygon = PackedVector2Array([
		Vector2(-12, 24), Vector2(12, 24), Vector2(11, 31), Vector2(-11, 31),
	])
	lantern.add_child(cage)
	_add_light(lantern, Vector2(0, 18), Color(1.0, 0.72, 0.42), 0.55, 1.25)

	# 脚边碎石：入口平台顶面几块暗石，让站脚的地方不那么干净
	for i in range(3):
		var rock := Polygon2D.new()
		rock.color = STONE_DARK.lightened(0.08 + 0.04 * i)
		var rx := 470.0 + 42.0 * i
		rock.polygon = PackedVector2Array([
			Vector2(rx, 620.0), Vector2(rx + 7.0, 611.0 + 2.0 * i),
			Vector2(rx + 16.0, 615.0), Vector2(rx + 20.0, 620.0),
		])
		parent.add_child(rock)

func _add_light(parent: Node, pos: Vector2, color: Color, energy: float, light_scale: float) -> void:
	var light := PointLight2D.new()
	light.position = pos
	light.color = color
	light.energy = energy
	light.texture_scale = light_scale
	light.texture = _radial_texture()
	parent.add_child(light)

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

# ---------- 触发器 ----------

func _build_triggers() -> void:
	var holder := Node2D.new()
	holder.name = "Triggers"
	add_child(holder)
	_add_trigger(holder, "BellTrigger", Rect2(1490, 600, 240, 180), "bell", "floor1_bell")
	_add_trigger(holder, "AltarTrigger", Rect2(2470, 470, 250, 160), "altar", "floor1_altar")
	_add_trigger(holder, "GateTrigger", Rect2(2780, 400, 110, 210), "gate", "floor1_gate")

func _add_trigger(parent: Node, node_name: String, rect: Rect2, key: String, dialogue_id: String) -> void:
	var area := Area2D.new()
	area.name = node_name
	area.collision_layer = 0
	area.collision_mask = 2  # 只认玩家（player.tscn 的 collision_layer = 2）
	area.position = rect.position + rect.size * 0.5
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		_play_once(key, dialogue_id)
		if key == "gate":
			_show_gate_notice()
	)
	parent.add_child(area)

func _build_kill_zone() -> void:
	# 掉出地图底部就按重伤处理，玩家自己会回出生点（见 player.gd _respawn）
	var area := Area2D.new()
	area.name = "KillZone"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(1450, 1240)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(3200, 200)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player"):
			body.call("take_damage", 99)
	)
	add_child(area)

func _spawn_enemies() -> void:
	var holder := Node2D.new()
	holder.name = "Enemies"
	add_child(holder)
	for i in range(SLIME_SPAWNS.size()):
		var slime := SLIME_SCENE.instantiate()
		slime.position = SLIME_SPAWNS[i]
		slime.name = "Slime%d" % (i + 1)
		holder.add_child(slime)

# ---------- 提示 ----------

func _show_gate_notice() -> void:
	if _toast != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "Notice"
	layer.layer = 3
	add_child(layer)
	_toast = Label.new()
	_toast.text = GATE_NOTICE
	_toast.modulate = Color(0.72, 0.84, 0.86, 0.0)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 20)
	layer.add_child(_toast)
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 0.95, 0.5)
	tween.tween_interval(2.5)
	tween.tween_property(_toast, "modulate:a", 0.0, 1.2)



