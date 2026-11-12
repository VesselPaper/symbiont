extends Area2D
## 蒸汽靴宝箱（M4-06，方案 C 的最小实现）
##
## 位置放在教学关祭坛右侧长廊，不和祭坛的 K 献祭判定重叠。
## 这里不是“商店”：当前没有货币系统，先用一次性宝箱把“有交互键、能拿到二段跳”跑通；
## 以后组长要定价，再把免费开启换成扣资源即可，宝箱/存档/二段跳接口不用动。
##
## 视觉仍用 Polygon2D/Line2D 代码拼，不引入图片素材。

const FLAG_TAKEN := "steam_boots_taken"
# 盖子铰链位置（箱身局部坐标）：箱身上沿是 y=-24，宽度 ±27，铰链取左后角
const LID_HINGE := Vector2(-27.0, -24.0)
const LID_OPEN_ANGLE := -1.35
const InteractionPrompt := preload("res://components/interaction_prompt.gd")

var _player_near := false
var _opened := false
var _prompt: Label
var _lid: Node2D
var _glow: Polygon2D
var _steam: CPUParticles2D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	z_index = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70, 64)
	var col := CollisionShape2D.new()
	col.position = Vector2(0, -30)
	col.shape = shape
	add_child(col)
	_build_visual()
	_build_prompt()
	# 读档/回头：已拿过就保持开箱状态，不能再刷一双
	_opened = GameManager.has_steam_boots or GameManager.has_flag(FLAG_TAKEN)
	_apply_open_visual(_opened)
	_prompt.visible = false

func _build_visual() -> void:
	var shadow := Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.24)
	shadow.polygon = PackedVector2Array([
		Vector2(-30, 2), Vector2(-15, -3), Vector2(15, -3),
		Vector2(30, 2), Vector2(12, 7), Vector2(-12, 7),
	])
	add_child(shadow)

	_glow = Polygon2D.new()
	_glow.name = "Glow"
	_glow.color = Color(0.82, 0.62, 0.28, 0.10)
	_glow.polygon = PackedVector2Array([
		Vector2(-42, -62), Vector2(42, -62), Vector2(54, 4), Vector2(-54, 4),
	])
	add_child(_glow)

	var body := Polygon2D.new()
	body.name = "ChestBody"
	body.color = Color(0.24, 0.18, 0.12, 1)
	body.polygon = PackedVector2Array([
		Vector2(-27, -24), Vector2(27, -24), Vector2(29, 0),
		Vector2(22, 4), Vector2(-22, 4), Vector2(-29, 0),
	])
	add_child(body)

	var body_rim := Line2D.new()
	body_rim.width = 1.8
	body_rim.default_color = Color(0.62, 0.46, 0.26, 0.9)
	body_rim.points = PackedVector2Array([
		Vector2(-26, -22), Vector2(26, -22), Vector2(25, -2), Vector2(-25, -2),
	])
	add_child(body_rim)

	for x in [-15.0, 0.0, 15.0]:
		var band := Polygon2D.new()
		band.color = Color(0.24, 0.34, 0.34, 0.85)
		band.polygon = PackedVector2Array([
			Vector2(x - 2, -24), Vector2(x + 2, -24),
			Vector2(x + 2, 1), Vector2(x - 2, 1),
		])
		add_child(band)

	# 盖子单独一个 Node2D，开箱时绕后铰链转开。
	# 之前盖子节点放在 (0,0)、多边形又画在 y=0..-16，正好压在箱身下半截，
	# 看着就像“盖子一开始掉在地上”。现在把铰链挪到箱身上沿左后角，
	# 多边形的 x=0 就是铰链，开箱时绕铰链转开。
	_lid = Node2D.new()
	_lid.name = "Lid"
	_lid.position = LID_HINGE
	add_child(_lid)
	var lid := Polygon2D.new()
	lid.color = Color(0.31, 0.23, 0.15, 1)
	lid.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(5, -11), Vector2(17, -16),
		Vector2(37, -16), Vector2(49, -11), Vector2(54, 0),
	])
	_lid.add_child(lid)
	var lid_rim := Line2D.new()
	lid_rim.width = 1.8
	lid_rim.default_color = Color(0.70, 0.52, 0.29, 0.95)
	lid_rim.points = PackedVector2Array([
		Vector2(0, -1), Vector2(5, -11), Vector2(16, -14),
		Vector2(38, -14), Vector2(49, -11), Vector2(54, -1),
	])
	_lid.add_child(lid_rim)
	var lock := Polygon2D.new()
	lock.color = Color(0.76, 0.58, 0.30, 0.95)
	lock.polygon = PackedVector2Array([
		Vector2(23, -4), Vector2(31, -4), Vector2(30, 5), Vector2(24, 5),
	])
	_lid.add_child(lock)

	_steam = CPUParticles2D.new()
	_steam.name = "Steam"
	_steam.amount = 7
	_steam.lifetime = 0.8
	_steam.one_shot = true
	_steam.emitting = false
	_steam.direction = Vector2(0, -1)
	_steam.spread = 35.0
	_steam.gravity = Vector2(0, -18)
	_steam.initial_velocity_min = 8.0
	_steam.initial_velocity_max = 22.0
	_steam.scale_amount_min = 0.8
	_steam.scale_amount_max = 2.0
	_steam.color = Color(0.78, 0.82, 0.78, 0.45)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.8))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	_steam.color_ramp = ramp
	_steam.position = Vector2(0, -16)
	add_child(_steam)

func _build_prompt() -> void:
	_prompt = InteractionPrompt.create(
		self, "K 开启", Vector2(-58, -74), Vector2(116, 28),
		16, Color(0.92, 0.88, 0.68, 0.95), 4, 4
	)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_near = true
	_prompt.visible = not _opened

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_near = false
	_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	# 反向输入：只认 K 按下沿，抬起/长按 echo/其它键不触发
	if _opened or not _player_near:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if key.physical_keycode != KEY_K and key.keycode != KEY_K:
		return
	_open()
	get_viewport().set_input_as_handled()

func _open() -> void:
	if _opened:
		return
	_opened = true
	_prompt.visible = false
	GameManager.has_steam_boots = true
	GameManager.set_flag(FLAG_TAKEN)
	GameManager.play_sfx("chest_open", 0.0)
	EventBus.item_picked.emit("steam_boots", 1)
	_steam.restart()
	_steam.emitting = true
	_animate_lid()

func _apply_open_visual(opened: bool) -> void:
	if _lid == null:
		return
	if opened:
		_lid.rotation = LID_OPEN_ANGLE
		_lid.position = LID_HINGE
		if _glow != null:
			_glow.color = Color(0.82, 0.62, 0.28, 0.04)

func _animate_lid() -> void:
	var tween := create_tween()
	tween.tween_property(_lid, "rotation", LID_OPEN_ANGLE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glow != null:
		tween.parallel().tween_property(_glow, "modulate:a", 0.0, 0.35)
