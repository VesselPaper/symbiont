extends Node2D
## 教学关美术底座（M2 美术补齐）
##
## 只做“看得见的东西”，不碰碰撞、不移动任何平台：
##   - 把原来一整块灰底换成竖直渐变天空 + 远景断柱 + 中景破拱
##   - 给地面/平台/墙补顶面亮边、砖缝、青苔、碎石
##   - 加锁链、吊灯、贴地雾、飘尘、暗角
## 地形节点本身（GroundLeft / JumpPlatform ...）一个都不改位置，避免破坏组长调好的
## 教学关手感；这里只改它们的 Visual 颜色并往 StaticBody 下挂装饰子节点。
## 视差层跟 abyss_backdrop.gd 一个思路：越远跟得越少。

const VIGNETTE_SHADER := preload("res://assets/shaders/vignette.gdshader")

@export var camera_path: NodePath
@export var world_width := 2560.0
@export var world_top := -200.0
@export var world_bottom := 760.0
@export var seed_value := 20261110

const STONE_GROUND := Color(0.170, 0.190, 0.200)
const STONE_PLATFORM := Color(0.200, 0.220, 0.235)
const STONE_PIT := Color(0.185, 0.205, 0.215)
const STONE_WALL := Color(0.070, 0.085, 0.095)
const RIM_COLOR := Color(0.42, 0.55, 0.56, 0.75)
const MOSS_COLOR := Color(0.140, 0.215, 0.180, 0.9)

var _camera: Node2D
var _layers: Array[Dictionary] = []
var _fog: Array[Dictionary] = []
var _spores: CPUParticles2D
var _rng := RandomNumberGenerator.new()
var _time := 0.0

func _ready() -> void:
	_rng.seed = seed_value
	if camera_path != NodePath(""):
		_camera = get_node_or_null(camera_path)
	# 关掉原来那块纯灰底，换成自己的渐变天空（不改它的碰撞/位置，纯粹视觉）
	var old_backdrop := get_parent().get_node_or_null("Backdrop")
	if old_backdrop is CanvasItem:
		old_backdrop.visible = false
	_build_sky()
	_build_shaft()
	_build_far()
	_build_mid()
	_build_fog()
	_build_spores()
	_dress_terrain()
	_dress_props()
	_build_vignette()

## 从上方漏下来的一束冷光：让画面上半部分不是一片死黑，也给入口一个方向感。
## 用 8 个顶点 + 逐顶点 alpha，左右边缘淡出，避免出现一块硬边的灰色梯形。
func _build_shaft() -> void:
	var beam := Polygon2D.new()
	beam.name = "LightShaft"
	beam.color = Color(1, 1, 1, 1)
	beam.polygon = PackedVector2Array([
		Vector2(220.0, world_top), Vector2(300.0, world_top),
		Vector2(420.0, world_top), Vector2(500.0, world_top),
		Vector2(720.0, 680.0), Vector2(610.0, 680.0),
		Vector2(470.0, 680.0), Vector2(360.0, 680.0),
	])
	beam.vertex_colors = PackedColorArray([
		Color(0.45, 0.62, 0.60, 0.0), Color(0.45, 0.62, 0.60, 0.10),
		Color(0.45, 0.62, 0.60, 0.10), Color(0.45, 0.62, 0.60, 0.0),
		Color(0.45, 0.62, 0.60, 0.0), Color(0.45, 0.62, 0.60, 0.03),
		Color(0.45, 0.62, 0.60, 0.03), Color(0.45, 0.62, 0.60, 0.0),
	])
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = mat
	add_child(beam)
	# 中间再叠一层更窄的，中心稍亮，边缘同样淡出
	var core := Polygon2D.new()
	core.color = Color(1, 1, 1, 1)
	core.polygon = PackedVector2Array([
		Vector2(310.0, world_top), Vector2(345.0, world_top),
		Vector2(380.0, world_top), Vector2(405.0, world_top),
		Vector2(560.0, 680.0), Vector2(520.0, 680.0),
		Vector2(470.0, 680.0), Vector2(435.0, 680.0),
	])
	core.vertex_colors = PackedColorArray([
		Color(0.62, 0.80, 0.76, 0.0), Color(0.62, 0.80, 0.76, 0.06),
		Color(0.62, 0.80, 0.76, 0.06), Color(0.62, 0.80, 0.76, 0.0),
		Color(0.62, 0.80, 0.76, 0.0), Color(0.62, 0.80, 0.76, 0.02),
		Color(0.62, 0.80, 0.76, 0.02), Color(0.62, 0.80, 0.76, 0.0),
	])
	core.material = mat
	add_child(core)

