extends StaticBody2D
## 教学关的物理门（M2-08）
##
## 组长原本要求“软隔离、不设门”；但试玩反馈明确说后面步骤在逻辑上要真的做不了。
## 这里用“骨栅栏”把每个分区隔开：Tutorial 推进到下一环时对应 gate_id 打开，
## 没做前面的事，门不会开，玩家也就不能靠跑图跳过。
##
## 不改平台位置/碰撞，只在平台之间的缝里加一扇竖门。

@export var gate_id := ""
@export var gate_height := 200.0
@export var gate_width := 34.0

const BONE_COLOR := Color(0.28, 0.28, 0.25, 0.96)
const BONE_RIM := Color(0.56, 0.56, 0.47, 0.75)
const RUNE_COLOR := Color(0.52, 0.82, 0.78, 0.65)

var _open := false
var _shape: CollisionShape2D
var _visual: Node2D

func _ready() -> void:
	add_to_group("tutorial_gate")
	_build_collision()
	_build_visual()
	collision_layer = 1
	collision_mask = 0
	z_index = 2

func _build_collision() -> void:
	_shape = CollisionShape2D.new()
	_shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(gate_width, gate_height)
	_shape.shape = rect
	add_child(_shape)

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var half := gate_height * 0.5
	# 两根竖骨 + 一根横骨 + 中间符文：读起来是“被锁住的通道”，不是装饰柱
	for x in [-gate_width * 0.28, gate_width * 0.28]:
		var bone := Polygon2D.new()
		bone.color = BONE_COLOR
		bone.polygon = PackedVector2Array([
			Vector2(x - 4, -half), Vector2(x + 4, -half),
			Vector2(x + 3, half), Vector2(x - 3, half),
		])
		_visual.add_child(bone)
		var rim := Line2D.new()
		rim.width = 1.5
		rim.default_color = BONE_RIM
		rim.points = PackedVector2Array([
			Vector2(x - 3, -half + 6), Vector2(x - 3, half - 6),
		])
		_visual.add_child(rim)
	var cross := Polygon2D.new()
	cross.color = BONE_COLOR
	cross.polygon = PackedVector2Array([
		Vector2(-gate_width * 0.5, -12), Vector2(gate_width * 0.5, -12),
		Vector2(gate_width * 0.5, -3), Vector2(-gate_width * 0.5, -3),
	])
	_visual.add_child(cross)
	var rune := Line2D.new()
	rune.width = 2.0
	rune.default_color = RUNE_COLOR
	rune.points = PackedVector2Array([
		Vector2(0, -24), Vector2(-11, 0), Vector2(0, 18), Vector2(11, 0), Vector2(0, -24),
	])
	_visual.add_child(rune)
	var glow := Polygon2D.new()
	glow.color = Color(0.40, 0.80, 0.74, 0.12)
	glow.polygon = PackedVector2Array([
		Vector2(-16, -34), Vector2(16, -34), Vector2(20, 26), Vector2(-20, 26),
	])
	_visual.add_child(glow)
	# 地上的碎石基座
	var base := Polygon2D.new()
	base.color = Color(0.12, 0.13, 0.13, 0.9)
	base.polygon = PackedVector2Array([
		Vector2(-gate_width * 0.7, half - 4), Vector2(gate_width * 0.7, half - 4),
		Vector2(gate_width * 0.55, half + 5), Vector2(-gate_width * 0.55, half + 5),
	])
	_visual.add_child(base)

func open() -> void:
	if _open:
		return
	_open = true
	collision_layer = 0
	collision_mask = 0
	if _shape != null:
		_shape.set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "position:y", gate_height * 0.55, 0.45)
	tween.parallel().tween_property(_visual, "modulate:a", 0.0, 0.45)
	tween.tween_callback(_hide_after_open)

func _hide_after_open() -> void:
	if _visual != null:
		_visual.visible = false

func is_open() -> bool:
	return _open

## 反向：把已经打开的门重新落下（Boss 战开始封场用）。
## open() 会把视觉沉下去并淡出，这里全部复位。
func close() -> void:
	if not _open and _shape != null and not _shape.disabled:
		return
	_open = false
	collision_layer = 1
	collision_mask = 0
	if _shape != null:
		_shape.set_deferred("disabled", false)
	if _visual != null:
		_visual.visible = true
		_visual.position = Vector2.ZERO
		_visual.modulate = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "modulate:a", 1.0, 0.25)
