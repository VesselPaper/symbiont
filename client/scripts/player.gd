class_name Player
extends CharacterBody2D
## 玩家控制器：移动 / 跳跃 / 二段跳 / 冲刺 / 攻击
## 角色建模：程序化多部件（兜帽 + 披风 + 四肢 + 武器 + 共生体），带全套动画
## 对应《美术风格与建模规划》3.1 主角；后续可用像素素材整体替换 $Visual

@export_group("移动")
@export var run_speed := 240.0          ## 最大跑速（px/s）
@export var accel_ground := 2600.0      ## 地面加速度
@export var accel_air := 1700.0         ## 空中加速度（空中微操控）
@export var friction := 2400.0          ## 地面减速

@export_group("跳跃")
@export var gravity := 1900.0           ## 基础重力
@export var jump_velocity := -560.0     ## 跳跃初速
@export var double_jump_velocity := -500.0 ## 二段跳初速
@export var fall_gravity_mult := 1.5    ## 下落加速倍率
@export var low_jump_mult := 0.45       ## 轻按跳跃变矮
@export var coyote_time := 0.1          ## 土狼时间
@export var jump_buffer := 0.12         ## 跳跃输入缓冲

@export_group("冲刺")
@export var dash_speed := 760.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.5

@export_group("攻击")
@export var attack_cooldown := 0.35

# 状态
var _jumps_left := 1
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _dash_timer := 0.0
var _dash_cd_timer := 0.0
var _attack_cd := 0.0
var _swing_t := 0.0
var _facing := 1
var _dash_dir := Vector2.RIGHT

# 动效状态
var _squash := Vector2.ONE
var _was_on_floor := true
var _walk_phase := 0.0
var _land_dust: CPUParticles2D

# 角色部件
var _cloak: Polygon2D
var _body: ColorRect
var _leg_l: ColorRect
var _leg_r: ColorRect
var _arm_l: ColorRect
var _arm_r: ColorRect
var _hood: Polygon2D
var _eye: ColorRect
var _sword: Node2D
var _sword_blade: ColorRect
var _symbiont: Node2D


func _ready() -> void:
	_land_dust = VisualLib.make_dust_puff()
	_land_dust.position = Vector2(0, -1)
	add_child(_land_dust)
	_build_visual()


# ---------------- 角色建模（程序化） ----------------

func _build_visual() -> void:
	var vis: Node2D = $Visual
	for c in vis.get_children():
		c.free()

	# 披风（最底层，下摆略宽）
	_cloak = Polygon2D.new()
	_cloak.polygon = PackedVector2Array([
		Vector2(-6, -15), Vector2(6, -15), Vector2(9, -4), Vector2(-9, -4),
	])
	_cloak.color = Color(0.36, 0.29, 0.20, 0.95)
	vis.add_child(_cloak)

	# 身体（袍）
	_body = ColorRect.new()
	_body.offset_left = -5.0
	_body.offset_top = -15.0
	_body.offset_right = 5.0
	_body.offset_bottom = -7.0
	_body.color = Color(0.85, 0.80, 0.66)
	vis.add_child(_body)

	# 腿（两节，脚下沿=地面）
	_leg_l = ColorRect.new()
	_leg_l.offset_left = -1.5
	_leg_l.offset_top = -3.5
	_leg_l.offset_right = 1.5
	_leg_l.offset_bottom = 3.5
	_leg_l.color = Color(0.42, 0.36, 0.25)
	_leg_l.position = Vector2(-2.5, -3.5)
	vis.add_child(_leg_l)
	_leg_r = _leg_l.duplicate()
	_leg_r.position = Vector2(2.5, -3.5)
	vis.add_child(_leg_r)

	# 手臂（肩部枢轴）
	_arm_l = ColorRect.new()
	_arm_l.offset_left = -1.25
	_arm_l.offset_top = -3.0
	_arm_l.offset_right = 1.25
	_arm_l.offset_bottom = 3.0
	_arm_l.color = Color(0.72, 0.66, 0.52)
	_arm_l.position = Vector2(-5.5, -10.5)
	vis.add_child(_arm_l)
	_arm_r = _arm_l.duplicate()
	_arm_r.position = Vector2(5.5, -10.5)
	vis.add_child(_arm_r)

	# 兜帽（多边形）
	_hood = Polygon2D.new()
	_hood.polygon = PackedVector2Array([
		Vector2(-5, -16.5), Vector2(-4.5, -22.5), Vector2(-2, -24.5),
		Vector2(2, -24.5), Vector2(4.5, -22.5), Vector2(5, -16.5),
	])
	_hood.color = Color(0.91, 0.86, 0.71)
	vis.add_child(_hood)

	# 面部暗区 + 眼
	var face := ColorRect.new()
	face.offset_left = 1.5
	face.offset_top = -21.0
	face.offset_right = 4.5
	face.offset_bottom = -17.5
	face.color = Color(0.35, 0.30, 0.24)
	vis.add_child(face)
	_eye = ColorRect.new()
	_eye.offset_left = 2.5
	_eye.offset_top = -20.0
	_eye.offset_right = 3.5
	_eye.offset_bottom = -19.0
	_eye.color = Color(0.13, 0.12, 0.16)
	vis.add_child(_eye)

	# 武器（短刃，握持枢轴）
	_sword = Node2D.new()
	_sword.position = Vector2(5.5, -9.5)
	var guard := ColorRect.new()
	guard.offset_left = -2.0
	guard.offset_top = -1.0
	guard.offset_right = 2.0
	guard.offset_bottom = 1.0
	guard.color = Color(0.63, 0.47, 0.27)
	_sword.add_child(guard)
	_sword_blade = ColorRect.new()
	_sword_blade.offset_left = -1.0
	_sword_blade.offset_top = -9.0
	_sword_blade.offset_right = 1.0
	_sword_blade.offset_bottom = 0.0
	_sword_blade.color = Color(0.83, 0.86, 0.84)
	_sword.add_child(_sword_blade)
	_sword.rotation = 0.55
	vis.add_child(_sword)

	# 肩上共生体（发光小精灵）
	_symbiont = Node2D.new()
	_symbiont.position = Vector2(-6, -19)
	var orb := Polygon2D.new()
	orb.polygon = PackedVector2Array([Vector2(0, -3), Vector2(3, 0), Vector2(0, 3), Vector2(-3, 0)])
	orb.color = Color(0.85, 0.98, 0.9)
	_symbiont.add_child(orb)
	_symbiont.add_child(VisualLib.make_glow(10.0, Color(0.6, 0.95, 0.85), 0.30))
	vis.add_child(_symbiont)