func _process(delta: float) -> void:
	_time += delta
	if _camera != null:
		for layer in _layers:
			var node: Node2D = layer["node"]
			var factor: float = layer["factor"]
			node.position = Vector2(
				_camera.global_position.x * (1.0 - factor),
				_camera.global_position.y * (1.0 - factor) * 0.30
			)
	for item in _fog:
		var fog: Node2D = item["node"]
		var base: Vector2 = item["base"]
		fog.position = base + Vector2(sin(_time * item["speed"] + item["phase"]) * 40.0, 0.0)
	if _spores != null and _camera != null:
		_spores.position = _camera.global_position

# ---------- 背景 ----------

func _build_sky() -> void:
	var sky := Polygon2D.new()
	sky.name = "Sky"
	sky.color = Color(1, 1, 1, 1)
	sky.polygon = PackedVector2Array([
		Vector2(-200.0, world_top), Vector2(world_width + 200.0, world_top),
		Vector2(world_width + 200.0, world_bottom + 80.0), Vector2(-200.0, world_bottom + 80.0),
	])
	# 上亮下暗的竖直渐变：上面的冷光像从洞口漏下来，底下是看不见的深渊
	sky.vertex_colors = PackedColorArray([
		Color(0.160, 0.190, 0.210), Color(0.150, 0.180, 0.200),
		Color(0.052, 0.062, 0.072), Color(0.046, 0.055, 0.064),
	])
	add_child(sky)

func _build_far() -> void:
	var root := Node2D.new()
	root.name = "Far"
	add_child(root)
	# 远端断柱：高低错落，压成雾色；柱顶断口用两三段折线破一下。
	# 数量按地图宽算（M4-19 教学关拉到 5000），不然过了 2600 背景就只剩一片渐变。
	var far_count := int(ceil(world_width / 360.0)) + 1
	for i in range(far_count):
		var x := -300.0 + float(i) * 360.0 + _rng.randf_range(-70.0, 70.0)
		var h := _rng.randf_range(280.0, 580.0)
		var w := _rng.randf_range(54.0, 120.0)
		var base_y := world_bottom - 20.0
		var pillar := Polygon2D.new()
		pillar.color = Color(0.190, 0.220, 0.240)
		pillar.polygon = PackedVector2Array([
			Vector2(x, base_y), Vector2(x, base_y - h),
			Vector2(x + w * 0.35, base_y - h - _rng.randf_range(4.0, 26.0)),
			Vector2(x + w * 0.72, base_y - h + _rng.randf_range(0.0, 16.0)),
			Vector2(x + w, base_y - h + _rng.randf_range(18.0, 52.0)),
			Vector2(x + w, base_y),
		])
		root.add_child(pillar)
		# 只给左侧一条轮廓光，黑块才不是死黑
		var rim := Line2D.new()
		rim.width = 1.6
		rim.default_color = Color(0.32, 0.42, 0.44, 0.45)
		rim.points = PackedVector2Array([Vector2(x, base_y - 10.0), Vector2(x, base_y - h + 20.0)])
		root.add_child(rim)
	_layers.append({"node": root, "factor": 0.16})

