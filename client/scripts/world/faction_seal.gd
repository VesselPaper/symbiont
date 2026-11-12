extends StaticBody2D
## 第二层阵营封印门（M3-01）
##
## 不是普通骨门：门上同时刻着工程师的齿轮和异教徒的骨环，必须选定一边才认人。
## 碰撞和视觉都在这里，场景只负责摆位置。

const OPEN_TIME := 0.65
const BARRIER_COLOR := Color(0.72, 0.78, 0.72, 0.45)
const ENGINEER_COLOR := Color(1.0, 0.72, 0.34, 0.78)
const HERETIC_COLOR := Color(0.66, 0.38, 0.86, 0.78)

var _opened := false
var _choice := ""
var _time := 0.0
var _barrier: Line2D
var _glow: Line2D
var _sigil: Node2D
var _rune_left: Polygon2D
var _rune_right: Polygon2D

func _ready() -> void:
	add_to_group("faction_seal")
	_build_visual()

func _build_visual() -> void:
	var top := -150.0
	var bottom := 150.0
	# 两根细铁柱框住中间的能量幕，避免只有一条光带看不出是门
	for dx in [-24.0, 24.0]:
		var post := Polygon2D.new()
		post.color = Color(0.105, 0.120, 0.130, 0.98)
		post.polygon = PackedVector2Array([
			Vector2(dx - 5, top), Vector2(dx + 5, top),
			Vector2(dx + 5, bottom), Vector2(dx - 5, bottom),
		])
		add_child(post)
		var rim := Line2D.new()
		rim.width = 1.2
		rim.default_color = Color(0.36, 0.42, 0.42, 0.55)
		rim.points = PackedVector2Array([
			Vector2(dx + (5.0 if dx > 0 else -5.0), top + 8),
			Vector2(dx + (5.0 if dx > 0 else -5.0), bottom - 8),
		])
		add_child(rim)

	_glow = Line2D.new()
	_glow.name = "Glow"
	_glow.width = 18.0
	_glow.default_color = Color(0.72, 0.78, 0.72, 0.10)
	_glow.antialiased = true
	_glow.points = PackedVector2Array([Vector2(0, top + 8), Vector2(0, bottom - 8)])
	add_child(_glow)

	_barrier = Line2D.new()
	_barrier.name = "Barrier"
	_barrier.width = 3.2
	_barrier.default_color = BARRIER_COLOR
	_barrier.antialiased = true
	var pts := PackedVector2Array()
	for i in range(13):
		var y := lerpf(top + 8.0, bottom - 8.0, float(i) / 12.0)
		pts.append(Vector2(sin(float(i) * 1.7) * 3.4, y))
	_barrier.points = pts
	add_child(_barrier)

	_sigil = Node2D.new()
	_sigil.name = "Sigil"
	_sigil.position = Vector2(0, 12)
	add_child(_sigil)
	# 左齿轮（工程师）和右骨环（异教徒）并排，选择前两边都暗着
	_rune_left = Polygon2D.new()
	_rune_left.name = "EngineerRune"
	_rune_left.color = Color(0.38, 0.40, 0.36, 0.65)
	_rune_left.position = Vector2(-11, 0)
	var gear := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		var r := 10.0 if i % 2 == 0 else 7.0
		gear.append(Vector2(cos(a) * r, sin(a) * r))
	_rune_left.polygon = gear
	_sigil.add_child(_rune_left)

	_rune_right = Polygon2D.new()
	_rune_right.name = "HereticRune"
	_rune_right.color = Color(0.38, 0.34, 0.42, 0.65)
	_rune_right.position = Vector2(11, 0)
	var ring := PackedVector2Array()
	for i in range(12):
		var a := TAU * float(i) / 12.0
		ring.append(Vector2(cos(a) * 8.0, sin(a) * 8.0))
	_rune_right.polygon = ring
	_sigil.add_child(_rune_right)

	# 中间一道细缝：选择后会从合拢变成单边亮，像门认了主人
	var seam := Line2D.new()
	seam.width = 1.0
	seam.default_color = Color(0.86, 0.82, 0.68, 0.5)
	seam.points = PackedVector2Array([Vector2(0, -8), Vector2(0, 8)])
	_sigil.add_child(seam)

func _process(delta: float) -> void:
	if _opened:
		return
	_time += delta
	# 能量幕微微呼吸，静止时也有“活着”的感觉
	var pulse := 0.88 + sin(_time * 2.2) * 0.12
	_barrier.modulate = Color(1, 1, 1, pulse)
	_glow.modulate = Color(1, 1, 1, pulse)

## 选择阵营后只亮对应的一半符文；门本身还没开，给玩家“认主”的反馈。
func set_faction(faction: String) -> void:
	_choice = faction
	if faction == "engineer":
		_rune_left.color = ENGINEER_COLOR
		_rune_right.color = Color(0.24, 0.22, 0.26, 0.35)
	elif faction == "heretic":
		_rune_left.color = Color(0.24, 0.22, 0.26, 0.35)
		_rune_right.color = HERETIC_COLOR

func open(faction: String = "", instant: bool = false) -> void:
	if _opened:
		return
	_opened = true
	if faction != "":
		set_faction(faction)
	var color := BARRIER_COLOR
	if _choice == "engineer":
		color = ENGINEER_COLOR
	elif _choice == "heretic":
		color = HERETIC_COLOR
	_barrier.default_color = color
	_glow.default_color = Color(color.r, color.g, color.b, 0.16)
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		col.disabled = true
	# 门往下沉、光幕拉长再淡掉，不做“瞬间消失”
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y + 22.0, OPEN_TIME if not instant else 0.01)
	tween.tween_property(_barrier, "modulate:a", 0.0, OPEN_TIME if not instant else 0.01)
	tween.tween_property(_glow, "modulate:a", 0.0, OPEN_TIME if not instant else 0.01)
	tween.tween_property(_sigil, "modulate:a", 0.0, OPEN_TIME if not instant else 0.01)
	if instant:
		visible = false

func is_open() -> bool:
	return _opened
