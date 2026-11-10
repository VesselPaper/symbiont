extends Node2D
## 深渊背景（美术底座，所有层共用）
##
## 一套东西五层叠加，做出"深、冷、有空气"的纵深感：
##   1 天光：屏幕空间竖直渐变 + 右上斜下来的冷光（CanvasLayer，不随相机动）
##   2 远景剪影：尖塔/断墙，视差系数小，几乎不动，压暗成雾色，边缘一道冷色轮廓光
##   3 中景建筑：尖拱、断柱，视差稍快；入口处固定一座大拱门当构图支点
##   4 前景垂藤：视差比相机快，压在角色前面，制造"从枝叶下穿过去"的感觉
##   5 雾团、飘尘、暗角
##
## 用法：关卡根下放一个 Node2D，挂这个脚本，把 camera_path 指向相机，
## 按关卡尺寸设 world_width / world_bottom。剪影全部代码生成，不依赖图片。
## 随机种子固定，同一关卡每次打开长得一样。

const SKY_SHADER := preload("res://assets/shaders/abyss_sky.gdshader")
const VIGNETTE_SHADER := preload("res://assets/shaders/vignette.gdshader")

@export var camera_path: NodePath
@export var world_width := 2800.0
@export var world_top := -320.0
@export var world_bottom := 1400.0
@export var seed_value := 20261110
## 远景剪影颜色（比天空略亮，靠"雾化"退到后面；比中景亮，才有空气透视）
@export var far_color := Color(0.135, 0.180, 0.200)
## 中景剪影颜色（比远景深一点）
@export var mid_color := Color(0.032, 0.046, 0.058)
## 前景垂藤颜色（几乎全黑）
@export var vine_color := Color(0.010, 0.014, 0.018)
## 剪影轮廓光：只描亮边，不填色，让黑块从背景里"浮"出来
@export var rim_color := Color(0.20, 0.34, 0.36, 0.45)
@export var spore_color := Color(0.62, 0.84, 0.82, 0.55)
## 入口大拱门背后的冷光，给构图一个亮点
@export var arch_glow := Color(0.18, 0.48, 0.48, 0.12)

var _camera: Node2D
var _layers: Array[Dictionary] = []
var _fog: Array[Dictionary] = []
var _spores: CPUParticles2D
var _rng := RandomNumberGenerator.new()
var _time := 0.0

func _ready() -> void:
	_rng.seed = seed_value
	if camera_path != NodePath(""):
		_camera = get_node_or_null(camera_path) as Node2D
	_build_sky()
	_build_spires("Far", 0.16, far_color, 300.0, 700.0, 150.0)
	_build_landmark()
	_build_arches("Mid", 0.34, mid_color)
	_build_vines("Vines", 1.12)
	_build_foreground()
	_build_fog()
	_build_spores()
	_build_vignette()

func _process(delta: float) -> void:
	_time += delta
	if _camera == null:
		return
	# 视差：越远的层跟得越少；负系数（前景）比相机跑得还快
	for layer in _layers:
		var node: Node2D = layer["node"]
		var factor: float = layer["factor"]
		# 垂直视差只给 0.35 权重：太强会让悬崖上下滑，露馅
		node.position = Vector2(
			_camera.global_position.x * (1.0 - factor),
			_camera.global_position.y * (1.0 - factor) * 0.35
		)
	# 雾团慢慢横向漂，不跟相机
	for i in range(_fog.size()):
		var item := _fog[i]
		var node: Node2D = item["node"]
		var base: Vector2 = item["base"]
		node.position = base + Vector2(sin(_time * item["speed"] + item["phase"]) * 60.0, 0.0)
	# 飘尘跟着相机走，等于永远在视野里飘
	if _spores != null:
		_spores.position = _camera.global_position

# ---------- 每层怎么搭 ----------

