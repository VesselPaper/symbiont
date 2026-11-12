extends Area2D
## 守门者跳砸震波（M3-02）
##
## 贴地横向跑的伤害波，只认玩家；撞墙/超时自己消失。
## 不挂 projectile 组：它是近战范围的延伸，不是敌方子弹。

const SPEED := 260.0
const LIFETIME := 1.65
const DAMAGE := 1

var direction := 1.0
var damage := DAMAGE
var _age := 0.0
var _visual: Node2D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	_build_visual()

func setup(dir: float, hit_damage: int = DAMAGE) -> void:
	direction = 1.0 if dir >= 0.0 else -1.0
	damage = hit_damage

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var glow := Polygon2D.new()
	glow.color = Color(0.44, 0.20, 0.58, 0.20)
	glow.polygon = PackedVector2Array([
		Vector2(-24, 0), Vector2(-12, -15), Vector2(16, -19),
		Vector2(30, -7), Vector2(26, 2), Vector2(-18, 4),
	])
	_visual.add_child(glow)
	var wave := Line2D.new()
	wave.width = 3.0
	wave.default_color = Color(0.82, 0.58, 1.0, 0.92)
	wave.antialiased = true
	wave.points = PackedVector2Array([
		Vector2(-20, 2), Vector2(-10, -7), Vector2(2, -12),
		Vector2(14, -8), Vector2(21, 2),
	])
	_visual.add_child(wave)
	var core := Line2D.new()
	core.width = 1.2
	core.default_color = Color(1.0, 0.92, 1.0, 0.9)
	core.points = PackedVector2Array([
		Vector2(-14, 0), Vector2(-6, -4), Vector2(4, -6), Vector2(12, -2),
	])
	_visual.add_child(core)
	_visual.scale.x = direction

func _physics_process(delta: float) -> void:
	_age += delta
	position.x += SPEED * direction * delta
	if _age >= LIFETIME:
		queue_free()
		return
	# 尾巴慢慢淡，避免一路全是实线
	_visual.modulate.a = clampf(1.0 - _age / LIFETIME, 0.0, 1.0)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.call("take_damage", damage, self)
	queue_free()
