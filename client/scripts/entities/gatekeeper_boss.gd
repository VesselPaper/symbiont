extends CharacterBody2D
## 守门者 Boss（M3-02）
##
## 上一个走到这里的容器，被寄生体留在这里守门。平时缓慢逼近；
## 远了就蓄力冲撞，近了就跳起砸地放两道震波；半血后动作变快。
##
## 数值 hp/attack_damage 从 DataDB 的 gatekeeper_boss 读；行为参数在顶部常量，
## 属于手感不属于数值表。死亡时发 EventBus.boss_defeated，出口门由关卡脚本打开。

const ENEMY_ID := "gatekeeper_boss"
const DEFAULT_HP := 24
const DEFAULT_ATTACK_DAMAGE := 2

const GRAVITY := 1900.0
const MAX_FALL_SPEED := 950.0
const CHASE_SPEED := 58.0
const CHASE_SPEED_PHASE2 := 78.0
const CHARGE_SPEED := 300.0
const CHARGE_TELEGRAPH := 0.58
const CHARGE_TIME := 0.55
const SLAM_TELEGRAPH := 0.52
const SLAM_JUMP := -560.0
const RECOVER_TIME := 0.42
const ATTACK_INTERVAL := 2.35
const ATTACK_INTERVAL_PHASE2 := 1.65
const CONTACT_COOLDOWN := 0.9
const FLASH_TIME := 0.12
const HIT_STUN := 0.12
const KNOCKBACK_FRICTION := 900.0
const DEATH_TIME := 1.35

const SHOCKWAVE_SCENE := preload("res://scenes/entities/boss_shockwave.tscn")
# M4-09：Boss 厅右移到 2800~4200，活动范围跟着走；不能再用旧厅的 2240~3550，
# 否则 Boss 会被卡在厅中段，出口门那半边永远打不到。
const ARENA_LEFT := 2900.0
const ARENA_RIGHT := 4050.0

enum State { IDLE, TELEGRAPH_CHARGE, CHARGE, TELEGRAPH_SLAM, SLAM_AIR, RECOVER, DEAD }

@export var activate_on_ready := false

var hp := DEFAULT_HP
var max_hp := DEFAULT_HP
var attack_damage := DEFAULT_ATTACK_DAMAGE
var _state := State.IDLE
var _state_time := 0.0
var _attack_cd := 1.4
var _contact_cd := 0.0
var _flash_timer := 0.0
var _stun_timer := 0.0
## 守门者很重：被推开得少，玩家反而被反作用力顶得更远。
var knockback_weight := 8.0
## 被打中时用什么材质声（player 按这个名字取 hit_<材质>）
var hit_material := "metal"
var _phase2 := false
var _dead := false
var _active := false
var _facing := -1
var _anim_time := 0.0
var _player: Node2D
var _visual: Node2D
var _sword: Node2D
var _eye: Polygon2D
var _body_color := Color(0.16, 0.17, 0.18, 1)

@onready var _contact: Area2D = $ContactArea

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("enemy")
	add_to_group("boss")
	_load_stats()
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_contact.body_entered.connect(_on_contact_body_entered)
	_build_visual()
	if activate_on_ready:
		activate()

func _load_stats() -> void:
	var db := get_node_or_null("/root/DataDB")
	if db == null:
		hp = DEFAULT_HP
		max_hp = DEFAULT_HP
		return
	var data: Dictionary = db.call("get_enemy", ENEMY_ID)
	if data.is_empty():
		hp = DEFAULT_HP
		max_hp = DEFAULT_HP
		attack_damage = DEFAULT_ATTACK_DAMAGE
		return
	max_hp = int(data.get("hp", DEFAULT_HP))
	hp = max_hp
	attack_damage = int(data.get("attack_damage", DEFAULT_ATTACK_DAMAGE))

func activate() -> void:
	_active = true
	_state = State.IDLE
	_state_time = 0.0
	_attack_cd = 1.2
	GameManager.play_sfx("boss_roar", 2.0)
	# 战斗音乐由音频总监接；无头/无 AudioDirector 时信号空跑，不阻断 Boss
	EventBus.boss_encounter_started.emit(ENEMY_ID)

func get_hp() -> int:
	return hp

func get_max_hp() -> int:
	return max_hp

func is_dead() -> bool:
	return _dead

func is_phase2() -> bool:
	return _phase2

func get_state_name() -> String:
	return State.keys()[_state]

func get_arena_bounds() -> Vector2:
	return Vector2(ARENA_LEFT, ARENA_RIGHT)

# ---------- 行为 ----------

func _physics_process(delta: float) -> void:
	_anim_time += delta
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
	if _contact_cd > 0.0:
		_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _dead:
		_apply_gravity(delta)
		move_and_slide()
		return
	if not _active:
		_apply_gravity(delta)
		move_and_slide()
		_update_visual()
		return
	if _stun_timer > 0.0:
		# 受击硬直期间中断当前动作，防止刚打退就立刻冲撞
		_stun_timer = maxf(_stun_timer - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, KNOCKBACK_FRICTION * delta)
		_apply_gravity(delta)
		move_and_slide()
		_update_visual()
		return
	_player = _resolve_player()
	if _player == null:
		return
	var dx := _player.global_position.x - global_position.x
	var dy := _player.global_position.y - global_position.y
	if absf(dx) > 2.0:
		_facing = 1 if dx > 0.0 else -1
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_state_time = maxf(_state_time - delta, 0.0)
	match _state:
		State.IDLE:
			_move_toward_player(dx, delta)
			if _attack_cd <= 0.0 and is_on_floor():
				_start_attack(absf(dx), dy)
		State.TELEGRAPH_CHARGE:
			velocity.x = 0.0
			if _state_time <= 0.0:
				_state = State.CHARGE
				_state_time = CHARGE_TIME
				velocity.x = _facing * CHARGE_SPEED
				GameManager.play_sfx("boss_charge", 0.0, 1.0 if not _phase2 else 1.08)
		State.CHARGE:
			velocity.x = _facing * CHARGE_SPEED
			if _state_time <= 0.0:
				_enter_recover()
		State.TELEGRAPH_SLAM:
			velocity.x = 0.0
			if _state_time <= 0.0:
				_state = State.SLAM_AIR
				velocity.y = SLAM_JUMP
				GameManager.play_sfx("steam", -1.0, 0.85)
		State.SLAM_AIR:
			velocity.x = _facing * 80.0
			if is_on_floor() and velocity.y >= 0.0:
				_spawn_shockwaves()
				_enter_recover()
		State.RECOVER:
			velocity.x = 0.0
			if _state_time <= 0.0:
				_state = State.IDLE
				_attack_cd = ATTACK_INTERVAL_PHASE2 if _phase2 else ATTACK_INTERVAL
	_apply_gravity(delta)
	move_and_slide()
	# 别让 Boss 被引到厅外的断口：它掉下去既不会死，也没法再打
	global_position.x = clampf(global_position.x, ARENA_LEFT, ARENA_RIGHT)
	# 站进 Boss 身体里只靠 body_entered 会只扣一次，持续贴脸要持续判定
	if _contact_cd <= 0.0:
		for body in _contact.get_overlapping_bodies():
			_try_contact_damage(body)
	_update_visual()

func _resolve_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group("player") as Node2D

func _move_toward_player(dx: float, delta: float) -> void:
	if absf(dx) > 62.0:
		var speed := CHASE_SPEED_PHASE2 if _phase2 else CHASE_SPEED
		velocity.x = signf(dx) * speed
	else:
		velocity.x = 0.0

func _start_attack(distance: float, dy: float) -> void:
	if distance > 210.0:
		_state = State.TELEGRAPH_CHARGE
		_state_time = CHARGE_TELEGRAPH * (0.72 if _phase2 else 1.0)
		velocity.x = 0.0
	else:
		_state = State.TELEGRAPH_SLAM
		_state_time = SLAM_TELEGRAPH * (0.78 if _phase2 else 1.0)
		velocity.x = 0.0
	# 玩家跳得高时优先跳砸，避免 Boss 一直在地面追不上
	if dy < -120.0:
		_state = State.TELEGRAPH_SLAM
		_state_time = SLAM_TELEGRAPH

func _enter_recover() -> void:
	_state = State.RECOVER
	_state_time = RECOVER_TIME
	velocity.x = 0.0

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

func _spawn_shockwaves() -> void:
	var camera := get_tree().get_first_node_in_group("camera")
	if camera != null and camera.has_method("shake"):
		camera.call("shake", 7.0, 0.32)
	GameManager.play_sfx("boss_slam", 2.0)
	GameManager.play_sfx("shockwave", 0.0)
	for dir in [-1.0, 1.0]:
		var wave := SHOCKWAVE_SCENE.instantiate()
		wave.position = global_position + Vector2(dir * 26.0, 30.0)
		wave.call("setup", dir, 1)
		get_parent().add_child(wave)
	EventBus.log_event("boss_slam", {"hp": hp})

func _on_contact_body_entered(body: Node2D) -> void:
	_try_contact_damage(body)

func _try_contact_damage(body: Node2D) -> void:
	if _dead or _contact_cd > 0.0:
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.call("take_damage", attack_damage, self)
		_contact_cd = CONTACT_COOLDOWN

# ---------- 受击 / 死亡 ----------

## 被推开：Boss 重量大，位移很短，但会中断当前动作并给玩家明显反作用力。
func apply_knockback(source_pos: Vector2, strength: float) -> void:
	if _dead or not _active:
		return
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = float(-_facing)
	velocity.x = dir * strength
	velocity.y = -40.0
	_stun_timer = HIT_STUN
	_state = State.IDLE
	_state_time = 0.0
	_attack_cd = maxf(_attack_cd, 0.45)

func take_damage(amount: int) -> void:
	if _dead:
		return
	hp = maxi(hp - amount, 0)
	_flash_timer = FLASH_TIME
	GameManager.play_sfx("boss_hit", -1.0)
	if not _phase2 and hp <= int(max_hp * 0.5):
		_phase2 = true
		_attack_cd = minf(_attack_cd, 0.8)
		GameManager.play_sfx("boss_roar", 1.0, 0.82)
		EventBus.log_event("boss_phase2", {"hp": hp})
	if hp <= 0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	_active = false
	_state = State.DEAD
	velocity.x = 0.0
	velocity.y = -120.0
	# 只撤掉“别人能撞到我”的层，保留和地形的碰撞；否则尸体会在倒地动画里沉进地板
	collision_layer = 0
	_contact.set_deferred("monitoring", false)
	EventBus.boss_defeated.emit(ENEMY_ID)
	EventBus.enemy_killed.emit(self, global_position)
	EventBus.log_event("boss_defeated", {"boss": ENEMY_ID, "sacrifice_count": GameManager.sacrifice_count})
	var tween := create_tween().set_parallel()
	tween.tween_property(_visual, "rotation", 1.45, DEATH_TIME)
	tween.tween_property(_visual, "modulate", Color(0.45, 0.40, 0.42, 0.0), DEATH_TIME)
	tween.tween_property(_eye, "modulate:a", 0.0, 0.35)
	var cleanup := create_tween()
	cleanup.tween_interval(DEATH_TIME + 0.1)
	cleanup.tween_callback(queue_free)

# ---------- 视觉 ----------

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var shadow := Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.42)
	shadow.position = Vector2(0, 31)
	shadow.polygon = PackedVector2Array([
		Vector2(-28, 2), Vector2(-16, -2), Vector2(0, -4),
		Vector2(16, -2), Vector2(28, 2), Vector2(12, 6), Vector2(-12, 6),
	])
	_visual.add_child(shadow)
	# 腿：厚重铁靴，站姿比普通敌人宽
	for dx in [-12.0, 12.0]:
		var leg := Polygon2D.new()
		leg.color = Color(0.09, 0.095, 0.100, 1)
		leg.polygon = PackedVector2Array([
			Vector2(dx - 7, -8), Vector2(dx + 7, -8), Vector2(dx + 9, 30), Vector2(dx - 9, 30),
		])
		_visual.add_child(leg)
		var boot := Polygon2D.new()
		boot.color = Color(0.18, 0.18, 0.16, 1)
		boot.polygon = PackedVector2Array([
			Vector2(dx - 11, 24), Vector2(dx + 11, 24), Vector2(dx + 13, 32), Vector2(dx - 13, 32),
		])
		_visual.add_child(boot)
	# 披风：从肩后垂到脚跟，跑动时拖在后面
	var cape := Polygon2D.new()
	cape.color = Color(0.050, 0.055, 0.060, 1)
	cape.polygon = PackedVector2Array([
		Vector2(-25, -26), Vector2(-14, -34), Vector2(4, -32),
		Vector2(12, 8), Vector2(4, 26), Vector2(-18, 20),
	])
	_visual.add_child(cape)
	var body := Polygon2D.new()
	body.color = _body_color
	body.polygon = PackedVector2Array([
		Vector2(-21, -28), Vector2(19, -28), Vector2(25, 2),
		Vector2(10, 10), Vector2(-15, 8), Vector2(-25, 0),
	])
	_visual.add_child(body)
	var chest := Polygon2D.new()
	chest.color = Color(0.22, 0.23, 0.24, 1)
	chest.polygon = PackedVector2Array([
		Vector2(-16, -22), Vector2(14, -22), Vector2(17, -8),
		Vector2(0, 2), Vector2(-17, -7),
	])
	_visual.add_child(chest)
	# 肩甲：左右各一块，顶端带尖
	for dx in [-23.0, 23.0]:
		var pauldron := Polygon2D.new()
		pauldron.color = Color(0.25, 0.26, 0.26, 1)
		pauldron.polygon = PackedVector2Array([
			Vector2(dx - 10, -26), Vector2(dx + 12, -25), Vector2(dx + 9, -12),
			Vector2(dx - 3, -8), Vector2(dx - 12, -15),
		])
		_visual.add_child(pauldron)
	var helmet := Polygon2D.new()
	helmet.color = Color(0.20, 0.21, 0.22, 1)
	helmet.polygon = PackedVector2Array([
		Vector2(-13, -44), Vector2(10, -46), Vector2(16, -35),
		Vector2(11, -24), Vector2(-10, -24), Vector2(-16, -34),
	])
	_visual.add_child(helmet)
	# 两只角：守门者不是人，轮廓第一眼就能看出来
	for dx in [-1.0, 1.0]:
		var horn := Polygon2D.new()
		horn.color = Color(0.30, 0.28, 0.25, 1)
		horn.polygon = PackedVector2Array([
			Vector2(dx * 10, -43), Vector2(dx * 18, -58), Vector2(dx * 20, -43),
			Vector2(dx * 14, -36),
		])
		_visual.add_child(horn)
	var visor := Polygon2D.new()
	visor.color = Color(0.02, 0.02, 0.02, 1)
	visor.polygon = PackedVector2Array([
		Vector2(-9, -35), Vector2(9, -35), Vector2(7, -28), Vector2(-7, -28),
	])
	_visual.add_child(visor)
	_eye = Polygon2D.new()
	_eye.color = Color(0.94, 0.24, 0.22, 1)
	_eye.position = Vector2(0, -31)
	_eye.polygon = PackedVector2Array([
		Vector2(-7, 0), Vector2(-5, -4), Vector2(0, -5), Vector2(6, -3), Vector2(7, 0),
	])
	_visual.add_child(_eye)
	# 右手大剑：斜拖在地上，蓄力时举起来
	_sword = Node2D.new()
	_sword.name = "SwordPivot"
	_sword.position = Vector2(23, -12)
	_sword.rotation = 0.55
	_visual.add_child(_sword)
	var grip := Polygon2D.new()
	grip.color = Color(0.22, 0.16, 0.12, 1)
	grip.polygon = PackedVector2Array([
		Vector2(-2, -3), Vector2(10, -3), Vector2(10, 3), Vector2(-2, 3),
	])
	_sword.add_child(grip)
	var guard := Polygon2D.new()
	guard.color = Color(0.40, 0.36, 0.26, 1)
	guard.polygon = PackedVector2Array([
		Vector2(8, -9), Vector2(12, -9), Vector2(14, 9), Vector2(10, 9),
	])
	_sword.add_child(guard)
	var blade := Polygon2D.new()
	blade.color = Color(0.58, 0.62, 0.60, 1)
	blade.polygon = PackedVector2Array([
		Vector2(12, -5), Vector2(62, -3), Vector2(70, 0),
		Vector2(62, 3), Vector2(12, 5),
	])
	_sword.add_child(blade)
	var edge := Line2D.new()
	edge.width = 1.4
	edge.default_color = Color(0.90, 0.94, 0.90, 0.85)
	edge.points = PackedVector2Array([Vector2(14, -4), Vector2(69, 0)])
	_sword.add_child(edge)

func _update_visual() -> void:
	if _visual == null:
		return
	var bob := sin(_anim_time * 2.2) * 1.2
	var tilt := 0.0
	var crouch := 0.0
	var sword_rot := 0.55
	var color := Color(1, 1, 1, 1)
	if _state == State.TELEGRAPH_CHARGE:
		tilt = -0.16 * _facing
		sword_rot = -0.45
		color = Color(1.0, 0.78, 0.64, 1.0)
	elif _state == State.CHARGE:
		tilt = 0.18 * _facing
		sword_rot = 1.15
	elif _state == State.TELEGRAPH_SLAM:
		crouch = 5.0
		sword_rot = -1.25
		color = Color(1.0, 0.72, 0.82, 1.0)
	elif _state == State.SLAM_AIR:
		sword_rot = 1.75
		crouch = -2.0
	elif _state == State.RECOVER:
		sword_rot = 0.95
	if _flash_timer > 0.0:
		color = Color(2.0, 1.7, 1.7, 1.0)
	if _phase2 and _state != State.DEAD:
		color = color.lerp(Color(1.0, 0.55, 0.72, 1.0), 0.25)
	_visual.position.y = bob + crouch
	_visual.rotation = tilt
	_visual.scale = Vector2(float(_facing), 1.0)
	_visual.modulate = color
	_sword.rotation = sword_rot
	if _eye != null:
		_eye.modulate = Color(1.0, 0.55, 0.55, 0.85 + 0.15 * sin(_anim_time * 5.0))
