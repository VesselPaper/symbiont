extends Area2D
## 粘液弹（关底 Boss 的第二技能）
##
## 从 Boss 嘴里朝玩家方向抛出，受重力走出抛物线；
## 碰到地面（或世界碰撞层）就在落点铺一滩毒液（scenes/entities/toxic_pool.tscn），
## 命中玩家也会扣一次血。

const TOXIC_POOL_SCENE := preload("res://scenes/entities/toxic_pool.tscn")

const GRAVITY := 1200.0
const DAMAGE := 1
const LIFETIME := 4.0

var velocity := Vector2.ZERO

var _time := 0.0
var _landed := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	z_index = 1
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	_build_visual()
	body_entered.connect(_on_body_entered)

func _build_visual() -> void:
	var drop := Polygon2D.new()
	drop.color = Color(0.46, 0.74, 0.22, 0.95)
	drop.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(7, -4), Vector2(9, 3),
		Vector2(4, 9), Vector2(-4, 9), Vector2(-9, 3), Vector2(-7, -4),
	])
	add_child(drop)
	var gloss := Polygon2D.new()
	gloss.color = Color(0.78, 0.94, 0.56, 0.7)
	gloss.polygon = PackedVector2Array([
		Vector2(-4, -5), Vector2(-1, -7), Vector2(2, -5), Vector2(0, -3),
	])
	add_child(gloss)
	var glow := PointLight2D.new()
	glow.texture = _radial_texture()
	glow.texture_scale = 0.5
	glow.energy = 0.7
	glow.color = Color(0.55, 0.95, 0.35)
	add_child(glow)

func _physics_process(delta: float) -> void:
	if _landed:
		return
	_time += delta
	velocity.y += GRAVITY * delta
	position += velocity * delta
	rotation += delta * 4.0
	# 落地：脚下有明显的地面（向下探 14px 能碰到世界层 1）就铺毒液
	var from := global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 16), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() or _time >= LIFETIME:
		var ground_y := global_position.y
		if not hit.is_empty():
			ground_y = float(hit["position"].y)
		_splash(Vector2(global_position.x, ground_y))

func _splash(at: Vector2) -> void:
	if _landed:
		return
	_landed = true
	var pool := TOXIC_POOL_SCENE.instantiate()
	get_parent().add_child(pool)
	pool.global_position = at
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	body.take_damage(DAMAGE, self)
	_splash(global_position)

func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex
