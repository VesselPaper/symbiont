extends Node2D
## 第一层 · 锈钟回廊（M2 关卡）
##
## 教学关之后的第一张正式地图。地形全部由本脚本按 PLATFORMS 数据生成，
## 改关卡形状只改下面那几张表，不用在编辑器里拖节点。
##
## 路线：入口平台 → 断口 → 下沉台阶 → 钟厅（吊钟/锁链/史莱姆）→ 上行台阶 → 祭坛厅
##       → 断桥 → 遗物廊 → 层门厅 → 层门
##
## 剧情五段各挂一个 Area2D 触发器，踩进去播对话，每个只播一次（靠 GameManager 旗标去重）：
##   钟厅 → floor1_bell    祭坛前 → floor1_altar    断桥 → floor1_bridge
##   遗物廊 → floor1_relic  层门前 → floor1_gate
## 进场景 0.6 秒后播 floor1_enter。
##
## 视觉：背景交给 Backdrop（components/abyss_backdrop.gd），地形是石块 + 顶部亮边，
## 吊钟、锁链、灯火都在 _build_props 里生成。

## 地形：x, 顶面 y, 宽, 厚（顶面是玩家站的那条线）
## M2-04 扩建：祭坛厅向右接断桥、遗物廊、层门厅，整体从 2900 拉到 4540。
## 断口保留 120px 间距，给跳跃留余地；平台之间不是等宽等高的方块，下面视觉会削成岩体。
const PLATFORMS: Array[Dictionary] = [
	{"rect": Rect2(0, 620, 620, 90), "stone": 0.0},        # 入口平台
	{"rect": Rect2(760, 680, 300, 90), "stone": 0.15},     # 断口对岸（低一级）
	{"rect": Rect2(1120, 760, 780, 130), "stone": 0.0},    # 钟厅地面
	{"rect": Rect2(1960, 720, 200, 90), "stone": 0.2},     # 上行台阶一
	{"rect": Rect2(2160, 660, 200, 90), "stone": 0.35},    # 上行台阶二
	{"rect": Rect2(2380, 600, 670, 120), "stone": 0.1},    # 祭坛厅（向右延伸接断桥）
	{"rect": Rect2(3170, 600, 140, 100), "stone": 0.3},    # 断桥对岸
	{"rect": Rect2(3430, 640, 260, 120), "stone": 0.0},    # 遗物廊（低一级）
	{"rect": Rect2(3810, 620, 180, 100), "stone": 0.2},    # 遗物廊出口
	{"rect": Rect2(4110, 600, 360, 110), "stone": 0.1},    # 层门厅
	{"rect": Rect2(-80, 300, 80, 900), "stone": 0.0},      # 左边界墙
	{"rect": Rect2(4540, 300, 80, 900), "stone": 0.0},     # 右边界墙
]

const SPAWN_POINT := Vector2(140, 560)
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
## 敌人离剧情触发器至少 260px：钟厅左右各一只，遗物廊出口一只。
## 对话时 dialogue.gd 还会把 enemy 分组整体冻结，双保险。
const SLIME_SPAWNS: Array[Vector2] = [
	Vector2(1240, 720), Vector2(2000, 706), Vector2(3900, 620)
]

## 摄像机参数与教学关一致：垂直视野 = 15 倍角色身高
const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

const INTRO_DELAY := 0.6
const INTRO_ID := "floor1_enter"
## 层门目前没有下一张地图：播完对话给一句占位提示，别让玩家以为卡死
const GATE_NOTICE := "第二层 · 还在建（M3 落地）"

const STONE_COLOR := Color(0.165, 0.190, 0.210)
const STONE_DARK := Color(0.075, 0.090, 0.105)
const STONE_RIM := Color(0.380, 0.470, 0.480)

@onready var _dialogue: Node = $Dialogue
@onready var _player: Node2D = $Player
@onready var _camera: Camera2D = $Camera2D

var _played: Dictionary = {}
var _toast: Label

func _ready() -> void:
	_build_platforms()
	_build_props()
	_build_triggers()
	_build_kill_zone()
	_spawn_enemies()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	var timer := get_tree().create_timer(INTRO_DELAY)
	timer.timeout.connect(_play_intro)

func _play_intro() -> void:
	_play_once("intro", INTRO_ID)

