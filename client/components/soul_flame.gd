extends Node2D
## 灵魂的"火焰状消逝"
##
## 灵魂没有实体，靠一簇簇细碎的白焰往上飘、边飘边碎掉，表现"正在一点点消散"。
## 每片碎片各自循环：从根部升起 → 侧向漂移 → 拉长变淡 → 熄灭后换个位置重来；
## 片数多、尺寸小、相位错开，所以看起来是零碎地剥落，而不是三根整齐的火舌。
## 只做表现，不碰逻辑；挂到灵魂/Boss 身上用。根部放在躯体内部，火焰会从体内升起。
##
## 参数：
##   fragment_count  碎片数量（默认 9）
##   base_radius     碎片出生点在根部附近的散布半径
##   rise_height     每片碎片向上飘的距离

@export var fragment_count := 9
@export var base_radius := 6.0
@export var rise_height := 26.0

var _tongues: Array[Polygon2D] = []
var _seeds: Array[Dictionary] = []
var _time := 0.0
var _rise := 1.0

func _ready() -> void:
	z_index = -1
	_build_fragments()
	_build_embers()

func _build_fragments() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in range(fragment_count):
		var tongue := Polygon2D.new()
		tongue.color = Color(0.82, 0.88, 0.94, 0.0)
		add_child(tongue)
		_tongues.append(tongue)
		# 每片碎片的随机参数：相位、寿命、横向漂移、起飞点、宽度
		_seeds.append({
			"phase": rng.randf_range(0.0, 1.0),
			"speed": rng.randf_range(0.42, 0.95),
			"drift": rng.randf_range(-9.0, 9.0),
			"x": rng.randf_range(-base_radius, base_radius),
			"y": rng.randf_range(-base_radius * 0.5, base_radius * 0.5),
			"w": rng.randf_range(1.4, 3.2),
			"h": rng.randf_range(9.0, 20.0),
			"alpha": rng.randf_range(0.22, 0.55),
			"sway": rng.randf_range(1.4, 3.8),
		})

func _build_embers() -> void:
	var embers := CPUParticles2D.new()
	embers.name = "SoulEmbers"
	embers.amount = 14
	embers.lifetime = 2.0
	embers.preprocess = 1.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 6.0
	embers.direction = Vector2(0, -1)
	embers.spread = 26.0
	embers.gravity = Vector2(0, -20)
	embers.initial_velocity_min = 8.0
	embers.initial_velocity_max = 24.0
	embers.scale_amount_min = 0.3
	embers.scale_amount_max = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.92, 1.0, 0.65))
	ramp.set_color(1, Color(0.62, 0.70, 0.82, 0.0))
	embers.color_ramp = ramp
	embers.position = Vector2(0, -6)
	add_child(embers)

func _process(delta: float) -> void:
	_time += delta
	for i in range(_tongues.size()):
		var tongue := _tongues[i]
		if tongue == null or not is_instance_valid(tongue):
			continue
		var s: Dictionary = _seeds[i]
		# life 在 0~1 之间循环：0 刚从体内冒出，1 已经碎散消失
		var life := fmod(_time * float(s["speed"]) + float(s["phase"]), 1.0)
		var rise := life * rise_height * _rise
		var sway := sin(_time * float(s["sway"]) + float(s["phase"]) * TAU) * (1.0 + life * 2.2)
		var drift := float(s["drift"]) * life
		var base := Vector2(float(s["x"]) + drift, float(s["y"]) - rise)
		tongue.position = base
		# 碎片越飘越细，末端甩出去，像被风扯散
		var w := float(s["w"]) * (1.0 - life * 0.55)
		var h := float(s["h"]) * (0.55 + life * 0.8) * _rise
		tongue.polygon = PackedVector2Array([
			Vector2(-w, 0),
			Vector2(-w * 0.5 + sway * 0.35, -h * 0.45),
			Vector2(sway, -h),
			Vector2(w * 0.45 + sway * 0.5, -h * 0.4),
			Vector2(w, 0),
		])
		# 出生时可见、中段最亮、末尾碎掉
		var alpha := sin(life * PI) * float(s["alpha"])
		tongue.color = Color(0.84, 0.90, 0.96, alpha)

## 汇入/消散时可以让火焰整体变旺或变弱（0~2）
func set_rise(value: float) -> void:
	_rise = clampf(value, 0.0, 2.0)
