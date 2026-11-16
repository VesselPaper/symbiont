extends Node2D
## 第一层 · 锈钟回廊（M2 关卡）
##
## 教学关之后的第一张正式地图。地形全部由本脚本按 PLATFORMS 数据生成，
## 改关卡形状只改下面那几张表，不用在编辑器里拖节点。
##
## 路线：入口平台 → 断口 → 下沉台阶 → 钟厅（断绳旁白 → 守钟人 → 吊钟 → 骨门墙）
##       → 上行台阶 → 祭坛厅 → 断桥 → 遗物廊 → 层门厅 → 层门
##
## 剧情五段各挂一个 Area2D 触发器，踩进去播对话，每个只播一次（靠 GameManager 旗标去重）：
##   钟厅 → floor1_bell    祭坛前 → floor1_altar    断桥 → floor1_bridge
##   遗物廊 → floor1_relic  层门前 → floor1_gate
## 进场景 0.6 秒后播 floor1_enter。
##
## 视觉：背景交给 Backdrop（components/abyss_backdrop.gd），地形是石块 + 顶部亮边，
## 吊钟、锁链、灯火都在 _build_props 里生成。

## 钟厅布局（M4-18）。
##
## 旧版的问题是所有东西挤在 440px 里：走进钟厅就同时看见守钟人和钟，
## 旁白还没念完人已经撞到跟前，拉完绳一步就到墙。现在的顺序和间距：
##
##   断口对岸 → 钟厅入口 → 断绳旁白 → 守钟人 → 钟（人走到钟下拉绳）→ 骨门墙 → 台阶
##     |______________ 1640 ______________|
##
## 守钟人站在钟的左边（x 比钟小），玩家先遇到人、听完规矩再走到钟下；
## 骨门就是钟厅右边那面墙，拉响钟才开。
const BELL_HALL_LEFT := 1120.0
const BELL_HALL_WIDTH := 1640.0             # 旧版 780，一次加长 860
const BELL_HALL_FLOOR_Y := 760.0
## 钟厅之后每一块地都跟着右移这么多；层门、相机右限幅也一起走
const HALL_SHIFT := BELL_HALL_WIDTH - 780.0
const BELL_X := 2250.0                      # 吊钟中心，玩家站在这底下拉绳
const WATCHMAN_X := 1950.0                  # 守钟人，钟左边 300px
## 骨门（组长说的“右边的墙”）：钟厅内的右墙，站在钟下拉绳时它就在画面右半边，
## 门一落地就能看见；再往右压到 2500 就会贴住钟龛，往右挪到 2620 铃响时又被推出画面。
const BONE_GATE_X := 2580.0                 # 骨门（右边的墙），钟右边 330px
const MAP_LEFT := -80.0                     # 左边界墙外沿
const MAP_RIGHT := 5300.0 + HALL_SHIFT      # 右边界墙 x，相机右限幅同值

## 地形：x, 顶面 y, 宽, 厚（顶面是玩家站的那条线）
## M2-04 扩建：祭坛厅向右接断桥、遗物廊、层门厅，整体从 2900 拉到 4540。
## M4-08 又往右拉到 5300；M4-18 把钟厅加长 860，整段跟着右移到 6160。
## 断口保留 120px 间距，给跳跃留余地；平台之间不是等宽等高的方块，下面视觉会削成岩体。
const PLATFORMS: Array[Dictionary] = [
	{"rect": Rect2(0, 620, 620, 90), "stone": 0.0},        # 入口平台
	{"rect": Rect2(760, 680, 300, 90), "stone": 0.15},     # 断口对岸（低一级）
	{"rect": Rect2(BELL_HALL_LEFT, BELL_HALL_FLOOR_Y, BELL_HALL_WIDTH, 130), "stone": 0.0},  # 钟厅地面
	{"rect": Rect2(1960 + HALL_SHIFT, 720, 200, 90), "stone": 0.2},     # 上行台阶一
	{"rect": Rect2(2160 + HALL_SHIFT, 660, 200, 90), "stone": 0.35},    # 上行台阶二
	{"rect": Rect2(2380 + HALL_SHIFT, 600, 670, 120), "stone": 0.1},    # 祭坛厅（向右延伸接断桥）
	{"rect": Rect2(3170 + HALL_SHIFT, 600, 140, 100), "stone": 0.3},    # 断桥对岸
	{"rect": Rect2(3430 + HALL_SHIFT, 640, 260, 120), "stone": 0.0},    # 遗物廊（低一级）
	{"rect": Rect2(3810 + HALL_SHIFT, 620, 180, 100), "stone": 0.2},    # 遗物廊出口
	{"rect": Rect2(4110 + HALL_SHIFT, 600, 360, 110), "stone": 0.1},    # 层门厅
	{"rect": Rect2(4470 + HALL_SHIFT, 600, 830, 110), "stone": 0.06},   # M4-08 层门厅后段
	{"rect": Rect2(MAP_LEFT, 300, 80, 900), "stone": 0.0},             # 左边界墙
	{"rect": Rect2(MAP_RIGHT, 300, 80, 900), "stone": 0.0},            # 右边界墙
]

const SPAWN_POINT := Vector2(140, 560)
## M4-08：层门厅后段加长后，门/入口/剧情触发统一用这个 x，避免三处各写一个数
const GATE_X := 5140.0 + HALL_SHIFT
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const CAMPFIRE_SCENE := preload("res://scenes/world/campfire.tscn")
const SOUL_BOSS_SCENE := preload("res://scenes/entities/soul_slime_boss.tscn")
const GATE_SCENE := preload("res://scenes/world/tutorial_gate.tscn")
const SPORE_SHOOTER_SCENE := preload("res://scenes/entities/spore_shooter.tscn")
const INSPECT_SCENE := preload("res://scenes/world/inspect_point.tscn")
const WATCHMAN_SCENE := preload("res://scenes/world/watchman.tscn")
const BELL_MECHANISM_SCENE := preload("res://scenes/world/bell_mechanism.tscn")
const BONE_GATE_SCENE := preload("res://scenes/world/bone_gate.tscn")
## 钟厅里不放怪（M4-18：组长要求敲钟这一段别有怪打断），
## 敌人只留钟厅之后的两只史莱姆和遗物廊出口的孢子射手。
## 敌人离剧情触发器至少 200px，对话时 dialogue.gd 还会把 enemy 分组整体冻结。
const SLIME_SPAWNS: Array[Vector2] = [
	Vector2(3140, 646),
	# M5-14（组长反馈「两怪物处：删史莱姆」）：原来遗物廊出口那块小台上挤着
	# 一只史莱姆（4760）和一个孢子射手（4720），刚跳过断桥就同时被两样东西贴脸。
	# 史莱姆删掉，只留射手；射手也按组长说的"不放在刚跳过来处"往后挪到大平台。
	Vector2(5200, 586), Vector2(5650, 586),
]