## 同一段剧情只播一次：旗标记在 GameManager，死了重进也不会重复念
func _play_once(key: String, dialogue_id: String) -> void:
	if _played.get(key, false):
		return
	_played[key] = true
	_dialogue.call("play", dialogue_id)

# ---------- 地形 ----------

func _build_platforms() -> void:
	var holder := Node2D.new()
	holder.name = "Terrain"
	# 地形压在背景之上、角色之下：Backdrop 根节点 z=-3，Props z=-1，角色 0
	holder.z_index = -2
	add_child(holder)
	for i in range(PLATFORMS.size()):
		var spec: Dictionary = PLATFORMS[i]
		var rect: Rect2 = spec["rect"]
		var body := StaticBody2D.new()
		body.name = "Plat%02d" % i
		body.position = rect.position + rect.size * 0.5
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		col.shape = shape
		body.add_child(col)
		var visual := Polygon2D.new()
		visual.name = "Visual"
		# 顶面保持一条能站人的直线，侧面和底部削成不规则岩体；
		# 边界墙（宽 80）仍用矩形，避免墙体露缝。
		if rect.size.x > 100.0:
			visual.polygon = _rock_silhouette(rect, i)
		else:
			visual.polygon = PackedVector2Array([
				Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
				Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
				Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
				Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
			])
		# 每块石头颜色略有差别，避免一整片死板的灰
		visual.color = STONE_COLOR.lightened(float(spec["stone"]) * 0.25)
		body.add_child(visual)
		# 顶面亮边：光从上面来，玩家一眼能看出哪儿能站
		var rim := Polygon2D.new()
		rim.name = "Rim"
		var rim_h := 5.0
		rim.polygon = PackedVector2Array([
			Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, -rect.size.y * 0.5 + rim_h),
			Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5 + rim_h),
		])
		rim.color = STONE_RIM
		body.add_child(rim)
		# 底部压暗，让石块有厚度
		var shade := Polygon2D.new()
		shade.name = "Shade"
		var shade_h := minf(18.0, rect.size.y * 0.25)
		shade.polygon = PackedVector2Array([
			Vector2(-rect.size.x * 0.5, rect.size.y * 0.5 - shade_h),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5 - shade_h),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
			Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
		])
		shade.color = STONE_DARK
		body.add_child(shade)
		# 石缝 / 苔痕 / 碎石：只在能站的大平台上加，边界墙不用
		if rect.size.x >= 120.0:
			_add_platform_detail(body, rect, i)
		holder.add_child(body)

## 平台侧面/底部的岩体轮廓：顶点都在碰撞矩形外或贴边，顶面两个点与碰撞顶线重合。
## 不用随机数，按平台序号错开缺口，保证每局长得一样，也方便截图对比。
func _rock_silhouette(rect: Rect2, index: int) -> PackedVector2Array:
	var half := rect.size.x * 0.5
	var h := rect.size.y
	var top := -h * 0.5
	var bottom := h * 0.5
	var notch := 4.0 + float(index % 3) * 4.0
	var bulge := 3.0 + float(index % 2) * 5.0
	return PackedVector2Array([
		Vector2(-half, top),
		Vector2(half, top),
		Vector2(half - 1.0, top + 9.0),
		Vector2(half + bulge, top + 26.0),
		Vector2(half - notch, top + 50.0),
		Vector2(half - 2.0, top + 68.0),
		Vector2(half - 16.0, bottom - 8.0),
		Vector2(half - 32.0, bottom + 5.0),
		Vector2(8.0, bottom + 9.0),
		Vector2(-half + 30.0, bottom + 3.0),
		Vector2(-half + 7.0, bottom - 16.0),
		Vector2(-half - bulge, top + 58.0),
		Vector2(-half + notch, top + 24.0),
	])

