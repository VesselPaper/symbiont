extends Node2D
## 灵魂本体（M4-52）：虚空和教学关共用同一套造型与呼吸感。
## 亮核 + 雾体 + 径向光晕 + 三根飘带；带上下浮动、飘带摆动、光晕呼吸。

var _t := 0.0
var _core: Polygon2D
var _haze: Polygon2D
var _glow: PointLight2D
var _tendrils: Array = []
var _base := Vector2.ZERO

func _ready() -> void:
	_base = position
	_build()

func _build() -> void:
	_glow = PointLight2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.88, 0.94, 1.0, 0.95))
	grad.set_color(1, Color(0.55, 0.70, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_glow.texture = tex
	_glow.texture_scale = 1.5
	_glow.energy = 1.15
	add_child(_glow)

	_haze = Polygon2D.new()
	_haze.color = Color(0.60, 0.73, 0.95, 0.16)
	_haze.polygon = _ellipse(15.0, 21.0, 14)
	add_child(_haze)

	_core = Polygon2D.new()
	_core.color = Color(0.94, 0.98, 1.0, 0.98)
	_core.polygon = _ellipse(6.6, 9.2, 14)
	add_child(_core)

	for i in range(3):
		var t := Line2D.new()
		t.width = 1.9 - 0.45 * float(i)
		t.default_color = Color(0.80, 0.90, 1.0, 0.34)
		var x := -5.0 + 5.0 * float(i)
		t.points = PackedVector2Array([Vector2(x, 9), Vector2(x * 1.5, 26), Vector2(x * 2.0, 44)])
		add_child(t)
		_tendrils.append(t)

func _process(delta: float) -> void:
	_t += delta
	# 呼吸：上下轻浮 + 雾体缩放 + 光晕明暗，和虚空里同一个节奏
	position.y = _base.y + sin(_t * 1.6) * 6.0
	if _haze != null:
		_haze.scale = Vector2.ONE * (1.0 + sin(_t * 1.9) * 0.10)
	if _core != null:
		_core.scale = Vector2.ONE * (1.0 + sin(_t * 3.1) * 0.06)
	if _glow != null:
		_glow.energy = 1.05 + sin(_t * 1.6) * 0.18
	for i in range(_tendrils.size()):
		var t: Line2D = _tendrils[i]
		var sway := sin(_t * 2.2 + float(i) * 1.1) * 3.4
		t.points = PackedVector2Array([
			Vector2(-5.0 + 5.0 * float(i), 9),
			Vector2((-5.0 + 5.0 * float(i)) * 1.5 + sway * 0.5, 26),
			Vector2((-5.0 + 5.0 * float(i)) * 2.0 + sway, 44),
		])

func _ellipse(rx: float, ry: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts
