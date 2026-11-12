extends Node2D
## 测试竞技场（M1-01 / M1-12 布局重排）
##
## 教学关：平地 + 左右边界墙，从左到右是
##   出生 → 走一段（MOVE）→ 跳台（顶 571：JUMP、拿剑、打木桩、木桩乙在下劈台前）
##   → 下劈方台（顶 440，POGO 要站上去）→ 浅坑（两级石阶 + 战斗）
##   → 祭坛台（顶 572，献祭）→ 蒸汽靴宝箱 → 长廊台阶（可选）→ 下一层的门
## 布局数字全部在 STAGE 表里（M4-19 拉开距离 / M4-21 去掉引导光点），改布局只改表。
## M1-03：挂载对话 UI（DialogueBox，CanvasLayer 子节点保证 UI 在顶层）和对话
## 组件（Dialogue），场景稳定后自动弹出开场寄生体低语（intro_parasite_1 链）。

## 开场对话延迟（秒）：等场景 / 玩家 / 相机稳定后再弹出
const INTRO_DIALOGUE_DELAY := 0.5
## 开场对话 id（台词内容一律从 DataDB 读，这里只指定入口 id）
const INTRO_DIALOGUE_ID := "intro_parasite_1"

## 教程结束后开放的下一层门（同一地图右侧，地图边界墙前面）
const FLOOR1_SCENE := "res://scenes/world/floor1.tscn"

## 教学关站位表（M4-19）。
##
## 组长反馈：教学关和钟厅一样“每个项目都挤在一起”。这一版把各环之间的横向距离
## 统一拉到 340~510px（一屏约 747px），地图从 4000 加到 5000：
##
##   出生 80 → 移动光点 560 → 跳台 820..2400（拿剑 1310、木桩甲 1650、下劈台 2075..2235）
##   → 浅坑 2460..2800（史莱姆 2620/2700）→ 祭坛台 2860..3400（祭坛 3130）
##   → 宝箱 3640 → 长廊台阶 4060..4770 → 层门 4900 → 右墙 5000
##
## 场景文件 test_arena.tscn 里的坐标只是给编辑器看的初值，运行时全部按这张表摆。
## 改布局只改表（外加 world_width 那一项会同步地面/右墙/镜头/背景），别再去 .tscn 挪节点。
##
## M4-21 起表里的 *_mark 只当「这一环的提示写在哪」的锚点（原先是光点站位，光点已删）。
const PLAYER_HALF_HEIGHT := 13.0   # 玩家碰撞盒 14×26，中心到脚底 13
const STAGE := {
	"world_width": 5000.0,
	"spawn": Vector2(80, 647),
	# 移动环：走完这 480px 才算学会走路（判定点）
	"move_mark": Vector2(560, 585),
	# M4-22 组长反馈：开头那句 A/D 提示压在 600 处那道 200px 高的骨栅门上，整句左移一个文字宽度。
	# 这里只管“话写在哪”，判定还是 move_mark(560)：句子写在入口上方，人继续往前走才算过。
	"move_hint": Vector2(406, 585),
	"move_gate": Vector2(600, 559),
	# 跳台（顶 571，比地面高 88）：拿剑、打桩、下劈都在这条长台上
	"ledge": Rect2(820, 571, 1580, 90),
	"jump_mark": Vector2(900, 500),
	"jump_gate": Vector2(1040, 471),
	"corpse": Vector2(1245, 567),
	"sword": Vector2(1310, 568),
	"weapon_mark": Vector2(1310, 500),
	"dummy_a": Vector2(1650, 557),
	"attack_mark": Vector2(1650, 480),
	"attack_gate": Vector2(1760, 471),
	# 下劈：小方台（顶 440）+ 悬在台前的木桩乙，下劈反弹才够得着
	"pogo": Rect2(2075, 440, 160, 131),
	"dummy_b": Vector2(2060, 496),
	"pogo_mark": Vector2(2155, 372),
	"pogo_gate": Vector2(2330, 449),
	# 浅坑：两侧各两级台阶，坑底和地面同高，史莱姆就站在坑里
	"pit_steps": [
		Rect2(2400, 607, 30, 52), Rect2(2430, 633, 30, 26),
		Rect2(2800, 633, 30, 26), Rect2(2830, 607, 30, 52),
	],
	"slimes": [Vector2(2620, 646), Vector2(2700, 646)],
	"combat_mark": Vector2(2660, 590),
	"combat_gate": Vector2(2790, 309),
	# 祭坛台（顶 572）＋ 祭坛
	"altar_hall": Rect2(2860, 572, 540, 90),
	"altar": Vector2(3130, 597),
	"pickup_mark": Vector2(3130, 498),
	"sacrifice_mark": Vector2(3130, 498),
	# 祭坛之后：宝箱落地面上，长廊台阶是可选路线，层门在地图最右
	"chest": Vector2(3640, 659),
	"gallery": [
		Rect2(4060, 607, 130, 26), Rect2(4240, 552, 120, 26),
		Rect2(4430, 505, 110, 26), Rect2(4620, 565, 150, 26),
	],
	"door": Vector2(4900, 659),
}