## 平台表面装饰：竖向石缝 + 顶角苔痕 + 碎石 + 底部支撑岩块。
## 都是纯装饰，不参与碰撞，也不影响 PLATFORMS 数据。
func _add_platform_detail(body: StaticBody2D, rect: Rect2, variant: int) -> void:
	var top := -rect.size.y * 0.5
	var bottom := rect.size.y * 0.5
	var half_w := rect.size.x * 0.5
	var seam_color := Color(0.040, 0.052, 0.062, 0.55)
	var x := 70.0
	# 缝间距按平台长度自适应，短平台少几道，长平台多几道
	var step := maxf(80.0, rect.size.x / 6.0)
	while x < rect.size.x - 50.0:
		var seam := Line2D.new()
		seam.width = 1.4
		seam.default_color = seam_color
		seam.points = PackedVector2Array([
			Vector2(-half_w + x, top + 7.0),
			Vector2(-half_w + x + 4.0, top + 20.0),
		])
		body.add_child(seam)
		x += step
	# 顶角苔痕：一小撮偏绿的暗色，别让石头全是蓝灰
	for sx in [-half_w + 10.0, half_w - 26.0]:
		var moss := Polygon2D.new()
		moss.color = Color(0.085, 0.125, 0.105, 0.6)
		moss.polygon = PackedVector2Array([
			Vector2(sx, top + 5.0), Vector2(sx + 22.0, top + 5.0),
			Vector2(sx + 16.0, top + 12.0), Vector2(sx + 4.0, top + 14.0),
		])
		body.add_child(moss)
	# 底部支撑岩块：不是一整条平滑底边，隔一段垂一块，像从岩壁上凿出来的路
	for k in range(2):
		var sx := -half_w + rect.size.x * (0.18 + 0.36 * k) + float(variant % 3) * 5.0
		var support := Polygon2D.new()
		support.color = STONE_DARK.lightened(0.04 + 0.02 * k)
		support.polygon = PackedVector2Array([
			Vector2(sx, top + 42.0), Vector2(sx + 38.0, top + 50.0),
			Vector2(sx + 30.0, bottom + 16.0), Vector2(sx + 4.0, bottom + 8.0),
		])
		body.add_child(support)
	# 长裂缝：从顶面往下斜着裂，打断"一整块石头"的平板感
	var crack := Line2D.new()
	crack.width = 1.1
	crack.default_color = Color(0.020, 0.028, 0.034, 0.65)
	crack.points = PackedVector2Array([
		Vector2(-half_w + 30.0 + variant * 9.0, top + 8.0),
		Vector2(-half_w + 42.0 + variant * 9.0, top + 26.0),
		Vector2(-half_w + 38.0 + variant * 9.0, top + 46.0),
	])
	body.add_child(crack)

	# 碎石：贴着顶面几块大小不一的石头，破掉完美的直线
	for i in range(2):
		var r := Polygon2D.new()
		r.color = STONE_RIM.darkened(0.28)
		var rx := -half_w + rect.size.x * (0.32 + 0.28 * i)
		var rw := 10.0 + 5.0 * i
		r.polygon = PackedVector2Array([
			Vector2(rx, top + 1.0), Vector2(rx + rw, top - 3.0),
			Vector2(rx + rw + 6.0, top + 4.0), Vector2(rx + 3.0, top + 5.0),
		])
		body.add_child(r)

# ---------- 场景物件 ----------