## 血条出现的距离（世界 px）：一屏多看得到 boss 才显示，走到长廊就收起来
const BOSS_BAR_RANGE := 900.0
## 摄像机参数与教学关一致：垂直视野 = 12 倍角色身高
## M4-62 组长要求“人物放大”：从原来的 15 收到 10（人物在屏幕上放大 1.5 倍）。
## 为什么不是 2 倍：2 倍时一次普通跳跃要占半屏、前方 100px 深的坑底又得占 343px，
## 加起来超过 720 的屏高 —— “平地跳镜头不动”和“站高台要看得见下方”不能同时成立，
## 组长选了 1.5 倍。
## M4-63 组长又说“正常的时候再拉远一点”，于是 10 → 12（人物约 60px 高，原来是 72px）。
## 物理数值（跳跃高度、判定框）一个都没动，只有视野跟着变。
const VIEW_HEIGHT_IN_CHARACTERS := 12.0
const PLAYER_CHARACTER_HEIGHT := 28.0
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

const INTRO_DELAY := 0.6
const INTRO_ID := "floor1_enter"
## M3-01：层门后接真正的第二层；走近门缝先等层门对话念完，再黑场过去
const FLOOR2_SCENE := "res://scenes/world/floor2.tscn"
const FLOOR2_NAME := "第二层 · 铸炉与圣坛"
const GAME_HUD_SCENE := preload("res://scenes/ui/game_hud.tscn")

const STONE_COLOR := Color(0.165, 0.190, 0.210)
const STONE_DARK := Color(0.075, 0.090, 0.105)
const STONE_RIM := Color(0.380, 0.470, 0.480)

@onready var _dialogue: Node = $Dialogue
@onready var _player: Node2D = $Player
@onready var _camera: Camera2D = $Camera2D

var _played: Dictionary = {}
var _want_floor2 := false
var _entering_floor2 := false
var _transition_layer: CanvasLayer
var _transition_rect: ColorRect
var _transition_label: Label
var _bell: Node2D
var _watchman: Node2D
var _bell_mechanism: Node2D
var _bone_gate: StaticBody2D
var _bell_rung := false
var _boss: Node = null
var _boss_spawned := false
## 关底战前那段"它是什么"的旁白只播一次（重进战场/读档回来不该再来一遍）
var _boss_intro_played := false
var _boss_gate: Node = null
var _boss_arena: Node = null
var _boss_hud: CanvasLayer
var _boss_bar: ProgressBar
var _boss_name: Label

func _ready() -> void:
	GameManager.mark_floor_start("floor1")
	# M5-09（组长要求）：钟厅里、钟绳前那座篝火删掉 —— 三层只留后面的补给点，
	# 拉绳前先给一堆火，等于把"守钟人—钟绳"这段的紧张感卸掉了。
	_build_platforms()
	_build_props()
	_build_mechanisms()
	_build_triggers()
	_build_boss_arena()
	_build_inspect_points()
	_build_floor2_entry()
	_build_kill_zone()
	_spawn_enemies()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_build_fade_in()
	_build_floor2_transition()
	_build_hud()
	SaveSystem.apply_pending_player(_player)
	# 存档里已经敲过钟：骨门直接开，守钟人切到“钟响之后”台词
	if GameManager.has_flag("floor1_bell_rung"):
		_apply_bell_rung(true)
	var timer := get_tree().create_timer(INTRO_DELAY)
	timer.timeout.connect(_play_intro)

## 从教学关黑场进来：第一层先全黑，再淡入层名，别让转场像硬切。
func _build_hud() -> void:
	if get_node_or_null("GameHUD") != null:
		return
	var hud := GAME_HUD_SCENE.instantiate()
	hud.name = "GameHUD"
	add_child(hud)

func _build_fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FloorTransitionIn"
	layer.layer = 4
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.015, 0.020, 0.024, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var label := Label.new()
	label.text = "第一层 · 锈钟回廊"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.72, 0.88, 0.86, 0.0)
	label.add_theme_font_size_override("font_size", 22)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position = Vector2(-150, -20)
	label.size = Vector2(300, 40)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	layer.add_child(label)
	var tw := create_tween()
	tw.tween_interval(0.10)
	tw.tween_property(rect, "color:a", 0.0, 0.55)
	tw.parallel().tween_property(label, "modulate:a", 0.6, 0.28)
	tw.tween_property(label, "modulate:a", 0.0, 0.35)
	tw.tween_callback(layer.queue_free)

func _process(_delta: float) -> void:
	_update_boss_hud()
	# 打倒关底：围栏升起，通往第二层的路才通
	if _boss_spawned and GameManager.has_flag("floor1_boss_defeated"):
		if _boss_gate != null and is_instance_valid(_boss_gate) and not bool(_boss_gate.call("is_open")):
			_boss_gate.call("open")
	# 玩家已经走进门缝，但层门对话还在念：等它念完再黑场，别把台词吞掉。
	if _want_floor2 and not _entering_floor2:
		if _dialogue != null and _dialogue.has_method("is_playing") and bool(_dialogue.call("is_playing")):
			return
		_enter_floor2()

func _play_intro() -> void:
	_play_once("intro", INTRO_ID)

## 同一段剧情只播一次：旗标记在 GameManager，死了重进也不会重复念
func _play_once(key: String, dialogue_id: String) -> void:
	if _played.get(key, false):
		return
	if _dialogue == null or not _dialogue.has_method("play"):
		# 测试/画廊场景会先把 Dialogue 摘掉再加载这一层，不能因为缺组件就崩
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
	# M4-18：钟厅从 780 加到 1640，中间空出来的两段要有东西看，不能是空跑道。
	# 这一段全是钟厅的背景（龛、墙、门框、断柱、壁灯、碎石），必须在吊钟之前加，
	# 否则同一层里后加的龛会盖住钟，钟就成了墙上一块看不见的补丁。
	_build_bell_hall(props)

	# 吊钟：钟厅的视觉中心。钟要挂到镜头（地面探索时视野约 y 396~816）里，
	# 所以钟底离地 40 多像素，玩家正好从钟下走过。
	var bell := Node2D.new()
	bell.name = "Bell"
	bell.position = Vector2(BELL_X, 620)
	props.add_child(bell)
	_bell = bell

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
	for dx in [-100.0, 0.0, 100.0]:
		var chain := Line2D.new()
		chain.width = 4.0
		chain.default_color = Color(0.075, 0.085, 0.095)
		chain.points = PackedVector2Array([
			Vector2(BELL_X + dx, 342.0), Vector2(BELL_X + dx + 6.0, 420.0),
			Vector2(BELL_X + dx, 470.0 if dx == 0.0 else 560.0)
		])
		props.add_child(chain)

	var beam := Polygon2D.new()
	beam.color = Color(0.070, 0.082, 0.092)
	beam.polygon = PackedVector2Array([
		Vector2(BELL_X - 170, 352), Vector2(BELL_X + 170, 352),
		Vector2(BELL_X + 170, 382), Vector2(BELL_X - 170, 382),
	])
	props.add_child(beam)

	# 灯火：祭坛暖光、钟厅冷光。没有贴图，用径向渐变纹理当光晕
	_add_light(props, Vector2(2600 + HALL_SHIFT, 520), Color(1.0, 0.78, 0.52), 0.85, 2.6)
	_add_light(props, Vector2(BELL_X, 560), Color(0.45, 0.78, 0.82), 0.5, 2.6)
	_add_light(props, Vector2(420, 585), Color(1.0, 0.70, 0.44), 0.35, 1.6)

	# 钟厅残旗：给冷灰的钟厅加一点暗紫布色，风一吹能看出这是"有人住过的地方"
	var banner := Polygon2D.new()
	banner.color = Color(0.150, 0.095, 0.170, 0.9)
	banner.polygon = PackedVector2Array([
		Vector2(BELL_X - 148, 372), Vector2(BELL_X - 98, 384), Vector2(BELL_X - 92, 560),
		Vector2(BELL_X - 108, 544), Vector2(BELL_X - 122, 582), Vector2(BELL_X - 138, 538),
		Vector2(BELL_X - 154, 566),
	])
	props.add_child(banner)
	var banner_rim := Line2D.new()
	banner_rim.width = 1.5
	banner_rim.default_color = Color(0.30, 0.20, 0.34, 0.7)
	banner_rim.points = PackedVector2Array([Vector2(BELL_X - 148, 372), Vector2(BELL_X - 98, 384)])
	props.add_child(banner_rim)

	# 扩建区：断桥、遗物廊、层门厅的物件；都在 Props 层，不挡玩家也不参与碰撞
	_build_ruin_props(props)
	_add_light(props, Vector2(3550, 585), Color(1.0, 0.72, 0.44), 0.42, 2.0)
	_add_light(props, Vector2(GATE_X - 70.0, 545), Color(0.58, 0.86, 0.92), 0.55, 2.4)

	# 层门：两根柱子 + 门楣 + 一条冷光缝。扩建后门移到地图最右的层门厅。
	var gate := Node2D.new()
	gate.name = "GateFrame"
	gate.position = Vector2(GATE_X, 600)
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
	# 钟厅加长后这几段整体右移，这里包一层位移节点，旧坐标不用逐个改，
	# 也不会出现漏改一个就错位的情况。层门厅那部分用 GATE_X，已经带着位移，留在外层。
	var zone := Node2D.new()
	zone.name = "RuinShifted"
	zone.position = Vector2(HALL_SHIFT, 0.0)
	parent.add_child(zone)

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
			zone.add_child(rope)
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
			zone.add_child(plank)
			var edge := Line2D.new()
			edge.width = 1.0
			edge.default_color = Color(0.34, 0.34, 0.28, 0.55)
			edge.position = plank.position
			edge.rotation = plank.rotation
			edge.points = PackedVector2Array([Vector2(-15, -2), Vector2(15, -2)])
			zone.add_child(edge)
		# 断口底部淡紫雾，提示下面是空的
		var mist := Polygon2D.new()
		mist.color = Color(0.16, 0.12, 0.20, 0.10)
		mist.polygon = _ellipse(Vector2((x1 + x2) * 0.5, y + 70.0), Vector2(52.0, 18.0), 20)
		zone.add_child(mist)

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
			zone.add_child(col)
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
		zone.add_child(arch)
		# 龛里的骨堆/小罐
		var urn := Polygon2D.new()
		urn.color = Color(0.24, 0.26, 0.23)
		urn.polygon = PackedVector2Array([
			Vector2(cx - 10, shrine_base - 8), Vector2(cx - 7, shrine_base - 26),
			Vector2(cx + 7, shrine_base - 26), Vector2(cx + 10, shrine_base - 8),
		])
		zone.add_child(urn)
		for b in range(3):
			var bone := Line2D.new()
			bone.width = 1.6
			bone.default_color = Color(0.52, 0.52, 0.44, 0.65)
			bone.points = PackedVector2Array([
				Vector2(cx - 8 + b * 6, shrine_base - 5),
				Vector2(cx - 4 + b * 6, shrine_base - 12 - b * 2),
			])
			zone.add_child(bone)

	# 中间石棺：遗物廊的视觉中心，盖板斜着滑开，露出一点内里
	var casket := Polygon2D.new()
	casket.color = Color(0.12, 0.14, 0.15)
	casket.polygon = PackedVector2Array([
		Vector2(3535, 640), Vector2(3535, 600), Vector2(3605, 600),
		Vector2(3605, 640), Vector2(3596, 648), Vector2(3544, 648),
	])
	zone.add_child(casket)
	var lid := Polygon2D.new()
	lid.color = Color(0.20, 0.22, 0.22)
	lid.position = Vector2(3568, 590)
	lid.rotation = -0.13
	lid.polygon = PackedVector2Array([
		Vector2(-36, -5), Vector2(36, -7), Vector2(38, 3), Vector2(-34, 5),
	])
	zone.add_child(lid)
	var casket_line := Line2D.new()
	casket_line.width = 1.2
	casket_line.default_color = Color(0.36, 0.39, 0.36, 0.8)
	casket_line.points = PackedVector2Array([Vector2(3539, 607), Vector2(3601, 607)])
	zone.add_child(casket_line)

	# M4-08：层门厅后段（4470~5140）不是空白跑道，补三根断柱、碎石和冷雾，
	# 让玩家在走到层门前还有一段“旧回廊”可看。全部是背景层，不参与碰撞。
	for spec in [
		{"x": 4610.0, "h": 132.0, "lean": -9.0},
		{"x": 4780.0, "h": 88.0, "lean": 7.0},
		{"x": 4940.0, "h": 158.0, "lean": -4.0},
	]:
		_add_broken_pillar(zone, float(spec["x"]), 600.0, float(spec["h"]), float(spec["lean"]))
	var mist := Polygon2D.new()
	mist.color = Color(0.16, 0.24, 0.26, 0.08)
	mist.polygon = _ellipse(Vector2(4780, 570), Vector2(190, 46), 24)
	zone.add_child(mist)
	_add_light(zone, Vector2(4780, 540), Color(0.50, 0.78, 0.84), 0.30, 2.2)

	# 层门厅：门两侧各一根断柱，柱头挂一盏冷灯，和地图尽头的门呼应
	for dx in [-120.0, 140.0]:
		var pillar := Polygon2D.new()
		pillar.color = Color(0.075, 0.09, 0.10)
		var px: float = GATE_X + float(dx)
		pillar.polygon = PackedVector2Array([
			Vector2(px - 18, 600), Vector2(px - 18, 390), Vector2(px - 8, 366),
			Vector2(px + 8, 370), Vector2(px + 18, 394), Vector2(px + 18, 600),
		])
		parent.add_child(pillar)
	var chain := Line2D.new()
	chain.width = 2.0
	chain.default_color = Color(0.11, 0.12, 0.13)
	chain.points = PackedVector2Array([
		Vector2(GATE_X, 270), Vector2(GATE_X - 6, 360), Vector2(GATE_X, 420)
	])
	parent.add_child(chain)
	var censer := Polygon2D.new()
	censer.color = Color(0.24, 0.28, 0.27)
	censer.polygon = PackedVector2Array([
		Vector2(GATE_X - 14, 420), Vector2(GATE_X + 14, 420),
		Vector2(GATE_X + 10, 436), Vector2(GATE_X - 10, 436),
	])
	parent.add_child(censer)


