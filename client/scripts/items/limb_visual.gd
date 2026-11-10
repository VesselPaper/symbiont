extends Node2D
## 怪物肢体拾取物的建模（M2-04）
##
## 之前只是一个 12×12 的绿色方块；这里用软体断肢的剪影：绿色胶质手臂、
## 左侧断口露出的骨片、右侧三根蜷曲指节、体液滴和一圈冷绿微光。
## 全部代码生成，拾取判定仍在父节点 Area2D 上，视觉大小不参与碰撞。

var _time := 0.0

func _ready() -> void:
	_build()

func _process(delta: float) -> void:
	_time += delta
	# 断肢还有神经反射：轻微摆一下，不要像静止道具
	rotation = sin(_time * 2.2) * 0.07
	var pulse := 1.0 + sin(_time * 3.4) * 0.025
	scale = Vector2(pulse, 1.0 / pulse)

func _build() -> void:
	# 地面阴影：让拾取物贴地，不然悬浮时会像飘在空中
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0.010, 0.018, 0.016, 0.45)
	shadow.polygon = PackedVector2Array([
		Vector2(-11, 7), Vector2(10, 7), Vector2(7, 10), Vector2(-7, 10),
	])
	add_child(shadow)

	# 冷绿微光：和史莱姆死亡孢子同一色系
	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = _radial_texture()
	glow.modulate = Color(0.36, 0.95, 0.54, 0.20)
	glow.scale = Vector2(0.52, 0.38)
	glow.position = Vector2(0, 1)
	add_child(glow)

	# 主肢：不是矩形，而是一段被斩断后蜷起的软体手臂
	var flesh := Polygon2D.new()
	flesh.name = "Flesh"
	flesh.color = Color(0.24, 0.56, 0.30)
	flesh.polygon = PackedVector2Array([
		Vector2(-11, 1), Vector2(-9, -3), Vector2(-5, -6), Vector2(0, -7),
		Vector2(5, -5), Vector2(10, -2), Vector2(13, 1), Vector2(11, 4),
		Vector2(7, 6), Vector2(2, 7), Vector2(-3, 6), Vector2(-8, 5), Vector2(-12, 3),
	])
	add_child(flesh)

	# 背部受光面：偏亮的青绿，给软体一点体积
	var back_light := Polygon2D.new()
	back_light.name = "BackLight"
	back_light.color = Color(0.42, 0.76, 0.43, 0.55)
	back_light.polygon = PackedVector2Array([
		Vector2(-7, -3), Vector2(-3, -5), Vector2(2, -5), Vector2(6, -3),
		Vector2(4, -1), Vector2(0, 0), Vector2(-4, -1),
	])
	add_child(back_light)

	# 断口：左侧深色创面 + 外翻的浅色软组织
	var cut := Polygon2D.new()
	cut.name = "Cut"
	cut.color = Color(0.12, 0.26, 0.17)
	cut.polygon = PackedVector2Array([
		Vector2(-12, 0), Vector2(-9, -3), Vector2(-7, -1), Vector2(-8, 3), Vector2(-11, 4),
	])
	add_child(cut)
	var cut_rim := Line2D.new()
	cut_rim.name = "CutRim"
	cut_rim.width = 1.2
	cut_rim.default_color = Color(0.55, 0.78, 0.48, 0.8)
	cut_rim.points = PackedVector2Array([
		Vector2(-12, 0), Vector2(-9, -3), Vector2(-7, -1), Vector2(-8, 3), Vector2(-11, 4),
	])
	add_child(cut_rim)

	# 骨片：断口里戳出来的一截，浅骨色，和绿色胶质拉开对比
	var bone := Polygon2D.new()
	bone.name = "Bone"
	bone.color = Color(0.70, 0.72, 0.58)
	bone.polygon = PackedVector2Array([
		Vector2(-15, -3), Vector2(-11, -7), Vector2(-8, -5),
		Vector2(-9, -1), Vector2(-12, 0),
	])
	add_child(bone)
	var bone_line := Line2D.new()
	bone_line.width = 1.0
	bone_line.default_color = Color(0.44, 0.48, 0.39, 0.9)
	bone_line.points = PackedVector2Array([Vector2(-14, -3), Vector2(-10, -6), Vector2(-8, -5)])
	add_child(bone_line)

	# 三根蜷曲指节：右端不是平滑圆弧，而是一节节收起来的小爪
	for spec in [
		{"pos": Vector2(10, -3), "rot": -0.5, "len": 4.0},
		{"pos": Vector2(12, 0), "rot": 0.1, "len": 4.6},
		{"pos": Vector2(10, 3), "rot": 0.6, "len": 4.0},
	]:
		var finger := Polygon2D.new()
		finger.name = "Finger"
		finger.color = Color(0.18, 0.45, 0.25)
		finger.position = spec["pos"]
		finger.rotation = spec["rot"]
		var l: float = spec["len"]
		finger.polygon = PackedVector2Array([
			Vector2(0, -1.8), Vector2(l, -1.2), Vector2(l + 1.2, 0.2), Vector2(l, 1.4), Vector2(0, 1.6),
		])
		add_child(finger)
		var tip := Line2D.new()
		tip.width = 0.8
		tip.default_color = Color(0.62, 0.82, 0.54, 0.7)
		tip.position = spec["pos"]
		tip.rotation = spec["rot"]
		tip.points = PackedVector2Array([Vector2(0, -1.4), Vector2(l, -0.8)])
		add_child(tip)

	# 体液：滴在地上的两三点，不用太亮，作为"刚掉下来"的痕迹
	for p in [Vector2(-6, 8), Vector2(2, 9), Vector2(8, 7)]:
		var drop := Polygon2D.new()
		drop.name = "Ichor"
		drop.color = Color(0.30, 0.72, 0.36, 0.8)
		drop.polygon = _ellipse(p, Vector2(2.2, 1.6), 8)
		add_child(drop)

	# 表面斑点：避免整块纯色，空洞骑士式的小块面
	for p in [Vector2(2, 1), Vector2(5, 3), Vector2(-3, 2)]:
		var speck := Polygon2D.new()
		speck.color = Color(0.12, 0.34, 0.18, 0.85)
		speck.polygon = _ellipse(p, Vector2(1.8, 1.1), 6)
		add_child(speck)

func _ellipse(center: Vector2, radii: Vector2, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

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
