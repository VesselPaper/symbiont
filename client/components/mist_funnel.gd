extends Node2D
## 寄生体化雾、漏斗形钻进身体（M4-40）。
##
## 做法：三层同心"雾锥"（上宽下窄的 Polygon2D）+ 一圈螺旋雾丝（Line2D）。
## 雾锥从寄生体位置张开，再一起收束到玩家胸口；雾丝边转边被吸进去。
## 不用粒子：无头回归要能断言节点存在与收束进度。

const CONE_LAYERS := 3
const WISPS := 18
const CONE_HEIGHT := 220.0
const CONE_HALF_W := 120.0

var from := Vector2.ZERO
var to := Vector2.ZERO
var _progress := 0.0
var _running := false

func play(origin: Vector2, target: Vector2, duration: float = 1.6) -> void:
	from = origin
	to = target
	position = origin
	_running = true
	_progress = 0.0
	_build()

	for layer in _cones():
		layer.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(layer, "modulate:a", 0.55 - 0.12 * layer.get_index(), 0.35)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.28, 0.28), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "position", target, duration).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(_set_progress, 0.0, 1.0, duration)
	tw.tween_callback(_finish)

func _set_progress(v: float) -> void:
	_progress = v

func _finish() -> void:
	_running = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)

func is_running() -> bool:
	return _running

func _cones() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Polygon2D and String(c.name).begins_with("Cone"):
			out.append(c)
	return out

func _build() -> void:
	for i in range(CONE_LAYERS):
		var cone := Polygon2D.new()
		cone.name = "Cone%d" % i
		cone.color = Color(0.02, 0.02, 0.03, 0.9)
		cone.z_index = -1
		# 上宽下窄的梯形：顶端开口大、底端收成一点，读起来就是"漏斗"
		var half_w := CONE_HALF_W * (1.0 - 0.18 * float(i))
		cone.polygon = PackedVector2Array([
			Vector2(-half_w, 0.0),
			Vector2(half_w, 0.0),
			Vector2(half_w * 0.08, CONE_HEIGHT),
			Vector2(-half_w * 0.08, CONE_HEIGHT),
		])
		cone.position = Vector2(0.0, -CONE_HEIGHT * 0.9 + float(i) * 18.0)
		add_child(cone)

	# 螺旋雾丝：从雾体外沿往中心卷，越靠内越短
	for i in range(WISPS):
		var w := Line2D.new()
		w.width = 1.6
		w.default_color = Color(0.10, 0.09, 0.14, 0.8)
		w.z_index = 1
		var a := TAU * float(i) / float(WISPS)
		var r := CONE_HALF_W * (0.55 + 0.45 * float(i % 3) / 2.0)
		var p0 := Vector2(cos(a), sin(a) * 0.35) * r - Vector2(0, CONE_HEIGHT * 0.75)
		var p1 := p0.lerp(Vector2(0, CONE_HEIGHT * 0.2), 0.35)
		w.points = PackedVector2Array([p0, p1])
		add_child(w)
