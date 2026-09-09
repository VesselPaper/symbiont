class_name Player
extends CharacterBody2D
## 玩家控制器：移动 / 跳跃 / 二段跳 / 冲刺 / 攻击（3 连段 + 下劈 pogo + 冲刺斩）
## 生命 / 能量 / 死亡重生；状态经 GameEvents 广播
## 角色：Kenney Tiny Dungeon 素材 sprite + 程序化共生体（颜色随人性↔异化变化）
## 调试：按 Y 循环 异化→平衡→人性，直观查看外观变化

@export_group("移动")
@export var run_speed := 240.0
@export var accel_ground := 2600.0
@export var accel_air := 800.0
@export var friction := 2400.0

@export_group("跳跃")
@export var gravity := 2000.0
@export var jump_velocity := -525.0
@export var double_jump_velocity := -430.0
@export var fall_gravity_mult := 1.6
@export var low_jump_mult := 1.8       ## 松键跳变矮（上升中松键 → 重力放大）
@export var coyote_time := 0.08
@export var jump_buffer := 0.1

@export_group("冲刺")
@export var dash_speed := 520.0
@export var dash_time := 0.14
@export var dash_cooldown := 1.1
@export var max_air_dashes := 1

@export_group("攻击")
@export var attack_cooldown := 0.35
@export var combo_window := 0.55

@export_group("生命 / 能量")
@export var max_hp := 4
@export var max_energy := 3
@export var iframe_time := 0.8
@export var knockback_speed := 260.0

@export_group("共生")
@export var humanity := 50.0           ## 人性值 0=异化 .. 100=人性（决定外观/技能）

var hp := 4
var energy := 0.0

# 状态
var _jumps_left := 1
var _air_dashes := 1
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _dash_timer := 0.0
var _dash_cd_timer := 0.0
var _attack_cd := 0.0
var _swing_t := 0.0
var _iframes := 0.0
var _combo := 0
var _combo_timer := 0.0
var _pogo_active := false
var _dash_attacking := false
var _facing := 1
var _dash_dir := Vector2.RIGHT
var _dead := false

# 动效
var _squash := Vector2.ONE
var _was_on_floor := true
var _walk_phase := 0.0
var _land_dust: CPUParticles2D
var _hero_sprite: Sprite2D
var _symbiont: Node2D
var _symbiont_orb: Polygon2D


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	_land_dust = VisualLib.make_dust_puff()
	_land_dust.position = Vector2(0, -1)
	add_child(_land_dust)
	_build_visual()
	_apply_symbiont_visual()
	GameEvents.enemy_killed.connect(func(_pos): gain_energy(1.0))
	GameEvents.player_hp_changed.emit(hp, max_hp)
	GameEvents.player_energy_changed.emit(energy, max_energy)


# ---------------- 角色视觉（素材 sprite + 共生体） ----------------

func _build_visual() -> void:
	var vis: Node2D = $Visual
	for c in vis.get_children():
		c.free()

	# 主角（Kenney 献祭者 sprite，脚贴地）
	_hero_sprite = Sprite2D.new()
	_hero_sprite.texture = VisualLib.get_hero_texture()
	_hero_sprite.position = Vector2(0, -8)
	vis.add_child(_hero_sprite)

	# 共生体（肩上发光小精灵，颜色随人性↔异化）
	_symbiont = Node2D.new()
	_symbiont.position = Vector2(-7, -20)
	_symbiont_orb = Polygon2D.new()
	_symbiont_orb.polygon = PackedVector2Array([Vector2(0, -3), Vector2(3, 0), Vector2(0, 3), Vector2(-3, 0)])
	_symbiont.add_child(_symbiont_orb)
	_symbiont.add_child(VisualLib.make_glow(10.0, Color(0.7, 0.6, 1.0), 0.3))
	vis.add_child(_symbiont)


func _apply_symbiont_visual() -> void:
	## 人性↔异化 外观反馈：异化=冷紫，人性=暖金
	var h := clampf(humanity / 100.0, 0.0, 1.0)
	var orb_color := Color(0.72, 0.5, 1.0).lerp(Color(0.98, 0.92, 0.6), h)
	if _symbiont_orb:
		_symbiont_orb.color = orb_color
	if _hero_sprite:
		# 主角微染：异化偏紫 / 人性偏暖
		_hero_sprite.modulate = Color(0.85, 0.72, 1.0).lerp(Color(1.0, 0.97, 0.9), h)


