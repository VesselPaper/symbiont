extends Node2D
## 测试竞技场（M1-01 / M1-12 布局重排）
##
## 平地 + 左右边界墙 + 教学关布局（M1-12 定稿）：
##   地面(顶660) → 第一平台 JumpPlatform(560-860, 顶570，尸体+剑+假人甲)
##   → 假人乙小台(900-960, 顶≈520，下劈反弹目标) → 第二平台 PogoPlatform(1000-1250, 顶440)
##   → 台阶 Step1(1250-1350, 顶410) → 祭坛平台 AltarPlatform(1350-1700, 顶380，祭坛+史莱姆战斗区)
## 玩家出生在左侧，用于验证移动 → 跳跃 → 拿剑 → 攻击 → 下劈跳高 → 战斗 → 献祭的
## 完整教学闭环。真正的楼层场景在 M2 制作。
## M1-03：挂载对话 UI（DialogueBox，CanvasLayer 子节点保证 UI 在顶层）和对话
## 组件（Dialogue），场景稳定后自动弹出开场寄生体低语（intro_parasite_1 链）。

## 开场对话延迟（秒）：等场景 / 玩家 / 相机稳定后再弹出
const INTRO_DIALOGUE_DELAY := 0.5
## 开场对话 id（台词内容一律从 DataDB 读，这里只指定入口 id）
const INTRO_DIALOGUE_ID := "intro_parasite_1"

## 教程结束后开放的下一层门（同一地图右侧，地图边界墙前面）
const FLOOR1_SCENE := "res://scenes/world/floor1.tscn"
const NEXT_FLOOR_DOOR_POS := Vector2(2460, 659)
## 演示快捷键：跳过教程直接进第一层（老师/组长试玩来不及打完整套教学时用）
const DEBUG_SKIP_KEY := KEY_F2

## 史莱姆场景与出生点：对话/教程前期场景无敌人（避免教学时被攻击的矛盾），
## 教程进入"战斗"步骤时由 spawn_enemies() 生成（M1-08 修正）。
## M1-13：AltarPlatform 移到最右侧(x2045~2395, 顶572)，史莱姆直接站在祭坛平台上（站 y≈559）
## M1-14：史莱姆生成在祭坛前面的坑区（PitFloor 顶 587，比祭坛平台 572 低 15px ≈ 半角色高）
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const SLIME_SPAWN_POINTS := [Vector2(1830, 574), Vector2(1960, 574)]

# ---- 摄像机（M1-09）----
## 垂直视野 = 角色身高的 N 倍（改这里即可调远近）；角色视觉身高 28px（见 player.gd CHARACTER_HEIGHT）
const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
## zoom = 视口高(720) ÷ (N×28)。N=12 → 336px 垂直视野 → zoom ≈ 2.14
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

@onready var _tutorial: Node = $Tutorial

var _door_root: Node2D
var _door_seam: Line2D
var _door_glow: Sprite2D
var _door_open := false
var _entering := false

func _ready() -> void:
	# 相机 zoom 由这里设置（垂直视野 = N 倍角色身高）；水平跟随/垂直死区由 camera_follow.gd 处理
	var camera := $Camera2D as Camera2D
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)

	# 下一层的门：先立着，教程完成后才亮、才能进（软隔离，和教学关一个思路）
	_build_next_floor_door()

	# M1-03：延时播放开场寄生体低语，让场景先稳定（玩家出生 → 低语弹出）
	var intro_timer := get_tree().create_timer(INTRO_DIALOGUE_DELAY)
	intro_timer.timeout.connect(_play_intro_dialogue)

func _process(_delta: float) -> void:
	# 教程跑完（献祭完成）就把门点亮；之后玩家走进门即切到第一层
	if not _door_open and _tutorial != null and _tutorial.has_method("is_completed"):
		if bool(_tutorial.call("is_completed")):
			_open_door()

func _unhandled_input(event: InputEvent) -> void:
	# 反向测试（规范第 6 条）：只认 F2 的按下沿，其它键、抬起、长按 echo 都不触发
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if key.keycode == DEBUG_SKIP_KEY:
		_enter_floor1()

# ---------- 下一层的门 ----------

func _build_next_floor_door() -> void:
	_door_root = Node2D.new()
	_door_root.name = "NextFloorDoor"
	_door_root.position = NEXT_FLOOR_DOOR_POS
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
	EventBus.log_event("floor_gate_open", {"floor": "floor1"})

func _enter_floor1() -> void:
	if _entering:
		return
	_entering = true
	GameManager.set_flag("floor1_unlocked")
	EventBus.player_moved_between_floors.emit("floor1")
	# 场景切换必须延后：现在可能正在物理回调/输入回调里，立刻换场景会中断查询
	get_tree().call_deferred("change_scene_to_file", FLOOR1_SCENE)

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
	for i in range(SLIME_SPAWN_POINTS.size()):
		var slime := SLIME_SCENE.instantiate()
		slime.position = SLIME_SPAWN_POINTS[i]
		slime.name = "Slime%d" % (i + 1)
		add_child(slime)

func _play_intro_dialogue() -> void:
	# Dialogue 是挂 dialogue.gd 组件的普通 Node，用 call() 动态调用，
	# 避免静态类型检查把 play() 当作 Node 上不存在的方法报错
	var dialogue := get_node_or_null("Dialogue")
	if dialogue != null and dialogue.has_method("play"):
		dialogue.call("play", INTRO_DIALOGUE_ID)