func _build_mid() -> void:
	var root := Node2D.new()
	root.name = "Mid"
	add_child(root)
	# 三座塌了半边的拱：柱子在，拱圈只留左半边，暗示这里曾经是通道。
	# 拱的间距固定 900，数量跟着地图宽走（5000 的地图要六座才铺满）。
	var arch_count := int(ceil(world_width / 900.0)) + 1
	for i in range(arch_count):
		var x := 240.0 + float(i) * 900.0
		var base_y := world_bottom - 10.0
		var w := 360.0
		var h := 300.0
		var t := 34.0
		for dx in [0.0, w - t]:
			var pillar := Polygon2D.new()
			pillar.color = Color(0.055, 0.070, 0.080)
			pillar.polygon = PackedVector2Array([
				Vector2(x + dx, base_y), Vector2(x + dx, base_y - h),
				Vector2(x + dx + t, base_y - h), Vector2(x + dx + t, base_y),
			])
			root.add_child(pillar)
		var ring := Polygon2D.new()
		ring.color = Color(0.055, 0.070, 0.080)
		var pts := PackedVector2Array()
		var cx := x + w * 0.5
		var r := w * 0.5
		for k in range(13):
			var a := PI * (1.0 - float(k) / 12.0)
			pts.append(Vector2(cx + cos(a) * r, base_y - h - sin(a) * r))
		for k in range(13):
			var a := PI * (1.0 - float(k) / 12.0)
			pts.append(Vector2(cx + cos(a) * (r - t), base_y - h - sin(a) * (r - t)))
		ring.polygon = pts
		root.add_child(ring)
		var rim := Line2D.new()
		rim.width = 1.4
		rim.default_color = Color(0.22, 0.31, 0.32, 0.40)
		var rim_pts := PackedVector2Array()
		for k in range(13):
			var a := PI * (1.0 - float(k) / 12.0)
			rim_pts.append(Vector2(cx + cos(a) * r, base_y - h - sin(a) * r))
		rim.points = rim_pts
		root.add_child(rim)
	_layers.append({"node": root, "factor": 0.34})

func _build_fog() -> void:
	var root := Node2D.new()
	root.name = "Fog"
	add_child(root)
	# 雾团铺满整张地图：数量按宽度算，位置按比例摊开
	var fog_count := int(ceil(world_width / 900.0)) + 1
	for i in range(fog_count):
		var fog := Polygon2D.new()
		fog.color = Color(0.16, 0.23, 0.25, 0.045 + (i % 3) * 0.012)
		fog.polygon = _ellipse(560.0 + (i % 3) * 170.0, 90.0 + (i % 3) * 30.0, 26)
		var base := Vector2(world_width * (0.10 + 0.80 * float(i) / maxf(float(fog_count - 1), 1.0)), world_bottom - 60.0)
		fog.position = base
		root.add_child(fog)
		_fog.append({"node": fog, "base": base, "speed": 0.10 + (i % 3) * 0.04, "phase": i * 2.1})

func _build_spores() -> void:
	_spores = CPUParticles2D.new()
	_spores.name = "Spores"
	_spores.amount = 50
	_spores.lifetime = 8.0
	_spores.preprocess = 2.0
	_spores.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_spores.emission_rect_extents = Vector2(760.0, 380.0)
	_spores.direction = Vector2(0, -1)
	_spores.spread = 180.0
	_spores.gravity = Vector2(0, 0)
	_spores.initial_velocity_min = 2.0
	_spores.initial_velocity_max = 9.0
	_spores.scale_amount_min = 0.4
	_spores.scale_amount_max = 1.3
	_spores.color = Color(0.58, 0.78, 0.74, 0.45)
	_spores.texture = _dot_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_spores.material = mat
	_spores.z_index = 9
	add_child(_spores)

func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VIGNETTE_SHADER
	rect.material = mat
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# ---------- 地形装饰（只改视觉，不动碰撞） ----------

func _dress_terrain() -> void:
	var names := {
		"GroundLeft": STONE_GROUND,
		"PitFloor": STONE_PIT,
		"JumpPlatform": STONE_PLATFORM,
		"PogoPlatform": STONE_PLATFORM,
		"AltarPlatform": STONE_PLATFORM,
		"WallLeft": STONE_WALL,
		"WallRight": STONE_WALL,
	}
	for body_name in names:
		var body := get_parent().get_node_or_null(body_name) as StaticBody2D
		if body == null:
			continue
		var visual := body.get_node_or_null("Visual") as Polygon2D
		if visual == null:
			continue
		visual.color = names[body_name]
		var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col == null or col.shape == null:
			continue
		if body_name.begins_with("Wall"):
			_add_wall_rim(body, body_name)
			continue
		_add_top_rim(body, col)
		_add_seams_and_moss(body, col)
		_add_edge_chunks(body, col)

