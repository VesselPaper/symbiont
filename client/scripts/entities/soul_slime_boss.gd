extends CharacterBody2D
## 第一层关底 · 魂史莱姆（Soul Slime）
##
## 由无数游魂黏成的巨型史莱姆：比主角大四到五倍，半透明的魂体里浮着一张模糊的人脸。
## 只有两个技能：
##   A. 跳砸：蓄力起跳 → 空中悬停一瞬 → 重重砸下，落地冲击波伤人
##   B. 吐粘液：朝玩家抛出一团粘液，抛物线落地后铺成一滩毒地板（4 秒后淡去）
## 玩家把它打空血后，第一层通往第二层的门才解封。

const SLIME_BULLET_SCENE := preload("res://scenes/entities/slime_bullet.tscn")
const SOUL_FLAME := preload("res://components/soul_flame.gd")

const MAX_HP := 26
const CONTACT_DAMAGE := 1
const CONTACT_COOLDOWN := 0.9
const SAME_FLOOR_TOLERANCE := 220.0

const GRAVITY := 1500.0
const MAX_FALL := 1100.0

const IDLE_TIME := 1.15
const SLAM_CROUCH := 0.42
const SLAM_JUMP_V := -640.0
const SLAM_HOVER := 0.42
const SLAM_DOWN_V := 1000.0
const SPIT_WINDUP := 0.55
const SPIT_SPEED_X := 300.0
const SPIT_SPEED_Y := -420.0

const DEATH_TIME := 1.2

enum State { IDLE, CROUCH, RISE, HOVER, SLAM, SPIT_WINDUP, DEAD }

var hp := MAX_HP

var _state: State = State.IDLE
var _timer := IDLE_TIME
var _hover_timer := 0.0
var _contact_cd := 0.0
var _is_dead := false
var _death_timer := 0.0
var _shockwave_done := false
var _anim_time := 0.0
var _visual: Node2D
var _body: Polygon2D
var _face: Node2D
var _contact_area: Area2D

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 4
	collision_mask = 1
	_build_body()
	_build_contact_area()
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.enemy_spawned.emit(self)