func _build_props() -> void:
	var props := Node2D.new()
	props.name = "Props"
	# 物件在角色之后、地形之前：吊钟和门框不会挡住玩家
	props.z_index = -1
	add_child(props)
	_build_entry_props(props)

	# 吊钟：钟厅的视觉中心。钟要挂到镜头（地面探索时视野约 y 396~816）里，
	# 所以钟底离地 40 多像素，玩家正好从钟下走过。
	var bell := Node2D.new()
	bell.name = "Bell"
	bell.position = Vector2(1600, 620)
	props.add_child(bell)

	var bell_body := Polygon2D.new()
	bell_body.color = Color(0.045, 0.055, 0.065)
	bell_body.polygon = PackedVector2Array([
		Vector2(-46, -150), Vector2(46, -150),
		Vector2(74, 40), Vector2(60, 96),
		Vector2(-60, 96), Vector2(-74, 40),
	])
	bell.add_child(bell_body)

	var bell_rim := Polygon2D.new()
	bell_rim.color = Color(0.150, 0.180, 0.190)
	bell_rim.polygon = PackedVector2Array([
		Vector2(-60, 84), Vector2(60, 84), Vector2(64, 100), Vector2(-64, 100),
	])
	bell.add_child(bell_rim)

	var bell_highlight := Line2D.new()
	bell_highlight.width = 3.0
	bell_highlight.default_color = Color(0.36, 0.46, 0.48, 0.9)
	bell_highlight.points = PackedVector2Array([Vector2(-38, -140), Vector2(-52, 10), Vector2(-48, 78)])
	bell.add_child(bell_highlight)

	# 挂钟的横梁与锁链（横梁和链子都在镜头里，别挂到画面外）
	for x in [1500.0, 1600.0, 1700.0]:
		var chain := Line2D.new()
		chain.width = 4.0
		chain.default_color = Color(0.075, 0.085, 0.095)
		chain.points = PackedVector2Array([
			Vector2(x, 342.0), Vector2(x + 6.0, 420.0), Vector2(x, 470.0 if x == 1600.0 else 560.0)
		])
		props.add_child(chain)

	var beam := Polygon2D.new()
	beam.color = Color(0.070, 0.082, 0.092)
	beam.polygon = PackedVector2Array([
		Vector2(1430, 352), Vector2(1770, 352), Vector2(1770, 382), Vector2(1430, 382),
	])
	props.add_child(beam)

	# 灯火：祭坛暖光、钟厅冷光。没有贴图，用径向渐变纹理当光晕
	_add_light(props, Vector2(2600, 520), Color(1.0, 0.78, 0.52), 0.85, 2.6)
	_add_light(props, Vector2(1600, 560), Color(0.45, 0.78, 0.82), 0.5, 2.6)
	_add_light(props, Vector2(420, 585), Color(1.0, 0.70, 0.44), 0.35, 1.6)

	# 钟厅残旗：给冷灰的钟厅加一点暗紫布色，风一吹能看出这是"有人住过的地方"
	var banner := Polygon2D.new()
	banner.color = Color(0.150, 0.095, 0.170, 0.9)
	banner.polygon = PackedVector2Array([
		Vector2(1452, 372), Vector2(1502, 384), Vector2(1508, 560),
		Vector2(1492, 544), Vector2(1478, 582), Vector2(1462, 538), Vector2(1446, 566),
	])
	props.add_child(banner)
	var banner_rim := Line2D.new()
	banner_rim.width = 1.5
	banner_rim.default_color = Color(0.30, 0.20, 0.34, 0.7)
	banner_rim.points = PackedVector2Array([Vector2(1452, 372), Vector2(1502, 384)])
	props.add_child(banner_rim)

	# 扩建区：断桥、遗物廊、层门厅的物件；都在 Props 层，不挡玩家也不参与碰撞
	_build_ruin_props(props)
	_add_light(props, Vector2(3550, 585), Color(1.0, 0.72, 0.44), 0.42, 2.0)
	_add_light(props, Vector2(4320, 545), Color(0.58, 0.86, 0.92), 0.55, 2.4)

	# 层门：两根柱子 + 门楣 + 一条冷光缝。扩建后门移到地图最右的层门厅。
	var gate := Node2D.new()
	gate.name = "GateFrame"
	gate.position = Vector2(4390, 600)
	props.add_child(gate)
	for dx in [-58.0, 58.0]:
		var post := Polygon2D.new()
		post.color = Color(0.095, 0.110, 0.125)
		post.polygon = PackedVector2Array([
			Vector2(dx - 16, -185), Vector2(dx + 16, -185), Vector2(dx + 16, 0), Vector2(dx - 16, 0),
		])
		gate.add_child(post)
	var lintel := Polygon2D.new()
	lintel.color = Color(0.105, 0.122, 0.138)
	lintel.polygon = PackedVector2Array([
		Vector2(-84, -205), Vector2(84, -205), Vector2(84, -175), Vector2(-84, -175),
	])
	gate.add_child(lintel)
	var seam := Line2D.new()
	seam.width = 6.0
	seam.default_color = Color(0.42, 0.72, 0.76, 0.55)
	seam.points = PackedVector2Array([Vector2(0, -173), Vector2(0, -6)])
	gate.add_child(seam)