func _add_top_rim(body: StaticBody2D, col: CollisionShape2D) -> void:
	var shape := col.shape as RectangleShape2D
	if shape == null:
		return
	var half_w := shape.size.x * 0.5
	var top_y := col.position.y - shape.size.y * 0.5
	var rim := Line2D.new()
	rim.name = "TopRim"
	rim.width = 2.0
	rim.default_color = RIM_COLOR
	rim.points = PackedVector2Array([
		Vector2(col.position.x - half_w, top_y + 1.0),
		Vector2(col.position.x + half_w, top_y + 1.0),
	])
	body.add_child(rim)
	# 顶面下面压一条暗线，让平台有厚度
	var under := Line2D.new()
	under.name = "TopShade"
	under.width = 2.0
	under.default_color = Color(0.04, 0.05, 0.06, 0.8)
	under.points = PackedVector2Array([
		Vector2(col.position.x - half_w + 2.0, top_y + 3.0),
		Vector2(col.position.x + half_w - 2.0, top_y + 3.0),
	])
	body.add_child(under)

func _add_seams_and_moss(body: StaticBody2D, col: CollisionShape2D) -> void:
	var shape := col.shape as RectangleShape2D
	if shape == null:
		return
	var half_w := shape.size.x * 0.5
	var top_y := col.position.y - shape.size.y * 0.5
	var left := col.position.x - half_w
	var right := col.position.x + half_w
	var bottom := col.position.y + shape.size.y * 0.5
	# 石块横缝：把 60px 厚的地面分成三到四层，避免整块像一块塑料
	var course_y := top_y + 20.0
	while course_y < bottom - 8.0:
		var course := Line2D.new()
		course.width = 1.0
		course.default_color = Color(0.055, 0.070, 0.080, 0.55)
		course.points = PackedVector2Array([
			Vector2(left + 12.0, course_y), Vector2(right - 12.0, course_y)
		])
		body.add_child(course)
		course_y += 17.0
	# 砖缝：每隔约 90px 一道短竖线，不铺满，免得像栅栏
	var seam_x := left + 46.0
	while seam_x < right - 30.0:
		var seam := Line2D.new()
		seam.width = 1.0
		seam.default_color = Color(0.06, 0.075, 0.085, 0.55)
		seam.points = PackedVector2Array([
			Vector2(seam_x, top_y + 4.0), Vector2(seam_x, top_y + 13.0)
		])
		body.add_child(seam)
		seam_x += _rng.randf_range(72.0, 108.0)
	# 青苔：只长在平台两端和靠左的边角
	for k in range(2):
		var mx := left + 14.0 + k * (shape.size.x - 40.0) * _rng.randf_range(0.45, 1.0)
		var moss := Polygon2D.new()
		moss.color = MOSS_COLOR
		moss.polygon = PackedVector2Array([
			Vector2(mx, top_y + 1.0), Vector2(mx + _rng.randf_range(10.0, 26.0), top_y + 1.0),
			Vector2(mx + _rng.randf_range(4.0, 14.0), top_y - _rng.randf_range(3.0, 7.0)),
		])
		body.add_child(moss)

func _add_edge_chunks(body: StaticBody2D, col: CollisionShape2D) -> void:
	# 平台边缘的小碎石和垂根：把"一整条矩形边"打散，学生试玩时不会觉得地形是硬拼的
	var shape := col.shape as RectangleShape2D
	if shape == null:
		return
	var half_w := shape.size.x * 0.5
	var top_y := col.position.y - shape.size.y * 0.5
	var bottom := col.position.y + shape.size.y * 0.5
	for side in [-1, 1]:
		var base_x: float = col.position.x + float(side) * (half_w - 8.0)
		for k in range(2):
			var chunk := Polygon2D.new()
			chunk.color = STONE_GROUND.darkened(_rng.randf_range(0.0, 0.18))
			var w := _rng.randf_range(5.0, 10.0)
			var h := _rng.randf_range(3.0, 7.0)
			chunk.polygon = PackedVector2Array([
				Vector2(base_x, top_y + 1.0), Vector2(base_x + side * w, top_y + 2.0),
				Vector2(base_x + side * (w - 2.0), top_y + h), Vector2(base_x, top_y + h + 1.0),
			])
			body.add_child(chunk)
		# 垂根/苔须：从平台底部往下挂，纯装饰，不参与碰撞
		for k in range(3):
			var vx: float = base_x + _rng.randf_range(-12.0, 12.0)
			var vine := Line2D.new()
			vine.width = 1.0
			vine.default_color = Color(0.030, 0.050, 0.042, 0.65)
			vine.points = PackedVector2Array([
				Vector2(vx, bottom - 2.0),
				Vector2(vx + _rng.randf_range(-5.0, 5.0), bottom + _rng.randf_range(8.0, 22.0)),
			])
			body.add_child(vine)