func _build_body() -> void:
	# 碰撞：一颗扁圆的魂体，宽 108 高 88 左右（主角 14×26 的 4~5 倍）
	var shape := CircleShape2D.new()
	shape.radius = 40.0
	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = shape
	col.position = Vector2(0, -24)
	add_child(col)

	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)

	# 魂体主块：宽扁的果冻轮廓，下沿做出滴落感，不是把旧造型压扁
	_body = Polygon2D.new()
	_body.name = "Body"
	_body.color = Color(0.62, 0.74, 0.86, 0.55)
	_body.polygon = PackedVector2Array([
		Vector2(-50, 16), Vector2(-54, -6), Vector2(-46, -30),
		Vector2(-30, -48), Vector2(-8, -60), Vector2(14, -60),
		Vector2(36, -47), Vector2(50, -27), Vector2(54, -4),
		Vector2(48, 17), Vector2(34, 24), Vector2(12, 26),
		Vector2(-10, 27), Vector2(-30, 23), Vector2(-44, 21),
	])
	_visual.add_child(_body)

	# 内层魂核：更亮的一团，横向铺开一点，呼吸般起伏
	var core := Polygon2D.new()
	core.name = "Core"
	core.color = Color(0.86, 0.93, 1.0, 0.35)
	core.polygon = PackedVector2Array([
		Vector2(-30, 2), Vector2(-34, -16), Vector2(-24, -34),
		Vector2(-8, -44), Vector2(10, -44), Vector2(26, -33),
		Vector2(34, -14), Vector2(30, 3), Vector2(12, 12), Vector2(-12, 12),
	])
	_visual.add_child(core)

	# 人脸：两只斜挑的空洞眼窝 + 一张下撇的嘴
	_face = Node2D.new()
	_face.name = "Face"
	_visual.add_child(_face)
	for dx in [-16.0, 16.0]:
		var socket := Polygon2D.new()
		socket.color = Color(0.06, 0.10, 0.16, 0.85)
		socket.polygon = PackedVector2Array([
			Vector2(dx - 10, -34), Vector2(dx + 9, -37),
			Vector2(dx + 8, -20), Vector2(dx - 8, -19),
		])
		_face.add_child(socket)
		var glint := Polygon2D.new()
		glint.color = Color(0.85, 0.95, 1.0, 0.85)
		glint.polygon = PackedVector2Array([
			Vector2(dx - 3, -31), Vector2(dx + 2, -32), Vector2(dx + 1, -26), Vector2(dx - 3, -26),
		])
		_face.add_child(glint)
	var mouth := Line2D.new()
	mouth.width = 2.6
	mouth.default_color = Color(0.06, 0.10, 0.16, 0.85)
	mouth.points = PackedVector2Array([
		Vector2(-16, -12), Vector2(-6, -7), Vector2(6, -7), Vector2(16, -12),
	])
	_face.add_child(mouth)

	# 身上和灵魂同款的白色火焰：沿背部排三簇，随呼吸一起飘
	# 魂焰从体内升起：根部压到躯干中段（y ≈ 0~-18），碎片穿过半透明魂体再飘到体外散掉
	for spec in [
		{"pos": Vector2(-30, -6), "scale": 1.5, "radius": 9.0},
		{"pos": Vector2(4, 2), "scale": 1.9, "radius": 11.0},
		{"pos": Vector2(34, -10), "scale": 1.3, "radius": 8.0},
		{"pos": Vector2(-4, -18), "scale": 1.4, "radius": 10.0},
	]:
		var flame := SOUL_FLAME.new()
		flame.position = spec["pos"]
		flame.scale = Vector2.ONE * float(spec["scale"])
		flame.set("base_radius", float(spec["radius"]))
		flame.set("rise_height", 42.0)
		flame.set("fragment_count", 8)
		_visual.add_child(flame)

	# 往上飘的魂丝
	var wisps := CPUParticles2D.new()
	wisps.amount = 16
	wisps.lifetime = 2.4
	wisps.preprocess = 1.0
	wisps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	wisps.emission_sphere_radius = 40.0
	wisps.direction = Vector2(0, -1)
	wisps.spread = 20.0
	wisps.gravity = Vector2(0, -30)
	wisps.initial_velocity_min = 8.0
	wisps.initial_velocity_max = 24.0
	wisps.scale_amount_min = 0.4
	wisps.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.80, 0.90, 1.0, 0.6))
	ramp.set_color(1, Color(0.55, 0.66, 0.86, 0.0))
	wisps.color_ramp = ramp
	wisps.position = Vector2(0, -30)
	add_child(wisps)

	var glow := PointLight2D.new()
	glow.name = "Glow"
	glow.texture = _radial_texture()
	glow.texture_scale = 2.4
	glow.energy = 0.8
	glow.color = Color(0.70, 0.86, 1.0)
	glow.position = Vector2(0, -26)
	add_child(glow)

func _build_contact_area() -> void:
	_contact_area = Area2D.new()
	_contact_area.name = "ContactArea"
	_contact_area.collision_layer = 0
	_contact_area.collision_mask = 2
	var shape := CircleShape2D.new()
	shape.radius = 40.0
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -26)
	_contact_area.add_child(col)
	add_child(_contact_area)
	_contact_area.body_entered.connect(_on_contact)

func _physics_process(delta: float) -> void:
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	_anim_time += delta
	if _is_dead:
		_update_death(delta)
		return
	match _state:
		State.IDLE:
			_apply_gravity(delta)
			move_and_slide()
			_timer -= delta
			if _timer <= 0.0:
				_pick_skill()
		State.CROUCH:
			_apply_gravity(delta)
			move_and_slide()
			_timer -= delta
			if _timer <= 0.0:
				_jump_up()
		State.RISE:
			_apply_gravity(delta)
			move_and_slide()
			if velocity.y >= 0.0 and global_position.y < _arena_floor_y - 120.0:
				_state = State.HOVER
				_hover_timer = SLAM_HOVER
				velocity = Vector2.ZERO
		State.HOVER:
			velocity = Vector2.ZERO
			_hover_timer -= delta
			if _hover_timer <= 0.0:
				_state = State.SLAM
				velocity.y = SLAM_DOWN_V
		State.SLAM:
			_apply_gravity(delta)
			move_and_slide()
			if is_on_floor():
				_on_slam_land()
		State.SPIT_WINDUP:
			_apply_gravity(delta)
			move_and_slide()
			_timer -= delta
			if _timer <= 0.0:
				_spit()
		State.DEAD:
			pass
	_update_visual()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

var _arena_floor_y := 600.0

func set_arena_floor(y: float) -> void:
	_arena_floor_y = y

