extends CharacterBody2D
## 孢子射手（M2-07）—— 第二个真正的敌人
##
## 行为：扎在遗物廊高处的孢子囊，不巡逻；玩家进入射程且在同一层时，
## 先鼓起孢子囊蓄力（0.55s），再朝玩家吐一颗直线孢子弹（1 伤害）。
## 这样玩家不能只靠贴脸乱砍，要读蓄力、绕开弹道。
##
## 数据来自 DataDB.get_enemy("spore_shooter")；行为常数在脚本顶部，改手感只改这里。
## 受击/死亡/掉肢体沿用史莱姆的接口（damageable/enemy 分组、EventBus 信号）。

const ENEMY_ID := "spore_shooter"
const DEFAULT_HP := 6
const DEFAULT_SPEED := 20.0
const DEFAULT_ATTACK_DAMAGE := 1

const GRAVITY := 1600.0
const MAX_FALL_SPEED := 700.0
const ATTACK_RANGE := 320.0
const SAME_FLOOR_TOLERANCE := 82.0
const TELEGRAPH_TIME := 0.55
const ATTACK_COOLDOWN := 1.85
const CONTACT_DAMAGE_COOLDOWN := 0.9
const VOICE_COOLDOWN := 5.5

const FLASH_TIME := 0.1
const HIT_FLASH_COLOR := Color(1.0, 0.35, 0.35)
const DEATH_TIME := 0.32

const PROJECTILE_SCENE := preload("res://scenes/entities/spore_projectile.tscn")
const LIMB_PICKUP_SCENE := preload("res://scenes/items/limb_pickup.tscn")
const CORPSE_SCENE := preload("res://scenes/entities/slime_corpse.tscn")

var hp: int
var attack_damage: int
## 孢子囊扎根在地里，不能整体位移；重量用于玩家反作用力计算，受击只做视觉后仰。
var knockback_weight := 2.0
## 被打中时用什么材质声（player 按这个名字取 hit_<材质>）
var hit_material := "flesh"
var _attack_cd := 0.9
var _telegraph := 0.0
var _flashing := 0.0
var _contact_cd := 0.0
var _voice_cd := 2.0
var _is_dying := false
var _anim_time := 0.0
var _base_color := Color(0.56, 0.72, 0.46, 1.0)
var _visual: Node2D
var _sac: Polygon2D
var _cap: Polygon2D
var _contact: Area2D
var _push_tween: Tween

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("enemy")
	_load_stats()
	_build_visual()
	_build_contact()
	var bus := _event_bus()
	if bus != null:
		bus.enemy_spawned.emit(self)

func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus")

func _load_stats() -> void:
	var db := get_node_or_null("/root/DataDB")
	var data: Dictionary = db.get_enemy(ENEMY_ID) if db != null else {}
	if data.is_empty():
		push_warning("SporeShooter: DataDB 缺少 %s，使用安全默认值" % ENEMY_ID)
		hp = DEFAULT_HP
		attack_damage = DEFAULT_ATTACK_DAMAGE
		return
	hp = int(data.get("hp", DEFAULT_HP))
	attack_damage = int(data.get("attack_damage", DEFAULT_ATTACK_DAMAGE))

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	_visual.z_index = 1
	add_child(_visual)
	var shadow := Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.30)
	shadow.position = Vector2(0, 15)
	shadow.polygon = PackedVector2Array([
		Vector2(-15, 0), Vector2(-8, -4), Vector2(2, -5),
		Vector2(11, -3), Vector2(16, 0), Vector2(6, 4), Vector2(-8, 4),
	])
	_visual.add_child(shadow)
	var stem := Polygon2D.new()
	stem.color = Color(0.25, 0.34, 0.22, 0.96)
	stem.polygon = PackedVector2Array([
		Vector2(-7, 13), Vector2(-4, -8), Vector2(4, -8), Vector2(8, 13),
	])
	_visual.add_child(stem)
	_cap = Polygon2D.new()
	_cap.color = _base_color
	_cap.polygon = PackedVector2Array([
		Vector2(-18, -6), Vector2(-15, -18), Vector2(-6, -26),
		Vector2(6, -26), Vector2(15, -18), Vector2(19, -6), Vector2(0, 1),
	])
	_visual.add_child(_cap)
	var cap_shade := Polygon2D.new()
	cap_shade.color = Color(0.30, 0.46, 0.28, 1.0)
	cap_shade.polygon = PackedVector2Array([
		Vector2(-17, -5), Vector2(-10, -2), Vector2(0, 3), Vector2(11, -2),
		Vector2(18, -5), Vector2(16, 2), Vector2(0, 7), Vector2(-15, 2),
	])
	_visual.add_child(cap_shade)
	var rim := Line2D.new()
	rim.width = 1.4
	rim.default_color = Color(0.76, 0.92, 0.62, 0.65)
	rim.points = PackedVector2Array([
		Vector2(-15, -18), Vector2(-7, -25), Vector2(6, -25), Vector2(15, -18),
	])
	_visual.add_child(rim)
	# 三颗孢子囊：蓄力时整颗亮起来，给玩家读招的时间
	for i in range(3):
		_sac = Polygon2D.new()
		_sac.color = Color(0.58, 0.86, 0.48, 0.82)
		var x := -10.0 + i * 10.0
		_sac.polygon = PackedVector2Array([
			Vector2(x - 4, -12), Vector2(x, -17), Vector2(x + 4, -12),
			Vector2(x + 3, -6), Vector2(x - 3, -6),
		])
		_visual.add_child(_sac)
	var eye := Polygon2D.new()
	eye.color = Color(0.04, 0.06, 0.03, 1.0)
	eye.position = Vector2(0, 5)
	eye.polygon = PackedVector2Array([
		Vector2(-4, -2), Vector2(4, -2), Vector2(3, 3), Vector2(-3, 3),
	])
	_visual.add_child(eye)
	var glint := Polygon2D.new()
	glint.color = Color(0.80, 0.98, 0.65, 0.9)
	glint.position = Vector2(1, 4)
	glint.polygon = PackedVector2Array([
		Vector2(-1, -1), Vector2(2, -1), Vector2(1, 1), Vector2(-1, 1),
	])
	_visual.add_child(glint)
	# 缠在根部的菌丝/旧布条，强调它是“长在这里”的
	for side in [-1.0, 1.0]:
		var tendril := Line2D.new()
		tendril.width = 2.0
		tendril.default_color = Color(0.30, 0.40, 0.26, 0.75)
		tendril.points = PackedVector2Array([
			Vector2(side * 5, 12), Vector2(side * 14, 16),
			Vector2(side * 18, 24), Vector2(side * 12, 30),
		])
		_visual.add_child(tendril)

func _build_contact() -> void:
	_contact = Area2D.new()
	_contact.name = "ContactArea"
	_contact.collision_layer = 0
	_contact.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	shape.position = Vector2(0, 4)
	_contact.add_child(shape)
	_contact.body_entered.connect(_on_contact_body_entered)
	add_child(_contact)

func _physics_process(delta: float) -> void:
	if _is_dying:
		velocity.x = 0.0
		return
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	_voice_cd = maxf(_voice_cd - delta, 0.0)
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	velocity.x = 0.0
	move_and_slide()
	var player := _get_player()
	if player == null:
		return
	var dx := absf(player.global_position.x - global_position.x)
	var dy := absf(player.global_position.y - global_position.y)
	var same_floor := dy <= SAME_FLOOR_TOLERANCE
	if dx <= ATTACK_RANGE and same_floor:
		if _voice_cd <= 0.0 and _telegraph <= 0.0:
			_voice_cd = VOICE_COOLDOWN
			GameManager.play_sfx("spore_voice", -12.0, randf_range(0.9, 1.05))
		if _telegraph <= 0.0:
			_attack_cd -= delta
			if _attack_cd <= 0.0:
				_begin_telegraph(player)
		if player.global_position.x < global_position.x:
			_visual.scale.x = -1.0
		else:
			_visual.scale.x = 1.0
	else:
		_attack_cd = maxf(_attack_cd, 0.55)

