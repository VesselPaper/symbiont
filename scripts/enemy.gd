class_name PatrolEnemy
extends CharacterBody2D
## 巡逻敌人：左右往返，撞墙或走出巡逻范围即回头；受击即灭（垂直切片简化版）

@export var speed := 55.0                ## 巡逻速度（px/s）
@export var patrol_half_width := 120.0   ## 巡逻半幅（相对出生点）

var _home_x := 0.0
var _dir := 1


func _ready() -> void:
	_home_x = global_position.x


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


func take_hit(_damage: int) -> void:
	## 受击接口：垂直切片简化为一击消灭
	queue_free()
