extends Area2D
## 地面拾取物通用脚本（M1-02 肢体 / M1-10 武器拾取物复用）
##
## 玩家碰到即拾取：emit EventBus.item_picked(item_id, 1) 后播放上浮淡出，
## 动画结束再销毁（M2-05：不再瞬间消失，至少让玩家看见自己捡到了什么）。
## 视觉为占位方块，美术资源到位后替换 Body 节点即可。
## M1-10：ITEM_ID 常量泛化为 @export item_id，默认仍是 "monster_limb"（M1-02 行为不变），
## 武器拾取物场景里配成 "iron_sword"。

const PICKUP_ANIM_TIME := 0.28
const PICKUP_RISE := 18.0

@export var item_id := "monster_limb"
## 上下浮动幅度 px。默认 0 = 静止（武器拾取物插在尸体上要静止）；
## 需要浮动的拾取物（如肢体）在各自场景里显式设 >0（见 limb_pickup.tscn float_amplitude=3.0）
@export var float_amplitude := 0.0
const FLOAT_SPEED := 3.5       # 浮动角速度 rad/s

var _base_y := 0.0
var _base_captured := false
var _time := 0.0
var _picked := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if item_id == "iron_sword":
		_build_weapon_ground_fx()

func _process(delta: float) -> void:
	# 基准高度要在"节点被放到最终位置之后"再记：父节点先 add_child 再设 global_position，
	# _ready 里记的初始值(0)是错的，会导致浮动动画把掉落物拽回屏幕顶部（M1-02 教训）。
	if _picked:
		return
	if not _base_captured:
		_base_y = position.y
		_base_captured = true
	_time += delta
	position.y = _base_y + sin(_time * FLOAT_SPEED) * float_amplitude

func _on_body_entered(body: Node2D) -> void:
	# mask=2 只探测玩家；has_method 兜底防御（只有玩家挂 take_damage）
	if _picked or not body.has_method("take_damage"):
		return
	_picked = true
	set_deferred("monitoring", false)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.item_picked.emit(item_id, 1)
	_play_pickup_anim()

## 拾取表现：先上浮缩小淡出，再销毁；信号已经立即发出，流程不会等动画。
func _play_pickup_anim() -> void:
	var visual := get_node_or_null("Visuals")
	if visual == null:
		visual = get_node_or_null("Visual")
	if visual != null:
		var tween := create_tween().set_parallel()
		tween.tween_property(visual, "position:y", visual.position.y - PICKUP_RISE, PICKUP_ANIM_TIME)
		tween.tween_property(visual, "scale", visual.scale * 0.72, PICKUP_ANIM_TIME)
		tween.tween_property(visual, "modulate:a", 0.0, PICKUP_ANIM_TIME)
		await tween.finished
	queue_free()

## 剑插地表现：剑根节点被场景旋转/缩放过，这里挂一个反向补偿的地面层，
## 保证阴影、裂纹始终贴地平放；只对铁剑生成，不影响肢体。
func _build_weapon_ground_fx() -> void:
	if has_node("GroundFX"):
		return
	var ground := Node2D.new()
	ground.name = "GroundFX"
	# 和剑同层，但排到 Visuals 前面：阴影在剑下面，又不会被 z=-2 的地形盖掉。
	ground.z_index = 0
	ground.rotation = -rotation
	ground.scale = Vector2(1.0 / maxf(scale.x, 0.001), 1.0 / maxf(scale.y, 0.001))
	add_child(ground)
	move_child(ground, 0)
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0.0, 0.0, 0.0, 0.34)
	shadow.position = Vector2(10, 3)
	shadow.polygon = PackedVector2Array([
		Vector2(-20, 0), Vector2(-12, -3), Vector2(4, -3),
		Vector2(20, 0), Vector2(8, 3), Vector2(-10, 3),
	])
	ground.add_child(shadow)
	var crack := Line2D.new()
	crack.name = "Crack"
	crack.width = 1.4
	crack.default_color = Color(0.05, 0.075, 0.070, 0.9)
	crack.points = PackedVector2Array([
		Vector2(-16, 2), Vector2(-8, 0), Vector2(-1, 3), Vector2(7, 1), Vector2(17, 2),
	])
	ground.add_child(crack)
	var dust := CPUParticles2D.new()
	dust.name = "Dust"
	dust.amount = 5
	dust.lifetime = 1.1
	dust.one_shot = true
	dust.emitting = false
	dust.explosiveness = 1.0
	dust.direction = Vector2(0, -1)
	dust.spread = 65.0
	dust.gravity = Vector2(0, 24)
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 12.0
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.2
	dust.color = Color(0.42, 0.38, 0.30, 0.28)
	dust.position = Vector2(8, 0)
	var dust_tex := GradientTexture2D.new()
	var dust_grad := Gradient.new()
	dust_grad.set_color(0, Color(1, 1, 1, 0.8))
	dust_grad.set_color(1, Color(1, 1, 1, 0))
	dust_tex.gradient = dust_grad
	dust_tex.width = 8
	dust_tex.height = 8
	dust_tex.fill = GradientTexture2D.FILL_RADIAL
	dust_tex.fill_from = Vector2(0.5, 0.5)
	dust_tex.fill_to = Vector2(1.0, 0.5)
	dust.texture = dust_tex
	ground.add_child(dust)
	dust.emitting = true
