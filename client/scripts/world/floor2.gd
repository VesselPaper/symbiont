extends Node2D
## 第二层 · 铸炉与圣坛（M3-01）
##
## 第一层向上走就是这里：左边是工程师的锅炉房，右边是异教徒的圣坛廊。
## 两个人都在拉拢主角，但封印门只认一边——选定阵营才开。
##
## 地形仍然由 PLATFORMS 数据生成，改路线只改表，不在编辑器里拖平台。
## 剧情入口：进入时 floor2_enter；两个 NPC 各自 offer/confirm/after；层门 floor2_gate。

const PLATFORMS: Array[Dictionary] = [
	{"rect": Rect2(0, 620, 520, 100), "stone": 0.0},      # 入口货梯残骸
	{"rect": Rect2(620, 680, 360, 100), "stone": 0.18},   # 下沉通道
	{"rect": Rect2(1080, 640, 700, 120), "stone": 0.05},  # 中央铸炉厅（工程师）
	{"rect": Rect2(1880, 600, 760, 120), "stone": 0.28},  # 圣坛廊（祭司）
	{"rect": Rect2(2740, 640, 520, 120), "stone": 0.12},  # 下行回廊
	{"rect": Rect2(3360, 600, 500, 110), "stone": 0.2},   # 封印门前厅
	{"rect": Rect2(3960, 560, 320, 120), "stone": 0.08},  # 封印后第一段
	{"rect": Rect2(4380, 600, 320, 120), "stone": 0.24},  # 断阶下沉段
	{"rect": Rect2(4800, 560, 420, 120), "stone": 0.06},  # 第三层门前长阶
	{"rect": Rect2(-80, 300, 80, 900), "stone": 0.0},     # 左边界墙
	{"rect": Rect2(5220, 300, 80, 900), "stone": 0.0},    # 右边界墙
]

const SPAWN_POINT := Vector2(140, 560)
const SEAL_POS := Vector2(3910, 430)
const NPC_SCENE := preload("res://scenes/world/faction_npc.tscn")
const SEAL_SCENE := preload("res://scenes/world/faction_seal.tscn")
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const CAMPFIRE_SCENE := preload("res://scenes/world/campfire.tscn")
const SPORE_SHOOTER_SCENE := preload("res://scenes/entities/spore_shooter.tscn")
const INSPECT_SCENE := preload("res://scenes/world/inspect_point.tscn")
const STEAM_BOOTS_CHEST_SCENE := preload("res://scenes/items/steam_boots_chest.tscn")
const FLOOR2_NAME := "第二层 · 铸炉与圣坛"
const FLOOR3_SCENE := "res://scenes/world/floor3.tscn"
const FLOOR3_NAME := "第三层 · 守门者之厅"
const GAME_HUD_SCENE := preload("res://scenes/ui/game_hud.tscn")

const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

const STONE_COLOR := Color(0.185, 0.155, 0.135)
const STONE_DARK := Color(0.062, 0.052, 0.048)
const STONE_RIM := Color(0.475, 0.385, 0.265)

@onready var _dialogue: Node = $Dialogue
@onready var _player: Node2D = $Player
@onready var _camera: Camera2D = $Camera2D

var _player_ref: Node2D
var _played: Dictionary = {}
var _npcs: Array[Node] = []
var _seal: Node
var _faction := ""
var _toast: Label
var _want_floor3 := false
var _entering_floor3 := false
var _transition_layer: CanvasLayer
var _transition_rect: ColorRect
var _transition_label: Label

func _ready() -> void:
	GameManager.mark_floor_start("floor2")
	_build_campfire()
	_build_platforms()
	_build_props()
	_build_npcs()
	_build_seal()
	_build_triggers()
	_build_inspect_points()
	_build_floor3_entry()
	_build_kill_zone()
	_spawn_enemies()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_build_fade_in()
	_build_floor3_transition()
	_build_hud()
	SaveSystem.apply_pending_player(get_node("Player") as Node2D)
	_restore_faction()
	var timer := get_tree().create_timer(0.55)
	timer.timeout.connect(_play_intro)

func _process(_delta: float) -> void:
	# 走进层门后如果 floor2_gate 还在播，等台词念完再黑场
	if _want_floor3 and not _entering_floor3:
		if _dialogue != null and _dialogue.has_method("is_playing") and bool(_dialogue.call("is_playing")):
			return
		_enter_floor3()

func _play_intro() -> void:
	_play_once("intro", "floor2_enter")

func _play_once(key: String, dialogue_id: String) -> void:
	if _played.get(key, false):
		return
	_played[key] = true
	_dialogue.call("play", dialogue_id)

# ---------- 阵营 ----------

## 关卡脚本只负责状态落库和场景反馈；NPC 通过这个方法提交选择，不直接写 GameManager。
func choose_faction(faction: String) -> bool:
	if faction != "engineer" and faction != "heretic":
		return false
	if _faction != "":
		return false
	_faction = faction
	GameManager.faction = faction
	GameManager.set_flag("floor2_faction_chosen")
	GameManager.set_flag("floor2_faction_%s" % faction)
	GameManager.current_floor = "floor_2"
	for npc in _npcs:
		if is_instance_valid(npc) and npc.has_method("mark_choice"):
			npc.call("mark_choice", faction)
	if _seal != null and _seal.has_method("open"):
		_seal.call("open", faction)
		GameManager.play_sfx("gate")
	if _player_ref != null and _player_ref.has_method("apply_faction"):
		_player_ref.call("apply_faction", faction)
	var camera := get_tree().get_first_node_in_group("camera")
	if camera != null and camera.has_method("shake"):
		camera.call("shake", 4.5, 0.26)
	_show_toast("已选择 · %s" % ("工程师" if faction == "engineer" else "异教徒"))
	EventBus.log_event("faction_chosen", {"faction": faction})
	return true

func get_faction() -> String:
	return _faction

func is_faction_chosen() -> bool:
	return _faction != ""

## 读档/重生进第二层：门直接开，NPC 和玩家外观恢复，不重播选择演出。
func _restore_faction() -> void:
	var restored := str(GameManager.faction)
	if restored != "engineer" and restored != "heretic":
		return
	_faction = restored
	for npc in _npcs:
		if is_instance_valid(npc) and npc.has_method("mark_choice"):
			npc.call("mark_choice", restored)
	if _seal != null and _seal.has_method("open"):
		_seal.call("open", restored, true)
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("apply_faction"):
		player.call("apply_faction", restored)

func _build_npcs() -> void:
	var holder := Node2D.new()
	holder.name = "FactionNPCs"
	holder.z_index = 2
	add_child(holder)
	var specs: Array[Dictionary] = [
		{
			"name": "Engineer", "faction": "engineer", "display": "工程师",
			"offer": "floor2_engineer_offer", "confirm": "floor2_engineer_confirm",
			"after": "floor2_engineer_after", "pos": Vector2(1220, 637),
		},
		{
			"name": "HereticPriest", "faction": "heretic", "display": "祭司",
			"offer": "floor2_heretic_offer", "confirm": "floor2_heretic_confirm",
			"after": "floor2_heretic_after", "pos": Vector2(2250, 597),
		},
	]
	for spec in specs:
		var npc := NPC_SCENE.instantiate()
		npc.name = str(spec["name"])
		npc.set("faction", str(spec["faction"]))
		npc.set("display_name", str(spec["display"]))
		npc.set("offer_id", str(spec["offer"]))
		npc.set("confirm_id", str(spec["confirm"]))
		npc.set("after_id", str(spec["after"]))
		npc.set("controller", self)
		npc.position = spec["pos"]
		holder.add_child(npc)
		_npcs.append(npc)
	_player_ref = get_tree().get_first_node_in_group("player") as Node2D

func _build_seal() -> void:
	var holder := Node2D.new()
	holder.name = "Mechanisms"
	holder.z_index = 2
	add_child(holder)
	_seal = SEAL_SCENE.instantiate()
	_seal.name = "FactionSeal"
	_seal.position = SEAL_POS
	holder.add_child(_seal)

# ---------- 地形 ----------

func _build_platforms() -> void:
	var holder := Node2D.new()
	holder.name = "Terrain"
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
		if rect.size.x > 100.0:
			visual.polygon = _rock_silhouette(rect, i)
		else:
			visual.polygon = PackedVector2Array([
				Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
				Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
				Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
				Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
			])
		visual.color = STONE_COLOR.lightened(float(spec["stone"]) * 0.24)
		body.add_child(visual)
		var rim := Polygon2D.new()
		rim.name = "Rim"
		rim.polygon = PackedVector2Array([
			Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
			Vector2(rect.size.x * 0.5, -rect.size.y * 0.5 + 5),
			Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5 + 5),
		])
		rim.color = STONE_RIM
		body.add_child(rim)
		var shade := Polygon2D.new()
		var shade_h := minf(18.0, rect.size.y * 0.25)
		shade.polygon = PackedVector2Array([
			Vector2(-rect.size.x * 0.5, rect.size.y * 0.5 - shade_h),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5 - shade_h),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
			Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
		])
		shade.color = STONE_DARK
		body.add_child(shade)
		if rect.size.x >= 120.0:
			_add_platform_detail(body, rect, i)
		holder.add_child(body)

func _rock_silhouette(rect: Rect2, index: int) -> PackedVector2Array:
	var half := rect.size.x * 0.5
	var h := rect.size.y
	var top := -h * 0.5
	var bottom := h * 0.5
	var notch := 4.0 + float(index % 3) * 5.0
	return PackedVector2Array([
		Vector2(-half, top), Vector2(half, top),
		Vector2(half - 1.0, top + 9.0), Vector2(half + 4.0, top + 28.0),
		Vector2(half - notch, top + 52.0), Vector2(half - 2.0, top + 72.0),
		Vector2(half - 14.0, bottom - 8.0), Vector2(half - 34.0, bottom + 4.0),
		Vector2(6.0, bottom + 8.0), Vector2(-half + 28.0, bottom + 3.0),
		Vector2(-half + 6.0, bottom - 15.0), Vector2(-half - 3.0, top + 58.0),
		Vector2(-half + notch, top + 25.0),
	])

func _add_platform_detail(body: StaticBody2D, rect: Rect2, variant: int) -> void:
	var top := -rect.size.y * 0.5
	var bottom := rect.size.y * 0.5
	var half_w := rect.size.x * 0.5
	# 铸炉层的石缝是暖色，不是第一层的冷青苔；脚下要像被炉火烤过
	var seam_color := Color(0.055, 0.040, 0.034, 0.6)
	var x := 70.0
	var step := maxf(82.0, rect.size.x / 6.0)
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
	# 铜绿/煤灰斑：两块不同色的小块，不是整齐苔痕
	for sx in [-half_w + 12.0, half_w - 30.0]:
		var stain := Polygon2D.new()
		stain.color = Color(0.22, 0.18, 0.10, 0.42) if variant % 2 == 0 else Color(0.12, 0.16, 0.14, 0.4)
		stain.polygon = PackedVector2Array([
			Vector2(sx, top + 5.0), Vector2(sx + 22.0, top + 5.0),
			Vector2(sx + 16.0, top + 12.0), Vector2(sx + 4.0, top + 14.0),
		])
		body.add_child(stain)
	for k in range(2):
		var sx := -half_w + rect.size.x * (0.2 + 0.36 * k)
		var support := Polygon2D.new()
		support.color = STONE_DARK.lightened(0.03 + 0.03 * k)
		support.polygon = PackedVector2Array([
			Vector2(sx, top + 42.0), Vector2(sx + 40.0, top + 50.0),
			Vector2(sx + 31.0, bottom + 16.0), Vector2(sx + 4.0, bottom + 8.0),
		])
		body.add_child(support)
	var crack := Line2D.new()
	crack.width = 1.1
	crack.default_color = Color(0.02, 0.018, 0.015, 0.7)
	crack.points = PackedVector2Array([
		Vector2(-half_w + 32.0 + variant * 9.0, top + 8.0),
		Vector2(-half_w + 44.0 + variant * 9.0, top + 26.0),
		Vector2(-half_w + 39.0 + variant * 9.0, top + 46.0),
	])
	body.add_child(crack)
	for i in range(2):
		var rock := Polygon2D.new()
		rock.color = STONE_RIM.darkened(0.32)
		var rx := -half_w + rect.size.x * (0.34 + 0.26 * i)
		var rw := 10.0 + 5.0 * i
		rock.polygon = PackedVector2Array([
			Vector2(rx, top + 1.0), Vector2(rx + rw, top - 3.0),
			Vector2(rx + rw + 6.0, top + 4.0), Vector2(rx + 3.0, top + 5.0),
		])
		body.add_child(rock)

# ---------- 场景物件 ----------

func _build_props() -> void:
	var props := Node2D.new()
	props.name = "Props"
	props.z_index = -1
	add_child(props)
	_build_entry_lift(props)
	_build_forge(props)
	_build_boots_chest(props)
	_build_chapel(props)
	_build_seal_corridor(props)
	_build_gate(props)
	_add_light(props, Vector2(1260, 560), Color(1.0, 0.62, 0.28), 0.9, 2.4)
	_add_light(props, Vector2(2260, 520), Color(0.62, 0.40, 0.92), 0.75, 2.5)
	_add_light(props, Vector2(4870, 520), Color(0.50, 0.76, 0.78), 0.50, 2.0)

## M4-09：封印门原先离第三层门只有 250px，走过去太快。这里把后段拉到 900px，
## 用断阶 + 断柱 + 冷雾把“选完阵营后走向终点”的路撑起来，不挡路、不加敌人。
## 篝火：圣坛廊中段（地图中部），见完两个 NPC 之后能歇一次
func _build_campfire() -> void:
	var fire := CAMPFIRE_SCENE.instantiate()
	fire.name = "Campfire"
	fire.position = Vector2(2500, 600)
	add_child(fire)

func _build_seal_corridor(parent: Node) -> void:
	for spec in [
		{"x": 4330.0, "base": 560.0, "height": 120.0, "tilt": -0.05, "cap": true},
		{"x": 4530.0, "base": 600.0, "height": 170.0, "tilt": 0.08, "cap": false},
		{"x": 4930.0, "base": 560.0, "height": 138.0, "tilt": -0.10, "cap": true},
	]:
		var column := Node2D.new()
		column.position = Vector2(spec["x"], spec["base"])
		column.rotation = spec["tilt"]
		parent.add_child(column)
		var shaft := Polygon2D.new()
		var h: float = spec["height"]
		shaft.color = Color(0.145, 0.142, 0.132)
		shaft.polygon = PackedVector2Array([
			Vector2(-15, 0), Vector2(15, 0), Vector2(12, -h), Vector2(-10, -h + 4),
		])
		column.add_child(shaft)
		# 断口不是平切：留一块参差的缺口，避免又变成一根直筒
		var break_line := Line2D.new()
		break_line.width = 2.2
		break_line.default_color = Color(0.38, 0.36, 0.30, 0.85)
		break_line.points = PackedVector2Array([
			Vector2(-11, -h + 4), Vector2(-3, -h + 12), Vector2(4, -h + 1), Vector2(12, -h + 7),
		])
		column.add_child(break_line)
		if spec["cap"]:
			var cap := Polygon2D.new()
			cap.color = Color(0.19, 0.18, 0.16)
			cap.position = Vector2(0, -h + 4)
			cap.polygon = PackedVector2Array([
				Vector2(-22, 0), Vector2(22, 0), Vector2(17, -12), Vector2(-18, -10),
			])
			column.add_child(cap)
		for i in range(3):
			var rubble := Polygon2D.new()
			rubble.color = Color(0.13, 0.125, 0.115)
			rubble.polygon = PackedVector2Array([
				Vector2(-8, 0), Vector2(8, -3), Vector2(13, 2), Vector2(-3, 5),
			])
			rubble.position = Vector2(-34.0 + i * 29.0, 2.0 + (i % 2) * 3.0)
			parent.add_child(rubble)
	# 冷雾：低低地铺在断阶上，和封印门的青色接上
	var mist := Polygon2D.new()
	mist.color = Color(0.30, 0.44, 0.42, 0.13)
	mist.position = Vector2(4620, 584)
	mist.polygon = _ring_points(1.0, 18)
	mist.scale = Vector2(190, 26)
	parent.add_child(mist)
	_add_light(parent, Vector2(4620, 548), Color(0.50, 0.80, 0.78), 0.42, 1.9)

## 入口是一台废弃货梯：告诉玩家“你是从下面上来的”，不是凭空站在走廊里。
func _build_entry_lift(parent: Node) -> void:
	for spec in [
		{"x": 190.0, "end_y": 360.0, "width": 3.0},
		{"x": 370.0, "end_y": 470.0, "width": 2.0},
	]:
		var chain := Line2D.new()
		chain.width = spec["width"]
		chain.default_color = Color(0.070, 0.062, 0.055)
		chain.points = PackedVector2Array([
			Vector2(spec["x"], -260.0),
			Vector2(spec["x"] + 8.0, 100.0),
			Vector2(spec["x"] + 2.0, spec["end_y"]),
		])
		parent.add_child(chain)
	var cage := Node2D.new()
	cage.name = "CargoCage"
	cage.position = Vector2(280, 620)
	parent.add_child(cage)
	# 歪掉的货梯底板：斜插在入口平台上，作为“上一层的出口”
	var deck := Polygon2D.new()
	deck.color = Color(0.16, 0.14, 0.12)
	deck.rotation = 0.06
	deck.polygon = PackedVector2Array([
		Vector2(-70, -5), Vector2(72, -9), Vector2(78, 2), Vector2(-64, 4),
	])
	cage.add_child(deck)
	for dx in [-68.0, 66.0]:
		var post := Polygon2D.new()
		post.color = Color(0.12, 0.105, 0.09)
		post.polygon = PackedVector2Array([
			Vector2(dx - 5, -6), Vector2(dx + 5, -7), Vector2(dx + 7, -98), Vector2(dx - 4, -96),
		])
		cage.add_child(post)
	var cage_rim := Line2D.new()
	cage_rim.width = 1.4
	cage_rim.default_color = Color(0.32, 0.26, 0.18, 0.7)
	cage_rim.points = PackedVector2Array([Vector2(-70, -4), Vector2(72, -8)])
	cage.add_child(cage_rim)
	# 货梯后面的冷光，和第一层层门的冷色接上
	var glow := Sprite2D.new()
	glow.texture = _radial_texture()
	glow.modulate = Color(0.45, 0.75, 0.76, 0.25)
	glow.scale = Vector2(1.5, 1.1)
	glow.position = Vector2(280, 500)
	parent.add_child(glow)

func _build_forge(parent: Node) -> void:
	# 主锅炉：横卧的铜绿色圆筒 + 烟囱 + 压力表，工程师就在它前面
	var boiler := Node2D.new()
	boiler.name = "Boiler"
	boiler.position = Vector2(1510, 640)
	parent.add_child(boiler)
	var shell := Polygon2D.new()
	shell.color = Color(0.22, 0.20, 0.16)
	shell.polygon = PackedVector2Array([
		Vector2(-128, -8), Vector2(-120, -80), Vector2(-90, -116),
		Vector2(80, -116), Vector2(118, -82), Vector2(128, -8),
		Vector2(100, 3), Vector2(-100, 3),
	])
	boiler.add_child(shell)
	var belly := Polygon2D.new()
	belly.color = Color(0.31, 0.24, 0.15)
	belly.polygon = PackedVector2Array([
		Vector2(-112, -18), Vector2(-100, -94), Vector2(80, -94),
		Vector2(108, -18), Vector2(88, -8), Vector2(-90, -8),
	])
	boiler.add_child(belly)
	for dx in [-80.0, -40.0, 0.0, 40.0, 80.0]:
		var rivet := Line2D.new()
		rivet.width = 2.0
		rivet.default_color = Color(0.14, 0.12, 0.09, 0.9)
		rivet.points = PackedVector2Array([Vector2(dx, -88), Vector2(dx, -16)])
		boiler.add_child(rivet)
	var gauge := Polygon2D.new()
	gauge.color = Color(0.78, 0.64, 0.36)
	gauge.position = Vector2(0, -58)
	gauge.polygon = _ring_points(13.0, 16)
	boiler.add_child(gauge)
	var gauge_core := Polygon2D.new()
	gauge_core.color = Color(0.12, 0.10, 0.08)
	gauge_core.position = Vector2(0, -58)
	gauge_core.polygon = _ring_points(9.0, 16)
	boiler.add_child(gauge_core)
	var needle := Line2D.new()
	needle.width = 1.6
	needle.default_color = Color(0.95, 0.55, 0.25)
	needle.points = PackedVector2Array([Vector2(0, -58), Vector2(7, -66)])
	boiler.add_child(needle)
	var chimney := Polygon2D.new()
	chimney.color = Color(0.14, 0.12, 0.10)
	chimney.polygon = PackedVector2Array([
		Vector2(54, -112), Vector2(86, -112), Vector2(80, -196), Vector2(58, -196),
	])
	boiler.add_child(chimney)
	var smoke := CPUParticles2D.new()
	smoke.amount = 18
	smoke.lifetime = 3.6
	smoke.preprocess = 1.2
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	smoke.emission_rect_extents = Vector2(12, 4)
	smoke.direction = Vector2(0, -1)
	smoke.spread = 24.0
	smoke.gravity = Vector2(8, -16)
	smoke.initial_velocity_min = 8.0
	smoke.initial_velocity_max = 18.0
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 3.0
	smoke.color = Color(0.38, 0.34, 0.30, 0.22)
	smoke.position = Vector2(68, -205)
	smoke.texture = _dot_texture()
	boiler.add_child(smoke)
	# 从锅炉伸向天花板的蒸汽管，沿着背景横向排开
	for spec in [
		{"x": 1580.0, "y": -60.0, "end_y": -250.0},
		{"x": 1700.0, "y": -30.0, "end_y": -250.0},
		{"x": 1120.0, "y": -40.0, "end_y": -250.0},
	]:
		var pipe := Line2D.new()
		pipe.width = 7.0
		pipe.default_color = Color(0.20, 0.17, 0.13, 0.95)
		pipe.points = PackedVector2Array([
			Vector2(spec["x"], spec["y"]),
			Vector2(spec["x"] + 14.0, spec["y"] - 52.0),
			Vector2(spec["x"] + 14.0, spec["end_y"]),
		])
		parent.add_child(pipe)
		var pipe_rim := Line2D.new()
		pipe_rim.width = 1.2
		pipe_rim.default_color = Color(0.44, 0.34, 0.20, 0.6)
		pipe_rim.points = pipe.points
		parent.add_child(pipe_rim)
	# 工程师工作台：桌面上散着齿轮、扳手和油灯
	# 组长反馈：整张桌子看起来浮在空中 —— 原来桌面 42px 比人还高、腿又细又短。
	# 现在桌面压到 32px、腿加粗到 12px 宽并插进地面 2px，读起来才是一张落地的长桌。
	var bench := Node2D.new()
	bench.name = "Workbench"
	bench.position = Vector2(1090, 642)
	parent.add_child(bench)
	var top := Polygon2D.new()
	top.color = Color(0.28, 0.21, 0.14)
	top.polygon = PackedVector2Array([
		Vector2(-70, -32), Vector2(70, -32), Vector2(64, -24), Vector2(-64, -24),
	])
	bench.add_child(top)
	for dx in [-54.0, 48.0]:
		var leg := Polygon2D.new()
		leg.color = Color(0.16, 0.13, 0.10)
		leg.polygon = PackedVector2Array([
			Vector2(dx - 6, -26), Vector2(dx + 6, -26), Vector2(dx + 8, 2), Vector2(dx - 8, 2),
		])
		bench.add_child(leg)
	for i in range(3):
		var gear := Line2D.new()
		gear.width = 1.6
		gear.default_color = Color(0.56, 0.46, 0.28, 0.85)
		var pts := PackedVector2Array()
		for k in range(8):
			var a := TAU * float(k) / 8.0
			pts.append(Vector2(-30.0 + i * 27.0 + cos(a) * 7.0, -36.0 + sin(a) * 7.0))
		gear.points = pts
		bench.add_child(gear)
	# 吊在锅炉上方的齿轮组，工厂的“骨架”
	for i in range(2):
		var wheel := Line2D.new()
		wheel.width = 3.0
		wheel.default_color = Color(0.34, 0.28, 0.18, 0.8)
		var cx := 1660.0 + i * 68.0
		var pts := PackedVector2Array()
		for k in range(13):
			var a := TAU * float(k) / 12.0
			pts.append(Vector2(cx + cos(a) * (26.0 + i * 8.0), 430.0 + sin(a) * (26.0 + i * 8.0)))
		wheel.points = pts
		parent.add_child(wheel)

## 蒸汽靴宝箱：剧情上这双靴子是工程师给的，所以从教学关挪到锅炉房、工作台右侧。
## 箱身多边形底边在 y=+4，压到地面顶 640 上正好落地。
func _build_boots_chest(parent: Node) -> void:
	var chest := STEAM_BOOTS_CHEST_SCENE.instantiate()
	chest.name = "SteamBootsChest"
	chest.position = Vector2(1330, 640)
	parent.add_child(chest)

## 圣坛廊：尖拱、垂布、蜡烛和骨堆，颜色从锅炉的铜色慢慢过渡到紫色。
func _build_chapel(parent: Node) -> void:
	for i in range(3):
		var x := 1960.0 + i * 230.0
		# 尖拱框：左右两根柱 + 一个三角形拱顶
		for dx in [0.0, 92.0]:
			var col := Polygon2D.new()
			col.color = Color(0.095, 0.075, 0.105)
			col.polygon = PackedVector2Array([
				Vector2(x + dx, 600), Vector2(x + dx, 360),
				Vector2(x + dx + 14, 346), Vector2(x + dx + 14, 600),
			])
			parent.add_child(col)
		var arch := Polygon2D.new()
		arch.color = Color(0.10, 0.075, 0.12)
		arch.polygon = PackedVector2Array([
			Vector2(x, 362), Vector2(x + 53, 288), Vector2(x + 106, 362),
			Vector2(x + 94, 362), Vector2(x + 53, 310), Vector2(x + 12, 362),
		])
		parent.add_child(arch)
		var arch_rim := Line2D.new()
		arch_rim.width = 1.4
		arch_rim.default_color = Color(0.30, 0.22, 0.38, 0.7)
		arch_rim.points = PackedVector2Array([
			Vector2(x + 12, 360), Vector2(x + 53, 300), Vector2(x + 94, 360),
		])
		parent.add_child(arch_rim)
		# 垂布：暗紫，长短不一
		var cloth := Polygon2D.new()
		cloth.color = Color(0.18, 0.08, 0.22, 0.85)
		var length := 150.0 - i * 28.0
		cloth.polygon = PackedVector2Array([
			Vector2(x + 18, 330), Vector2(x + 88, 336),
			Vector2(x + 82, 330 + length), Vector2(x + 66, 318 + length),
			Vector2(x + 50, 336 + length), Vector2(x + 30, 322 + length),
		])
		parent.add_child(cloth)
	# 圣坛台阶与骨堆
	var dais := Node2D.new()
	dais.name = "HereticDais"
	dais.position = Vector2(2310, 600)
	parent.add_child(dais)
	for i in range(3):
		var step := Polygon2D.new()
		step.color = Color(0.15, 0.12, 0.16).lightened(0.04 * i)
		var w := 120.0 - i * 22.0
		step.polygon = PackedVector2Array([
			Vector2(-w, 0), Vector2(w, 0), Vector2(w - 6, -12), Vector2(-w + 6, -12),
		])
		step.position = Vector2(0, -i * 8.0)
		dais.add_child(step)
	for i in range(9):
		var bone := Line2D.new()
		bone.width = 1.8
		bone.default_color = Color(0.55, 0.52, 0.44, 0.7)
		var bx := -80.0 + (i % 4) * 23.0
		var by := -8.0 - float(i / 4) * 5.0
		bone.points = PackedVector2Array([
			Vector2(bx, by), Vector2(bx + 12.0, by - 7.0), Vector2(bx + 20.0, by + 1.0),
		])
		dais.add_child(bone)
	# 一排蜡烛，火焰用一点暖紫，和第一层的橙色烛火区分
	for i in range(5):
		var cx := 2130.0 + i * 50.0
		var candle := Polygon2D.new()
		candle.color = Color(0.48, 0.41, 0.34)
		candle.polygon = PackedVector2Array([
			Vector2(cx - 3, 598), Vector2(cx + 3, 598), Vector2(cx + 2, 574), Vector2(cx - 2, 574),
		])
		parent.add_child(candle)
		var flame := Polygon2D.new()
		flame.color = Color(0.92, 0.58, 1.0, 0.9)
		flame.polygon = PackedVector2Array([
			Vector2(cx - 2, 574), Vector2(cx, 564), Vector2(cx + 2, 574),
		])
		parent.add_child(flame)