func _pick_skill() -> void:
	var player := _get_player()
	if player == null:
		_timer = IDLE_TIME
		return
	# 两种技能从开场就随机切换，不按距离、也没有第二形态
	if randf() < 0.5:
		_state = State.CROUCH
		_timer = SLAM_CROUCH
		_shockwave_done = false
	else:
		_state = State.SPIT_WINDUP
		_timer = SPIT_WINDUP

func _jump_up() -> void:
	var player := _get_player()
	velocity = Vector2(0, SLAM_JUMP_V)
	if player != null:
		velocity.x = signf(player.global_position.x - global_position.x) * 90.0
	_state = State.RISE

func _on_slam_land() -> void:
	if _shockwave_done:
		return
	_shockwave_done = true
	velocity = Vector2.ZERO
	_spawn_shockwave()
	GameManager.play_sfx("boss_roar", -6.0)
	_state = State.IDLE
	_timer = IDLE_TIME

## 落地冲击波：一圈短暂的范围伤害，只在贴地时命中
func _spawn_shockwave() -> void:
	var wave := Area2D.new()
	wave.name = "Shockwave"
	wave.collision_layer = 0
	wave.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = Vector2(220, 46)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, 18)
	wave.add_child(col)
	wave.body_entered.connect(func(body: Node2D) -> void:
		if body.has_method("take_damage"):
			body.take_damage(1, self)
	)
	add_child(wave)
	var vis := Polygon2D.new()
	vis.color = Color(0.72, 0.86, 1.0, 0.22)
	vis.polygon = PackedVector2Array([
		Vector2(-110, 40), Vector2(110, 40), Vector2(90, 6), Vector2(-90, 6),
	])
	wave.add_child(vis)
	var tw := create_tween()
	tw.tween_property(vis, "modulate:a", 0.0, 0.35)
	tw.tween_callback(wave.queue_free)

func _spit() -> void:
	var player := _get_player()
	if player == null:
		_state = State.IDLE
		_timer = IDLE_TIME
		return
	var bullet := SLIME_BULLET_SCENE.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = global_position + Vector2(0, -42)
	var dir := signf(player.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	bullet.velocity = Vector2(dir * SPIT_SPEED_X, SPIT_SPEED_Y)
	GameManager.play_sfx("slime_voice", -8.0, 0.85)
	_state = State.IDLE
	_timer = IDLE_TIME

func _update_visual() -> void:
	if _visual == null:
		return
	var breath := 1.0 + sin(_anim_time * 2.2) * 0.03
	_visual.scale = Vector2(breath, 2.0 - breath)
	if _state == State.CROUCH:
		_visual.scale = Vector2(1.12, 0.82)
	elif _state == State.HOVER:
		_visual.scale = Vector2(0.94, 1.08)
	elif _state == State.SLAM:
		_visual.scale = Vector2(0.88, 1.16)
	# 空中时脸更明显地"浮"出来
	if _face != null:
		_face.modulate.a = 0.85 if _state == State.HOVER or _state == State.HOVER else 0.75

func _on_contact(body: Node2D) -> void:
	if _is_dead or _contact_cd > 0.0:
		return
	if not body.has_method("take_damage"):
		return
	body.take_damage(CONTACT_DAMAGE, self)
	_contact_cd = CONTACT_COOLDOWN

## 给关卡的 Boss 血条用
func is_dead() -> bool:
	return _is_dead

func get_hp() -> int:
	return hp

func get_max_hp() -> int:
	return MAX_HP

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = maxi(hp - amount, 0)
	GameManager.play_sfx("enemy_hit", -2.0)
	if _body != null:
		_body.color = Color(1.0, 0.92, 0.92, 0.75)
		var tw := create_tween()
		tw.tween_property(_body, "color", Color(0.62, 0.74, 0.86, 0.55), 0.12)
	if hp <= 0:
		_die()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_state = State.DEAD
	_death_timer = DEATH_TIME
	_contact_area.set_deferred("monitoring", false)
	velocity = Vector2.ZERO
	set_collision_layer_value(1, false)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.enemy_killed.emit(self, global_position)
		bus.boss_defeated.emit("soul_slime")
	GameManager.set_flag("floor1_boss_defeated")
	GameManager.play_sfx("boss_roar", -4.0)

func _update_death(delta: float) -> void:
	_death_timer -= delta
	_visual.modulate.a = clampf(_death_timer / DEATH_TIME, 0.0, 1.0)
	_visual.scale = Vector2.ONE * (1.0 + (1.0 - _death_timer / DEATH_TIME) * 0.35)
	if _death_timer <= 0.0:
		queue_free()

func _get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player")

func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex
