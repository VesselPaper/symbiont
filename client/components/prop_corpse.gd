extends Node2D
## 教学关的尸体（M4-21 建模）。
##
## 组长反馈：原来只是「一个黄色矩形」（场景里 Body 是 52×10 的灰条、Head 是 10×10 的方块，
## 美术又把它染成土黄，横在地上像一块砖）。这一版按空洞骑士那种剪影风格重画：
## 斗篷盖住大半身子、露出头骨和几根肋骨、一只手臂朝着铁剑伸出去，身体底下压一道暗影。
##
## 全部用 Polygon2D / Line2D 拼，不依赖贴图（项目里没有尸体素材）。
## 朝向固定：头在左、脚在右、手臂朝向右侧的剑（剑在 x+65 处）。
## 原场景里的 Body/Head 两个占位节点在 _ready 里隐藏，避免和新模型重叠。

## 地面线：尸体躺在平台顶面上，节点原点在身体中线，所以地面在 +4
const GROUND_Y := 4.0

const COLOR_SHADOW := Color(0.05, 0.06, 0.07, 0.45)
const COLOR_CLOAK := Color(0.17, 0.18, 0.21, 1.0)
const COLOR_CLOAK_DARK := Color(0.10, 0.11, 0.13, 1.0)
const COLOR_BONE := Color(0.58, 0.56, 0.50, 1.0)
const COLOR_BONE_DIM := Color(0.34, 0.33, 0.31, 1.0)
const COLOR_LEATHER := Color(0.12, 0.13, 0.15, 1.0)

func _ready() -> void:
	# 占位方块不再显示（老场景里的 Body/Head）
	for name in ["Body", "Head"]:
		var placeholder := get_node_or_null(name) as Node2D
		if placeholder != null:
			placeholder.visible = false
	_build_shadow()
	_build_legs()
	_build_cloak()
	_build_ribs()
	_build_arm()
	_build_skull()

## 身体底下的一道暗影：让尸体“压在地上”，不是浮着
func _build_shadow() -> void:
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = COLOR_SHADOW
	var pts := PackedVector2Array()
	var cx := 4.0
	var rx := 46.0
	var ry := 5.0
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cx + cos(a) * rx, GROUND_Y + 2.0 + sin(a) * ry * 0.5))
	shadow.polygon = pts
	shadow.z_index = -1
	add_child(shadow)

## 两条腿：一条伸直、一条蜷起，末端是磨破的靴子
func _build_legs() -> void:
	# 伸直的那条：从腰（+14）拉到脚（+42）
	var leg := Polygon2D.new()
	leg.name = "LegOut"
	leg.color = COLOR_CLOAK_DARK
	leg.polygon = PackedVector2Array([
		Vector2(12, -4), Vector2(38, 0), Vector2(44, 3),
		Vector2(43, 6), Vector2(36, 5), Vector2(12, 2),
	])
	add_child(leg)
	# 蜷起的那条：膝盖顶起来一块，在斗篷下沿露出
	var knee := Polygon2D.new()
	knee.name = "LegBent"
	knee.color = COLOR_LEATHER
	knee.polygon = PackedVector2Array([
		Vector2(8, 2), Vector2(16, -9), Vector2(24, -6),
		Vector2(26, 0), Vector2(20, 5), Vector2(10, 5),
	])
	add_child(knee)
	# 靴子：脚掌一小段，横在地上
	var boot := Polygon2D.new()
	boot.name = "Boot"
	boot.color = COLOR_LEATHER
	boot.polygon = PackedVector2Array([
		Vector2(40, -1), Vector2(50, 0), Vector2(51, 4), Vector2(40, 4),
	])
	add_child(boot)
	var boot_rim := Line2D.new()
	boot_rim.width = 1.0
	boot_rim.default_color = Color(0.24, 0.25, 0.27, 0.8)
	boot_rim.points = PackedVector2Array([Vector2(41, 0.5), Vector2(50, 1.5)])
	add_child(boot_rim)

## 斗篷：盖住躯干的一大块，边缘有折口，不是一块直板
func _build_cloak() -> void:
	var cloak := Polygon2D.new()
	cloak.name = "Cloak"
	cloak.color = COLOR_CLOAK
	cloak.polygon = PackedVector2Array([
		Vector2(-32, 3), Vector2(-34, -3), Vector2(-28, -10),
		Vector2(-16, -14), Vector2(-2, -13), Vector2(10, -8),
		Vector2(18, -2), Vector2(18, 3), Vector2(6, 5),
		Vector2(-12, 5), Vector2(-24, 5),
	])
	add_child(cloak)
	# 折口：两道深色线，暗示布褶
	for i in range(2):
		var fold := Line2D.new()
		fold.width = 1.0
		fold.default_color = Color(0.09, 0.10, 0.12, 0.85)
		var x0 := -22.0 + i * 14.0
		fold.points = PackedVector2Array([
			Vector2(x0, -9.0 + i * 1.5), Vector2(x0 + 4.0, -2.0), Vector2(x0 + 2.0, 4.0),
		])
		add_child(fold)
	# 斗篷被撕开的口子：露出肋骨的位置，边缘用暗色勾一下
	var tear := Polygon2D.new()
	tear.name = "Tear"
	tear.color = Color(0.06, 0.07, 0.08, 0.9)
	tear.polygon = PackedVector2Array([
		Vector2(-6, -11), Vector2(9, -7), Vector2(7, -1), Vector2(-7, -4),
	])
	add_child(tear)

## 肋骨：撕口里露出的三根弯骨
func _build_ribs() -> void:
	for i in range(3):
		var rib := Line2D.new()
		rib.width = 1.4
		rib.default_color = COLOR_BONE_DIM
		var y0 := -9.0 + float(i) * 2.4
		rib.points = PackedVector2Array([
			Vector2(-5.0, y0), Vector2(1.0, y0 - 1.2), Vector2(7.0, y0 + 0.4),
		])
		add_child(rib)

## 手臂：从斗篷里伸出来，朝右侧的铁剑伸过去（差一点点够不到）
func _build_arm() -> void:
	var arm := Line2D.new()
	arm.name = "Arm"
	arm.width = 2.6
	arm.default_color = COLOR_BONE
	arm.points = PackedVector2Array([
		Vector2(-6, -6), Vector2(12, -1), Vector2(26, 1), Vector2(34, 2),
	])
	add_child(arm)
	# 手：三根指骨张开，指着剑
	for i in range(3):
		var finger := Line2D.new()
		finger.width = 1.4
		finger.default_color = COLOR_BONE
		var spread := (float(i) - 1.0) * 2.2
		finger.points = PackedVector2Array([
			Vector2(34, 2), Vector2(40, 2 + spread), Vector2(43, 3 + spread),
		])
		add_child(finger)
	# 袖子：手臂根部盖一小块布
	var sleeve := Polygon2D.new()
	sleeve.name = "Sleeve"
	sleeve.color = COLOR_CLOAK
	sleeve.polygon = PackedVector2Array([
		Vector2(-10, -9), Vector2(-2, -8), Vector2(0, -3), Vector2(-9, -3),
	])
	add_child(sleeve)

## 头骨：圆的、眼窝两个洞、下颌一条线，微微侧向地面
func _build_skull() -> void:
	var skull := Polygon2D.new()
	skull.name = "Skull"
	skull.color = COLOR_BONE
	var pts := PackedVector2Array()
	var cx := -38.0
	var cy := -4.0
	var r := 9.0
	for i in range(14):
		var a := TAU * float(i) / 14.0
		# 稍微压扁、偏侧躺：纵向半径 0.85
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r * 0.85))
	skull.polygon = pts
	add_child(skull)
	# 眼窝：两个小暗洞，位置偏右（朝剑那边）
	for dy in [-1.8, 2.4]:
		var socket := Polygon2D.new()
		socket.color = Color(0.07, 0.08, 0.09, 1)
		socket.polygon = PackedVector2Array([
			Vector2(-35.5, cy + dy - 1.4), Vector2(-33.0, cy + dy - 1.0),
			Vector2(-33.2, cy + dy + 1.2), Vector2(-35.6, cy + dy + 1.0),
		])
		add_child(socket)
	# 下颌：一条暗线，把颅骨和地面之间留出一点缝
	var jaw := Line2D.new()
	jaw.width = 1.0
	jaw.default_color = COLOR_BONE_DIM
	jaw.points = PackedVector2Array([Vector2(-44, 1.5), Vector2(-36, 3.0), Vector2(-31, 2.0)])
	add_child(jaw)
	# 头发/兜帽残片：压在颅骨后侧一小块暗色
	var hood := Polygon2D.new()
	hood.name = "Hood"
	hood.color = COLOR_CLOAK_DARK
	hood.polygon = PackedVector2Array([
		Vector2(-48, -10), Vector2(-42, -12), Vector2(-36, -9),
		Vector2(-38, -2), Vector2(-46, -1),
	])
	add_child(hood)
