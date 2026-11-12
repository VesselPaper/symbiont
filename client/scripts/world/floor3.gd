extends Node2D
## 第三层 · 守门者之厅（M3-02）
##
## 路线：入口断梯 → 骑士像廊 → 上行台阶 → 守门者之厅。
## 厅里只有一个守门者，出口门在它死前锁着；死后走进门结算结局。
##
## 结局判定只看 GameManager.sacrifice_count：只做过新手那次（==1）走人类，
## 多献祭一次以上走异化；结局名/说明从 DataDB 的 endings 表读。

const PLATFORMS: Array[Dictionary] = [
	{"rect": Rect2(0, 620, 520, 110), "stone": 0.0},      # 入口断梯
	{"rect": Rect2(620, 660, 360, 110), "stone": 0.18},   # 下沉通道
	{"rect": Rect2(1060, 600, 560, 120), "stone": 0.05},  # 骑士像廊
	{"rect": Rect2(1700, 640, 380, 120), "stone": 0.22},  # 下行台阶
	{"rect": Rect2(2200, 620, 500, 120), "stone": 0.16},  # 断兵回廊（M4-09）
	{"rect": Rect2(2800, 600, 1400, 130), "stone": 0.10}, # 守门者之厅
	{"rect": Rect2(-80, 300, 80, 900), "stone": 0.0},     # 左边界墙
	{"rect": Rect2(4200, 300, 80, 900), "stone": 0.0},    # 右边界墙
]
const SPAWN_POINT := Vector2(140, 560)
const BOSS_SCENE := preload("res://scenes/entities/gatekeeper_boss.tscn")
const EXIT_SCENE := preload("res://scenes/world/boss_exit_door.tscn")
const SHAFT_SCENE := preload("res://scenes/world/return_shaft.tscn")
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const SPORE_SHOOTER_SCENE := preload("res://scenes/entities/spore_shooter.tscn")
const ENDING_SCENE := preload("res://scenes/ui/ending_screen.tscn")
const GAME_HUD_SCENE := preload("res://scenes/ui/game_hud.tscn")
const TEST_ARENA := "res://scenes/world/test_arena.tscn"
const FLOOR3_NAME := "第三层 · 守门者之厅"

const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

const STONE_COLOR := Color(0.155, 0.155, 0.160)
const STONE_DARK := Color(0.045, 0.045, 0.052)
const STONE_RIM := Color(0.390, 0.410, 0.400)

@onready var _dialogue: Node = $Dialogue
@onready var _camera: Camera2D = $Camera2D
@onready var _player: Node2D = $Player

var _played: Dictionary = {}
var _boss: Node
var _exit_door: StaticBody2D
var _return_shaft: Area2D
var _returning := false
var _boss_started := false
var _boss_hud: CanvasLayer
var _boss_bar: ProgressBar
var _boss_name: Label
var _want_ending := false
var _ending_lock := false
var _ending_active := false
var _ending_screen: CanvasLayer

func _ready() -> void:
	_build_platforms()
	_build_props()
	_build_exit_door()
	_build_return_shaft()
	_build_boss()
	_build_triggers()
	_build_kill_zone()
	_spawn_enemies()
	_build_boss_hud()
	_build_fade_in()
	_build_hud()
	SaveSystem.apply_pending_player(_player)
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	GameManager.current_floor = "floor_3"
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.player_died.connect(_on_player_died)
	var timer := get_tree().create_timer(0.55)
	timer.timeout.connect(_play_intro)

func _process(_delta: float) -> void:
	if _ending_active or _returning:
		return
	_update_boss_hud()
	# 玩家已经碰到出口，但 Boss 临死前的话还没念完：等念完再出结局
	if _want_ending and not _ending_active and not _ending_lock:
		if _dialogue != null and _dialogue.has_method("is_playing") and bool(_dialogue.call("is_playing")):
			return
		_show_ending()

func _on_dialogue_finished(dialogue_id: String) -> void:
	if dialogue_id == "floor3_boss_intro" and _boss != null and not bool(_boss.call("is_dead")):
		_boss.call("activate")
		_boss_started = true
	elif dialogue_id == "floor3_after_boss":
		# 最后一段低语念完才允许结算；玩家可以先站在门口等
		_ending_lock = false

func _on_player_died() -> void:
	# Boss 死后、最后一段低语没念完就摔死：复活后门已经开着，不能把结算永久锁死
	_ending_lock = false
	_want_ending = false

func _play_intro() -> void:
	_play_once("intro", "floor3_enter")

func _play_once(key: String, dialogue_id: String) -> void:
	if _played.get(key, false):
		return
	_played[key] = true
	_dialogue.call("play", dialogue_id)

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
		if rect.size.x > 100.0:
			visual.polygon = _rock_silhouette(rect, i)
		else:
			visual.polygon = PackedVector2Array([
				Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
				Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
				Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
				Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
			])
		visual.color = STONE_COLOR.lightened(float(spec["stone"]) * 0.22)
		body.add_child(visual)
		var rim := Polygon2D.new()
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
	var notch := 4.0 + float(index % 3) * 4.0
	return PackedVector2Array([
		Vector2(-half, top), Vector2(half, top),
		Vector2(half - 1.0, top + 9.0), Vector2(half + 3.0, top + 26.0),
		Vector2(half - notch, top + 50.0), Vector2(half - 2.0, top + 70.0),
		Vector2(half - 15.0, bottom - 8.0), Vector2(half - 33.0, bottom + 4.0),
		Vector2(8.0, bottom + 8.0), Vector2(-half + 28.0, bottom + 3.0),
		Vector2(-half + 6.0, bottom - 15.0), Vector2(-half - 4.0, top + 58.0),
		Vector2(-half + notch, top + 24.0),
	])

func _add_platform_detail(body: StaticBody2D, rect: Rect2, variant: int) -> void:
	var top := -rect.size.y * 0.5
	var bottom := rect.size.y * 0.5
	var half_w := rect.size.x * 0.5
	var seam_color := Color(0.028, 0.030, 0.034, 0.65)
	var x := 70.0
	var step := maxf(84.0, rect.size.x / 6.0)
	while x < rect.size.x - 50.0:
		var seam := Line2D.new()
		seam.width = 1.4
		seam.default_color = seam_color
		seam.points = PackedVector2Array([
			Vector2(-half_w + x, top + 7.0),
			Vector2(-half_w + x + 4.0, top + 18.0),
		])
		body.add_child(seam)
		x += step
	# 烬痕：Boss 厅被火烧过，顶角有暗红焦斑
	for sx in [-half_w + 12.0, half_w - 30.0]:
		var scorch := Polygon2D.new()
		scorch.color = Color(0.22, 0.075, 0.045, 0.36)
		scorch.polygon = PackedVector2Array([
			Vector2(sx, top + 5.0), Vector2(sx + 24.0, top + 5.0),
			Vector2(sx + 15.0, top + 13.0), Vector2(sx + 3.0, top + 14.0),
		])
		body.add_child(scorch)
	for k in range(2):
		var sx := -half_w + rect.size.x * (0.18 + 0.38 * k)
		var support := Polygon2D.new()
		support.color = STONE_DARK.lightened(0.03 + 0.03 * k)
		support.polygon = PackedVector2Array([
			Vector2(sx, top + 42.0), Vector2(sx + 38.0, top + 50.0),
			Vector2(sx + 30.0, bottom + 16.0), Vector2(sx + 4.0, bottom + 8.0),
		])
		body.add_child(support)
	var crack := Line2D.new()
	crack.width = 1.1
	crack.default_color = Color(0.012, 0.013, 0.016, 0.8)
	crack.points = PackedVector2Array([
		Vector2(-half_w + 30.0 + variant * 9.0, top + 8.0),
		Vector2(-half_w + 44.0 + variant * 9.0, top + 25.0),
		Vector2(-half_w + 38.0 + variant * 9.0, top + 45.0),
	])
	body.add_child(crack)
	for i in range(2):
		var rock := Polygon2D.new()
		rock.color = STONE_RIM.darkened(0.38)
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
	_build_entry_chains(props)
	_build_statue_gallery(props)
	_build_broken_arms(props)
	_build_boss_hall(props)
	_add_light(props, Vector2(3000, 540), Color(0.90, 0.30, 0.18), 0.55, 2.8)
	_add_light(props, Vector2(3780, 520), Color(0.55, 0.12, 0.12), 0.5, 3.2)
	_add_light(props, Vector2(4090, 470), Color(0.50, 0.70, 0.72), 0.35, 1.7)

func _build_entry_chains(parent: Node) -> void:
	# 从最上层垂下来的断链，告诉玩家这里已经有人来过、有人死过
	for spec in [
		{"x": 180.0, "end": 300.0, "w": 3.2},
		{"x": 390.0, "end": 440.0, "w": 2.0},
		{"x": 760.0, "end": 390.0, "w": 2.4},
	]:
		var chain := Line2D.new()
		chain.width = spec["w"]
		chain.default_color = Color(0.055, 0.055, 0.060)
		chain.points = PackedVector2Array([
			Vector2(spec["x"], -260.0),
			Vector2(spec["x"] + 9.0, 60.0),
			Vector2(spec["x"] + 2.0, spec["end"]),
		])
		parent.add_child(chain)
	# 断梯残骸：入口平台的左缘，斜插的几块铁板
	for i in range(3):
		var step := Polygon2D.new()
		step.color = Color(0.13, 0.13, 0.135)
		step.position = Vector2(40.0 + i * 34.0, 620.0 - i * 8.0)
		step.rotation = -0.08 + i * 0.05
		step.polygon = PackedVector2Array([
			Vector2(-48, -4), Vector2(48, -6), Vector2(44, 3), Vector2(-44, 5),
		])
		parent.add_child(step)

func _build_statue_gallery(parent: Node) -> void:
	# 四座断头骑士像：都是之前没能走出去的容器，和守门者呼应
	for i in range(4):
		var x := 1120.0 + i * 132.0
		var base := Node2D.new()
		base.name = "KnightStatue%d" % i
		base.position = Vector2(x, 600)
		parent.add_child(base)
		var plinth := Polygon2D.new()
		plinth.color = Color(0.13, 0.13, 0.135)
		plinth.polygon = PackedVector2Array([
			Vector2(-22, 0), Vector2(22, 0), Vector2(18, -32), Vector2(-18, -34),
		])
		base.add_child(plinth)
		var body := Polygon2D.new()
		body.color = Color(0.17, 0.17, 0.175)
		body.polygon = PackedVector2Array([
			Vector2(-16, -32), Vector2(-12, -66), Vector2(4, -72),
			Vector2(14, -60), Vector2(15, -32), Vector2(6, -24), Vector2(-8, -24),
		])
		base.add_child(body)
		# 断头：脖子上一道不平的断口，有的像被剑削掉
		var neck := Polygon2D.new()
		neck.color = Color(0.20, 0.20, 0.195)
		neck.polygon = PackedVector2Array([
			Vector2(-9, -72), Vector2(7, -75), Vector2(6, -62),
			Vector2(-8, -58), Vector2(-11, -64),
		])
		base.add_child(neck)
		var sword := Line2D.new()
		sword.width = 3.0
		sword.default_color = Color(0.36, 0.36, 0.34, 0.8)
		sword.points = PackedVector2Array([
			Vector2(17, -48), Vector2(24, -8), Vector2(26, 16),
		])
		base.add_child(sword)
		var crack := Line2D.new()
		crack.width = 1.0
		crack.default_color = Color(0.04, 0.04, 0.045, 0.8)
		crack.points = PackedVector2Array([
			Vector2(x - 8, 566), Vector2(x + 2, 586), Vector2(x, 600),
		])
		parent.add_child(crack)

## M4-09：进 Boss 厅前多走 500px，用插在地上的断剑/破盾交代“前面死过很多容器”。
func _build_broken_arms(parent: Node) -> void:
	for i in range(5):
		var x := 2260.0 + i * 108.0
		var blade := Line2D.new()
		blade.width = 3.4
		blade.default_color = Color(0.36, 0.36, 0.34, 0.75)
		blade.points = PackedVector2Array([
			Vector2(x, 620), Vector2(x - 5, 594), Vector2(x - 2, 558 + i * 3),
		])
		parent.add_child(blade)
		var guard := Line2D.new()
		guard.width = 2.0
		guard.default_color = Color(0.28, 0.27, 0.24, 0.8)
		guard.points = PackedVector2Array([
			Vector2(x - 15, 592 - i * 2), Vector2(x + 12, 598 + i * 2),
		])
		parent.add_child(guard)
		var rubble := Polygon2D.new()
		rubble.color = Color(0.105, 0.105, 0.11)
		rubble.polygon = PackedVector2Array([
			Vector2(-10, 0), Vector2(10, -2), Vector2(14, 3), Vector2(-4, 5),
		])
		rubble.position = Vector2(x, 621)
		parent.add_child(rubble)
	for spec in [{"x": 2360.0, "y": 600.0}, {"x": 2580.0, "y": 606.0}]:
		var shield := Polygon2D.new()
		shield.color = Color(0.19, 0.18, 0.16)
		shield.polygon = PackedVector2Array([
			Vector2(-16, -22), Vector2(0, -28), Vector2(16, -22),
			Vector2(13, -4), Vector2(0, 4), Vector2(-13, -4),
		])
		shield.position = Vector2(spec["x"], spec["y"])
		shield.rotation = -0.18
		parent.add_child(shield)
		var crest := Line2D.new()
		crest.width = 2.0
		crest.default_color = Color(0.30, 0.28, 0.24, 0.6)
		crest.points = PackedVector2Array([
			Vector2(-8, -13), Vector2(0, -19), Vector2(8, -13), Vector2(0, -5),
		])
		shield.add_child(crest)
	_add_light(parent, Vector2(2450, 586), Color(0.50, 0.64, 0.62), 0.30, 1.5)