## 扩建区物件：断桥的垂绳/塌板、遗物廊的壁龛与石棺、层门厅的立柱。
## 全部是背景层装饰，玩家脚下仍只认 PLATFORMS 的矩形碰撞。
func _build_ruin_props(parent: Node) -> void:
	# 四个 120px 断口各挂两组断绳和几块垂板，让"这里过不去"一眼能看出来
	for spec in [
		{"x1": 3050.0, "x2": 3170.0, "y": 600.0},
		{"x1": 3310.0, "x2": 3430.0, "y": 600.0},
		{"x1": 3690.0, "x2": 3810.0, "y": 640.0},
		{"x1": 3990.0, "x2": 4110.0, "y": 620.0},
	]:
		var x1: float = spec["x1"]
		var x2: float = spec["x2"]
		var y: float = spec["y"]
		for side_x in [x1 + 6.0, x2 - 6.0]:
			var rope := Line2D.new()
			rope.width = 2.2
			rope.default_color = Color(0.16, 0.18, 0.16, 0.9)
			var dir := 1.0 if side_x < (x1 + x2) * 0.5 else -1.0
			rope.points = PackedVector2Array([
				Vector2(side_x, y - 6.0),
				Vector2(side_x + dir * 18.0, y + 26.0),
				Vector2(side_x + dir * 8.0, y + 70.0),
			])
			parent.add_child(rope)
		# 断板：斜插在断口里，不横跨整个缺口，避免看起来像能走
		for i in range(2):
			var plank := Polygon2D.new()
			plank.color = Color(0.12, 0.13, 0.12, 0.95)
			var px := x1 + 42.0 + i * 34.0
			plank.position = Vector2(px, y + 24.0 + i * 18.0)
			plank.rotation = -0.45 + i * 0.7
			plank.polygon = PackedVector2Array([
				Vector2(-16, -3), Vector2(16, -3), Vector2(16, 3), Vector2(-16, 3),
			])
			parent.add_child(plank)
			var edge := Line2D.new()
			edge.width = 1.0
			edge.default_color = Color(0.34, 0.34, 0.28, 0.55)
			edge.position = plank.position
			edge.rotation = plank.rotation
			edge.points = PackedVector2Array([Vector2(-15, -2), Vector2(15, -2)])
			parent.add_child(edge)
		# 断口底部淡紫雾，提示下面是空的
		var mist := Polygon2D.new()
		mist.color = Color(0.16, 0.12, 0.20, 0.10)
		mist.polygon = _ellipse(Vector2((x1 + x2) * 0.5, y + 70.0), Vector2(52.0, 18.0), 20)
		parent.add_child(mist)

	# 遗物廊：三座壁龛，中间放石棺；暗示这里曾经是收殓尸骨的地方
	var shrine_base := 640.0
	for i in range(3):
		var x := 3470.0 + i * 78.0
		for dx in [0.0, 50.0]:
			var col := Polygon2D.new()
			col.color = Color(0.085, 0.10, 0.11)
			col.polygon = PackedVector2Array([
				Vector2(x + dx, shrine_base), Vector2(x + dx, shrine_base - 128),
				Vector2(x + dx + 12, shrine_base - 128), Vector2(x + dx + 12, shrine_base),
			])
			parent.add_child(col)
		var arch := Polygon2D.new()
		arch.color = Color(0.10, 0.12, 0.13)
		var pts := PackedVector2Array()
		var cx := x + 31.0
		var r := 31.0
		for k in range(13):
			var a := PI * (1.0 - float(k) / 12.0)
			pts.append(Vector2(cx + cos(a) * r, shrine_base - 128 - sin(a) * r))
		for k in range(13):
			var a := PI * (1.0 - float(k) / 12.0)
			pts.append(Vector2(cx + cos(a) * (r - 9.0), shrine_base - 128 - sin(a) * (r - 9.0)))
		arch.polygon = pts
		parent.add_child(arch)
		# 龛里的骨堆/小罐
		var urn := Polygon2D.new()
		urn.color = Color(0.24, 0.26, 0.23)
		urn.polygon = PackedVector2Array([
			Vector2(cx - 10, shrine_base - 8), Vector2(cx - 7, shrine_base - 26),
			Vector2(cx + 7, shrine_base - 26), Vector2(cx + 10, shrine_base - 8),
		])
		parent.add_child(urn)
		for b in range(3):
			var bone := Line2D.new()
			bone.width = 1.6
			bone.default_color = Color(0.52, 0.52, 0.44, 0.65)
			bone.points = PackedVector2Array([
				Vector2(cx - 8 + b * 6, shrine_base - 5),
				Vector2(cx - 4 + b * 6, shrine_base - 12 - b * 2),
			])
			parent.add_child(bone)

	# 中间石棺：遗物廊的视觉中心，盖板斜着滑开，露出一点内里
	var casket := Polygon2D.new()
	casket.color = Color(0.12, 0.14, 0.15)
	casket.polygon = PackedVector2Array([
		Vector2(3535, 640), Vector2(3535, 600), Vector2(3605, 600),
		Vector2(3605, 640), Vector2(3596, 648), Vector2(3544, 648),
	])
	parent.add_child(casket)
	var lid := Polygon2D.new()
	lid.color = Color(0.20, 0.22, 0.22)
	lid.position = Vector2(3568, 590)
	lid.rotation = -0.13
	lid.polygon = PackedVector2Array([
		Vector2(-36, -5), Vector2(36, -7), Vector2(38, 3), Vector2(-34, 5),
	])
	parent.add_child(lid)
	var casket_line := Line2D.new()
	casket_line.width = 1.2
	casket_line.default_color = Color(0.36, 0.39, 0.36, 0.8)
	casket_line.points = PackedVector2Array([Vector2(3539, 607), Vector2(3601, 607)])
	parent.add_child(casket_line)

	# 层门厅：门两侧各一根断柱，柱头挂一盏冷灯，和地图尽头的门呼应
	for dx in [-120.0, 140.0]:
		var pillar := Polygon2D.new()
		pillar.color = Color(0.075, 0.09, 0.10)
		var px: float = 4390.0 + float(dx)
		pillar.polygon = PackedVector2Array([
			Vector2(px - 18, 600), Vector2(px - 18, 390), Vector2(px - 8, 366),
			Vector2(px + 8, 370), Vector2(px + 18, 394), Vector2(px + 18, 600),
		])
		parent.add_child(pillar)
	var chain := Line2D.new()
	chain.width = 2.0
	chain.default_color = Color(0.11, 0.12, 0.13)
	chain.points = PackedVector2Array([Vector2(4390, 270), Vector2(4384, 360), Vector2(4390, 420)])
	parent.add_child(chain)
	var censer := Polygon2D.new()
	censer.color = Color(0.24, 0.28, 0.27)
	censer.polygon = PackedVector2Array([
		Vector2(4376, 420), Vector2(4404, 420), Vector2(4400, 436), Vector2(4380, 436),
	])
	parent.add_child(censer)