## 物理门：每环一个，只有做完前面那一环才开。高度按玩家跳跃高度留死角：
## move/jump/attack 200，pogo 420，combat 700。位置由 STAGE 决定，这里只管高度。
const TUTORIAL_GATE_HEIGHTS := {
	"move": 200.0, "jump": 200.0, "attack": 200.0, "pogo": 420.0, "combat": 700.0,
}
## 演示快捷键：跳过教程直接进第一层（老师/组长试玩来不及打完整套教学时用）
const DEBUG_SKIP_KEY := KEY_F2

## 史莱姆场景：对话/教程前期场景无敌人（避免教学时被攻击的矛盾），
## 教程进入"战斗"步骤时由 spawn_enemies() 生成（M1-08 修正），位置见 STAGE["slimes"]。
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const TUTORIAL_GATE_SCENE := preload("res://scenes/world/tutorial_gate.tscn")
const ORIGIN_RELIC_SCENE := preload("res://scenes/items/origin_relic.tscn")
const ENDING_SCENE := preload("res://scenes/ui/ending_screen.tscn")
const GAME_HUD_SCENE := preload("res://scenes/ui/game_hud.tscn")
const TRUE_HE_RETURN_DIALOGUE := "true_he_return"
const TRUE_HE_RELIC_POS := Vector2(430, 628)

# ---- 摄像机（M1-09）----
## 垂直视野 = 角色身高的 N 倍（改这里即可调远近）；角色视觉身高 28px（见 player.gd CHARACTER_HEIGHT）
const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
## zoom = 视口高(720) ÷ (N×28)。N=12 → 336px 垂直视野 → zoom ≈ 2.14
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

@onready var _tutorial: Node = $Tutorial
@onready var _altar: Node = $Altar
@onready var _dialogue: Node = $Dialogue

var _door_root: Node2D
var _door_seam: Line2D
var _door_glow: Sprite2D
var _door_open := false
var _entering := false
var _gates: Dictionary = {}
var _combat_started := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _fade_label: Label
var _true_he_mode := false
var _true_he_shown := false
var _relic: Node
var _ending_screen: CanvasLayer
var _refusing := false