## 钟厅填充（M4-18）。
##
## 钟厅从 780 加到 1640 以后，中间空出两段路：断绳旁白到守钟人、钟到骨门。
## 这两段要是只有地面，就成了空白跑道，所以补石龛、门框、断柱、壁灯和碎石。
## 全部在 Props 层（z=-1），不挡玩家也不参与碰撞——脚下能站哪儿仍然只认 PLATFORMS。
func _build_bell_hall(parent: Node) -> void:
	var hall := Node2D.new()
	hall.name = "BellHall"
	parent.add_child(hall)

	# 钟的石龛：后壁凹进去一块，钟挂在龛里，龛口上窄下宽。
	# 龛壁用比钟亮一档的石头色：钟是近黑的剪影，贴在近黑的墙上会直接看不见
	# （第一版用了 0.028/0.036/0.044，截图里钟和墙只差 1 个色阶）。
	var back := Polygon2D.new()
	back.name = "BellNiche"
	back.color = Color(0.125, 0.145, 0.160)
	back.polygon = PackedVector2Array([
		Vector2(BELL_X - 186, BELL_HALL_FLOOR_Y), Vector2(BELL_X - 160, 470),
		Vector2(BELL_X + 160, 470), Vector2(BELL_X + 186, BELL_HALL_FLOOR_Y),
	])
	hall.add_child(back)
	# 龛顶阴影：收口那一段压暗，看着像往里凹，不是一块平贴的墙板
	var niche_shadow := Polygon2D.new()
	niche_shadow.name = "NicheShadow"
	niche_shadow.color = Color(0.030, 0.038, 0.046)
	niche_shadow.polygon = PackedVector2Array([
		Vector2(BELL_X - 160, 396), Vector2(BELL_X + 160, 396),
		Vector2(BELL_X + 160, 470), Vector2(BELL_X - 160, 470),
	])
	hall.add_child(niche_shadow)
	var niche_rim := Line2D.new()
	niche_rim.width = 2.0
	niche_rim.default_color = Color(0.30, 0.42, 0.44, 0.40)
	niche_rim.points = PackedVector2Array([
		Vector2(BELL_X - 186, BELL_HALL_FLOOR_Y - 4), Vector2(BELL_X - 160, 396),
		Vector2(BELL_X + 160, 396), Vector2(BELL_X + 186, BELL_HALL_FLOOR_Y - 4),
	])
	hall.add_child(niche_rim)
	# 龛脚两团冷雾：钟底和地面之间不要一刀切
	for dx in [-150.0, 150.0]:
		var mist := Polygon2D.new()
		mist.color = Color(0.16, 0.24, 0.26, 0.10)
		mist.polygon = _ellipse(Vector2(BELL_X + dx, 744.0), Vector2(70.0, 20.0), 20)
		hall.add_child(mist)
	_add_light(hall, Vector2(BELL_X, 440), Color(0.50, 0.80, 0.86), 0.26, 2.0)

	# 骨门的门框：两道石壁夹着门口，门楣压在上面，上面再压一段后墙。
	# 玩家看到的“钟厅右边的墙”就是这一块，拉响钟以后骨门从门口沉下去。
	for side in [-1.0, 1.0]:
		var jamb := Polygon2D.new()
		jamb.name = "GateJamb" if side < 0.0 else "GateJambRight"
		jamb.color = Color(0.080, 0.096, 0.108)
		jamb.polygon = PackedVector2Array([
			Vector2(BONE_GATE_X + side * 19, BELL_HALL_FLOOR_Y),
			Vector2(BONE_GATE_X + side * 19, 452),
			Vector2(BONE_GATE_X + side * 46, 452),
			Vector2(BONE_GATE_X + side * 46, BELL_HALL_FLOOR_Y),
		])
		hall.add_child(jamb)
		var jamb_rim := Line2D.new()
		jamb_rim.width = 1.4
		jamb_rim.default_color = Color(0.34, 0.40, 0.40, 0.55)
		jamb_rim.points = PackedVector2Array([
			Vector2(BONE_GATE_X + side * 19, BELL_HALL_FLOOR_Y - 8),
			Vector2(BONE_GATE_X + side * 19, 456),
		])
		hall.add_child(jamb_rim)
	var lintel := Polygon2D.new()
	lintel.name = "GateLintel"
	lintel.color = Color(0.105, 0.122, 0.136)
	lintel.polygon = PackedVector2Array([
		Vector2(BONE_GATE_X - 64, 418), Vector2(BONE_GATE_X + 64, 418),
		Vector2(BONE_GATE_X + 56, 454), Vector2(BONE_GATE_X - 56, 454),
	])
	hall.add_child(lintel)
	var lintel_rim := Line2D.new()
	lintel_rim.width = 1.6
	lintel_rim.default_color = Color(0.38, 0.46, 0.44, 0.5)
	lintel_rim.points = PackedVector2Array([
		Vector2(BONE_GATE_X - 64, 418), Vector2(BONE_GATE_X + 64, 418),
	])
	hall.add_child(lintel_rim)
	var upper_wall := Polygon2D.new()
	upper_wall.name = "GateWall"
	upper_wall.color = Color(0.062, 0.074, 0.086)
	upper_wall.polygon = PackedVector2Array([
		Vector2(BONE_GATE_X - 158, 300), Vector2(BONE_GATE_X + 158, 300),
		Vector2(BONE_GATE_X + 150, 418), Vector2(BONE_GATE_X - 150, 418),
	])
	hall.add_child(upper_wall)
	# 门洞两侧的墙身一直落到地面：只画上半截的话，门洞左右各留一条背景色的缝，
	# 站在钟厅里看就像墙上多了两个能钻的窟窿。骨门本身堵住中间的洞。
	var wing_left := Polygon2D.new()
	wing_left.name = "GateWingLeft"
	wing_left.color = Color(0.070, 0.083, 0.096)
	wing_left.polygon = PackedVector2Array([
		Vector2(BONE_GATE_X - 152, 418), Vector2(BONE_GATE_X - 41, 418),
		Vector2(BONE_GATE_X - 41, BELL_HALL_FLOOR_Y), Vector2(BONE_GATE_X - 152, BELL_HALL_FLOOR_Y),
	])
	hall.add_child(wing_left)
	var wing_right := Polygon2D.new()
	wing_right.name = "GateWingRight"
	wing_right.color = Color(0.070, 0.083, 0.096)
	wing_right.polygon = PackedVector2Array([
		Vector2(BONE_GATE_X + 41, 418), Vector2(BONE_GATE_X + 170, 418),
		Vector2(BONE_GATE_X + 170, BELL_HALL_FLOOR_Y), Vector2(BONE_GATE_X + 41, BELL_HALL_FLOOR_Y),
	])
	hall.add_child(wing_right)
	# 墙上的两道横缝，让这面后墙不是一整块黑
	for y in [344.0, 386.0]:
		var seam := Line2D.new()
		seam.width = 1.2
		seam.default_color = Color(0.045, 0.055, 0.065, 0.6)
		seam.points = PackedVector2Array([
			Vector2(BONE_GATE_X - 150, y), Vector2(BONE_GATE_X + 150, y),
		])
		hall.add_child(seam)

	# 缓冲段一的蜡烛：钟厅唯一一处暖色，落在"听完旁白、还没见到人"那段路上。
	# M5-13（组长反馈"石柱蜡烛错位悬空"）：原来直接挂在 y=620 的半空 ——
	# 钟厅地面在 BELL_HALL_FLOOR_Y（760），那一段墙上并没有托子，蜡烛就悬在空中。
	# 现在改成"落地石柱 + 柱头蜡烛"：柱脚由地面高度算出来，蜡烛坐在柱头，
	# 高度不再写死；位置也往左挪远一点，别和 1620 那根断柱叠在一起。
	var sconce_h := 96.0
	var sconce := Node2D.new()
	sconce.name = "HallSconce"
	sconce.position = Vector2(1420, BELL_HALL_FLOOR_Y - sconce_h)
	hall.add_child(sconce)
	var sconce_post := Polygon2D.new()
	sconce_post.color = Color(0.115, 0.125, 0.135, 0.95)
	sconce_post.polygon = PackedVector2Array([
		Vector2(-6, 11), Vector2(6, 11), Vector2(8, sconce_h), Vector2(-8, sconce_h),
	])
	sconce.add_child(sconce_post)
	var sconce_cup := Polygon2D.new()
	sconce_cup.color = Color(0.20, 0.18, 0.16, 0.92)
	sconce_cup.polygon = PackedVector2Array([
		Vector2(-7, 0), Vector2(7, 0), Vector2(5, 11), Vector2(-5, 11),
	])
	sconce.add_child(sconce_cup)
	var flame := Polygon2D.new()
	flame.color = Color(0.98, 0.72, 0.40, 0.85)
	flame.polygon = PackedVector2Array([Vector2(-3, -2), Vector2(0, -15), Vector2(3, -2)])
	sconce.add_child(flame)
	_add_light(sconce, Vector2(0, -8), Color(1.0, 0.70, 0.42), 0.30, 1.5)

	# 缓冲段二两侧各一根断柱：钟到骨门这段 370px，不能光秃秃地走过去
	_add_broken_pillar(hall, 1620.0, BELL_HALL_FLOOR_Y, 176.0, 12.0)
	_add_broken_pillar(hall, 2510.0, BELL_HALL_FLOOR_Y, 104.0, -8.0)

	# 地上碎石：长廊里几处大小不一的石块，破掉地面的直线
	for i in range(4):
		var rock := Polygon2D.new()
		rock.color = STONE_DARK.lightened(0.06 + 0.03 * i)
		var rx := 1320.0 + 330.0 * i + float(i * i) * 24.0
		rock.polygon = PackedVector2Array([
			Vector2(rx, BELL_HALL_FLOOR_Y), Vector2(rx + 9.0, BELL_HALL_FLOOR_Y - 7.0 - i),
			Vector2(rx + 19.0, BELL_HALL_FLOOR_Y - 3.0), Vector2(rx + 24.0, BELL_HALL_FLOOR_Y),
		])
		hall.add_child(rock)

## 一根断柱：倾斜的柱身 + 斜压的柱头 + 柱脚散碎石。
## 断桥区、层门厅后段、钟厅缓冲段用的是同一套画法，抽成一处，别各写一份。
func _add_broken_pillar(parent: Node, bx: float, floor_y: float, height: float, lean: float) -> void:
	var col := Polygon2D.new()
	col.color = Color(0.082, 0.096, 0.108)
	col.polygon = PackedVector2Array([
		Vector2(bx - 17, floor_y), Vector2(bx - 14 + lean, floor_y - height),
		Vector2(bx + 10 + lean, floor_y - height - 9), Vector2(bx + 17, floor_y),
	])
	parent.add_child(col)
	var cap := Polygon2D.new()
	cap.color = Color(0.13, 0.15, 0.16)
	cap.polygon = PackedVector2Array([
		Vector2(bx - 22 + lean, floor_y - height), Vector2(bx + 16 + lean, floor_y - height - 9),
		Vector2(bx + 16 + lean, floor_y - height + 1), Vector2(bx - 22 + lean, floor_y - height + 8),
	])
	parent.add_child(cap)
	# 柱脚碎石：告诉玩家这里塌过，不是没做完的贴图
	for k in range(2):
		var rubble := Polygon2D.new()
		rubble.color = Color(0.10, 0.12, 0.12)
		rubble.polygon = PackedVector2Array([
			Vector2(bx - 30 - k * 8, floor_y), Vector2(bx - 18 - k * 8, floor_y - 5),
			Vector2(bx - 8 - k * 8, floor_y),
		])
		parent.add_child(rubble)


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