func _begin_telegraph(player: Node2D) -> void:
	_telegraph = TELEGRAPH_TIME
	GameManager.play_sfx("spore_charge", -3.0)
	# 动作前摇：整颗孢子囊在 0.55s 内从暗绿涨到亮白绿
	var tween := create_tween()
	tween.tween_property(_sac, "color", Color(0.92, 1.0, 0.72, 1.0), TELEGRAPH_TIME * 0.8)
	tween.tween_callback(_fire_at_player.bind(player))

func _fire_at_player(player: Node2D) -> void:
	if _is_dying or player == null or not is_instance_valid(player):
		return
	var projectile := PROJECTILE_SCENE.instantiate()
	var parent := get_parent()
	if parent == null:
		return
	GameManager.play_sfx("spore_fire", -2.0)
	parent.add_child(projectile)
	projectile.global_position = global_position + Vector2(0, -12)
	var dir: Vector2 = player.global_position + Vector2(0, -8) - projectile.global_position
	projectile.call("setup", dir.normalized(), attack_damage)
	_sac.color = Color(0.58, 0.86, 0.48, 0.82)
	_telegraph = 0.0
	_attack_cd = ATTACK_COOLDOWN

func _process(delta: float) -> void:
	_anim_time += delta
	if _is_dying:
		return
	var pulse := sin(_anim_time * 2.2) * 0.015
	_visual.scale.y = 1.0 + pulse
	if _flashing > 0.0:
		_flashing -= delta
		if _flashing <= 0.0:
			_cap.color = _base_color
	if _telegraph > 0.0:
		_telegraph -= delta
		# 蓄力中轻微抖动，和静止的孢子囊区分开
		_visual.position.x = sin(_anim_time * 32.0) * 0.8
	else:
		_visual.position.x = 0.0

func _on_contact_body_entered(body: Node2D) -> void:
	if _contact_cd > 0.0 or _is_dying:
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, self)
		_contact_cd = CONTACT_DAMAGE_COOLDOWN

## 扎根怪不能整体击退，做一次短促后仰再回正，仍然能看出“被打退”。
func apply_knockback(source_pos: Vector2, strength: float) -> void:
	if _is_dying:
		return
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = 1.0
	var offset := dir * clampf(strength * 0.10, 4.0, 12.0)
	if _push_tween != null and _push_tween.is_valid():
		_push_tween.kill()
	_visual.position.x = offset
	_push_tween = create_tween()
	_push_tween.tween_property(_visual, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_QUAD)

func take_damage(amount: int) -> void:
	if hp <= 0 or _is_dying:
		return
	hp = maxi(hp - amount, 0)
	_cap.color = HIT_FLASH_COLOR
	_flashing = FLASH_TIME
	GameManager.play_sfx("enemy_hit", -2.0)
	if hp <= 0:
		_die()

func _die() -> void:
	if _is_dying:
		return
	_is_dying = true
	_telegraph = 0.0
	_contact.set_deferred("monitoring", false)
	var bus := _event_bus()
	if bus != null:
		bus.enemy_killed.emit(self, global_position)
		bus.log_event("spore_shooter_killed", {"pos": global_position})
	_spawn_death_burst()
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.25, 0.55), DEATH_TIME)
	tween.parallel().tween_property(_visual, "modulate:a", 0.0, DEATH_TIME)
	tween.tween_callback(_finish_death)

func _finish_death() -> void:
	if not is_inside_tree():
		return
	_spawn_corpse()
	_spawn_limb()
	queue_free()

func _spawn_corpse() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var corpse := CORPSE_SCENE.instantiate()
	parent.add_child(corpse)
	corpse.global_position = global_position + Vector2(0, 10)
	# 孢子射手的尸体颜色偏黄绿，和史莱姆区分
	corpse.modulate = Color(0.82, 1.0, 0.72, 1.0)

func _spawn_limb() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var pickup := LIMB_PICKUP_SCENE.instantiate()
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector2(14, 8)

func _spawn_death_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.amount = 24
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.5
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 90)
	p.initial_velocity_min = 45.0
	p.initial_velocity_max = 130.0
	p.color = Color(0.72, 0.96, 0.55, 0.9)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			var d := Vector2(x - 1.5, y - 1.5).length() / 2.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	p.texture = ImageTexture.create_from_image(img)
	p.global_position = global_position
	parent.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.7).timeout.connect(p.queue_free)

func _get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player")
