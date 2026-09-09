class_name PatrolEnemy
extends CharacterBody2D
## 巡逻敌人：左右往返，撞墙或走出巡逻范围即回头；受击即灭（垂直切片简化版）

@export var speed := 55.0                ## 巡逻速度（px/s）
@export var patrol_half_width := 120.0   ## 巡逻半幅（相对出生点）

var _home_x := 0.0
var _dir := 1
var _segs: Array[ColorRect] = []
var _wiggle_t := 0.0


func _ready() -> void:
	_home_x = global_position.x
	# 分节蠕虫造型（替换占位色块）：体节 + 暖黄单眼 + 眼部微光
	var vis: Node2D = $Visual
	for c in vis.get_children():
		c.free()
	for i in 3:
		var seg := ColorRect.new()
		seg.offset_left = -7.0 + i * 5.0
		seg.offset_right = seg.offset_left + 5.0
		seg.offset_top = -13.0
		seg.offset_bottom = 0.0
		var v := 0.07 * i
		seg.color = Color(0.45 + v, 0.38 + v, 0.30 + v)
		vis.add_child(seg)
		_segs.append(seg)
	var eye := ColorRect.new()
	eye.offset_left = 1.0
	eye.offset_top = -11.0
	eye.offset_right = 4.0
	eye.offset_bottom = -8.0
	eye.color = Color(0.98, 0.76, 0.36)
	vis.add_child(eye)
	var glow := VisualLib.make_glow(9.0, Color(0.98, 0.76, 0.36), 0.28)
	glow.position = Vector2(2.5, -9.5)
	vis.add_child(glow)


func _physics_process(delta: float) -> void:
	# 重力（防止悬空）
	if not is_on_floor():
		velocity.y += 1900.0 * delta
	velocity.x = _dir * speed
	move_and_slide()

	if is_on_wall():
		_dir *= -1
	elif absf(global_position.x - _home_x) >= patrol_half_width:
		_dir *= -1
	$Visual.scale.x = _dir

	# 体节蠕动
	_wiggle_t += delta
	for i in _segs.size():
		_segs[i].position.y = sin(_wiggle_t * 9.0 + i * 1.3) * 1.5


func take_hit(_damage: int) -> void:
	## 受击接口：垂直切片简化为一击消灭
	queue_free()