# ---------------- 物理 ----------------

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if _dead:
		velocity = Vector2.ZERO
		return

	if is_on_floor():
		_coyote_timer = coyote_time
		_jumps_left = 1
		_air_dashes = 1

	var want_attack := Input.is_action_just_pressed("attack")

	if _dash_timer > 0.0:
		velocity.x = _dash_dir.x * dash_speed
		velocity.y = 0.0
		if want_attack and _attack_cd <= 0.0:
			_start_dash_attack()
		move_and_slide()
		return

	if Input.is_action_just_pressed("dash") and _dash_cd_timer <= 0.0:
		_start_dash()
		return

	if want_attack and _attack_cd <= 0.0:
		_start_attack()

	var input_dir := Input.get_axis("move_left", "move_right")
	if input_dir != 0.0:
		_facing = 1 if input_dir > 0.0 else -1

	var g := gravity
	if velocity.y > 0.0:
		g *= fall_gravity_mult
	elif velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		g *= low_jump_mult
	velocity.y += g * delta

	if input_dir != 0.0:
		var accel := accel_ground if is_on_floor() else accel_air
		velocity.x = move_toward(velocity.x, input_dir * run_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

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

	if is_on_floor() and not _was_on_floor:
		_squash = Vector2(1.22, 0.78)
		_land_dust.restart()
	_was_on_floor = is_on_floor()


# ---------------- 动画 ----------------

func _process(delta: float) -> void:
	var vis: Node2D = $Visual
	var t := Time.get_ticks_msec() / 1000.0

	# 调试：Y 循环 人性↔异化，直观查看外观变化
	if Input.is_action_just_pressed("cycle_humanity"):
		humanity = 0.0 if humanity >= 100.0 else humanity + 50.0
		_apply_symbiont_visual()

	_squash = _squash.lerp(Vector2.ONE, minf(1.0, 14.0 * delta))

	# 走路起伏 / 冲刺前倾 / 挥剑脉冲
	vis.rotation = lerpf(vis.rotation, 0.12 * _facing if _dash_timer > 0.0 else 0.0, 0.2)
	var bob := 0.0
	if is_on_floor() and absf(velocity.x) > 20.0:
		_walk_phase += delta * 11.0
		bob = -absf(sin(_walk_phase)) * 1.5
	var scale_x := _facing * _squash.x
	if _swing_t > 0.0:
		_swing_t = maxf(_swing_t - delta, 0.0)
		scale_x = _facing * (1.0 + 0.06 * (1.0 - _swing_t / 0.12))
	vis.scale = Vector2(scale_x, _squash.y)
	vis.position.y = lerpf(vis.position.y, bob, minf(1.0, 18.0 * delta))

	# 共生体漂浮
	if _symbiont:
		_symbiont.position.y = -20.0 + sin(t * 1.6) * 1.5

	# 无敌帧闪烁 / 受击色
	if _iframes > 0.0:
		vis.modulate.a = 0.55 if fmod(_iframes, 0.12) < 0.06 else 1.0
	else:
		vis.modulate = vis.modulate.lerp(Color.WHITE, 10.0 * delta)


# ---------------- 战斗 ----------------

func _start_attack() -> void:
	_attack_cd = attack_cooldown
	if _combo_timer > 0.0 and _combo < 2:
		_combo += 1
	else:
		_combo = 0
	_combo_timer = combo_window
	var pogo := not is_on_floor() and Input.is_action_pressed("move_down")
	_swing_t = 0.12
	var hb: Area2D = $AttackHitbox
	hb.rotation = 0.0
	if pogo:
		_pogo_active = true
		hb.position = Vector2(0, 12)
		hb.scale = Vector2.ONE
	else:
		_pogo_active = false
		hb.position = Vector2(13, -8)
		hb.scale.x = _facing
	hb.monitoring = true
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(hb):
		hb.monitoring = false
		_pogo_active = false
		_dash_attacking = false
		hb.position = Vector2(13, -8)


func _start_dash_attack() -> void:
	_dash_attacking = true
	_attack_cd = 0.4
	var hb: Area2D = $AttackHitbox
	hb.rotation = 0.0
	hb.position = Vector2(16, -8)
	hb.scale.x = _facing
	hb.monitoring = true
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(hb):
		hb.monitoring = false
		_dash_attacking = false


func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body.has_method("take_hit"):
		var dmg := 2 if _dash_attacking else 1
		body.take_hit(dmg)
		gain_energy(0.5)
		if _pogo_active:
			_bounce()
		GameEvents.stats_event.emit("hit", {"dmg": dmg})


func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	if area is EnemyProjectile:
		if is_instance_valid(area):
			area.queue_free()
		gain_energy(0.5)
		if _pogo_active:
			_bounce()


func _bounce() -> void:
	velocity.y = -jump_velocity * 0.72
	_squash = Vector2(1.15, 0.85)


func gain_energy(amount: float) -> void:
	var before := energy
	energy = minf(energy + amount, max_energy)
	if energy != before:
		GameEvents.player_energy_changed.emit(energy, max_energy)


func take_damage(amount: int, from: Vector2) -> void:
	if _dead or _iframes > 0.0:
		return
	hp = maxi(hp - amount, 0)
	_iframes = iframe_time
	var dir := global_position - from
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector2(-_facing, 0.0)
	velocity = dir.normalized() * knockback_speed + Vector2(0, -160.0)
	_squash = Vector2(1.3, 0.7)
	GameEvents.player_hp_changed.emit(hp, max_hp)
	GameEvents.stats_event.emit("player_hurt", {"amount": amount})
	$Visual.modulate = Color(1.8, 0.9, 0.9)
	if hp <= 0:
		die()


func die() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	_squash = Vector2(0.6, 1.5)
	GameEvents.player_died.emit()
	GameEvents.stats_event.emit("death", {})


func reset_after_death() -> void:
	_dead = false
	hp = max_hp
	energy = 0.0
	_iframes = 1.5
	velocity = Vector2.ZERO
	_combo = 0
	$Visual.modulate = Color.WHITE
	GameEvents.player_hp_changed.emit(hp, max_hp)
	GameEvents.player_energy_changed.emit(energy, max_energy)


# ---------------- 工具 ----------------

func _tick_timers(delta: float) -> void:
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_dash_cd_timer = maxf(_dash_cd_timer - delta, 0.0)
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_swing_t = maxf(_swing_t - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	_combo_timer = maxf(_combo_timer - delta, 0.0)


func _start_dash() -> void:
	if not is_on_floor():
		if _air_dashes <= 0:
			return
		_air_dashes -= 1
	var input_dir := Input.get_axis("move_left", "move_right")
	_dash_dir = Vector2(input_dir, 0.0) if input_dir != 0.0 else Vector2(_facing, 0.0)
	_dash_timer = dash_time
	_dash_cd_timer = dash_cooldown


func _consume_jump_input() -> void:
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