## 入口区装饰：头顶断链、一盏挂灯、脚边碎石。
## 这一片是玩家开局唯一看得到的画面，必须有东西可看，不能只有一块灰平台。
func _build_entry_props(parent: Node) -> void:
	for spec in [
		{"x": 236.0, "end_y": 470.0, "width": 2.6},
		{"x": 560.0, "end_y": 372.0, "width": 1.7},
	]:
		var chain := Line2D.new()
		chain.width = spec["width"]
		chain.default_color = Color(0.060, 0.070, 0.080)
		chain.points = PackedVector2Array([
			Vector2(spec["x"], -200.0),
			Vector2(spec["x"] + 10.0, 140.0),
			Vector2(spec["x"] + 2.0, spec["end_y"]),
		])
		parent.add_child(chain)

	# 挂灯：入口唯一的暖色点。灯罩用梯形剪影，里面一块暖玻璃，再加一圈光晕
	var lantern := Node2D.new()
	lantern.name = "EntryLantern"
	lantern.position = Vector2(238.0, 470.0)
	parent.add_child(lantern)
	# PointLight2D 只照亮别的面，自己不会发光；这里额外贴一张径向渐变当可见光晕
	var halo := Sprite2D.new()
	halo.texture = _radial_texture()
	halo.modulate = Color(1.0, 0.66, 0.34, 0.38)
	halo.scale = Vector2(0.35, 0.35)
	halo.position = Vector2(0, 18)
	lantern.add_child(halo)
	var outer_halo := Sprite2D.new()
	outer_halo.texture = _radial_texture()
	outer_halo.modulate = Color(1.0, 0.60, 0.30, 0.08)
	outer_halo.scale = Vector2(0.9, 0.9)
	outer_halo.position = Vector2(0, 18)
	lantern.add_child(outer_halo)
	var cap := Polygon2D.new()
	cap.color = Color(0.095, 0.108, 0.118)
	cap.polygon = PackedVector2Array([
		Vector2(-13, 0), Vector2(13, 0), Vector2(9, 6), Vector2(-9, 6),
	])
	lantern.add_child(cap)
	var glass := Polygon2D.new()
	glass.color = Color(0.92, 0.68, 0.38, 0.9)
	glass.polygon = PackedVector2Array([
		Vector2(-7, 5), Vector2(7, 5), Vector2(10, 26), Vector2(-10, 26),
	])
	lantern.add_child(glass)
	var cage := Polygon2D.new()
	cage.color = Color(0.075, 0.085, 0.095)
	cage.polygon = PackedVector2Array([
		Vector2(-12, 24), Vector2(12, 24), Vector2(11, 31), Vector2(-11, 31),
	])
	lantern.add_child(cage)
	_add_light(lantern, Vector2(0, 18), Color(1.0, 0.72, 0.42), 0.55, 1.25)

	# 脚边碎石：入口平台顶面几块暗石，让站脚的地方不那么干净
	for i in range(3):
		var rock := Polygon2D.new()
		rock.color = STONE_DARK.lightened(0.08 + 0.04 * i)
		var rx := 470.0 + 42.0 * i
		rock.polygon = PackedVector2Array([
			Vector2(rx, 620.0), Vector2(rx + 7.0, 611.0 + 2.0 * i),
			Vector2(rx + 16.0, 615.0), Vector2(rx + 20.0, 620.0),
		])
		parent.add_child(rock)

func _add_light(parent: Node, pos: Vector2, color: Color, energy: float, light_scale: float) -> void:
	var light := PointLight2D.new()
	light.position = pos
	light.color = color
	light.energy = energy
	light.texture_scale = light_scale
	light.texture = _radial_texture()
	parent.add_child(light)

func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

func _ellipse(center: Vector2, radii: Vector2, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

# ---------- 触发器 ----------

func _build_triggers() -> void:
	var holder := Node2D.new()
	holder.name = "Triggers"
	add_child(holder)
	_add_trigger(holder, "BellTrigger", Rect2(1490, 600, 240, 180), "bell", "floor1_bell")
	_add_trigger(holder, "AltarTrigger", Rect2(2470, 470, 250, 160), "altar", "floor1_altar")
	_add_trigger(holder, "BridgeTrigger", Rect2(3000, 470, 160, 210), "bridge", "floor1_bridge")
	_add_trigger(holder, "RelicTrigger", Rect2(3450, 490, 220, 230), "relic", "floor1_relic")
	_add_trigger(holder, "GateTrigger", Rect2(4300, 390, 150, 230), "gate", "floor1_gate")

func _add_trigger(parent: Node, node_name: String, rect: Rect2, key: String, dialogue_id: String) -> void:
	var area := Area2D.new()
	area.name = node_name
	area.collision_layer = 0
	area.collision_mask = 2  # 只认玩家（player.tscn 的 collision_layer = 2）
	area.position = rect.position + rect.size * 0.5
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		_play_once(key, dialogue_id)
		if key == "gate":
			_show_gate_notice()
	)
	parent.add_child(area)

func _build_kill_zone() -> void:
	# 掉出地图底部就按重伤处理，玩家自己会回出生点（见 player.gd _respawn）
	var area := Area2D.new()
	area.name = "KillZone"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(2300, 1240)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4800, 200)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player"):
			body.call("take_damage", 99)
	)
	add_child(area)

func _spawn_enemies() -> void:
	var holder := Node2D.new()
	holder.name = "Enemies"
	add_child(holder)
	for i in range(SLIME_SPAWNS.size()):
		var slime := SLIME_SCENE.instantiate()
		slime.position = SLIME_SPAWNS[i]
		slime.name = "Slime%d" % (i + 1)
		holder.add_child(slime)

# ---------- 提示 ----------

func _show_gate_notice() -> void:
	if _toast != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "Notice"
	layer.layer = 3
	add_child(layer)
	_toast = Label.new()
	_toast.text = GATE_NOTICE
	_toast.modulate = Color(0.72, 0.84, 0.86, 0.0)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 20)
	layer.add_child(_toast)
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 0.95, 0.5)
	tween.tween_interval(2.5)
	tween.tween_property(_toast, "modulate:a", 0.0, 1.2)



