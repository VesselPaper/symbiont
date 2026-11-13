extends Node2D
## 灵魂上方的"火焰状消逝"
##
## 灵魂形态没有实体，靠几片向上飘的白焰 + 火星来表现"正在一点点消散"。
## 每片火舌自己循环：从根部升起 → 变大变淡 → 消失后重来，节奏错开，看起来像连续燃烧。
## 只做表现，不碰逻辑；挂到灵魂节点上用。

var _flames: Array[Polygon2D] = []
var _cores: Array[Polygon2D] = []
var _time := 0.0
var _rise := 1.0

func _ready() -> void:
	z_index = -1
	_build_flames()
	_build_embers()

func _build_flames() -> void:
	for i in range(3):
		var tongue := Polygon2D.new()
		tongue.color = Color(0.80, 0.86, 0.92, 0.0 if i > 0 else 0.55)
		add_child(tongue)
		_flames.append(tongue)
		var core := Polygon2D.new()
		core.color = Color(0.95, 0.97, 1.0, 0.0)
		add_child(core)
		_cores.append(core)

func _build_embers() -> void:
	var embers := CPUParticles2D.new()
	embers.name = "SoulEmbers"
	embers.amount = 10
	embers.lifetime = 2.2
	embers.preprocess = 1.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 7.0
	embers.direction = Vector2(0, -1)
	embers.spread = 18.0
	embers.gravity = Vector2(0, -22)
	embers.initial_velocity_min = 10.0
	embers.initial_velocity_max = 26.0
	embers.scale_amount_min = 0.35
	embers.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.92, 1.0, 0.75))
	ramp.set_color(1, Color(0.62, 0.70, 0.82, 0.0))
	embers.color_ramp = ramp
	embers.position = Vector2(0, -16)
	add_child(embers)

func _process(delta: float) -> void:
	_time += delta
	for i in range(_flames.size()):
		var tongue := _flames[i]
		if tongue == null or not is_instance_valid(tongue):
			continue
		# 每片火舌错开相位，循环 1.6s：升起 → 放大变淡 → 熄灭
		var phase := fmod(_time * 0.62 + float(i) * 0.34, 1.0)
		var life := phase
		var height := (22.0 - float(i) * 5.0) * (0.6 + life * 0.9) * _rise
		var width := (5.0 - float(i) * 0.9) * (1.0 - life * 0.45)
		var sway := sin(_time * 3.0 + float(i) * 1.9) * (2.0 + life * 3.0)
		var base := Vector2(0, -life * 18.0)
		tongue.position = base
		tongue.polygon = PackedVector2Array([
			Vector2(-width, 0),
			Vector2(-width * 0.6 + sway * 0.4, -height * 0.45),
			Vector2(sway, -height),
			Vector2(width * 0.55 + sway * 0.5, -height * 0.5),
			Vector2(width, 0),
		])
		var alpha := sin(phase * PI) * (0.52 if i == 0 else 0.34)
		tongue.color = Color(0.80, 0.86, 0.94, alpha)
		var core := _cores[i]
		if core != null and is_instance_valid(core):
			core.position = base + Vector2(0, -height * 0.28)
			core.polygon = PackedVector2Array([
				Vector2(-width * 0.42, 0),
				Vector2(sway * 0.3, -height * 0.42),
				Vector2(width * 0.4, 0),
			])
			core.color = Color(0.98, 0.99, 1.0, alpha * 0.9)

## 汇入/消散时可以让火焰整体变旺或变弱（0~2）
func set_rise(value: float) -> void:
	_rise = clampf(value, 0.0, 2.0)