func _build_boss_hall(parent: Node) -> void:
	# 厅顶横梁与吊链，压住 Boss 的剪影
	for x in [3100.0, 3360.0, 3620.0, 3880.0]:
		var chain := Line2D.new()
		chain.width = 2.2
		chain.default_color = Color(0.050, 0.050, 0.055)
		chain.points = PackedVector2Array([
			Vector2(x, -240.0), Vector2(x + 6.0, 100.0), Vector2(x, 260.0),
		])
		parent.add_child(chain)
	var beam := Polygon2D.new()
	beam.color = Color(0.070, 0.070, 0.075)
	beam.polygon = PackedVector2Array([
		Vector2(2900, 330), Vector2(4160, 330), Vector2(4160, 360), Vector2(2900, 360),
	])
	parent.add_child(beam)
	# 地面符文：三个同心环，Boss 站中间；纯装饰，不参与碰撞
	var arena := Node2D.new()
	arena.name = "ArenaRune"
	arena.position = Vector2(3520, 590)
	parent.add_child(arena)
	for r in [70.0, 106.0, 142.0]:
		var ring := Line2D.new()
		ring.width = 1.6
		ring.default_color = Color(0.34, 0.12, 0.14, 0.55)
		var pts := PackedVector2Array()
		for i in range(40):
			var a := TAU * float(i) / 40.0
			pts.append(Vector2(cos(a) * r, sin(a) * r * 0.22))
		ring.points = pts
		ring.position = Vector2(0, 0)
		arena.add_child(ring)
	# 两侧火盆：Boss 厅唯一的光，红色，和外面冷灰分开
	for dx in [-250.0, 250.0]:
		var brazier := Node2D.new()
		brazier.position = Vector2(3520 + dx, 600)
		parent.add_child(brazier)
		var bowl := Polygon2D.new()
		bowl.color = Color(0.24, 0.18, 0.14)
		bowl.polygon = PackedVector2Array([
			Vector2(-18, -30), Vector2(18, -30), Vector2(13, -8), Vector2(-13, -8),
		])
		brazier.add_child(bowl)
		var stem := Polygon2D.new()
		stem.color = Color(0.15, 0.13, 0.11)
		stem.polygon = PackedVector2Array([
			Vector2(-3, -8), Vector2(3, -8), Vector2(5, 0), Vector2(-5, 0),
		])
		brazier.add_child(stem)
		var flame := Polygon2D.new()
		flame.color = Color(1.0, 0.36, 0.18, 0.9)
		flame.polygon = PackedVector2Array([
			Vector2(-10, -30), Vector2(-4, -46), Vector2(1, -34),
			Vector2(7, -52), Vector2(11, -30),
		])
		brazier.add_child(flame)
	# 厅尽头的大铁门框：告诉玩家“出口在那里”，但门本身是锁着的
	var frame := Node2D.new()
	frame.name = "ExitFrame"
	frame.position = Vector2(4100, 600)
	parent.add_child(frame)
	for dx in [-78.0, 78.0]:
		var post := Polygon2D.new()
		post.color = Color(0.060, 0.060, 0.062)
		post.polygon = PackedVector2Array([
			Vector2(dx - 14, -240), Vector2(dx + 14, -240), Vector2(dx + 14, 0), Vector2(dx - 14, 0),
		])
		frame.add_child(post)
	var lintel := Polygon2D.new()
	lintel.color = Color(0.075, 0.075, 0.078)
	lintel.polygon = PackedVector2Array([
		Vector2(-94, -252), Vector2(94, -252), Vector2(88, -226), Vector2(-88, -226),
	])
	frame.add_child(lintel)
	# 门外透进来的冷光：门没开时只能看到一条缝
	var seam := Line2D.new()
	seam.width = 4.0
	seam.default_color = Color(0.48, 0.70, 0.72, 0.45)
	seam.points = PackedVector2Array([Vector2(0, -220), Vector2(0, -4)])
	frame.add_child(seam)

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

# ---------- Boss / 出口 ----------

func _build_exit_door() -> void:
	var holder := Node2D.new()
	holder.name = "Mechanisms"
	holder.z_index = 2
	add_child(holder)
	_exit_door = EXIT_SCENE.instantiate() as StaticBody2D
	_exit_door.name = "BossExitDoor"
	_exit_door.position = Vector2(4100, 470)
	holder.add_child(_exit_door)

func _build_return_shaft() -> void:
	# 旧货梯放在入口最左边：Boss 死后要真的走回这里，才有“回头”的重量
	var holder := Node2D.new()
	holder.name = "ReturnShaftHolder"
	holder.z_index = 2
	add_child(holder)
	_return_shaft = SHAFT_SCENE.instantiate() as Area2D
	_return_shaft.name = "ReturnShaft"
	_return_shaft.position = Vector2(232, 590)
	_return_shaft.set("controller", self)
	holder.add_child(_return_shaft)

func is_dialogue_playing() -> bool:
	return _dialogue != null and _dialogue.has_method("is_playing") and bool(_dialogue.call("is_playing"))

## 第三层 → 教学关起点：真 HE 的回头路。只在守门者死后可用。
func return_to_start() -> void:
	if _returning or not GameManager.has_flag("boss_defeated"):
		return
	_returning = true
	GameManager.set_flag("true_he_return")
	GameManager.current_floor = "start"
	EventBus.player_moved_between_floors.emit("start")
	EventBus.log_event("true_he_return", {"sacrifice_count": GameManager.sacrifice_count})
	var layer := CanvasLayer.new()
	layer.name = "ReturnTransition"
	layer.layer = 4
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.012, 0.012, 0.014, 1.0)
	rect.modulate = Color(1, 1, 1, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var label := Label.new()
	label.text = "回到起点"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.76, 0.82, 0.74, 0.0)
	label.add_theme_font_size_override("font_size", 22)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position = Vector2(-190, -20)
	label.size = Vector2(380, 40)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	layer.add_child(label)
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, 0.50)
	tween.parallel().tween_property(label, "modulate:a", 0.9, 0.35)
	tween.tween_interval(0.28)
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_file(TEST_ARENA)
	)

func _build_boss() -> void:
	var holder := Node2D.new()
	holder.name = "BossHolder"
	add_child(holder)
	_boss = BOSS_SCENE.instantiate()
	_boss.name = "Gatekeeper"
	_boss.position = Vector2(3520, 570)
	holder.add_child(_boss)

func _on_boss_defeated(boss_id: String) -> void:
	if boss_id != "gatekeeper_boss":
		return
	GameManager.set_flag("boss_defeated")
	_ending_lock = true
	if _exit_door != null and _exit_door.has_method("open"):
		_exit_door.call("open")
		GameManager.play_sfx("gate")
	_show_boss_hud(false)
	var camera := get_tree().get_first_node_in_group("camera")
	if camera != null and camera.has_method("shake"):
		camera.call("shake", 8.0, 0.5)
	# 死亡动作先走 0.8s，再补最后一段低语；别在尸体还没倒下时抢话
	var timer := get_tree().create_timer(0.8)
	timer.timeout.connect(func() -> void:
		if _dialogue != null and _dialogue.has_method("play"):
			_dialogue.call("play", "floor3_after_boss")
	)
	EventBus.log_event("floor3_clear", {"sacrifice_count": GameManager.sacrifice_count})

func _build_boss_hud() -> void:
	_boss_hud = CanvasLayer.new()
	_boss_hud.name = "BossHUD"
	_boss_hud.layer = 3
	add_child(_boss_hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(390, 20)
	panel.size = Vector2(500, 66)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.012, 0.012, 0.72)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.36, 0.16, 0.16, 0.7)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
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
	_boss_name.text = "守门者 · 上一任容器"
	_boss_name.add_theme_font_size_override("font_size", 15)
	_boss_name.add_theme_color_override("font_color", Color(0.88, 0.68, 0.58, 0.95))
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
	fill.bg_color = Color(0.63, 0.16, 0.15, 0.95)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.06, 0.95)
	_boss_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_boss_bar)
	_boss_hud.visible = false

func _show_boss_hud(show: bool) -> void:
	if _boss_hud != null:
		_boss_hud.visible = show

func _update_boss_hud() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	if bool(_boss.call("is_dead")):
		_show_boss_hud(false)
		return
	if not _boss_started:
		return
	_show_boss_hud(true)
	var hp := int(_boss.call("get_hp"))
	var max_hp := maxi(int(_boss.call("get_max_hp")), 1)
	_boss_bar.max_value = float(max_hp)
	_boss_bar.value = float(hp)
	if bool(_boss.call("is_phase2")):
		_boss_name.text = "守门者 · 第二阶段"

# ---------- 触发器 / 敌人 / 结局 ----------

func _build_triggers() -> void:
	var holder := Node2D.new()
	holder.name = "Triggers"
	add_child(holder)
	# 走进厅口才开场；对话期间 Boss 冻结，念完才 activate
	var arena := Area2D.new()
	arena.name = "ArenaTrigger"
	arena.collision_layer = 0
	arena.collision_mask = 2
	arena.position = Vector2(3010, 500)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(90, 240)
	col.shape = shape
	arena.add_child(col)
	arena.body_entered.connect(func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		if not _played.get("boss_intro", false):
			_played["boss_intro"] = true
			_dialogue.call("play", "floor3_boss_intro")
	)
	holder.add_child(arena)

	# 出口判定：门开了之后走进去才结算；门没开时碰撞会先挡住
	var exit := Area2D.new()
	exit.name = "EndingTrigger"
	exit.collision_layer = 0
	exit.collision_mask = 2
	exit.position = Vector2(4100, 500)
	var ecol := CollisionShape2D.new()
	var eshape := RectangleShape2D.new()
	eshape.size = Vector2(70, 190)
	ecol.shape = eshape
	exit.add_child(ecol)
	exit.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player") and _exit_door != null and bool(_exit_door.call("is_open")):
			_want_ending = true
	)
	holder.add_child(exit)

func _build_kill_zone() -> void:
	var area := Area2D.new()
	area.name = "KillZone"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(2100, 1240)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4400, 200)
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
		{"name": "Slime1", "pos": Vector2(1240, 588)},
		{"name": "Slime2", "pos": Vector2(1860, 628)},
		{"name": "SporeShooter", "pos": Vector2(2140, 588)},
	]:
		var scene := SLIME_SCENE if str(spec["name"]).begins_with("Slime") else SPORE_SHOOTER_SCENE
		var enemy := scene.instantiate()
		enemy.name = str(spec["name"])
		enemy.position = spec["pos"]
		holder.add_child(enemy)

func resolve_ending_id(sacrifice_count: int) -> String:
	# 真 HE 是隐藏优先线；正常流程在祭坛就结算，这里兜底防止有人带着旗标回到出口门
	if GameManager.has_flag("true_he_unlocked"):
		return "true_he"
	# 新手教学那次是保命的“无条件献祭”，所以 ==1 算守住了人线
	return "human" if sacrifice_count <= 1 else "transformed"

func _show_ending() -> void:
	if _ending_active:
		return
	_ending_active = true
	_want_ending = false
	var ending_id := resolve_ending_id(GameManager.sacrifice_count)
	GameManager.set("state", GameManager.GameState.ENDING)
	EventBus.ending_reached.emit(ending_id)
	EventBus.log_event("ending_reached", {"ending": ending_id, "sacrifice_count": GameManager.sacrifice_count})
	if _ending_screen == null:
		_ending_screen = ENDING_SCENE.instantiate() as CanvasLayer
		add_child(_ending_screen)
		_ending_screen.restart_requested.connect(_restart_from_ending)
	_ending_screen.call("show_ending", ending_id)

func _restart_from_ending() -> void:
	_ending_active = false
	GameManager.start_new_game()
	get_tree().change_scene_to_file(TEST_ARENA)

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
	rect.color = Color(0.012, 0.012, 0.014, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var label := Label.new()
	label.text = FLOOR3_NAME
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.78, 0.78, 0.72, 0.0)
	label.add_theme_font_size_override("font_size", 22)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position = Vector2(-190, -20)
	label.size = Vector2(380, 40)
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
