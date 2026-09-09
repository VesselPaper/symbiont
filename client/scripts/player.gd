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

# 美术动效状态
var _squash := Vector2.ONE        ## 挤压拉伸（落地/起跳）
var _was_on_floor := true
var _bob_t := 0.0                 ## 走路起伏相位
var _land_dust: CPUParticles2D


func _ready() -> void:
	# 落地尘土
	_land_dust = VisualLib.make_dust_puff()
	_land_dust.position = Vector2(0, -1)
	add_child(_land_dust)
	# 肩上共生体（发光小精灵）
	var sib := Node2D.new()
	sib.position = Vector2(-6, -19)
	var orb := Polygon2D.new()
	orb.polygon = PackedVector2Array([Vector2(0, -3), Vector2(3, 0), Vector2(0, 3), Vector2(-3, 0)])
	orb.color = Color(0.85, 0.98, 0.9)
	sib.add_child(orb)
	sib.add_child(VisualLib.make_glow(10.0, Color(0.6, 0.95, 0.85), 0.30))
	$Visual.add_child(sib)


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
			_jumps_left = 1
			_squash = Vector2(0.85, 1.15)
			_consume_jump_input()
		elif _jumps_left > 0:
			velocity.y = double_jump_velocity
			_jumps_left -= 1
			_squash = Vector2(0.85, 1.15)
			_consume_jump_input()

	move_and_slide()

	# 落地检测 → 挤压 + 尘土
	if is_on_floor() and not _was_on_floor:
		_squash = Vector2(1.22, 0.78)
		_land_dust.restart()
	_was_on_floor = is_on_floor()

	# 动效：挤压回弹 + 走路起伏 + 朝向翻转
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, 14.0 * delta))
	var bob := 0.0
	if is_on_floor() and absf(velocity.x) > 20.0:
		_bob_t += delta * 11.0
		bob = -absf(sin(_bob_t)) * 1.5
	var vis: Node2D = $Visual
	vis.scale = Vector2(_facing * _squash.x, _squash.y)
	vis.position.y = lerpf(vis.position.y, bob, minf(1.0, 18.0 * delta))


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
