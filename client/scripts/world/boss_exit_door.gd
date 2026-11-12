extends StaticBody2D
## 守门者之厅出口（M3-02）
##
## Boss 没死之前是一扇实心铁门，死了才沉下去。门本身不负责结局，
## 只负责挡住玩家，结局由 floor3.gd 的出口判定处理。

const OPEN_TIME := 0.9
var _opened := false
var _bars: Node2D
var _seam: Line2D

func _ready() -> void:
	add_to_group("boss_exit")
	_build_visual()

func _build_visual() -> void:
	var frame := Node2D.new()
	frame.name = "Frame"
	add_child(frame)
	for dx in [-31.0, 31.0]:
		var post := Polygon2D.new()
		post.color = Color(0.075, 0.080, 0.085)
		post.polygon = PackedVector2Array([
			Vector2(dx - 7, -130), Vector2(dx + 7, -130),
			Vector2(dx + 7, 130), Vector2(dx - 7, 130),
		])
		frame.add_child(post)
	var lintel := Polygon2D.new()
	lintel.color = Color(0.090, 0.095, 0.100)
	lintel.polygon = PackedVector2Array([
		Vector2(-44, -148), Vector2(44, -148), Vector2(38, -124), Vector2(-38, -124),
	])
	frame.add_child(lintel)

	_bars = Node2D.new()
	_bars.name = "Bars"
	add_child(_bars)
	var plate := Polygon2D.new()
	plate.color = Color(0.135, 0.140, 0.135)
	plate.polygon = PackedVector2Array([
		Vector2(-27, -120), Vector2(27, -120), Vector2(27, 120), Vector2(-27, 120),
	])
	_bars.add_child(plate)
	for i in range(5):
		var bar := Line2D.new()
		bar.width = 4.0
		bar.default_color = Color(0.055, 0.060, 0.058)
		var x := -20.0 + i * 10.0
		bar.points = PackedVector2Array([Vector2(x, -116), Vector2(x, 116)])
		_bars.add_child(bar)
	# 门上的冷光缝：Boss 死后会熄灭
	_seam = Line2D.new()
	_seam.width = 2.0
	_seam.default_color = Color(0.42, 0.64, 0.66, 0.35)
	_seam.points = PackedVector2Array([Vector2(0, -112), Vector2(0, 112)])
	_bars.add_child(_seam)
	var lock := Polygon2D.new()
	lock.color = Color(0.36, 0.30, 0.20, 0.95)
	lock.position = Vector2(0, 0)
	lock.polygon = PackedVector2Array([
		Vector2(-7, -5), Vector2(7, -5), Vector2(8, 8), Vector2(-8, 8),
	])
	_bars.add_child(lock)

func open(instant: bool = false) -> void:
	if _opened:
		return
	_opened = true
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		col.disabled = true
	if instant:
		visible = false
		return
	var tween := create_tween().set_parallel()
	tween.tween_property(_bars, "position:y", 250.0, OPEN_TIME)
	tween.tween_property(_bars, "modulate:a", 0.0, OPEN_TIME)
	_seam.default_color = Color(0.42, 0.64, 0.66, 0.0)
	# 门沉下去时震一下地面，补足重量感
	var camera := get_tree().get_first_node_in_group("camera")
	if camera != null and camera.has_method("shake"):
		camera.call("shake", 3.0, 0.22)

func is_open() -> bool:
	return _opened