func _add_wall_rim(body: StaticBody2D, body_name: String) -> void:
	# 墙的内侧画一条竖直冷光，跟地面的顶面亮边呼应
	var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or col.shape == null:
		return
	var shape := col.shape as RectangleShape2D
	if shape == null:
		return
	var inner_x := col.position.x + shape.size.x * 0.5 if body_name == "WallLeft" else col.position.x - shape.size.x * 0.5
	var rim := Line2D.new()
	rim.name = "InnerRim"
	rim.width = 1.6
	rim.default_color = Color(0.22, 0.30, 0.32, 0.45)
	rim.points = PackedVector2Array([
		Vector2(inner_x, col.position.y - shape.size.y * 0.5 + 8.0),
		Vector2(inner_x, col.position.y + shape.size.y * 0.5 - 8.0),
	])
	body.add_child(rim)

# ---------- 场景摆件 ----------

func _dress_props() -> void:
	var props := Node2D.new()
	props.name = "ArenaProps"
	# 父节点 BackdropArt 是 -3：子节点 +2 → 世界 -1，压在角色后面、地形前面
	props.z_index = 2
	add_child(props)
	# 锁链：从画面上方垂下来，短链挂在半空，破一下空旷的背景。
	# M4-19 地图到 5000：后段（宝箱/长廊/层门）也要有链子，否则那 1700px 是空墙
	for x in [180.0, 620.0, 1180.0, 1720.0, 2280.0, 2840.0, 3380.0, 3960.0, 4520.0, 4860.0]:
		var chain := Line2D.new()
		chain.width = 3.0
		chain.default_color = Color(0.150, 0.160, 0.170, 0.95)
		var pts := PackedVector2Array()
		var y := 210.0
		var length := _rng.randf_range(180.0, 330.0)
		while y < 210.0 + length:
			pts.append(Vector2(x + (4.0 if int(y) % 3 == 0 else -4.0), y))
			y += 14.0
		chain.points = pts
		props.add_child(chain)
	# 出生点左边一盏吊灯：给入口一点暖光，玩家一睁眼能看到路
	_add_lantern(props, Vector2(232.0, 552.0), 210.0, 0.40, 0.34)
	# 中段和祭坛区再挂两盏，给长走廊一点暖色路标（不挡路，只在背景层）
	_add_lantern(props, Vector2(760.0, 505.0), 210.0, 0.34, 0.26)
	_add_lantern(props, Vector2(1500.0, 512.0), 210.0, 0.30, 0.22)
	_add_lantern(props, Vector2(2060.0, 500.0), 210.0, 0.32, 0.24)
	# 后段（宝箱 → 长廊 → 层门）四盏，越往后越暗，但一段路至少有一处暖色
	_add_lantern(props, Vector2(2760.0, 505.0), 210.0, 0.26, 0.18)
	_add_lantern(props, Vector2(3480.0, 500.0), 210.0, 0.24, 0.16)
	_add_lantern(props, Vector2(4140.0, 512.0), 210.0, 0.22, 0.15)
	_add_lantern(props, Vector2(4720.0, 498.0), 210.0, 0.28, 0.19)
	# 立在台面上的断柱：近景有高有低，画面才不是一条水平线
	_add_broken_pillar(props, 140.0, 660.0, 340.0, 48.0)
	_add_broken_pillar(props, 1960.0, 660.0, 300.0, 42.0)
	_add_broken_pillar(props, 2900.0, 660.0, 250.0, -34.0)
	_add_broken_pillar(props, 3860.0, 660.0, 320.0, 40.0)
	_add_broken_pillar(props, 4680.0, 660.0, 270.0, -30.0)
	# 碎石：平台边角和地面散几块，别让地面是一条直线
	for i in range(14):
		var rock := Polygon2D.new()
		rock.color = Color(0.12, 0.14, 0.15, 0.95)
		var size := _rng.randf_range(6.0, 14.0)
		rock.polygon = PackedVector2Array([
			Vector2(-size, 0), Vector2(-size * 0.4, -size * 0.7),
			Vector2(size * 0.5, -size * 0.5), Vector2(size, 0),
		])
		rock.position = Vector2(_rng.randf_range(320.0, world_width - 300.0), 659.0 - _rng.randf_range(0.0, 3.0))
		props.add_child(rock)
	# 尸体不再由背景美术兼职：M4-21 起由 components/prop_corpse.gd 自己建模
	# （原来这里只是把占位方块染成土黄 + 补四根肋骨，组长说“就一个黄色矩形”）

