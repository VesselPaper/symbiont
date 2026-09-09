class_name Player
extends CharacterBody2D
## 垂直切片手感验证 —— 玩家控制器
## 移动 / 跳跃 / 二段跳 / 冲刺 / 攻击（全部参数可在编辑器调整）

@export_group("移动")
@export var run_speed := 240.0          ## 最大跑速（px/s）
@export var accel_ground := 2600.0      ## 地面加速度
@export var accel_air := 1700.0         ## 空中加速度（空中微操控）
@export var friction := 2400.0          ## 地面减速

@export_group("跳跃")
@export var gravity := 1900.0           ## 基础重力
@export var jump_velocity := -560.0     ## 跳跃初速
@export var double_jump_velocity := -500.0 ## 二段跳初速
@export var fall_gravity_mult := 1.5    ## 下落加速倍率（手感干脆）
@export var low_jump_mult := 0.45       ## 轻按跳跃变矮
@export var coyote_time := 0.1          ## 土狼时间（离开平台后仍可跳）
@export var jump_buffer := 0.12         ## 跳跃输入缓冲（落地前提前按）

@export_group("冲刺")
@export var dash_speed := 760.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.5

@export_group("攻击")
@export var attack_cooldown := 0.35     ## 攻击冷却（s）

var _jumps_left := 1
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _dash_timer := 0.0
var _dash_cd_timer := 0.0
var _attack_cd := 0.0
var _facing := 1
var _dash_dir := Vector2.RIGHT


func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if is_on_floor():
		_coyote_timer = coyote_time
		_jumps_left = 1

	# 冲刺中：锁定横向速度，忽略重力与输入
	if _dash_timer > 0.0:
		velocity.x = _dash_dir.x * dash_speed
		velocity.y = 0.0
		move_and_slide()
		return

	if Input.is_action_just_pressed("dash") and _dash_cd_timer <= 0.0:
		_start_dash()
		return

	# 攻击（冲刺判定之后，保证冲刺时不被打断）
	if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
		_do_attack()

	var input_dir := Input.get_axis("move_left", "move_right")
	if input_dir != 0.0:
		_facing = 1 if input_dir > 0.0 else -1
	$Visual.scale.x = _facing

	# 重力：下落加速 / 轻按跳跃变矮
	var g := gravity
	if velocity.y > 0.0:
		g *= fall_gravity_mult
	elif velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		g *= low_jump_mult
	velocity.y += g * delta

	# 水平移动
	if input_dir != 0.0:
		var accel := accel_ground if is_on_floor() else accel_air
		velocity.x = move_toward(velocity.x, input_dir * run_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	# 跳跃：输入缓冲 + 土狼时间 + 二段跳
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer
	if _jump_buffer_timer > 0.0:
		if is_on_floor() or _coyote_timer > 0.0:
			velocity.y = jump_velocity
			_jumps_left = 0
			_consume_jump_input()
		elif _jumps_left > 0:
			velocity.y = double_jump_velocity
			_jumps_left -= 1
			_consume_jump_input()

	move_and_slide()


func _tick_timers(delta: float) -> void:
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_dash_cd_timer = maxf(_dash_cd_timer - delta, 0.0)
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)


func _start_dash() -> void:
	var input_dir := Input.get_axis("move_left", "move_right")
	_dash_dir = Vector2(input_dir, 0.0) if input_dir != 0.0 else Vector2(_facing, 0.0)
	_dash_timer = dash_time
	_dash_cd_timer = dash_cooldown


func _consume_jump_input() -> void:
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0


func _do_attack() -> void:
	_attack_cd = attack_cooldown
	var hitbox: Area2D = $AttackHitbox
	hitbox.scale.x = _facing
	hitbox.monitoring = true
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(hitbox):
		hitbox.monitoring = false


func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body.has_method("take_hit"):
		body.take_hit(1)