func _build_gate(parent: Node) -> void:
	var gate := Node2D.new()
	gate.name = "GateFrame"
	gate.position = Vector2(5070, 560)
	parent.add_child(gate)
	for dx in [-58.0, 58.0]:
		var post := Polygon2D.new()
		post.color = Color(0.095, 0.095, 0.105)
		post.polygon = PackedVector2Array([
			Vector2(dx - 16, -190), Vector2(dx + 16, -190), Vector2(dx + 16, 0), Vector2(dx - 16, 0),
		])
		gate.add_child(post)
	var lintel := Polygon2D.new()
	lintel.color = Color(0.105, 0.108, 0.120)
	lintel.polygon = PackedVector2Array([
		Vector2(-84, -210), Vector2(84, -210), Vector2(84, -180), Vector2(-84, -180),
	])
	gate.add_child(lintel)
	var seam := Line2D.new()
	seam.width = 6.0
	seam.default_color = Color(0.50, 0.78, 0.78, 0.55)
	seam.points = PackedVector2Array([Vector2(0, -178), Vector2(0, -6)])
	gate.add_child(seam)
	var label := Label.new()
	label.text = "第三层"
	label.position = Vector2(-40, -238)
	label.size = Vector2(80, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.50, 0.72, 0.74, 0.75))
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	gate.add_child(label)

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

func _dot_texture() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			var d := Vector2(x - 1.5, y - 1.5).length() / 2.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _ring_points(radius: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts

# ---------- 触发器 / 调查 ----------

func _build_triggers() -> void:
	var holder := Node2D.new()
	holder.name = "Triggers"
	add_child(holder)
	# 层门前只播一次剧情；封印门没开之前玩家走不到这里
	_add_trigger(holder, "GateTrigger", Rect2(4900, 430, 160, 130), "gate", "floor2_gate")

func _add_trigger(parent: Node, node_name: String, rect: Rect2, key: String, dialogue_id: String) -> void:
	var area := Area2D.new()
	area.name = node_name
	area.collision_layer = 0
	area.collision_mask = 2
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
	var holder := Node2D.new()
	holder.name = "InspectPoints"
	holder.z_index = 4
	add_child(holder)
	var point := INSPECT_SCENE.instantiate()
	point.name = "GateInspect"
	point.position = Vector2(4085, 506)
	point.set("dialogue_id", "floor2_gate")
	point.set("prompt_text", "层门")
	point.set("dialogue_path", NodePath("../../Dialogue"))
	holder.add_child(point)

func _build_kill_zone() -> void:
	var area := Area2D.new()
	area.name = "KillZone"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(2200, 1240)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4500, 200)
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
	for spec in [
		{"name": "Slime1", "pos": Vector2(1660, 628)},
		{"name": "Slime2", "pos": Vector2(2920, 628)},
		# 组长反馈后半程空：下行回廊、封印后两段断阶各补一只，避开 4900 的层门触发器
		{"name": "Slime3", "pos": Vector2(3150, 626)},
		{"name": "Slime4", "pos": Vector2(4100, 546)},
		{"name": "Slime5", "pos": Vector2(4520, 586)},
		{"name": "SporeShooter", "pos": Vector2(3520, 590)},
	]:
		var scene := SLIME_SCENE if str(spec["name"]).begins_with("Slime") else SPORE_SHOOTER_SCENE
		var enemy := scene.instantiate()
		enemy.name = str(spec["name"])
		enemy.position = spec["pos"]
		holder.add_child(enemy)

# ---------- 提示 / 转场 ----------

func _show_toast(text: String) -> void:
	if _toast != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "Notice"
	layer.layer = 3
	add_child(layer)
	_toast = Label.new()
	_toast.text = text
	_toast.modulate = Color(0.82, 0.78, 0.66, 0.0)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 20)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		_toast.add_theme_font_override("font", font)
	layer.add_child(_toast)
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 0.95, 0.35)
	tween.tween_interval(2.2)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.9)
	tween.tween_callback(layer.queue_free)

## 第三层入口：层门框中间的门缝判定，右侧边界墙前留出 70px 站脚。
func _build_floor3_entry() -> void:
	var area := Area2D.new()
	area.name = "Floor3Entry"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(5122, 500)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(62, 190)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player"):
			_want_floor3 = true
	)
	add_child(area)

func _build_floor3_transition() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "Floor3Transition"
	_transition_layer.layer = 4
	add_child(_transition_layer)
	_transition_rect = ColorRect.new()
	_transition_rect.color = Color(0.012, 0.012, 0.014, 1.0)
	_transition_rect.modulate = Color(1, 1, 1, 0.0)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_layer.add_child(_transition_rect)
	_transition_label = Label.new()
	_transition_label.text = FLOOR3_NAME
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transition_label.modulate = Color(0.78, 0.78, 0.72, 0.0)
	_transition_label.add_theme_font_size_override("font_size", 22)
	_transition_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_transition_label.position = Vector2(-190, -20)
	_transition_label.size = Vector2(380, 40)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		_transition_label.add_theme_font_override("font", font)
	_transition_layer.add_child(_transition_label)

func _enter_floor3() -> void:
	if _entering_floor3:
		return
	_entering_floor3 = true
	GameManager.set_flag("floor3_unlocked")
	GameManager.current_floor = "floor_3"
	EventBus.player_moved_between_floors.emit("floor3")
	if _transition_rect != null:
		var tween := create_tween()
		tween.tween_property(_transition_rect, "modulate:a", 1.0, 0.50)
		tween.parallel().tween_property(_transition_label, "modulate:a", 0.9, 0.35)
		tween.tween_interval(0.28)
		tween.tween_callback(_change_to_floor3)
	else:
		get_tree().call_deferred("change_scene_to_file", FLOOR3_SCENE)

func _change_to_floor3() -> void:
	get_tree().change_scene_to_file(FLOOR3_SCENE)

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
	rect.color = Color(0.018, 0.014, 0.012, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var label := Label.new()
	label.text = FLOOR2_NAME
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.88, 0.74, 0.56, 0.0)
	label.add_theme_font_size_override("font_size", 22)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position = Vector2(-180, -20)
	label.size = Vector2(360, 40)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	layer.add_child(label)
	var tween := create_tween()
	tween.tween_interval(0.10)
	tween.tween_property(rect, "color:a", 0.0, 0.55)
	tween.parallel().tween_property(label, "modulate:a", 0.65, 0.28)
	tween.tween_property(label, "modulate:a", 0.0, 0.35)
	tween.tween_callback(layer.queue_free)