# ---------- 机关与守钟人（M2-06） ----------

## 钟厅的“硬门槛”（M4-18 改了顺序和位置）：
## 守钟人站在钟的左边 300px（WATCHMAN_X），钟挂在 WATCHMAN_X 右边，
## 骨门就是钟厅右边那面墙（BONE_GATE_X），拉完钟绳才沉下去。
## 玩家必须先走过守钟人、再走到钟下拉绳，不能隔着半张地图把钟拉了。
func _build_mechanisms() -> void:
	var holder := Node2D.new()
	holder.name = "Mechanisms"
	holder.z_index = 2
	add_child(holder)

	_bone_gate = BONE_GATE_SCENE.instantiate() as StaticBody2D
	_bone_gate.name = "BoneGate"
	_bone_gate.position = Vector2(BONE_GATE_X, 620)
	holder.add_child(_bone_gate)

	_bell_mechanism = BELL_MECHANISM_SCENE.instantiate() as Node2D
	_bell_mechanism.name = "BellMechanism"
	_bell_mechanism.position = Vector2(BELL_X, 742)
	_bell_mechanism.set("controller", self)
	holder.add_child(_bell_mechanism)

	_watchman = WATCHMAN_SCENE.instantiate() as Node2D
	_watchman.name = "Watchman"
	_watchman.position = Vector2(WATCHMAN_X, BELL_HALL_FLOOR_Y)
	_watchman.set("dialogue_path", NodePath("../../Dialogue"))
	# 守钟人画在钟前面（Mechanisms 层 z=2，钟在 Props 层 z=-1）
	holder.add_child(_watchman)

## 拉钟绳：只执行一次；钟摆、波纹、骨门、对话、守钟人状态都在这里收口。
func ring_bell() -> bool:
	if _bell_rung:
		return false
	_apply_bell_rung(false)
	GameManager.play_sfx("bell")
	_dialogue.call("play", "floor1_bell_ring")
	return true

func _apply_bell_rung(instant: bool) -> void:
	_bell_rung = true
	GameManager.set_flag("floor1_bell_rung")
	if _bell_mechanism != null and _bell_mechanism.has_method("mark_rung"):
		_bell_mechanism.call("mark_rung")
	if _watchman != null and _watchman.has_method("mark_bell_rung"):
		_watchman.call("mark_bell_rung")
	if _bone_gate != null and _bone_gate.has_method("open"):
		_bone_gate.call("open", instant)
	if instant:
		return
	_animate_bell_ring()
	_spawn_ring_waves()
	var camera := get_tree().get_first_node_in_group("camera")
	if camera != null and camera.has_method("shake"):
		camera.call("shake", 6.0, 0.34)

func _animate_bell_ring() -> void:
	if _bell == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for angle in [0.075, -0.055, 0.035, -0.018, 0.0]:
		tween.tween_property(_bell, "rotation", angle, 0.18)
	tween.tween_callback(_reset_bell_rotation)

func _reset_bell_rotation() -> void:
	if _bell != null:
		_bell.rotation = 0.0

## 钟声波纹：三层圆环从钟腹向外扩，和震动一起给“钟真的响了”的反馈。
func _spawn_ring_waves() -> void:
	if _bell == null:
		return
	var holder := Node2D.new()
	holder.name = "BellRingWaves"
	holder.position = _bell.position + Vector2(0, 34)
	holder.z_index = 3
	add_child(holder)
	for i in range(3):
		var ring := Line2D.new()
		ring.width = 2.0 - i * 0.35
		ring.default_color = Color(0.78, 0.68, 0.40, 0.70 - i * 0.14)
		ring.antialiased = true
		var points := PackedVector2Array()
		for j in range(28):
			var angle := TAU * float(j) / 28.0
			points.append(Vector2(cos(angle), sin(angle)) * 18.0)
		ring.points = points
		ring.scale = Vector2(0.5, 0.5)
		holder.add_child(ring)
		var tween := create_tween()
		tween.set_parallel()
		tween.tween_property(ring, "scale", Vector2(5.0 + i * 1.4, 0.75 + i * 0.2), 0.70 + i * 0.12)
		tween.tween_property(ring, "modulate:a", 0.0, 0.62 + i * 0.10)
	# 波纹放完自己清掉，别在场景里留空节点
	var cleanup := create_tween()
	cleanup.tween_interval(1.0)
	cleanup.tween_callback(holder.queue_free)

