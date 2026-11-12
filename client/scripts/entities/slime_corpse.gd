extends Node2D
## 史莱姆尸体（M2-05）
##
## 史莱姆死亡后不再直接消失：留一具能看出来的软体尸体（压扁、断口、汁液、骨片），
## 停留几秒再淡出。纯表现，不挂碰撞、不进 damageable，玩家不能踩/不能再打。
## 放在敌人死亡位置，肢体拾取物在旁边错开，避免两个模型叠在一起。

const LIFETIME := 7.0
const FADE_TIME := 1.4

var _time := 0.0
var _faded := false

func _ready() -> void:
	z_index = -1
	_build()

func _process(delta: float) -> void:
	_time += delta
	if not _faded and _time >= LIFETIME - FADE_TIME:
		_faded = true
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
		tween.tween_callback(queue_free)

func _build() -> void:
	var shadow := Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.30)
	shadow.polygon = PackedVector2Array([
		Vector2(-26, 5), Vector2(-16, 0), Vector2(0, -2),
		Vector2(17, 0), Vector2(26, 5), Vector2(14, 9), Vector2(-14, 9),
	])
	add_child(shadow)
	# 压扁的主躯干，轮廓仍能看出是软体
	var flesh := Polygon2D.new()
	flesh.color = Color(0.19, 0.39, 0.28, 0.95)
	flesh.polygon = PackedVector2Array([
		Vector2(-24, 1), Vector2(-17, -6), Vector2(-7, -9),
		Vector2(4, -8), Vector2(14, -5), Vector2(24, 1),
		Vector2(18, 7), Vector2(7, 10), Vector2(-7, 10), Vector2(-18, 7),
	])
	add_child(flesh)
	var belly := Polygon2D.new()
	belly.color = Color(0.11, 0.24, 0.18, 0.95)
	belly.polygon = PackedVector2Array([
		Vector2(-20, 4), Vector2(-8, 8), Vector2(3, 9),
		Vector2(14, 6), Vector2(20, 3), Vector2(10, 8), Vector2(-9, 9),
	])
	add_child(belly)
	# 断口：深色创面 + 一点亮边，别让尸体看起来只是压扁的史莱姆
	var cut := Polygon2D.new()
	cut.color = Color(0.20, 0.07, 0.16, 0.95)
	cut.polygon = PackedVector2Array([
		Vector2(17, -5), Vector2(25, -1), Vector2(24, 5), Vector2(15, 5),
		Vector2(18, 1),
	])
	add_child(cut)
	var cut_rim := Line2D.new()
	cut_rim.width = 1.3
	cut_rim.default_color = Color(0.58, 0.30, 0.52, 0.75)
	cut_rim.points = PackedVector2Array([Vector2(16, -4), Vector2(25, -1), Vector2(24, 5)])
	add_child(cut_rim)
	# 骨片与汁液：两三个小分件，远看也能判断"这里死过东西"
	var bone := Polygon2D.new()
	bone.color = Color(0.72, 0.72, 0.62, 0.9)
	bone.position = Vector2(10, 1)
	bone.polygon = PackedVector2Array([
		Vector2(-4, 0), Vector2(-1, -3), Vector2(3, -2), Vector2(5, 1), Vector2(1, 3),
	])
	add_child(bone)
	for i in range(3):
		var drop := Polygon2D.new()
		drop.color = Color(0.30, 0.55, 0.25, 0.55)
		drop.position = Vector2(-14 + i * 10, 8 + (i % 2) * 3)
		drop.polygon = PackedVector2Array([
			Vector2(-3, 0), Vector2(0, -2), Vector2(3, 0), Vector2(1, 2), Vector2(-1, 2),
		])
		add_child(drop)
