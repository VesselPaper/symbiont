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
## 悬崖（M5-11）：这一段下面没有地面，装饰要跳过它，
## 不然石头/断柱会浮在空气里 —— 组长说的"纯灰色陨星、悬在半空"就是这么来的。
@export var gap_from := -1.0
@export var gap_to := -1.0

## M5-28（组长反馈"高台的材质和平地不一样"）：三档石材色统一成一种。
## 原来平台比地面亮一档、坑底又另算一档，两块地形挨着就是两种颜色，怎么看都是拼的。
const STONE_GROUND := Color(0.176, 0.196, 0.208)
const STONE_PLATFORM := STONE_GROUND
const STONE_PIT := STONE_GROUND
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
	# 推迟一帧再画（M5-03）：
	# 教学关的 test_arena.gd 在 _ready 里才按 STAGE 表把地图从 4000 拉到 6250、把三块平台
	# 重新摆一遍。子节点的 _ready 比父节点早，如果这里当场按 4000 的尺寸把天空/远景/砖缝画完，
	# 之后地图一变宽，4000 以外那一段就没背景、没亮边、没砖缝 —— 看起来就是"一大块纯灰地形"。
	# 这一帧的延迟被开场黑幕盖住，看不出来。
	call_deferred("_build_all")

func _build_all() -> void:
	if not is_inside_tree():
		return
	_build_sky()
	_build_shaft()
	_build_far()
	_build_mid()
	_build_left_wall()
	_build_wall_detail()
	_build_under_ground()
	_build_fog()
	_build_spores()
	_dress_terrain()
	# 全局石材纹理铺在所有地形上（跨过平台/地面/台阶的边界，看不出拼接）
	_build_terrain_material()
	# 地表细节要在 _dress_terrain 之后：地面顶边颜色已经定好，碎石/草才压得住
	_build_surface_detail()
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

## 左侧岩壁（M5-27，组长反馈"开局左边只有一条细墙线，屏幕左侧一片空白"）。
##
## 原来左墙就是 WallLeft 那根 40px 宽的竖条，镜头又夹在 limit_left=0，
## 出生点在 x≈140，一开局画面最左边就是空的。这里在墙**外侧**补一整面岩壁：
## 从 x=-420 一直到贴着墙，轮廓做成锯齿状，分三层明暗，底部压暗、顶上有苔 ——
## 墙线从此变成"岩壁的内沿"，不是一根细线。
func _build_left_wall() -> void:
	var wall := Node2D.new()
	wall.name = "LeftWallArt"
	add_child(wall)
	# 三层：越靠左越暗（远离镜头），最外层几乎和背景一个色
	var layers := [
		{"from": -420.0, "to": 92.0, "color": Color(0.058, 0.068, 0.080), "jag": 34.0},
		{"from": -300.0, "to": 74.0, "color": Color(0.086, 0.100, 0.112), "jag": 22.0},
		{"from": -180.0, "to": 58.0, "color": Color(0.118, 0.134, 0.146), "jag": 12.0},
	]
	for i in range(layers.size()):
		var spec: Dictionary = layers[i]
		var x0: float = spec["from"]
		var x1: float = spec["to"]
		var color: Color = spec["color"]
		var jag: float = spec["jag"]
		var pts := PackedVector2Array()
		# 内沿（靠向玩家那一侧）画成折线：上窄下宽，像被凿出来的岩壁断面
		var y := world_top
		while y <= 700.0:
			var inset := jag * _rng.randf_range(0.35, 1.0) * (1.0 if int(y) % 2 == 0 else -0.4)
			pts.append(Vector2(x1 - inset, y))
			y += 46.0
		pts.append(Vector2(x1 - jag * 0.2, 700.0))
		pts.append(Vector2(x0, 760.0))
		pts.append(Vector2(x0, world_top))
		var poly := Polygon2D.new()
		# 每层的点顺序反过来攒的，先攒内沿再回外沿，直接拼成闭合多边形
		var closed := PackedVector2Array()
		closed.append(Vector2(x0, world_top))
		for p in pts:
			closed.append(p)
		poly.polygon = closed
		poly.color = color
		wall.add_child(poly)
	# 岩壁的裂缝：几条从上往下的暗线，别让三层色块太干净
	for k in range(5):
		var crack := Line2D.new()
		crack.width = 1.4
		crack.default_color = Color(0.028, 0.034, 0.040, 0.75)
		var cx := _rng.randf_range(-160.0, 40.0)
		var pts2 := PackedVector2Array()
		var cy := -140.0
		while cy < 660.0:
			pts2.append(Vector2(cx + _rng.randf_range(-9.0, 9.0), cy))
			cy += _rng.randf_range(70.0, 130.0)
		crack.points = pts2
		wall.add_child(crack)
	# 墙根一撮苔和碎石：岩壁落地的位置不能是一刀切
	for k in range(6):
		var moss := Polygon2D.new()
		moss.color = Color(0.130, 0.205, 0.170, 0.5)
		var mx := _rng.randf_range(-60.0, 54.0)
		moss.polygon = PackedVector2Array([
			Vector2(mx, 659.0), Vector2(mx + _rng.randf_range(10.0, 26.0), 659.0),
			Vector2(mx + 8.0, 659.0 - _rng.randf_range(3.0, 9.0)),
		])
		wall.add_child(moss)
	# 墙上一盏极暗的壁灯，给"这面墙是人凿的"一个线索（不亮，只是轮廓）
	var bracket := Node2D.new()
	bracket.position = Vector2(-40.0, 470.0)
	wall.add_child(bracket)
	var arm := Polygon2D.new()
	arm.color = Color(0.086, 0.098, 0.108, 0.95)
	arm.polygon = PackedVector2Array([
		Vector2(-26, 0), Vector2(6, -2), Vector2(8, 4), Vector2(-24, 6),
	])
	bracket.add_child(arm)
	var cup := Polygon2D.new()
	cup.color = Color(0.140, 0.130, 0.118, 0.9)
	cup.polygon = PackedVector2Array([
		Vector2(-6, 2), Vector2(6, 2), Vector2(4, 10), Vector2(-4, 10),
	])
	bracket.add_child(cup)

## 左右两堵墙的墙面装饰（M5-30，组长"有墙壁的部分要修饰，现在都是直直地下来"）。
##
## 原来 WallLeft / WallRight 就是两根 40px 宽的纯色竖条，从上到下一条直线。
## 这里在墙**内部**（不越出碰撞盒，避免又出现"没有碰撞的灰块"）画：
## 岩层横缝、两条裂缝、几块凸出的石棱、墙根的苔，以及两盏壁灯架。
## 画在墙自己的局部坐标里，跟着墙走 —— 墙在关卡里被挪到地图两端也自动对。
func _build_wall_detail() -> void:
	for body_name in ["WallLeft", "WallRight"]:
		var body := get_parent().get_node_or_null(str(body_name)) as StaticBody2D
		if body == null:
			continue
		var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var shape := col.shape as RectangleShape2D if col != null else null
		if shape == null:
			continue
		var half_w := shape.size.x * 0.5
		var half_h := shape.size.y * 0.5
		var top := -half_h
		var bottom := half_h
		var detail := Node2D.new()
		detail.name = "WallDetail"
		body.add_child(detail)

		# ① 岩层横缝：一层层往下砌，缝的位置错开一点
		var y := top + 30.0
		var row := 0
		while y < bottom - 20.0:
			var seam := Line2D.new()
			seam.name = "WallCourse"
			seam.width = 1.0
			seam.default_color = Color(0.030, 0.038, 0.046, 0.55)
			var inset := 3.0 + float(row % 3) * 3.5
			seam.points = PackedVector2Array([
				Vector2(-half_w + inset, y),
				Vector2(-half_w + 6.0, y + 1.5),
				Vector2(half_w - 6.0, y - 1.0),
				Vector2(half_w - inset, y),
			])
			detail.add_child(seam)
			y += 26.0
			row += 1

		# ② 两条纵向裂缝，打断"一根直条"的观感
		for k in range(2):
			var crack := Line2D.new()
			crack.name = "WallCrack"
			crack.width = 1.4
			crack.default_color = Color(0.022, 0.028, 0.034, 0.7)
			var cx := -half_w * 0.35 + float(k) * half_w * 0.7
			var pts := PackedVector2Array()
			var cy := top + _rng.randf_range(20.0, 60.0)
			while cy < bottom - 40.0:
				pts.append(Vector2(cx + _rng.randf_range(-3.0, 3.0), cy))
				cy += _rng.randf_range(50.0, 110.0)
			crack.points = pts
			detail.add_child(crack)

		# ③ 凸出的石棱：贴在墙面上，朝玩家那一侧（左墙朝右、右墙朝左）
		var dir := 1.0 if str(body_name) == "WallLeft" else -1.0
		var ledge_y := top + 90.0
		while ledge_y < bottom - 60.0:
			var w := _rng.randf_range(6.0, 10.0)
			var h := _rng.randf_range(4.0, 8.0)
			var block := Polygon2D.new()
			block.name = "WallLedge"
			var tone := _rng.randf_range(0.105, 0.150)
			block.color = Color(tone, tone * 1.08, tone * 1.14, 0.95)
			block.polygon = PackedVector2Array([
				Vector2(dir * (half_w - 1.0), ledge_y), Vector2(dir * (half_w - w), ledge_y + h * 0.4),
				Vector2(dir * (half_w - w), ledge_y + h), Vector2(dir * (half_w - 1.0), ledge_y + h * 0.6),
			])
			detail.add_child(block)
			ledge_y += _rng.randf_range(70.0, 160.0)

		# ④ 墙根的苔：贴地那一段
		var moss_y := bottom - 6.0
		for k in range(5):
			var moss := Polygon2D.new()
			moss.name = "WallMoss"
			moss.color = Color(0.120, 0.190, 0.158, 0.5)
			var mx := _rng.randf_range(-half_w + 2.0, half_w - 12.0)
			var mw := _rng.randf_range(8.0, 20.0)
			moss.polygon = PackedVector2Array([
				Vector2(mx, moss_y), Vector2(mx + mw, moss_y),
				Vector2(mx + mw - 3.0, moss_y - _rng.randf_range(3.0, 7.0)),
			])
			detail.add_child(moss)

		# ⑤ 两盏壁灯架：给"这是一面人砌的墙"一个线索，也顺便打断竖条
		for gy in [top + 190.0, bottom - 260.0]:
			var bracket := Node2D.new()
			bracket.name = "WallBracket"
			bracket.position = Vector2(dir * (half_w - 4.0), gy)
			detail.add_child(bracket)
			var arm := Polygon2D.new()
			arm.color = Color(0.090, 0.102, 0.112, 0.95)
			arm.polygon = PackedVector2Array([
				Vector2(0, 0), Vector2(-dir * 16.0, 2.0), Vector2(-dir * 15.0, 7.0), Vector2(0, 5.0),
			])
			bracket.add_child(arm)
			var cup := Polygon2D.new()
			cup.color = Color(0.150, 0.138, 0.122, 0.9)
			cup.polygon = PackedVector2Array([
				Vector2(-4.0, 1.0), Vector2(4.0, 1.0), Vector2(3.0, 8.0), Vector2(-3.0, 8.0),
			])
			bracket.add_child(cup)

## 地面下方（M5-27，组长反馈"地面底下是空的"）。
##
## 地面本体只有 60px 厚（659..689），再往下就是天空渐变 —— 站在地面上往下看是一片空虚。
## 这里补一整块"岩体"：669 往下一直到 980，分三层，加水平岩层线和几块大石。
## 悬崖那一段（gap_from..gap_to）故意不填 —— 那儿本来就是深渊。
func _build_under_ground() -> void:
	var mass := Node2D.new()
	mass.name = "UnderGround"
	add_child(mass)
	var bands := [
		{"top": 686.0, "bottom": 760.0, "color": Color(0.155, 0.172, 0.185)},
		{"top": 760.0, "bottom": 860.0, "color": Color(0.110, 0.126, 0.140)},
		{"top": 860.0, "bottom": 1000.0, "color": Color(0.072, 0.084, 0.096)},
	]
	var spans := [[-200.0, gap_from if gap_from >= 0.0 else world_width + 200.0]]
	if gap_from >= 0.0:
		spans.append([gap_to, world_width + 200.0])
	for span in spans:
		var x0: float = span[0]
		var x1: float = span[1]
		for band in bands:
			var poly := Polygon2D.new()
			poly.name = "UndergroundBand"
			poly.color = band["color"]
			var top: float = band["top"]
			var bottom: float = band["bottom"]
			var pts := PackedVector2Array()
			# 上沿不拉直线：每 180px 抖一下，像自然岩层的断面
			var x := x0
			while x <= x1:
				pts.append(Vector2(x, top + _rng.randf_range(-5.0, 5.0)))
				x += 180.0
			x = x1
			while x >= x0:
				pts.append(Vector2(x, bottom + _rng.randf_range(-8.0, 8.0)))
				x -= 180.0
			poly.polygon = pts
			mass.add_child(poly)
		# 岩层横线：把三大块再切细，读得出"一层一层压下去"
		for band in bands:
			var y0: float = band["top"]
			var step := 26.0
			while y0 < float(band["bottom"]) - 10.0:
				var seam := Line2D.new()
				seam.width = 1.0
				seam.default_color = Color(0.030, 0.036, 0.042, 0.55)
				seam.points = PackedVector2Array([Vector2(x0 + 10.0, y0), Vector2(x1 - 10.0, y0)])
				mass.add_child(seam)
				y0 += step
		# 几块大石：从地底往上顶出来的圆钝岩块
		var bx := x0 + 120.0
		while bx < x1 - 100.0:
			var boulder := Polygon2D.new()
			boulder.color = Color(0.180, 0.196, 0.208, 0.95)
			boulder.polygon = _boulder_points(bx, 690.0 + _rng.randf_range(0.0, 40.0),
				_rng.randf_range(26.0, 54.0))
			mass.add_child(boulder)
			# 石头顶上一线受光，不然和岩层糊成一团。多边形点已经是世界坐标，
			# 取"最高的那一小段"（y 最小的几个点）连起来。
			var lit := Line2D.new()
			lit.width = 1.4
			lit.default_color = Color(0.300, 0.320, 0.325, 0.45)
			var pts_all := boulder.polygon
			var top_y := 1.0e9
			for p in pts_all:
				top_y = minf(top_y, p.y)
			var lit_pts := PackedVector2Array()
			for p in pts_all:
				if p.y <= top_y + 14.0:
					lit_pts.append(p)
			if lit_pts.size() >= 2:
				lit.points = lit_pts
				mass.add_child(lit)
			bx += _rng.randf_range(220.0, 420.0)

## 一块圆钝的石头（半埋在岩层里，只露上半截）
func _boulder_points(cx: float, cy: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 9
	for i in range(steps + 1):
		var a := PI + PI * float(i) / float(steps)      # 半圆，开口朝下
		var wob := 1.0 + sin(float(i) * 2.1 + cx * 0.01) * 0.18
		pts.append(Vector2(cx + cos(a) * r * wob, cy + sin(a) * r * wob * 0.62))
	pts.append(Vector2(cx + r, cy + r * 0.4))
	pts.append(Vector2(cx - r, cy + r * 0.4))
	return pts

## 地表细节（M5-27）：草、碎石、干裂，贴着地面顶边撒，让地面不是一块光板。
## 全部画在 z=-1（地形之上、角色之下），且**不超出地面顶边 8px**，
## 免得又变成"走过去踩不到的小灰块"（M5-25 那条教训）。
func _build_surface_detail() -> void:
	var holder := Node2D.new()
	holder.name = "SurfaceDetail"
	holder.z_index = 2          # 父节点 -3 → 世界 -1
	add_child(holder)
	var x := 60.0
	while x < world_width - 60.0:
		if not _over_gap(x):
			var r := _rng.randf()
			if r < 0.55:
				_add_grass_tuft(holder, x)
			else:
				_add_pebbles(holder, x)
		x += _rng.randf_range(34.0, 78.0)

## 一撮草：3~5 根细叶，从地面往上冒 7~13px，根部压暗
func _add_grass_tuft(parent: Node2D, x: float) -> void:
	var tuft := Node2D.new()
	tuft.position = Vector2(x, 659.0)
	parent.add_child(tuft)
	var blades := int(_rng.randf_range(3.0, 6.0))
	for i in range(blades):
		var blade := Line2D.new()
		blade.width = 1.2
		blade.default_color = Color(0.115, 0.185, 0.150, 0.65)
		var lx := _rng.randf_range(-7.0, 7.0)
		var h := _rng.randf_range(7.0, 13.0)
		var lean := _rng.randf_range(-4.0, 5.0)
		blade.points = PackedVector2Array([
			Vector2(lx, 0.0),
			Vector2(lx + lean * 0.5, -h * 0.6),
			Vector2(lx + lean, -h),
		])
		tuft.add_child(blade)
	# 根部的暗影：草不会凭空长在一块亮板上
	var root := Polygon2D.new()
	root.color = Color(0.045, 0.060, 0.052, 0.55)
	root.polygon = PackedVector2Array([
		Vector2(-9.0, 1.0), Vector2(9.0, 1.0), Vector2(6.0, -1.5), Vector2(-6.0, -1.5),
	])
	tuft.add_child(root)

## 两三块碎石：半埋在地表，露出来的高度 ≤5px，读作"地面的碎石"而不是台阶
func _add_pebbles(parent: Node2D, x: float) -> void:
	var group := Node2D.new()
	group.position = Vector2(x, 659.0)
	parent.add_child(group)
	var count := int(_rng.randf_range(2.0, 4.0))
	for i in range(count):
		var rock := Polygon2D.new()
		rock.color = Color(0.150, 0.166, 0.176, 0.95)
		var w := _rng.randf_range(5.0, 11.0)
		var h := _rng.randf_range(2.5, 5.0)
		var px := _rng.randf_range(-14.0, 14.0)
		rock.polygon = PackedVector2Array([
			Vector2(px - w, 0.5), Vector2(px - w * 0.4, 0.5 - h),
			Vector2(px + w * 0.5, 0.5 - h * 0.8), Vector2(px + w, 0.5),
		])
		group.add_child(rock)
		# 顶上一线亮边：石头的受光面
		var rim := Line2D.new()
		rim.width = 1.0
		rim.default_color = Color(0.260, 0.285, 0.290, 0.55)
		rim.points = PackedVector2Array([
			Vector2(px - w * 0.4, 0.5 - h), Vector2(px + w * 0.5, 0.5 - h * 0.8),
		])
		group.add_child(rim)

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
		# 组长反馈：坑边的灰矩形看着像一块能站的平台，走上去却没有碰撞 ——
		# 那是这层远景断柱。把颜色压暗、轮廓光减弱，让它们退到雾里当背景，
		# 不再和前景石台抢同一个灰度。
		pillar.color = Color(0.105, 0.125, 0.140)
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
		rim.default_color = Color(0.24, 0.32, 0.34, 0.26)
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
		# M5-11：悬崖右岸是运行时新建的地面，也得和左岸一样补亮边/砖缝，不然右岸是一块纯灰
		"GroundRight": STONE_GROUND,
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
		# M5-30（组长："第一层的地图就很好，教学关照着做就行"）：
		# 地形不给矩形了，换成和第一层同一套岩体轮廓（顶面两个点严格贴碰撞顶边，
		# 左右各鼓几像素、底部挂几块碎岩），一眼看不出是"方盒子拼的"。
		if not body_name.begins_with("Wall"):
			var rect := _body_rect(body)
			if rect.size != Vector2.ZERO:
				visual.scale = Vector2.ONE
				visual.position = Vector2.ZERO
				visual.polygon = _rock_silhouette(rect.size, int(rect.position.x) % 5)
		# M5-28：地形统一压到 z=-1。这样"全局材质层"（z=0，插在 Player 前面）能盖住地形，
		# 又不会盖住玩家 —— 地形和玩家都是 z=0 时只能靠树的先后顺序，平台节点在 Player 后面，
		# 材质层就永远被平台压住（组长看到的就是"平台还是一块平灰"）。
		body.z_index = -1
		var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col == null or col.shape == null:
			continue
		if body_name.begins_with("Wall"):
			_add_wall_rim(body, body_name)
			continue
		# M5-28：顶面亮边不再按块画（那样方台底下会多出一道亮纹），
		# 改由 `_build_terrain_material()` 沿整条地形轮廓画一条连续的。
		_add_seams_and_moss(body, col)
		# M5-28（组长反馈"矩形地面拼上去一眼看出接缝，高台和平地材质不一样"）：
		# 地面断面的石块/砌层不再按"每块地形自己"画，改成 `_build_terrain_material()`
		# 在**世界坐标**里统一铺一层，跨过地面/平台/台阶的边界，看不出拼接。

## 全局地形材质（M5-28）。
##
## 原来的做法是每块地形（GroundLeft / JumpPlatform / …）各自在自己的局部坐标里
## 从左上角开始铺泥土层、石块、横缝 —— 两块地形挨着的时候，图案在边界处断掉，
## 高台又用了另一种底色，于是"高台像是贴上去的"，而且边界上还有一条明显的分界。
##
## 现在：所有地形共用同一种石材底色，石块、砌层、竖缝全部按**世界坐标**铺，
## 只画在"落在某块地形内部"的那些位置 —— 岩浆一层连续的石壁，穿过平台和地面。
## 画出来的东西挂在地形节点下面（继承它的层级），所以既在视觉层之上，又不会挡住玩家。
func _build_terrain_material() -> void:
	var rects := _terrain_rects()
	if rects.is_empty():
		return
	var anchor := get_parent().get_node_or_null("GroundLeft") as StaticBody2D
	if anchor == null:
		anchor = get_parent().get_node_or_null("JumpPlatform") as StaticBody2D
	if anchor == null:
		return
	# 挂到关卡根上、并插到 Player 前面：
	# 地形和玩家都是 z=0，同级按树的先后顺序画 —— 放在玩家之前，就"盖住地形、不盖角色"。
	var parent := get_parent()
	var root := Node2D.new()
	root.name = "TerrainMaterial"
	parent.add_child(root)
	var player := parent.get_node_or_null("Player")
	if player != null:
		parent.move_child(root, player.get_index())

	var top := 1.0e9
	var bottom := -1.0e9
	for r in rects:
		top = minf(top, r.position.y)
		bottom = maxf(bottom, r.end.y)

	# ① 砌层：横向一格格铺，每格颜色深浅略有不同（不是一条均匀的灰）
	var y := top + 6.0
	var row := 0
	while y < bottom - 2.0:
		var tone := 0.150 + float(row % 3) * 0.012 + _rng.randf_range(-0.006, 0.006)
		for span in _spans_at(rects, y):
			var band := Polygon2D.new()
			band.name = "CourseBand"
			band.color = Color(tone, tone * 1.05, tone * 1.10, 0.55)
			band.polygon = PackedVector2Array([
				Vector2(span.x, y), Vector2(span.y, y),
				Vector2(span.y, y + 12.0), Vector2(span.x, y + 12.0),
			])
			root.add_child(band)
			var seam := Line2D.new()
			seam.name = "CourseSeam"
			seam.width = 1.0
			seam.default_color = Color(0.052, 0.062, 0.070, 0.42)
			seam.points = PackedVector2Array([Vector2(span.x + 2.0, y + 0.5), Vector2(span.y - 2.0, y + 0.5)])
			root.add_child(seam)
		y += 12.0
		row += 1

	# ② 石块：按世界网格铺，只在落进地形里的位置画，跨越边界也不断。
	# M5-28 二次调整：石块原来等宽等高、一行行排得太齐，看着像贴砖 ——
	# 现在宽高随机、每块单独错位、随机跳过一些、边上再补几块大石，才像天然岩面。
	var gx := -80.0
	while gx < world_width + 80.0:
		var stones_y := top + 4.0
		while stones_y < bottom - 4.0:
			var cx := gx + _rng.randf_range(-14.0, 14.0)
			var cy := stones_y + _rng.randf_range(-7.0, 7.0)
			if _inside_terrain(rects, Vector2(cx, cy)) and _rng.randf() > 0.12:
				var w := _rng.randf_range(20.0, 58.0)
				var h := _rng.randf_range(7.0, 15.0)
				var tone2 := _rng.randf_range(0.138, 0.222)
				var stone := Polygon2D.new()
				stone.name = "TerrainStone"
				stone.color = Color(tone2, tone2 * 1.04, tone2 * 1.10, 0.90)
				var skew := _rng.randf_range(-3.0, 3.0)
				var dent := _rng.randf_range(-3.0, 3.0)
				stone.polygon = PackedVector2Array([
					Vector2(cx - w * 0.5, cy + skew),
					Vector2(cx - w * 0.2, cy + skew - 1.6),
					Vector2(cx + w * 0.5, cy + skew + dent),
					Vector2(cx + w * 0.5 - 2.0, cy + skew + h),
					Vector2(cx - w * 0.5 + 2.0, cy + skew + h + 1.0),
				])
				root.add_child(stone)
				var lit := Line2D.new()
				lit.name = "TerrainStoneLit"
				lit.width = 1.0
				lit.default_color = Color(0.285, 0.300, 0.305, 0.16)
				lit.points = PackedVector2Array([
					Vector2(cx - w * 0.5 + 1.0, cy + skew + 1.0),
					Vector2(cx + w * 0.5 - 1.0, cy + skew + dent),
				])
				root.add_child(lit)
			stones_y += _rng.randf_range(11.0, 17.0)
		gx += _rng.randf_range(44.0, 92.0)

	# ③ 竖缝：稀疏几条，穿过平台和地面，让两块地形读成一整面石壁
	var jx := 40.0
	while jx < world_width - 20.0:
		var spans := _vspans_at(rects, jx)
		for span2 in spans:
			if span2.y - span2.x < 16.0:
				continue
			var joint := Line2D.new()
			joint.name = "TerrainJoint"
			joint.width = 1.0
			joint.default_color = Color(0.048, 0.058, 0.066, 0.36)
			var jitter := _rng.randf_range(-2.0, 2.0)
			joint.points = PackedVector2Array([
				Vector2(jx + jitter, span2.x + _rng.randf_range(4.0, 12.0)),
				Vector2(jx + jitter * 0.4, (span2.x + span2.y) * 0.5),
				Vector2(jx - jitter, span2.y - _rng.randf_range(4.0, 16.0)),
			])
			root.add_child(joint)
		jx += _rng.randf_range(120.0, 260.0)

	# ④ 顶面亮边：按**整个地形轮廓**画一条连续线（M5-28 二次修）。
	# 原来是一块地形画一条 —— 下劈方台坐在跳台顶面上的时候，跳台那条亮边正好从方台屁股底下穿过去，
	# 看着就是"平台底下有一道亮纹、再往下一刀切平"（组长指的就是这个）。
	# 现在只沿"每个横坐标最上面那层地形"画，方台底下那段自然没有线。
	_add_terrain_rim(root, rects)

## 每个 x 上，地形最上面那层的 y（没有地形返回 INF）
func _top_at(rects: Array[Rect2], x: float) -> float:
	var best := 1.0e9
	for r in rects:
		if x >= r.position.x and x <= r.end.x:
			best = minf(best, r.position.y)
	return best

## 顶面亮边 + 亮边下的暗影，沿整条轮廓（按断开的段分开画，悬崖那段自然断开）
func _add_terrain_rim(root: Node2D, rects: Array[Rect2]) -> void:
	var left := 1.0e9
	var right := -1.0e9
	for r in rects:
		left = minf(left, r.position.x)
		right = maxf(right, r.end.x)
	var segments: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	var prev_y := 1.0e9
	var x := left
	while x <= right + 0.1:
		var y := _top_at(rects, x)
		if y > 1.0e8 or (cur.size() >= 1 and absf(y - prev_y) > 4.0):
			# 没有地形，或者这里是个竖直落差（平台侧面）：断开，
			# 亮边只画在"能站人的水平顶面"上，侧面不留一道亮竖线
			if cur.size() >= 2:
				segments.append(cur)
			cur = PackedVector2Array()
			prev_y = 1.0e9
			x += 2.0
			continue
		cur.append(Vector2(x, y + 1.0))
		prev_y = y
		x += 2.0
	if cur.size() >= 2:
		segments.append(cur)
	for seg in segments:
		var rim := Line2D.new()
		rim.name = "TerrainRim"
		rim.width = 2.0
		rim.default_color = Color(0.335, 0.358, 0.362, 0.92)
		rim.points = seg
		root.add_child(rim)
		var shade := Line2D.new()
		shade.name = "TerrainRimShade"
		shade.width = 2.0
		shade.default_color = Color(0.040, 0.050, 0.058, 0.60)
		var shifted := PackedVector2Array()
		for p in seg:
			shifted.append(p + Vector2(0.0, 3.5))
		shade.points = shifted
		root.add_child(shade)

## 地形矩形（世界坐标）：地面、平台、台阶都算
func _terrain_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var parent := get_parent()
	for n in ["GroundLeft", "GroundRight", "PitFloor", "JumpPlatform", "PogoPlatform", "AltarPlatform"]:
		var body := parent.get_node_or_null(n) as StaticBody2D
		if body == null:
			continue
		var r := _body_rect(body)
		if r.size != Vector2.ZERO:
			out.append(r)
	for holder_name in ["HollowSteps", "CorridorGallery"]:
		var holder := parent.get_node_or_null(str(holder_name))
		if holder == null:
			continue
		for child in holder.get_children():
			var body2 := child as StaticBody2D
			if body2 == null:
				continue
			var r2 := _body_rect(body2)
			if r2.size != Vector2.ZERO:
				out.append(r2)
	return out

func _body_rect(body: StaticBody2D) -> Rect2:
	var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or col.shape == null:
		return Rect2()
	var shape := col.shape as RectangleShape2D
	if shape == null:
		return Rect2()
	var size := shape.size
	return Rect2(body.global_position + col.position - size * 0.5, size)

## 某一高度上，地形覆盖的横向区间（[x0, x1] 的 Vector2 列表，已合并重叠段）
func _spans_at(rects: Array[Rect2], y: float) -> Array[Vector2]:
	var raw: Array[Vector2] = []
	for r in rects:
		if y >= r.position.y and y <= r.end.y:
			raw.append(Vector2(r.position.x, r.end.x))
	return _merge_spans(raw)

## 某一横坐标上，地形覆盖的纵向区间
func _vspans_at(rects: Array[Rect2], x: float) -> Array[Vector2]:
	var raw: Array[Vector2] = []
	for r in rects:
		if x >= r.position.x and x <= r.end.x:
			raw.append(Vector2(r.position.y, r.end.y))
	return _merge_spans(raw)

func _merge_spans(raw: Array[Vector2]) -> Array[Vector2]:
	var list := raw.duplicate()
	list.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array[Vector2] = []
	for s in list:
		if out.is_empty() or s.x > out[out.size() - 1].y + 0.5:
			out.append(s)
		else:
			out[out.size() - 1].y = maxf(out[out.size() - 1].y, s.y)
	return out

func _inside_terrain(rects: Array[Rect2], p: Vector2) -> bool:
	for r in rects:
		if r.has_point(p):
			return true
	return false

	# M5-25（组长反馈"坑两边灰色矩形、有个多出来的一点没有碰撞体积"）：
	# `_add_edge_chunks` 会在碰撞盒边缘**多画出去几像素**的碎石和垂根 ——
	# 那是纯装饰、没有碰撞，走过去看着像悬空的灰块。不画了，地形边缘就是碰撞边缘。

## 岩体轮廓（和第一层 floor1.gd 的 `_rock_silhouette` 同一套写法）：
## 顶面两点严格在 rect 的顶上（玩家踩的就是这条线），左右各鼓 3~7px、底部挂 5~9px 的碎岩。
func _rock_silhouette(size: Vector2, index: int) -> PackedVector2Array:
	var half := size.x * 0.5
	var h := size.y
	var top := -h * 0.5
	var bottom := h * 0.5
	var notch := 4.0 + float(index % 3) * 4.0
	var bulge := 3.0 + float(index % 2) * 5.0
	return PackedVector2Array([
		Vector2(-half, top),
		Vector2(half, top),
		Vector2(half - 1.0, top + 9.0),
		Vector2(half + bulge, top + 26.0),
		Vector2(half - notch, top + 50.0),
		Vector2(half - 2.0, top + 68.0),
		Vector2(half - 16.0, bottom - 8.0),
		Vector2(half - 32.0, bottom + 5.0),
		Vector2(8.0, bottom + 9.0),
		Vector2(-half + 30.0, bottom + 3.0),
		Vector2(-half + 7.0, bottom - 16.0),
		Vector2(-half - bulge, top + 58.0),
		Vector2(-half + notch, top + 24.0),
	])

func _add_seams_and_moss(body: StaticBody2D, col: CollisionShape2D) -> void:
	var shape := col.shape as RectangleShape2D
	if shape == null:
		return
	var half_w := shape.size.x * 0.5
	var top_y := col.position.y - shape.size.y * 0.5
	var left := col.position.x - half_w
	var right := col.position.x + half_w
	var bottom := col.position.y + shape.size.y * 0.5
	# M5-28：横向砌层已改由 `_build_terrain_material()` 在世界坐标里统一铺，
	# 这里不再按"每块地形自己"画横缝 —— 那样两块地形挨着时图案会在边界断掉。
	# 砖缝：每隔约 90px 一道短竖线，不铺满，免得像栅栏
	# M5-20（组长反馈"借力跳高下方的平台两侧只有灰色矩形"）：
	# 原来砖缝只从顶面往下画 9px，矮平台够用，但下劈方台有 131px 高 ——
	# 一整面墙就只剩几条横线，侧面读起来是一块纯灰。现在按厚度决定缝的深度：
	# 越厚的平台缝越深，厚的直接打到离底 8px，侧面才有"砌起来的石头"的感觉。
	var seam_len := 9.0
	if shape.size.y > 48.0:
		seam_len = maxf(shape.size.y * 0.62, 18.0)
	var seam_x := left + 46.0
	while seam_x < right - 30.0:
		var seam := Line2D.new()
		seam.width = 1.0
		seam.default_color = Color(0.06, 0.075, 0.085, 0.55)
		# 缝不画成一条笔直的线：错开一点，才像石头砌缝而不是画格子
		var jitter := _rng.randf_range(-2.0, 2.0)
		seam.points = PackedVector2Array([
			Vector2(seam_x, top_y + 4.0),
			Vector2(seam_x + jitter, top_y + 4.0 + seam_len * 0.55),
			Vector2(seam_x - jitter, top_y + 4.0 + seam_len),
		])
		body.add_child(seam)
		seam_x += _rng.randf_range(72.0, 108.0)
	# 厚平台（下劈方台那种）再补几道从上到下的深裂，别让侧面是一整片均匀的灰
	if shape.size.y > 90.0:
		var crack_x := left + _rng.randf_range(28.0, 60.0)
		var crack := Line2D.new()
		crack.width = 1.6
		crack.default_color = Color(0.045, 0.055, 0.065, 0.6)
		crack.points = PackedVector2Array([
			Vector2(crack_x, top_y + 6.0),
			Vector2(crack_x + _rng.randf_range(-8.0, 8.0), top_y + shape.size.y * 0.45),
			Vector2(crack_x + _rng.randf_range(-10.0, 10.0), bottom - 8.0),
		])
		body.add_child(crack)
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
	# M5-12：装饰位置不再写死到 4860（地图 M4-19 之后拉到 6250，右边一千多像素一片空墙，
	# 看起来就是"后半段没做完"）。现在按 world_width 铺：每 560px 一条链、每 700px 一盏灯，
	# 一直铺到最后一屏；落在悬崖上的自动跳过（见 _over_gap）。
	for x in _spread(180.0, 560.0):
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
	# 吊灯：入口那盏最亮，越往后越暗，但每一段路至少有一处暖色
	var lantern_i := 0
	for x in _spread(232.0, 700.0):
		if _over_gap(x):
			continue
		var strength := clampf(0.42 - float(lantern_i) * 0.035, 0.16, 0.42)
		_add_lantern(props, Vector2(x, 505.0 + float(lantern_i % 2) * 6.0), 210.0,
			strength, strength * 0.68)
		lantern_i += 1
	# 立在台面上的断柱：M5-22（组长反馈「史莱克村再往前走那里有一个灰色矩形，删除掉」
	# 「降下去的地方也有一个矩形，也删除」）——这些断柱在深色背景上就是一块纯灰的矩形，
	# 读起来像没做完的占位方块，不像柱子。不调颜色了，直接**不放**：
	# 近景只留吊灯、锁链、碎石，地形本身有亮边和砖缝，画面反而干净。
	# （_add_broken_pillar 函数留着：楼层脚本自己要立柱子时还在用同一套画法。）
	# 碎石：地面散几块，别让地面是一条直线（悬崖跳过）
	for i in range(int(world_width / 420.0) + 4):
		var rock := Polygon2D.new()
		rock.color = Color(0.12, 0.14, 0.15, 0.95)
		var size := _rng.randf_range(6.0, 14.0)
		rock.polygon = PackedVector2Array([
			Vector2(-size, 0), Vector2(-size * 0.4, -size * 0.7),
			Vector2(size * 0.5, -size * 0.5), Vector2(size, 0),
		])
		var rx := _rng.randf_range(320.0, world_width - 300.0)
		if _over_gap(rx):
			continue
		rock.position = Vector2(rx, 659.0 - _rng.randf_range(0.0, 3.0))
		props.add_child(rock)
	# 尸体不再由背景美术兼职：M4-21 起由 components/prop_corpse.gd 自己建模
	# （原来这里只是把占位方块染成土黄 + 补四根肋骨，组长说“就一个黄色矩形”）

## 从 start 开始、每隔 step 取一个点，直到地图右端留 200px 余量
func _spread(start: float, step: float) -> Array:
	var out: Array = []
	var x := start
	while x < world_width - 200.0:
		out.append(x)
		x += step
	return out

## 这个 x 是不是落在悬崖上方（没有地面，装饰别浮在那里）
func _over_gap(x: float) -> bool:
	return gap_from >= 0.0 and x >= gap_from - 40.0 and x <= gap_to + 40.0

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
## M4-23 组长反馈：这些灰柱子“看着像能站上去的平台，走上去却没有碰撞”，
## 还有几处地面被当成“纯色矩形错误地形”。现在把它们压到只比远景亮一点的灰，
## 轮廓光砍半，并在柱脚加一道贴地暗影 —— 读起来是背景里的旧柱子，不是可站的地形。
func _add_broken_pillar(parent: Node2D, x: float, base_y: float, height: float, width: float) -> void:
	var half := width * 0.5
	var pillar := Polygon2D.new()
	pillar.color = Color(0.105, 0.120, 0.132, 1)
	pillar.polygon = PackedVector2Array([
		Vector2(x - half, base_y - 6.0), Vector2(x - half, base_y - height),
		Vector2(x - half + 8.0, base_y - height + 14.0),
		Vector2(x + half - 7.0, base_y - height - 10.0),
		Vector2(x + half, base_y - height + 4.0),
		Vector2(x + half, base_y - 6.0),
	])
	parent.add_child(pillar)
	# 贴地暗影：柱子压在背景里，别让它像一块浮着的地形
	var shadow := Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.32)
	shadow.polygon = _ellipse(half + 7.0, 4.5, 12)
	shadow.position = Vector2(x, base_y - 3.0)
	parent.add_child(shadow)
	var rim := Line2D.new()
	rim.width = 1.4
	rim.default_color = Color(0.24, 0.31, 0.33, 0.22)
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
