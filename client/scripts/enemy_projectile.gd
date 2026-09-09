class_name EnemyProjectile
extends Area2D
## 孢子抛射弹（孢子怪攻击）：直线飞行，命中玩家造成伤害
## 可被玩家攻击击碎；被下劈命中时玩家弹跳（见 player._on_attack_hitbox_area_entered）

var velocity := Vector2.ZERO
var damage := 1
var _lifetime := 5.0
var _dead := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 2
	body_entered.connect(_on_body)

	# 视觉：发光孢子（叠加）
	var core := ColorRect.new()
	core.offset_left = -4.0
	core.offset_top = -4.0
	core.offset_right = 4.0
	core.offset_bottom = 4.0
	core.color = Color(0.82, 0.85, 0.35)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	core.material = mat
	add_child(core)
	add_child(VisualLib.make_glow(10.0, Color(0.82, 0.85, 0.35), 0.4))


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _on_body(body: Node2D) -> void:
	if _dead:
		return
	if body is CharacterBody2D and body.has_method("take_damage"):
		_dead = true
		body.take_damage(damage, global_position)
		queue_free()