func _build_sky() -> void:
	# CanvasLayer 的层号 -1：压在世界下面（世界层默认 0）
	var layer := CanvasLayer.new()
	layer.name = "Sky"
	layer.layer = -1
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "SkyRect"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	rect.material = mat
	layer.add_child(rect)
	# 先入树、再套全屏锚点：CanvasLayer 下的 Control 以视口为父，设早了拿不到尺寸
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_spires(layer_name: String, factor: float, color: Color, h_min: float, h_max: float, spacing: float) -> void:
	var root := Node2D.new()
	root.name = layer_name
	add_child(root)
	var x := -world_width * 0.3
	var limit := world_width * 1.3
	while x < limit:
		var w := _rng.randf_range(spacing * 0.5, spacing * 0.95)
		var h := _rng.randf_range(h_min, h_max)
		var top := world_bottom - h
		# 每根塔明暗略有差别，一片同色会糊成一块
		var body_color := color.lightened(_rng.randf_range(0.0, 0.18))
		var body := Polygon2D.new()
		body.color = body_color
		var pts := PackedVector2Array([
			Vector2(x, world_bottom),
			Vector2(x + w * 0.06, top + h * 0.42),
			Vector2(x + w * 0.22, top + h * 0.30),
			Vector2(x + w * 0.40, top + h * 0.07),
			Vector2(x + w * 0.52, top),
			Vector2(x + w * 0.68, top + h * 0.10),
			Vector2(x + w * 0.84, top + h * 0.26),
			Vector2(x + w * 0.95, top + h * 0.44),
			Vector2(x + w, world_bottom),
		])
		body.polygon = pts
		root.add_child(body)
		# 左边一道轮廓光：光从上方来，亮边压左缘，黑剪影才有厚度
		var rim := Line2D.new()
		rim.width = _rng.randf_range(1.0, 2.0)
		rim.default_color = rim_color
		rim.points = PackedVector2Array([
			pts[1], pts[2], pts[3], pts[4],
		])
		root.add_child(rim)
		x += w + _rng.randf_range(spacing * 0.08, spacing * 0.34)
	_layers.append({"node": root, "factor": factor})

## 入口大拱门：固定位置，不随机。给开场一个"门在那儿"的构图支点，
## 也让玩家一眼知道该往右走。
func _build_landmark() -> void:
	var root := Node2D.new()
	root.name = "Landmark"
	add_child(root)
	var center := Vector2(60.0, world_bottom - 340.0)
	# 入口拱门固定摆在世界 x≈60：相机贴左边界时，视差后正好落在画面右半边，
	# 给开场一个"门在那儿"的支点，又不挡住出生点。
	# 拱门后面的冷光：径向渐变，越靠中心越亮，兼作远景空气透视
	var glow := Sprite2D.new()
	var tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	glow.texture = tex
	glow.modulate = arch_glow
	glow.scale = Vector2(5.5, 3.6)
	glow.position = center + Vector2(0, -20)
	root.add_child(glow)
	# 拱门本体：两根柱子 + 一圈尖拱石框（中间镂空，能透出后面的光）
	var arch := _arch_polygons(center.x - 130.0, world_bottom, 260.0, 430.0, 26.0)
	for poly in arch:
		var node := Polygon2D.new()
		node.color = mid_color.lightened(0.10)
		node.polygon = poly
		root.add_child(node)
	# 拱顶外缘轮廓光，和远处尖塔一个语言
	var arc_rim := Line2D.new()
	arc_rim.width = 2.0
	arc_rim.default_color = rim_color
	arc_rim.points = _arch_outer_arc(center.x - 130.0, world_bottom - 430.0, 260.0, 26.0)
	root.add_child(arc_rim)
	_layers.append({"node": root, "factor": 0.30})