# ---------------- 物理 ----------------

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

	# 攻击（冲刺判定之后）
	if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
		_do_attack()

	var input_dir := Input.get_axis("move_left", "move_right")
	if input_dir != 0.0:
		_facing = 1 if input_dir > 0.0 else -1

	# 重力
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


# ---------------- 动画（每帧，覆盖冲刺/攻击姿态） ----------------

func _process(delta: float) -> void:
	var vis: Node2D = $Visual
	var t := Time.get_ticks_msec() / 1000.0

	# 挤压回弹
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, 14.0 * delta))

	# 姿态：走路 / 跳跃 / 待机
	var moving := is_on_floor() and absf(velocity.x) > 20.0
	if moving:
		_walk_phase += delta * 11.0
		_leg_l.position.y = -3.5 - maxf(0.0, sin(_walk_phase)) * 2.5
		_leg_r.position.y = -3.5 - maxf(0.0, sin(_walk_phase + PI)) * 2.5
		_arm_l.position.y = -10.5 + sin(_walk_phase + PI) * 1.2
		_arm_r.position.y = -10.5 + sin(_walk_phase) * 1.2
		_sword.rotation = 0.55 + sin(_walk_phase) * 0.1
	elif not is_on_floor():
		_leg_l.position = Vector2(-2.5, -5.0)
		_leg_r.position = Vector2(2.5, -5.0)
		_arm_l.position = Vector2(-5.5, -14.5)
		_arm_r.position = Vector2(5.5, -14.5)
		_sword.rotation = lerpf(_sword.rotation, 0.9, 0.2)
	else:
		_leg_l.position = _leg_l.position.lerp(Vector2(-2.5, -3.5), 0.25)
		_leg_r.position = _leg_r.position.lerp(Vector2(2.5, -3.5), 0.25)
		_arm_l.position = _arm_l.position.lerp(Vector2(-5.5, -10.5), 0.25)
		_arm_r.position = _arm_r.position.lerp(Vector2(5.5, -10.5), 0.25)
		_sword.rotation = lerpf(_sword.rotation, 0.55, 0.15)

	# 呼吸 + 共生体漂浮
	_body.scale.y = 1.0 + 0.02 * sin(t * 2.0)
	_symbiont.position.y = -19.0 + sin(t * 1.6) * 1.5

	# 冲刺前倾
	vis.rotation = lerpf(vis.rotation, 0.12 * _facing if _dash_timer > 0.0 else 0.0, 0.2)

	# 攻击挥剑
	var scale_x := _facing * _squash.x
	if _swing_t > 0.0:
		_swing_t = maxf(_swing_t - delta, 0.0)
		var prog := 1.0 - _swing_t / 0.12
		_sword.rotation = lerpf(-1.5, 0.7, prog)
		scale_x = _facing * (1.0 + 0.06 * prog)
	vis.scale = Vector2(scale_x, _squash.y)
	vis.position.y = lerpf(vis.position.y, 0.0, minf(1.0, 18.0 * delta))


# ---------------- 工具 ----------------

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
	_swing_t = 0.12
	var hitbox: Area2D = $AttackHitbox
	hitbox.scale.x = _facing
	hitbox.monitoring = true
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(hitbox):
		hitbox.monitoring = false


func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body.has_method("take_hit"):
		body.take_hit(1)