# ---------- 触发器 ----------

func _build_triggers() -> void:
	var holder := Node2D.new()
	holder.name = "Triggers"
	add_child(holder)
	# 钟厅旁白放在钟厅入口进来 120px 处：玩家刚进门就听到“钟绳断了”，
	# 讲完这三句再走 590px 才见到守钟人，不会台词和人一起糊在脸上。
	_add_trigger(holder, "BellTrigger", Rect2(BELL_HALL_LEFT + 120.0, 600, 240, 200), "bell", "floor1_bell")
	_add_trigger(holder, "AltarTrigger", Rect2(2470 + HALL_SHIFT, 470, 250, 160), "altar", "floor1_altar")
	_add_trigger(holder, "BridgeTrigger", Rect2(3000 + HALL_SHIFT, 470, 160, 210), "bridge", "floor1_bridge")
	_add_trigger(holder, "RelicTrigger", Rect2(3450 + HALL_SHIFT, 490, 220, 230), "relic", "floor1_relic")
	_add_trigger(holder, "GateTrigger", Rect2(GATE_X - 90.0, 390, 150, 230), "gate", "floor1_gate")

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
	)
	parent.add_child(area)

func _build_inspect_points() -> void:
	# M2-05：剧情触发器只负责"第一次路过"，这里给玩家主动按 K 的重复调查入口。
	# 位置都在平台顶面上方，不压玩家落点；远离祭坛的 K 献祭判定区。
	var holder := Node2D.new()
	holder.name = "InspectPoints"
	# 调查符文和 K 提示要压在钟/祭坛/门框上方，否则物件挡住提示
	holder.z_index = 4
	add_child(holder)
	# M4-04：层门只是出口，剧情路过看一次就够，不再挂重复 K 调查。
	# M5-08（组长反馈「前方祭坛前调查删除」）：祭坛前面那个 K 调查点也删了 ——
	# 祭坛自己本来就有一行"献上肢体（K）"，再挂一个"祭坛调查（K）"两个提示叠在一起，
	# 玩家站在同一点上不知道按 K 到底会献祭还是只是看字。祭坛的机制提示由祭坛自己负责。
	# 这里保留空的 InspectPoints 容器：其它层/后续要加调查点时有地方挂，测试也不用改路径。
	var specs: Array[Dictionary] = []
	for spec in specs:
		var point := INSPECT_SCENE.instantiate()
		point.name = str(spec["name"])
		point.position = spec["pos"]
		point.set("dialogue_id", str(spec["id"]))
		point.set("prompt_text", str(spec["text"]))
		# 调查点挂在 InspectPoints 下，Dialogue 在根节点下；相对路径从点本身算
		point.set("dialogue_path", NodePath("../../Dialogue"))
		holder.add_child(point)

func _build_kill_zone() -> void:
	var area := Area2D.new()
	area.name = "KillZone"
	area.collision_layer = 0
	area.collision_mask = 2
	# 掉出地图的重伤区：范围和整张地图一样宽（M4-18 地图拉到 6160 以后，
	# 原来固定的 4800 只盖到 4700，右半段掉下去不会死）
	area.position = Vector2((MAP_LEFT + MAP_RIGHT) * 0.5, 1240)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(MAP_RIGHT - MAP_LEFT + 160.0, 200)
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

	# M2-07：遗物廊出口右侧的孢子射手；站在高台，逼玩家躲直线孢子弹。
	# M5-14（组长要求）：从 4720（刚跳过断桥的落点）后移到 5450 ——
	# 那是层门厅后段最宽的一块平台，玩家落地后还得往前走一段才撞上它，
	# 不再是"刚跳过来就被球打"。
	var shooter := SPORE_SHOOTER_SCENE.instantiate()
	shooter.name = "SporeShooter"
	shooter.position = Vector2(5450, 586)
	holder.add_child(shooter)

## 篝火：这一层不再放（M5-09 组长要求删掉钟绳前那座火，见 _ready 的注释）。
## 保留函数是为了以后要加补给点时知道"放哪、怎么摆"，目前没人调用。
func _build_campfire() -> void:
	var fire := CAMPFIRE_SCENE.instantiate()
	fire.name = "Campfire"
	fire.position = Vector2(2500, 760)
	add_child(fire)

## 第一层关底：走到层门厅后段，魂史莱姆从地里涌出来；打倒之前层门是封的
func _build_boss_arena() -> void:
	if GameManager.has_flag("floor1_boss_defeated"):
		return
	# 关底围栏：Boss 战开始后落下，挡住通往层门的路；打倒才升起
	_boss_gate = GATE_SCENE.instantiate()
	_boss_gate.name = "BossGate"
	_boss_gate.position = Vector2(5980, 470)
	_boss_gate.set("gate_id", "boss")
	_boss_gate.set("gate_height", 260.0)
	add_child(_boss_gate)
	_boss_gate.call("open")

	var area := Area2D.new()
	area.name = "BossArena"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(5440, 470)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(110, 300)
	var col := CollisionShape2D.new()
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player"):
			_spawn_boss()
	)
	add_child(area)
	_boss_arena = area

func _spawn_boss() -> void:
	# 关底只有一只：打到过的层不再刷，重复触发也不再刷
	if _boss_spawned or GameManager.has_flag("floor1_boss_defeated"):
		return
	if _boss != null and is_instance_valid(_boss):
		return
	_boss_spawned = true
	_boss = SOUL_BOSS_SCENE.instantiate()
	_boss.name = "SoulSlimeBoss"
	_boss.position = Vector2(5850, 548)
	add_child(_boss)
	if _boss_arena != null and is_instance_valid(_boss_arena):
		_boss_arena.set_deferred("monitoring", false)
	if _boss_gate != null and is_instance_valid(_boss_gate):
		_boss_gate.call("close")
	if _boss.has_method("set_arena_floor"):
		_boss.call("set_arena_floor", 600.0)
	# M5-16（组长要求"灵魂聚合体前加剧情说明缘由"）：先把它是怎么来的讲清楚，再交手。
	# 顺序必须是"先放 boss、再播旁白"：dialogue.gd 冻结敌人是遍历已有的 enemy 节点，
	# 反过来播的话，这只 boss 不在冻结名单里，会在旁白念到一半时自己跳起来砸人。
	_play_boss_intro()