func _build_arches(layer_name: String, factor: float, color: Color) -> void:
	var root := Node2D.new()
	root.name = layer_name
	add_child(root)
	var x := -world_width * 0.2
	var limit := world_width * 1.2
	while x < limit:
		var w := _rng.randf_range(120.0, 260.0)
		var h := _rng.randf_range(260.0, 700.0)
		var thick := _rng.randf_range(16.0, 30.0)
		var polys := _arch_polygons(x, world_bottom, w, h, thick)
		var tint := color.lightened(_rng.randf_range(0.0, 0.22))
		for poly in polys:
			var node := Polygon2D.new()
			node.color = tint
			node.polygon = poly
			root.add_child(node)
		# 断梁：一部分拱门顶上再压一块歪石，暗示这里塌过
		if _rng.randf() < 0.4:
			var beam := Polygon2D.new()
			beam.color = tint
			var by := world_bottom - h - _rng.randf_range(10.0, 60.0)
			beam.polygon = PackedVector2Array([
				Vector2(x - 20.0, by),
				Vector2(x + w + _rng.randf_range(20.0, 90.0), by - _rng.randf_range(20.0, 60.0)),
				Vector2(x + w + 40.0, by + 18.0),
				Vector2(x - 20.0, by + 30.0),
			])
			root.add_child(beam)
		x += w + _rng.randf_range(240.0, 520.0)
	_layers.append({"node": root, "factor": factor})

## 拱门几何：三块多边形（左柱、右柱、拱圈），拱圈中间是空的，透出背景光
func _arch_polygons(x: float, base_y: float, width: float, height: float, thick: float) -> Array:
	var spring_y := base_y - height          # 起拱线
	var cx := x + width * 0.5
	var r_out := width * 0.5 + thick
	var r_in := width * 0.5
	var left_pillar := PackedVector2Array([
		Vector2(x, base_y), Vector2(x, spring_y),
		Vector2(x + thick, spring_y), Vector2(x + thick, base_y),
	])
	var right_pillar := PackedVector2Array([
		Vector2(x + width - thick, base_y), Vector2(x + width - thick, spring_y),
		Vector2(x + width, spring_y), Vector2(x + width, base_y),
	])
	# 半圆拱圈：外圈从左扫到右，内圈再从右扫回左，中间自然镂空
	var ring := PackedVector2Array()
	var segments := 18
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var a := PI * (1.0 - t)
		ring.append(Vector2(cx + cos(a) * r_out, spring_y - sin(a) * r_out))
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var a := PI * t
		ring.append(Vector2(cx + cos(a) * r_in, spring_y - sin(a) * r_in))
	return [left_pillar, right_pillar, ring]

func _arch_outer_arc(x: float, base_y: float, width: float, thick: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cx := x + width * 0.5
	var r := width * 0.5 + thick
	var segments := 18
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var a := PI * (1.0 - t)
		pts.append(Vector2(cx + cos(a) * r, base_y - sin(a) * r))
	return pts

func _build_vines(layer_name: String, factor: float) -> void:
	var root := Node2D.new()
	root.name = layer_name
	add_child(root)
	var x := -world_width * 0.1
	var limit := world_width * 1.1
	while x < limit:
		# 从画面最上沿垂下来，长度要够到视野里；太短就全挂在镜头上面看不见
		var length := _rng.randf_range(520.0, 900.0)
		var line := Line2D.new()
		line.width = _rng.randf_range(3.0, 8.0)
		line.default_color = vine_color
		line.points = PackedVector2Array([
			Vector2(x, world_top),
			Vector2(x + _rng.randf_range(-30.0, 30.0), world_top + length * 0.45),
			Vector2(x + _rng.randf_range(-46.0, 46.0), world_top + length),
		])
		root.add_child(line)
		# 藤蔓末端挂一片更暗的叶影，破一下直线
		if _rng.randf() < 0.5:
			var leaf := Polygon2D.new()
			leaf.color = vine_color
			var tip: Vector2 = line.points[2]
			leaf.polygon = PackedVector2Array([
				tip + Vector2(-6, 0), tip + Vector2(2, 16), tip + Vector2(10, 4),
			])
			root.add_child(leaf)
		x += _rng.randf_range(260.0, 620.0)
	_layers.append({"node": root, "factor": factor})

## 前景：压在最靠前的一层，z_index 高于角色，形成遮挡框住画面
func _build_foreground() -> void:
	var root := Node2D.new()
	root.name = "Foreground"
	root.z_index = 6
	add_child(root)
	# 从近到远的几根粗藤：最靠前的两根在出生画面里正好框住左右两边
	var xs := [100.0, 380.0, 620.0, 900.0, 1400.0, 1900.0, 2400.0]
	for x in xs:
		var line := Line2D.new()
		line.width = _rng.randf_range(11.0, 18.0)
		line.default_color = Color(0.012, 0.018, 0.022, 0.95)
		var length := _rng.randf_range(620.0, 1000.0)
		line.points = PackedVector2Array([
			Vector2(x, world_top),
			Vector2(x + _rng.randf_range(-40.0, 40.0), world_top + length * 0.5),
			Vector2(x + _rng.randf_range(-60.0, 60.0), world_top + length),
		])
		# 越往下越细，不然像一根黑柱子
		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 1.0))
		taper.add_point(Vector2(0.7, 0.55))
		taper.add_point(Vector2(1.0, 0.15))
		line.width_curve = taper
		root.add_child(line)
	# 左下角一块近黑岩影，把画面边缘压住
	var rock := Polygon2D.new()
	rock.color = Color(0.012, 0.016, 0.022, 1)
	rock.polygon = PackedVector2Array([
		Vector2(-40.0, world_bottom + 60.0),
		Vector2(-40.0, world_bottom - 180.0),
		Vector2(30.0, world_bottom - 250.0),
		Vector2(110.0, world_bottom - 160.0),
		Vector2(150.0, world_bottom + 60.0),
	])
	root.add_child(rock)
	_layers.append({"node": root, "factor": 1.16})

func _build_fog() -> void:
	var root := Node2D.new()
	root.name = "Fog"
	add_child(root)
	for i in range(4):
		var fog := Polygon2D.new()
		fog.color = Color(0.16, 0.24, 0.27, 0.05 + i * 0.012)
		fog.polygon = _ellipse(520.0 + i * 160.0, 120.0 + i * 40.0, 28)
		var base := Vector2(world_width * (0.18 + 0.3 * i), world_bottom - 320.0 - i * 180.0)
		fog.position = base
		root.add_child(fog)
		_fog.append({"node": fog, "base": base, "speed": 0.08 + i * 0.03, "phase": i * 1.7})
	# 贴地雾：只铺在平台高度附近，让地面和深渊之间有一层空气
	for i in range(2):
		var mist := Polygon2D.new()
		mist.color = Color(0.18, 0.28, 0.30, 0.06)
		mist.polygon = _ellipse(620.0, 70.0, 24)
		mist.position = Vector2(world_width * (0.25 + 0.4 * i), world_bottom - 60.0)
		root.add_child(mist)

func _build_spores() -> void:
	_spores = CPUParticles2D.new()
	_spores.name = "Spores"
	_spores.amount = 90
	_spores.lifetime = 9.0
	_spores.preprocess = 3.0
	_spores.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_spores.emission_rect_extents = Vector2(820.0, 460.0)
	_spores.direction = Vector2(0, -1)
	_spores.spread = 180.0
	_spores.gravity = Vector2(0, 0)
	_spores.initial_velocity_min = 3.0
	_spores.initial_velocity_max = 12.0
	_spores.scale_amount_min = 0.5
	_spores.scale_amount_max = 1.8
	_spores.color = spore_color
	_spores.texture = _dot_texture()
	# 加色混合：尘点叠在暗背景上会微微发光，比普通半透明更"空气"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_spores.material = mat
	_spores.z_index = 3
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

# ---------- 小工具 ----------

func _ellipse(rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _dot_texture() -> ImageTexture:
	# 4x4 的软圆点，代码生成，避免为粒子单独存一张图
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			var d := Vector2(x - 1.5, y - 1.5).length() / 2.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
