extends StaticBody2D
## 骨门（M2-06）——钟厅到台阶之间的硬门槛。
##
## 骨门只认钟声：初始 collision_layer=1 挡住玩家；ring_bell() 调 open() 后
## 关闭碰撞并下沉。这里不写数值、不写剧情，只负责“挡住/打开”和视觉。

const BONE_COLOR := Color(0.34, 0.31, 0.25, 0.95)
const BONE_RIM := Color(0.62, 0.58, 0.47, 0.85)
const IRON_COLOR := Color(0.16, 0.17, 0.16, 0.9)

var _open := false
var _shape: CollisionShape2D
var _visual: Node2D

func _ready() -> void:
	_build_collision()
	_build_visual()
	# 默认挡住；如果 floor1 读到已敲钟旗标，会立刻调 open(true)
	collision_layer = 1
	collision_mask = 0

func _build_collision() -> void:
	_shape = CollisionShape2D.new()
	_shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(36, 280)
	_shape.shape = rect
	add_child(_shape)

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	_visual.z_index = 2
	add_child(_visual)
	# 三根竖骨 + 横骨：不靠贴图，也能看出是“骨头门”而不是木栅栏
	for i in range(3):
		var bone := Polygon2D.new()
		bone.color = BONE_COLOR
		var x := -13.0 + i * 13.0
		bone.polygon = PackedVector2Array([
			Vector2(x - 3, -140), Vector2(x + 3, -140),
			Vector2(x + 3, 140), Vector2(x - 3, 140),
		])
		_visual.add_child(bone)
		var rim := Line2D.new()
		rim.width = 1.6
		rim.default_color = BONE_RIM
		rim.points = PackedVector2Array([
			Vector2(x - 3, -136), Vector2(x - 3, 136),
		])
		_visual.add_child(rim)
	# 上下横骨/铁箍，把三根竖骨锁在一起
	for y in [-108.0, 0.0, 108.0]:
		var bar := Polygon2D.new()
		bar.color = IRON_COLOR if y == 0.0 else BONE_COLOR
		bar.polygon = PackedVector2Array([
			Vector2(-23, y - 5), Vector2(23, y - 5),
			Vector2(23, y + 5), Vector2(-23, y + 5),
		])
		_visual.add_child(bar)
	# 中间的锁扣：骨门上的锁扣就是敲钟后断掉的那块
	var lock := Polygon2D.new()
	lock.color = Color(0.26, 0.22, 0.18, 0.95)
	lock.polygon = PackedVector2Array([
		Vector2(-8, -7), Vector2(8, -7), Vector2(8, 7), Vector2(-8, 7),
	])
	_visual.add_child(lock)
	var skull := Polygon2D.new()
	skull.color = Color(0.56, 0.51, 0.41, 0.9)
	skull.position = Vector2(0, -106)
	skull.polygon = PackedVector2Array([
		Vector2(-9, -7), Vector2(-5, -13), Vector2(5, -13),
		Vector2(9, -7), Vector2(7, 5), Vector2(-7, 5),
	])
	_visual.add_child(skull)
	var socket_l := Polygon2D.new()
	socket_l.color = Color(0.06, 0.06, 0.05, 1.0)
	socket_l.position = Vector2(-4, -8)
	socket_l.polygon = PackedVector2Array([
		Vector2(-2, -1), Vector2(0, -2), Vector2(2, 0), Vector2(0, 2),
	])
	skull.add_child(socket_l)
	var socket_r := socket_l.duplicate() as Polygon2D
	socket_r.position = Vector2(4, -8)
	skull.add_child(socket_r)

func open(instant: bool = false) -> void:
	if _open:
		return
	_open = true
	collision_layer = 0
	collision_mask = 0
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if instant:
		_visual.visible = false
		visible = false
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "position:y", _visual.position.y + 92.0, 0.55)
	tween.parallel().tween_property(_visual, "modulate:a", 0.0, 0.55)
	tween.tween_callback(_hide_after_open)

func _hide_after_open() -> void:
	if _visual != null:
		_visual.visible = false

func is_open() -> bool:
	return _open