## 关底战前那一段旁白（台词在 database/game_data/seed.sql 的 floor1_soul_boss 里）
func _play_boss_intro() -> void:
	if _boss_intro_played:
		return
	_boss_intro_played = true
	var dialogue := get_node_or_null("Dialogue")
	if dialogue != null and dialogue.has_method("play"):
		dialogue.call("play", "floor1_soul_boss")
	_build_boss_hud()
	EventBus.boss_encounter_started.emit("soul_slime")
	EventBus.log_event("boss_encounter_started", {"boss": "soul_slime", "floor": "floor1"})

# ---------- 第二层入口 / 转场 ----------

## 门缝里的判定区：玩家从层门框中间穿过去时置位，_process 等台词播完再切场景。
func _build_floor2_entry() -> void:
	var area := Area2D.new()
	area.name = "Floor2Entry"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(GATE_X + 18.0, 500)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 190)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		# 关底魂史莱姆没倒下之前，门被魂力封着：只提示，不切场景
		if not GameManager.has_flag("floor1_boss_defeated"):
			_show_sealed_hint()
			return
		_want_floor2 = true
	)
	add_child(area)

## 顶部 Boss 血条：和第三层守门者同一套样式，名字「灵魂聚合体」
func _build_boss_hud() -> void:
	if _boss_hud != null:
		return
	_boss_hud = CanvasLayer.new()
	_boss_hud.name = "BossHUD"
	_boss_hud.layer = 3
	add_child(_boss_hud)
	var panel := PanelContainer.new()
	panel.name = "BossPanel"
	panel.position = Vector2(390, 26)
	panel.size = Vector2(500, 66)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.016, 0.024, 0.74)
	style.set_border_width_all(2)
	style.border_color = Color(0.32, 0.46, 0.60, 0.7)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	_boss_hud.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)
	_boss_name = Label.new()
	_boss_name.text = "灵魂聚合体"
	_boss_name.add_theme_font_size_override("font_size", 15)
	_boss_name.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0, 0.95))
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		_boss_name.add_theme_font_override("font", font)
	box.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(0, 14)
	_boss_bar.max_value = 1.0
	_boss_bar.value = 1.0
	_boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.52, 0.64, 0.92, 0.95)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.10, 0.95)
	_boss_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_boss_bar)
	_boss_hud.visible = false

## M5-10（组长反馈「boss 血条死亡复活后不见了，靠近才显、走远重置」）：
## 血条只跟"玩家离 boss 有多近"走，不再跟"这一局有没有开过战"走。
## 玩家倒下复活会被送回出生点，靠这条判断血条自己收起来；再走回 boss 面前又出现，
## 不需要任何一次性开关（以前那个开关正是复活后血条再也回不来的原因）。
func _update_boss_hud() -> void:
	if _boss_hud == null:
		return
	if _boss == null or not is_instance_valid(_boss):
		_boss_hud.visible = false
		return
	if bool(_boss.call("is_dead")):
		_boss_hud.visible = false
		return
	var near := true
	if _player != null and is_instance_valid(_player):
		near = _player.global_position.distance_to(_boss.global_position) <= BOSS_BAR_RANGE
	_boss_hud.visible = near
	if not near:
		# 走远了顺带把血条按满格重置：回来时从满格开始读，不会残留上一场的进度
		_boss_bar.value = _boss_bar.max_value
		return
	var hp := int(_boss.call("get_hp"))
	var max_hp := maxi(int(_boss.call("get_max_hp")), 1)
	_boss_bar.max_value = float(max_hp)
	_boss_bar.value = float(hp)

var _sealed_hint: Label

## 门被封住时的提示（只出现一次，几秒后淡出）
func _show_sealed_hint() -> void:
	if _sealed_hint != null and is_instance_valid(_sealed_hint):
		return
	_sealed_hint = Label.new()
	_sealed_hint.text = "门被魂力封着 —— 先解决掉守在这儿的那个东西"
	_sealed_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sealed_hint.position = Vector2(GATE_X - 260.0, 430)
	_sealed_hint.size = Vector2(520, 30)
	_sealed_hint.add_theme_font_size_override("font_size", 16)
	_sealed_hint.add_theme_color_override("font_color", Color(0.76, 0.86, 0.96, 0.9))
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		_sealed_hint.add_theme_font_override("font", font)
	add_child(_sealed_hint)
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(_sealed_hint, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_sealed_hint.queue_free)

func _build_floor2_transition() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "Floor2Transition"
	_transition_layer.layer = 4
	add_child(_transition_layer)
	_transition_rect = ColorRect.new()
	_transition_rect.name = "Fade"
	_transition_rect.color = Color(0.018, 0.014, 0.012, 1.0)
	_transition_rect.modulate = Color(1, 1, 1, 0.0)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_layer.add_child(_transition_rect)
	_transition_label = Label.new()
	_transition_label.name = "FloorName"
	_transition_label.text = FLOOR2_NAME
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transition_label.modulate = Color(0.88, 0.74, 0.56, 0.0)
	_transition_label.add_theme_font_size_override("font_size", 22)
	_transition_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_transition_label.position = Vector2(-180, -20)
	_transition_label.size = Vector2(360, 40)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		_transition_label.add_theme_font_override("font", font)
	_transition_layer.add_child(_transition_label)

func _enter_floor2() -> void:
	if _entering_floor2:
		return
	_entering_floor2 = true
	GameManager.set_flag("floor2_unlocked")
	GameManager.current_floor = "floor_2"
	EventBus.player_moved_between_floors.emit("floor2")
	if _transition_rect != null:
		var tween := create_tween()
		tween.tween_property(_transition_rect, "modulate:a", 1.0, 0.50)
		tween.parallel().tween_property(_transition_label, "modulate:a", 0.9, 0.35)
		tween.tween_interval(0.28)
		tween.tween_callback(_change_to_floor2)
	else:
		get_tree().call_deferred("change_scene_to_file", FLOOR2_SCENE)

func _change_to_floor2() -> void:
	get_tree().change_scene_to_file(FLOOR2_SCENE)

