extends Area2D
## 起点骨片（M3-03）
##
## 只在该周目从第三层回头时生成。碰到就收进身上；之后拿去祭坛“归还”，
## 不走进祭坛的普通献祭流程。视觉是一块发白光的旧骨片，和紫色寄生组织反着来。

const PICKUP_RISE := 24.0
const PICKUP_TIME := 0.45

var _time := 0.0
var _base_y := 0.0
var _picked := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_y = position.y
	_build_visual()

func _build_visual() -> void:
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0.0, 0.0, 0.0, 0.30)
	shadow.position = Vector2(0, 17)
	shadow.polygon = PackedVector2Array([
		Vector2(-18, 2), Vector2(-9, -2), Vector2(8, -2), Vector2(20, 2),
		Vector2(9, 6), Vector2(-10, 6),
	])
	add_child(shadow)
	var halo := Sprite2D.new()
	halo.name = "Halo"
	halo.texture = _radial_texture()
	halo.position = Vector2(0, -2)
	halo.scale = Vector2(0.9, 0.9)
	halo.modulate = Color(0.82, 0.95, 0.84, 0.30)
	add_child(halo)
	var shard := Node2D.new()
	shard.name = "Shard"
	shard.rotation = -0.28
	add_child(shard)
	var bone := Polygon2D.new()
	bone.color = Color(0.80, 0.77, 0.62, 1)
	bone.polygon = PackedVector2Array([
		Vector2(-14, -4), Vector2(-6, -8), Vector2(8, -6),
		Vector2(14, 0), Vector2(8, 4), Vector2(-8, 5),
	])
	shard.add_child(bone)
	var notch := Polygon2D.new()
	notch.color = Color(0.13, 0.12, 0.10, 0.9)
	notch.polygon = PackedVector2Array([
		Vector2(-3, -3), Vector2(4, -5), Vector2(3, 2), Vector2(-2, 3),
	])
	shard.add_child(notch)
	var vein := Line2D.new()
	vein.width = 1.2
	vein.default_color = Color(0.88, 0.72, 0.36, 0.8)
	vein.points = PackedVector2Array([Vector2(-11, -2), Vector2(0, -1), Vector2(11, -3)])
	shard.add_child(vein)
	var spark := CPUParticles2D.new()
	spark.name = "Spark"
	spark.amount = 6
	spark.lifetime = 1.4
	spark.preprocess = 0.5
	spark.direction = Vector2(0, -1)
	spark.spread = 50.0
	spark.gravity = Vector2(0, -5)
	spark.initial_velocity_min = 3.0
	spark.initial_velocity_max = 9.0
	spark.scale_amount_min = 0.4
	spark.scale_amount_max = 0.9
	spark.color = Color(0.86, 0.94, 0.78, 0.55)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 8
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	spark.texture = tex
	add_child(spark)

func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 96
	tex.height = 96
	return tex

func _process(delta: float) -> void:
	if _picked:
		return
	_time += delta
	position.y = _base_y + sin(_time * 2.2) * 2.0
	var halo := get_node_or_null("Halo") as Sprite2D
	if halo != null:
		halo.modulate.a = 0.24 + sin(_time * 2.6) * 0.06

func _on_body_entered(body: Node2D) -> void:
	if _picked or not body.is_in_group("player"):
		return
	_picked = true
	set_deferred("monitoring", false)
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.call("set_flag", "true_he_relic")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.item_picked.emit("origin_relic", 1)
	_play_pickup()

func _play_pickup() -> void:
	var shard := get_node_or_null("Shard") as Node2D
	var tween: Tween
	if shard != null:
		tween = create_tween().set_parallel()
		tween.tween_property(shard, "position:y", -PICKUP_RISE, PICKUP_TIME)
		tween.tween_property(shard, "scale", Vector2(0.7, 0.7), PICKUP_TIME)
		tween.tween_property(shard, "modulate:a", 0.0, PICKUP_TIME)
	if tween != null:
		await tween.finished
	_play_voice()
	queue_free()

func _play_voice() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var dialogue := root.find_child("Dialogue", true, false)
	if dialogue == null or not dialogue.has_method("play"):
		return
	if dialogue.has_method("is_playing") and bool(dialogue.call("is_playing")):
		return
	dialogue.call("play", "true_he_relic_pickup")
