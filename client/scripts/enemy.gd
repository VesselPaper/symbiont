class_name PatrolEnemy
extends CharacterBody2D
## 敌人分型（GDD 第 6 节）—— Kenney Tiny Dungeon 素材 sprite
##   patrol  巡逻仆役：地面往返，接触伤害，HP1
##   spitter 孢子怪：站桩远程抛弹，HP2（弹可被击碎/下劈）
##   diver   深渊飞虫：空中往返 + 悬浮预警俯冲，HP2
## 通用：受击闪白+硬直、接触伤害、死亡粒子；事件经 GameEvents

@export var speed := 55.0
@export var patrol_half_width := 120.0
@export var hp := 1
@export var touch_damage := 1

enum EnemyType { PATROL, SPITTER, DIVER }
var type: EnemyType = EnemyType.PATROL
var type_key := "patrol"

const PLAYER_LAYER := 2
const PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")

# 状态
var _home_x := 0.0
var _dir := 1
var _dead := false
var _hit_cd := 0.0
var _flash := 0.0
var _wiggle_t := 0.0

# spitter
var _shoot_timer := 0.0
var _telegraph := -1.0

# diver
var _base_y := 0.0
var _dive_state := 0
var _dive_timer := 0.0
var _target_y := 0.0


func _ready() -> void:
	_home_x = global_position.x
	_base_y = global_position.y
	_build_visual()
	_build_hurt_area()
	_shoot_timer = randf_range(1.2, 2.2)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)

	match type:
		EnemyType.PATROL:
			_physics_patrol(delta)
		EnemyType.SPITTER:
			_physics_spitter(delta)
		EnemyType.DIVER:
			_physics_diver(delta)

	# 轻微体型起伏（生存感）
	_wiggle_t += delta
	var spr := $Visual.get_child(0) if $Visual.get_child_count() > 0 else null
	if spr is Sprite2D:
		spr.scale.y = 1.0 + 0.06 * sin(_wiggle_t * 8.0)

	# 受击闪白
	if _flash > 0.0:
		$Visual.modulate = Color(1.8, 1.1, 1.1)
	elif _dive_state != 1:
		$Visual.modulate = Color.WHITE


# ---------------- 三型行为 ----------------

func _physics_patrol(delta: float) -> void:
	if not is_on_floor():
		velocity.y += 1900.0 * delta
	velocity.x = _dir * speed
	move_and_slide()
	if is_on_wall():
		_dir *= -1
	elif absf(global_position.x - _home_x) >= patrol_half_width:
		_dir *= -1


func _physics_spitter(delta: float) -> void:
	if not is_on_floor():
		velocity.y += 1900.0 * delta
	velocity.x = 0.0
	move_and_slide()

	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _telegraph < 0.0:
		_shoot_timer = 2.6 + randf_range(-0.4, 0.4)
		_telegraph = 0.45
	if _telegraph > 0.0:
		_telegraph -= delta
		if _telegraph <= 0.0:
			_telegraph = -1.0
			_spawn_projectile()


func _physics_diver(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	match _dive_state:
		0:  # 空中往返
			velocity.x = _dir * speed * 1.3
			velocity.y = (_base_y - global_position.y) * 4.0
			move_and_slide()
			if absf(global_position.x - _home_x) >= patrol_half_width:
				_dir *= -1
			if player and absf(player.global_position.x - global_position.x) < 90.0 \
					and player.global_position.y > global_position.y - 10.0:
				_dive_state = 1
				_dive_timer = 0.55
				_target_y = player.global_position.y + 60.0
		1:  # 悬浮预警（闪白）
			velocity = Vector2.ZERO
			_dive_timer -= delta
			$Visual.modulate = Color(1.6, 1.6, 1.6) if fmod(_dive_timer, 0.12) < 0.06 else Color.WHITE
			if _dive_timer <= 0.0:
				_dive_state = 2
		2:  # 俯冲
			velocity.x = 0.0
			velocity.y += 1000.0 * delta
			move_and_slide()
			if is_on_floor() or global_position.y > _target_y + 150.0:
				_dive_state = 0
				$Visual.modulate = Color.WHITE
				_dir *= -1


func _spawn_projectile() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var dir := -1.0
	if player and player.global_position.x > global_position.x:
		dir = 1.0
	var proj := PROJECTILE_SCRIPT.new()
	proj.velocity = Vector2(dir * 130.0, 40.0)
	proj.global_position = global_position + Vector2(dir * 8.0, -6.0)
	get_parent().add_child(proj)


# ---------------- 视觉（素材 sprite） ----------------

func _build_visual() -> void:
	var vis: Node2D = $Visual
	for c in vis.get_children():
		c.free()
	var tex: Texture2D
	match type:
		EnemyType.PATROL:
			tex = VisualLib.get_enemy_patrol_texture()
		EnemyType.SPITTER:
			tex = VisualLib.get_enemy_spitter_texture()
		EnemyType.DIVER:
			tex = VisualLib.get_enemy_diver_texture()
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = Vector2(0, -6)
	vis.add_child(spr)


# ---------------- 碰撞 / 受击 ----------------

func _build_hurt_area() -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = PLAYER_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	area.add_child(shape)
	area.body_entered.connect(_on_player_touch)
	add_child(area)


func _on_player_touch(body: Node2D) -> void:
	if _dead:
		return
	if body is CharacterBody2D and body.has_method("take_damage"):
		body.take_damage(touch_damage, global_position)


func take_hit(dmg: int) -> void:
	if _dead or _hit_cd > 0.0:
		return
	_hit_cd = 0.25
	hp -= dmg
	_flash = 0.12
	velocity.x = -_dir * 90.0
	velocity.y = -120.0
	GameEvents.enemy_damaged.emit()
	if hp <= 0:
		_die()


func _die() -> void:
	_dead = true
	GameEvents.enemy_killed.emit(global_position)
	GameEvents.stats_event.emit("kill", {"type": type_key})
	var burst := VisualLib.make_dust_puff()
	burst.color = Color(0.9, 0.75, 0.4, 0.8)
	burst.amount = 12
	burst.global_position = global_position
	get_parent().add_child(burst)
	burst.emitting = true
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(burst):
		burst.queue_free()
	queue_free()
