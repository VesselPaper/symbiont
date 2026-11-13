extends Area2D
## 毒液地板（关底 Boss 的第二技能产物）
##
## 粘液弹落地后在地面铺开一滩：踩上去持续掉血，4 秒后慢慢淡去消失。
## 纯 Area2D + 代码绘制，不挡路、不影响跳跃。

const LIFETIME := 4.0
const FADE_TIME := 1.2
const TICK_INTERVAL := 0.9
const DAMAGE := 1

var _time := 0.0
var _tick := 0.0
var _fading := false
var _visual: Node2D
var _area_shape: CollisionShape2D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	z_index = -1
	var shape := RectangleShape2D.new()
	shape.size = Vector2(96, 18)
	_area_shape = CollisionShape2D.new()
	_area_shape.shape = shape
	_area_shape.position = Vector2(0, -9)
	add_child(_area_shape)
	_build_visual()
	body_entered.connect(_on_body_entered)

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	_visual.modulate.a = 0.0
	add_child(_visual)
	var puddle := Polygon2D.new()
	puddle.color = Color(0.30, 0.52, 0.12, 0.85)
	puddle.polygon = PackedVector2Array([
		Vector2(-48, 0), Vector2(-40, -8), Vector2(-22, -12), Vector2(0, -14),
		Vector2(24, -11), Vector2(42, -6), Vector2(48, 0), Vector2(30, 4),
		Vector2(-6, 5), Vector2(-32, 4),
	])
	_visual.add_child(puddle)
	var rim := Line2D.new()
	rim.width = 1.4
	rim.default_color = Color(0.62, 0.86, 0.34, 0.7)
	rim.points = PackedVector2Array([
		Vector2(-40, -8), Vector2(-22, -12), Vector2(0, -14),
		Vector2(24, -11), Vector2(42, -6),
	])
	_visual.add_child(rim)
	# 冒泡：几颗慢慢鼓起的小泡
	for i in range(5):
		var bubble := Polygon2D.new()
		bubble.color = Color(0.52, 0.78, 0.26, 0.55)
		var bx := -34.0 + float(i) * 17.0
		bubble.polygon = _ring_points(3.0 + float(i % 2) * 1.5, 8)
		bubble.position = Vector2(bx, -6)
		_visual.add_child(bubble)
	var tw := create_tween()
	tw.tween_property(_visual, "modulate:a", 1.0, 0.25)

func _process(delta: float) -> void:
	_time += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_INTERVAL
		for body in get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(DAMAGE, self)
	if not _fading and _time >= LIFETIME - FADE_TIME:
		_fading = true
		var tw := create_tween()
		tw.tween_property(_visual, "modulate:a", 0.0, FADE_TIME)
		tw.tween_callback(queue_free)

func _on_body_entered(_body: Node2D) -> void:
	_tick = 0.0

func _ring_points(radius: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts
