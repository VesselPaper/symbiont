extends Area2D
## 孢子弹（M2-07）
##
## 直线飞行的远程弹：mask=3 同时探地形(1)和玩家(2)，碰地形/玩家即销毁。
## 这里不引用 Player 类，只调用 take_damage，保持和近战敌人一致的伤害入口。

const SPEED := 190.0
const LIFETIME := 2.6
const DAMAGE := 1
const COLOR := Color(0.66, 0.94, 0.52, 0.95)

var _velocity := Vector2.ZERO
var _life := LIFETIME
var _time := 0.0
var _dead := false
var _damage := DAMAGE
var _visual: Node2D
var _core: Polygon2D

func setup(direction: Vector2, damage: int = DAMAGE) -> void:
	_velocity = direction.normalized() * SPEED
	_damage = damage
	rotation = _velocity.angle()

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("enemy_projectile")
	body_entered.connect(_on_body_entered)
	_build_visual()
	rotation = _velocity.angle()

func _build_visual() -> void:
	_visual = Node2D.new()
	add_child(_visual)
	var glow := Polygon2D.new()
	glow.color = Color(0.45, 0.85, 0.45, 0.20)
	glow.polygon = PackedVector2Array([
		Vector2(-11, 0), Vector2(0, -11), Vector2(11, 0), Vector2(0, 11),
	])
	_visual.add_child(glow)
	_core = Polygon2D.new()
	_core.color = COLOR
	_core.polygon = PackedVector2Array([
		Vector2(-6, 0), Vector2(-2, -6), Vector2(6, -3),
		Vector2(7, 2), Vector2(1, 6), Vector2(-4, 4),
	])
	_visual.add_child(_core)
	var rim := Line2D.new()
	rim.width = 1.2
	rim.default_color = Color(0.88, 1.0, 0.78, 0.9)
	rim.points = PackedVector2Array([
		Vector2(-5, -4), Vector2(2, -6), Vector2(6, -2),
	])
	_visual.add_child(rim)
	# 尾迹用几粒小孢子，飞行方向看得出，不靠贴图
	var trail := CPUParticles2D.new()
	trail.amount = 8
	trail.lifetime = 0.28
	trail.one_shot = false
	trail.direction = Vector2(-1, 0)
	trail.spread = 28.0
	trail.gravity = Vector2(0, 0)
	trail.initial_velocity_min = 18.0
	trail.initial_velocity_max = 42.0
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.1
	trail.color = Color(0.60, 0.90, 0.52, 0.55)
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	for y in range(3):
		for x in range(3):
			var d := Vector2(x - 1, y - 1).length() / 1.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	trail.texture = ImageTexture.create_from_image(img)
	trail.position = Vector2(-8, 0)
	add_child(trail)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	_life -= delta
	global_position += _velocity * delta
	_visual.position = Vector2(0, sin(_time * 18.0) * 1.6)
	if _life <= 0.0:
		_burst_and_free()

func _on_body_entered(body: Node2D) -> void:
	if _dead:
		return
	# 地形：孢子打在石头上直接爆开；玩家：走统一 take_damage
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(_damage, self)
		_burst_and_free()
		return
	if body is StaticBody2D or body is TileMap or body is CollisionObject2D:
		_burst_and_free()

func _burst_and_free() -> void:
	if _dead:
		return
	_dead = true
	set_deferred("monitoring", false)
	var parent := get_parent()
	if parent != null:
		var p := CPUParticles2D.new()
		p.amount = 10
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.28
		p.direction = Vector2(0, -1)
		p.spread = 180.0
		p.gravity = Vector2(0, 45)
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 80.0
		p.color = Color(0.62, 0.92, 0.52, 0.8)
		var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
		for y in range(3):
			for x in range(3):
				var d := Vector2(x - 1, y - 1).length() / 1.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
		p.texture = ImageTexture.create_from_image(img)
		p.global_position = global_position
		parent.add_child(p)
		p.emitting = true
		get_tree().create_timer(0.4).timeout.connect(p.queue_free)
	queue_free()