# ---------- 小工具 ----------

## 吊灯：一根锁链 + 铁笼 + 暖色玻璃 + 光晕 + 点光；入口那盏最亮，往深处逐渐弱
func _add_lantern(parent: Node2D, pos: Vector2, chain_top: float, halo_strength: float, light_energy: float) -> void:
	var chain := Line2D.new()
	chain.width = 2.2
	chain.default_color = Color(0.13, 0.14, 0.15, 0.95)
	var pts := PackedVector2Array()
	var y := chain_top
	while y < pos.y - 10.0:
		pts.append(Vector2(pos.x + (3.0 if int(y) % 4 == 0 else -3.0), y))
		y += 14.0
	chain.points = pts
	parent.add_child(chain)

	var lantern := Node2D.new()
	lantern.position = pos
	parent.add_child(lantern)
	var cage := Polygon2D.new()
	cage.color = Color(0.16, 0.15, 0.13, 1)
	cage.polygon = PackedVector2Array([
		Vector2(-7, -10), Vector2(7, -10), Vector2(9, 8), Vector2(-9, 8)
	])
	lantern.add_child(cage)
	var glass := Polygon2D.new()
	glass.color = Color(1.0, 0.66, 0.34, 0.95)
	glass.polygon = PackedVector2Array([Vector2(-4, -6), Vector2(4, -6), Vector2(3, 5), Vector2(-3, 5)])
	lantern.add_child(glass)
	var halo := Sprite2D.new()
	halo.texture = _radial_texture()
	halo.modulate = Color(1.0, 0.66, 0.34, halo_strength)
	halo.scale = Vector2(0.38, 0.38)
	halo.position = Vector2(0, 2)
	lantern.add_child(halo)
	var light := PointLight2D.new()
	light.texture = _radial_texture()
	light.color = Color(1.0, 0.70, 0.44)
	light.energy = light_energy
	light.texture_scale = 1.3
	light.position = Vector2(0, 2)
	lantern.add_child(light)

## 断柱：立在台面上的残柱，断口用两三段折线，左侧一条轮廓光
func _add_broken_pillar(parent: Node2D, x: float, base_y: float, height: float, width: float) -> void:
	var half := width * 0.5
	var pillar := Polygon2D.new()
	pillar.color = Color(0.165, 0.185, 0.195, 1)
	pillar.polygon = PackedVector2Array([
		Vector2(x - half, base_y - 6.0), Vector2(x - half, base_y - height),
		Vector2(x - half + 8.0, base_y - height + 14.0),
		Vector2(x + half - 7.0, base_y - height - 10.0),
		Vector2(x + half, base_y - height + 4.0),
		Vector2(x + half, base_y - 6.0),
	])
	parent.add_child(pillar)
	var rim := Line2D.new()
	rim.width = 1.8
	rim.default_color = Color(0.30, 0.40, 0.42, 0.40)
	rim.points = PackedVector2Array([
		Vector2(x - half + 1.0, base_y - 16.0),
		Vector2(x - half + 1.0, base_y - height + 10.0),
	])
	parent.add_child(rim)
	# 柱脚碎石，避免柱子像插进地板里
	for i in range(2):
		var rock := Polygon2D.new()
		rock.color = Color(0.12, 0.14, 0.15, 0.95)
		var s := 7.0 + 4.0 * i
		rock.polygon = PackedVector2Array([
			Vector2(-s, 0), Vector2(-s * 0.4, -s * 0.8),
			Vector2(s * 0.6, -s * 0.5), Vector2(s, 0),
		])
		rock.position = Vector2(x - half + 4.0 + 10.0 * i, base_y - 4.0)
		parent.add_child(rock)

func _ellipse(rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

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

func _dot_texture() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			var d := Vector2(x - 1.5, y - 1.5).length() / 2.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