func _ready() -> void:
	# 相机 zoom 由这里设置（垂直视野 = N 倍角色身高）；水平跟随/垂直死区由 camera_follow.gd 处理
	var camera := $Camera2D as Camera2D
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)

	# M4-19：先按 STAGE 表把地形和道具摆好，后面所有构建都读同一张表
	_apply_stage()
	# 下一层的门：先立着，教程完成后才亮、才能进（软隔离，和教学关一个思路）
	_build_hollow_steps()
	_build_corridor_gallery()
	_build_next_floor_door()
	_build_tutorial_gates()
	_build_fade_overlay()
	_build_hud()
	# 教程 8 个提示气泡锚点也在这张表里，推给 Tutorial；它自己的常量只作无场景时的兜底
	if _tutorial != null and _tutorial.has_method("set_step_anchors"):
		_tutorial.call("set_step_anchors", station_anchors())
	# 真 HE 二周目：从第三层货梯回来时跳过整套教学，只留“还骨片”这一件事
	if GameManager.has_flag("true_he_return") and GameManager.has_flag("boss_defeated"):
		_setup_true_he_return()
	if _altar != null and _altar.has_signal("refuse_requested"):
		_altar.connect("refuse_requested", Callable(self, "_on_refuse_requested"))
		_altar.call("set_refuse_allowed", not _true_he_mode)
	var loaded_player := get_node_or_null("Player") as Node2D
	if loaded_player != null:
		SaveSystem.apply_pending_player(loaded_player)

	# M1-03：延时播放开场寄生体低语，让场景先稳定（玩家出生 → 低语弹出）
	var intro_timer := get_tree().create_timer(INTRO_DIALOGUE_DELAY)
	intro_timer.timeout.connect(_play_intro_dialogue)

# ---------- 站位表落地（M4-19） ----------

## 把 STAGE 表铺到场景上：地面/边界墙/背景/镜头限幅跟着 world_width 走，
## 三块平台按 rect 摆，道具和玩家按表定坐标。场景文件里那些数字只是编辑器里看的初值，
## 运行到这里就全被覆盖，所以改布局只需要改表。
func _apply_stage() -> void:
	var stage_w: float = STAGE["world_width"]

	# 地面与左右墙：地面还是整条地图的地板（顶 659），右墙钉在地图尽头
	var ground := $GroundLeft as StaticBody2D
	ground.position = Vector2(stage_w * 0.5, 689)
	(ground.get_node("CollisionShape2D") as CollisionShape2D).shape.size = Vector2(stage_w, 60)
	(ground.get_node("Visual") as Polygon2D).polygon = _box_polygon(Vector2(stage_w, 60))
	($WallRight as Node2D).position = Vector2(stage_w, 75)

	# 背景板、视差背景、镜头右限幅：三者必须和地面同宽，不然走到头会看见空白
	($Backdrop as Node2D).position = Vector2(stage_w * 0.5, 360)
	($Backdrop as Polygon2D).polygon = _box_polygon(Vector2(stage_w, 720))
	($BackdropArt as Node).set("world_width", stage_w)
	($Camera2D as Camera2D).limit_right = int(stage_w)

	# 三块平台：跳台、下劈小方台、祭坛台
	_place_platform($JumpPlatform as StaticBody2D, STAGE["ledge"], Vector2(300, 90))
	_place_platform($PogoPlatform as StaticBody2D, STAGE["pogo"], Vector2(250, 90))
	_place_platform($AltarPlatform as StaticBody2D, STAGE["altar_hall"], Vector2(300, 90))

	# 道具与玩家
	($Player as Node2D).position = STAGE["spawn"]
	($Corpse as Node2D).position = STAGE["corpse"]
	($WeaponPickup as Node2D).position = STAGE["sword"]
	($DummyA as Node2D).position = STAGE["dummy_a"]
	($DummyB as Node2D).position = STAGE["dummy_b"]
	($Altar as Node2D).position = STAGE["altar"]
	($SteamBootsChest as Node2D).position = STAGE["chest"]

## 平台原点是中心：碰撞换成 rect 大小、子节点归零、视觉按原始多边形缩放。
## 原来 JumpPlatform 的碰撞挂在 +343.5 这种手调偏移上，挪平台就得连子节点一起改，
## 这里统一成“原点=中心”，以后只给 rect 就行。
func _place_platform(body: StaticBody2D, rect: Rect2, unit: Vector2) -> void:
	body.position = rect.position + rect.size * 0.5
	var col := body.get_node("CollisionShape2D") as CollisionShape2D
	var shape := col.shape as RectangleShape2D
	shape.size = rect.size
	col.position = Vector2.ZERO
	var vis := body.get_node("Visual") as Polygon2D
	vis.position = Vector2.ZERO
	vis.scale = Vector2(rect.size.x / unit.x, rect.size.y / unit.y)

func _box_polygon(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])

## 教程 8 个目标文字锚点（下标就是 tutorial.gd 的 Step 枚举）。
## 给 Tutorial 用，也给测试用：测试从这里读坐标，改布局就不用再抄一份数字。
## 只负责“这环的话写在哪”，不再有光点停在上面（M4-21 组长要求删掉指引光）。
## M4-22：MOVE 那句用 move_hint（左移一个文字宽度避开骨栅门），判定点仍是 move_mark。
func station_anchors() -> Array[Vector2]:
	return [
		STAGE["move_hint"], STAGE["jump_mark"], STAGE["weapon_mark"], STAGE["attack_mark"],
		STAGE["pogo_mark"], STAGE["combat_mark"], STAGE["pickup_mark"], STAGE["sacrifice_mark"],
	]

## 位置判定①：玩家是否已横向走到某个站位（MOVE 环用）
## 只看横向：这一段本来就是平地，纵向没什么可判的
func player_reached(mark_key: String, player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not STAGE.has(mark_key):
		return false
	var mark: Vector2 = STAGE[mark_key]
	return (player as Node2D).global_position.x >= mark.x

## 位置判定②：玩家是否**双脚站上**某块平台（JUMP / POGO 环用）
## 组长定稿：下劈成功的标志是站上那块方台，不是挥出下劈动作 —— 所以这里要求 is_on_floor，
## 且脚底贴住该平台顶面（±6px）、横向落在矩形内（左右各留 4px，别把边缘算成站上去）
func player_on_platform(rect_key: String, player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not STAGE.has(rect_key):
		return false
	var body := player as CharacterBody2D
	if body == null or not body.is_on_floor():
		return false
	var rect: Rect2 = STAGE[rect_key]
	var x := body.global_position.x
	if x < rect.position.x + 4.0 or x > rect.end.x - 4.0:
		return false
	var feet := body.global_position.y + PLAYER_HALF_HEIGHT
	return absf(feet - rect.position.y) <= 6.0

func _process(_delta: float) -> void:
	if _refusing:
		return
	# 教程跑完（献祭完成）就把门点亮；之后玩家走进门即切到第一层
	if not _door_open and _tutorial != null and _tutorial.has_method("is_completed"):
		if bool(_tutorial.call("is_completed")):
			_open_door()
	# 战斗门不跟教程的“第一只击杀”走：必须把战斗区史莱姆清空才开，
	# 否则玩家杀一只就能跳过第二只直接去祭坛。
	if _combat_started and not _is_gate_open("combat"):
		if get_tree().get_nodes_in_group("enemy").is_empty():
			_open_tutorial_gate("combat")

# ---------- 教学物理门 ----------

func _build_tutorial_gates() -> void:
	var holder := Node2D.new()
	holder.name = "TutorialGates"
	add_child(holder)
	for gate_id in ["move", "jump", "attack", "pogo", "combat"]:
		var gate := TUTORIAL_GATE_SCENE.instantiate()
		gate.name = "Gate_%s" % gate_id
		gate.set("gate_id", gate_id)
		gate.set("gate_height", TUTORIAL_GATE_HEIGHTS[gate_id])
		gate.position = STAGE["%s_gate" % gate_id]
		holder.add_child(gate)
		_gates[gate_id] = gate

func open_tutorial_gate(gate_id: String) -> void:
	_open_tutorial_gate(gate_id)

func _open_tutorial_gate(gate_id: String) -> void:
	var gate: Node = _gates.get(gate_id)
	if gate != null and is_instance_valid(gate) and gate.has_method("open"):
		gate.call("open")
		GameManager.play_sfx("gate")

func _is_gate_open(gate_id: String) -> bool:
	var gate: Node = _gates.get(gate_id)
	if gate == null or not is_instance_valid(gate):
		return true
	return bool(gate.call("is_open"))

func _unhandled_input(event: InputEvent) -> void:
	# 反向测试（规范第 6 条）：只认 F2 的按下沿，其它键、抬起、长按 echo 都不触发
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	# 真 HE 二周目不能按 F2 跳回第一层，否则“还骨片”会被绕过
	if _true_he_mode:
		return
	if key.keycode == DEBUG_SKIP_KEY:
		_enter_floor1()

# ---------- 下一层的门 ----------

## M4-03：史莱姆浅坑两侧各两级石阶。原来 PitFloor 是一块高 72px 的凸台，
## 从跳台走过去像突然踩到桌子；现在用 26/52px 两级台阶落下去，再对称爬上来。
func _build_hollow_steps() -> void:
	_build_slab_holder("HollowSteps", STAGE["pit_steps"],
		["HollowStepL1", "HollowStepL2", "HollowStepR1", "HollowStepR2"])

## 祭坛后的可选阶梯（M4-07）：不参与教学门判定，走地面也能直达出口。
func _build_corridor_gallery() -> void:
	_build_slab_holder("CorridorGallery", STAGE["gallery"],
		["GalleryStep1", "GalleryStep2", "GalleryStep3", "GalleryStep4"])

## 浅坑台阶和长廊台阶是同一套画法（石台 + 顶面亮边），抽成一个函数，
## 免得两处各抄一份、以后改颜色只改一半。
func _build_slab_holder(holder_name: String, rects: Array, names: Array) -> void:
	var holder := Node2D.new()
	holder.name = holder_name
	add_child(holder)
	for i in range(rects.size()):
		var rect: Rect2 = rects[i]
		var body := StaticBody2D.new()
		body.name = str(names[i])
		body.collision_mask = 0
		body.position = rect.position + rect.size * 0.5
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		col.shape = shape
		body.add_child(col)
		var half := rect.size * 0.5
		var slab := Polygon2D.new()
		slab.color = Color(0.145, 0.148, 0.150, 1)
		slab.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
		body.add_child(slab)
		var edge := Line2D.new()
		edge.width = 2.0
		edge.default_color = Color(0.30, 0.31, 0.31, 0.85)
		edge.points = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y)])
		body.add_child(edge)
		holder.add_child(body)

func _build_next_floor_door() -> void:
	_door_root = Node2D.new()
	_door_root.name = "NextFloorDoor"
	_door_root.position = STAGE["door"]
	# 门框压在玩家后面：走进去时人挡门，不是门挡人（背景 Backdrop z=-2）
	_door_root.z_index = -1
	add_child(_door_root)

	# 门后的光：教程没完成时很暗，完成后调亮
	_door_glow = Sprite2D.new()
	_door_glow.texture = _radial_texture()
	_door_glow.modulate = Color(0.35, 0.80, 0.82, 0.06)
	_door_glow.scale = Vector2(1.3, 1.3)
	_door_glow.position = Vector2(0, -86)
	_door_root.add_child(_door_glow)

	var post_color := Color(0.130, 0.150, 0.160)
	for dx in [-48.0, 48.0]:
		var post := Polygon2D.new()
		post.color = post_color
		post.polygon = PackedVector2Array([
			Vector2(dx - 14, -178), Vector2(dx + 14, -178), Vector2(dx + 14, 0), Vector2(dx - 14, 0),
		])
		_door_root.add_child(post)
		# 门框内侧一圈冷色轮廓光，不然柱子跟平背景一个亮度，看不出是门
		var rim := Line2D.new()
		rim.width = 2.0
		rim.default_color = Color(0.34, 0.52, 0.53, 0.55)
		rim.points = PackedVector2Array([
			Vector2(dx + (14.0 if dx > 0 else -14.0), -172),
			Vector2(dx + (14.0 if dx > 0 else -14.0), -6),
		])
		_door_root.add_child(rim)
	var lintel := Polygon2D.new()
	lintel.color = Color(0.160, 0.180, 0.190)
	lintel.polygon = PackedVector2Array([
		Vector2(-76, -196), Vector2(76, -196), Vector2(72, -166), Vector2(-72, -166),
	])
	_door_root.add_child(lintel)

	# 门槛：把门和地面接上，别让柱子浮着
	var sill := Polygon2D.new()
	sill.color = Color(0.190, 0.210, 0.215)
	sill.polygon = PackedVector2Array([
		Vector2(-64, -10), Vector2(64, -10), Vector2(64, 0), Vector2(-64, 0),
	])
	_door_root.add_child(sill)

	# 门缝：整个门的"开关"就看这条线的亮度
	_door_seam = Line2D.new()
	_door_seam.name = "DoorSeam"
	_door_seam.width = 5.0
	_door_seam.default_color = Color(0.18, 0.30, 0.32, 0.25)
	_door_seam.points = PackedVector2Array([Vector2(0, -164), Vector2(0, -4)])
	_door_root.add_child(_door_seam)

	# 门牌：中文字体必须显式加载，否则方块
	var label := Label.new()
	label.text = "第一层"
	label.position = Vector2(-40, -226)
	label.size = Vector2(80, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.50, 0.72, 0.74, 0.75))
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	_door_root.add_child(label)

	# 进入判定：只认玩家（collision_mask 2），门没开时不切场景
	var area := Area2D.new()
	area.name = "DoorArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(0, -90)
	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 180)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		if _door_open:
			_enter_floor1()
	)
	_door_root.add_child(area)

func _open_door() -> void:
	_door_open = true
	_door_seam.default_color = Color(0.55, 0.95, 0.92, 0.85)
	_door_glow.modulate = Color(0.45, 0.95, 0.90, 0.30)
	GameManager.play_sfx("gate")
	EventBus.log_event("floor_gate_open", {"floor": "floor1"})

func _enter_floor1() -> void:
	if _entering:
		return
	_entering = true
	GameManager.set_flag("floor1_unlocked")
	EventBus.player_moved_between_floors.emit("floor1")
	# M2-09：先黑屏 + 层名，再换场景；换场景必须延后，别在物理/输入回调里立刻切
	if _fade_rect != null:
		var tween := create_tween()
		tween.tween_property(_fade_rect, "modulate:a", 1.0, 0.50)
		tween.parallel().tween_property(_fade_label, "modulate:a", 0.9, 0.35)
		tween.tween_interval(0.28)
		tween.tween_callback(_change_to_floor1)
	else:
		get_tree().call_deferred("change_scene_to_file", FLOOR1_SCENE)

func _change_to_floor1() -> void:
	get_tree().change_scene_to_file(FLOOR1_SCENE)

## 黑场 + 层名：不靠图片，纯 CanvasLayer；黑场到 1 后换场景，floor1 自己再做淡入
func _build_hud() -> void:
	if get_node_or_null("GameHUD") != null:
		return
	var hud := GAME_HUD_SCENE.instantiate()
	hud.name = "GameHUD"
	add_child(hud)

func _build_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FloorTransition"
	_fade_layer.layer = 4
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color(0.015, 0.020, 0.024, 1.0)
	_fade_rect.modulate = Color(1, 1, 1, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)
	_fade_label = Label.new()
	_fade_label.name = "FloorName"
	_fade_label.text = "第一层 · 锈钟回廊"
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.modulate = Color(0.72, 0.88, 0.86, 0.0)
	_fade_label.add_theme_font_size_override("font_size", 22)
	_fade_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fade_label.position = Vector2(-150, -20)
	_fade_label.size = Vector2(300, 40)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		_fade_label.add_theme_font_override("font", font)
	_fade_layer.add_child(_fade_label)

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

## 生成史莱姆（教程战斗步骤调用；可重复调用会叠加，调用方保证只调一次）
func spawn_enemies() -> void:
	_combat_started = true
	var points: Array = STAGE["slimes"]
	for i in range(points.size()):
		var slime := SLIME_SCENE.instantiate()
		slime.position = points[i]
		slime.name = "Slime%d" % (i + 1)
		add_child(slime)

func _play_intro_dialogue() -> void:
	if _refusing:
		return
	# Dialogue 是挂 dialogue.gd 组件的普通 Node，用 call() 动态调用，
	# 避免静态类型检查把 play() 当作 Node 上不存在的方法报错
	var dialogue := get_node_or_null("Dialogue")
	if dialogue != null and dialogue.has_method("play"):
		dialogue.call("play", TRUE_HE_RETURN_DIALOGUE if _true_he_mode else INTRO_DIALOGUE_ID)

## 真 HE 二周目：教学已完成过，只开全部门、给剑、在起点放一块骨片。
## 不再走 Tutorial 状态机，避免玩家被“走到光点”重新锁一遍。
func _setup_true_he_return() -> void:
	_true_he_mode = true
	GameManager.current_floor = "start"
	if _tutorial != null:
		_tutorial.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := get_node_or_null("ObjectiveHUD")
	if hud != null:
		hud.visible = false
		if hud.has_method("hide_bubble"):
			hud.call("hide_bubble")
	# 二周目不重新走门：全开，玩家能直接跑到祭坛
	for gate_id in TUTORIAL_GATE_HEIGHTS.keys():
		_open_tutorial_gate(str(gate_id))
	var player := get_node_or_null("Player")
	if player != null:
		player.set("has_weapon", true)
	var sword_ground := get_node_or_null("WeaponPickup")
	if sword_ground != null:
		sword_ground.queue_free()
	if not GameManager.has_flag("true_he_relic"):
		var holder := Node2D.new()
		holder.name = "TrueHEProps"
		add_child(holder)
		_relic = ORIGIN_RELIC_SCENE.instantiate()
		_relic.name = "OriginRelic"
		_relic.position = TRUE_HE_RELIC_POS
		holder.add_child(_relic)

## M1-07：新手祭坛的拒绝出口。只有“手里有肢体、还没献祭、教程未完成”时才生效，
## 避免在普通祭坛/已完成教学/真 HE 里误触。
func _on_refuse_requested() -> void:
	if _refusing or _true_he_mode or _tutorial == null:
		return
	if bool(_tutorial.call("is_completed")):
		return
	if int(GameManager.sacrifice_count) > 0:
		return
	if int(GameManager.monster_limb_count) <= 0:
		if _altar != null and _altar.has_method("show_no_limb"):
			_altar.call("show_no_limb")
		return
	_refuse()

func _refuse() -> void:
	_refusing = true
	if _altar != null and _altar.has_method("set_refuse_allowed"):
		_altar.call("set_refuse_allowed", false)
	if _tutorial != null:
		_tutorial.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := get_node_or_null("ObjectiveHUD")
	if hud != null:
		hud.visible = false
		if hud.has_method("hide_bubble"):
			hud.call("hide_bubble")
	_dialogue.call("play", "refuse_die")
	await EventBus.dialogue_finished
	if not is_inside_tree():
		return
	var fade := create_tween()
	fade.tween_property(_fade_rect, "modulate:a", 1.0, 0.65)
	await fade.finished
	if not is_inside_tree():
		return
	GameManager.set_flag("refuse_die")
	GameManager.set("state", GameManager.GameState.ENDING)
	EventBus.ending_reached.emit("refuse_die")
	EventBus.log_event("ending_reached", {"ending": "refuse_die", "sacrifice_count": GameManager.sacrifice_count})
	if _ending_screen == null:
		_ending_screen = ENDING_SCENE.instantiate() as CanvasLayer
		add_child(_ending_screen)
		_ending_screen.restart_requested.connect(_restart_from_refuse)
	_ending_screen.call("show_ending", "refuse_die")

func _restart_from_refuse() -> void:
	_refusing = false
	GameManager.start_new_game()
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func show_true_he() -> void:
	if _true_he_shown:
		return
	_true_he_shown = true
	GameManager.set("state", GameManager.GameState.ENDING)
	EventBus.ending_reached.emit("true_he")
	EventBus.log_event("ending_reached", {"ending": "true_he", "sacrifice_count": GameManager.sacrifice_count})
	if _ending_screen == null:
		_ending_screen = ENDING_SCENE.instantiate() as CanvasLayer
		add_child(_ending_screen)
		_ending_screen.restart_requested.connect(_restart_from_true_he)
	_ending_screen.call("show_ending", "true_he")

func _restart_from_true_he() -> void:
	_true_he_shown = false
	GameManager.start_new_game()
	get_tree().change_scene_to_file("res://scenes/world/test_arena.tscn")
