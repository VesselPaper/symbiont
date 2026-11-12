extends CanvasLayer
## 游戏内 HUD（M1-06）
##
## 左下角：五枚生命骨片 + 献祭计数；拾取物品时上方浮一行短提示。
## 放左下角是为了避开教学关左上角的目标条和顶部对话框；不挡落点。
## 只读玩家/GameManager，不改任何战斗数值。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const MAX_HEARTS := 5
const HEART_SPACING := 22.0
const HUD_POS := Vector2(24, 646)
const TOAST_TIME := 1.8

var _hearts: Array[Polygon2D] = []
var _sacrifice_label: Label
var _toast_label: Label
var _toast_timer := 0.0
var _last_hp := -1
var _player: Node

func _ready() -> void:
	layer = 1
	_build()
	if get_node_or_null("PauseMenu") == null:
		var pause := PAUSE_SCENE.instantiate()
		pause.name = "PauseMenu"
		add_child(pause)
	EventBus.item_picked.connect(_on_item_picked)
	refresh()

func _build() -> void:
	var anchor := Node2D.new()
	anchor.name = "HUDAnchor"
	anchor.position = HUD_POS
	add_child(anchor)
	var accent := ColorRect.new()
	accent.name = "Accent"
	accent.position = Vector2(-10, -4)
	accent.size = Vector2(2, 54)
	accent.color = Color(0.46, 0.62, 0.54, 0.55)
	anchor.add_child(accent)
	for i in range(MAX_HEARTS):
		var heart := Polygon2D.new()
		heart.name = "Heart%d" % i
		heart.position = Vector2(i * HEART_SPACING, 0)
		heart.polygon = PackedVector2Array([
			Vector2(0, -9), Vector2(5, -6), Vector2(8, -1),
			Vector2(6, 5), Vector2(0, 10), Vector2(-6, 5),
			Vector2(-8, -1), Vector2(-5, -6),
		])
		heart.color = Color(0.16, 0.18, 0.17, 0.9)
		anchor.add_child(heart)
		var outline := Line2D.new()
		outline.width = 1.0
		outline.default_color = Color(0.56, 0.62, 0.54, 0.50)
		outline.points = PackedVector2Array([
			Vector2(0, -9), Vector2(5, -6), Vector2(8, -1),
			Vector2(6, 5), Vector2(0, 10), Vector2(-6, 5),
			Vector2(-8, -1), Vector2(-5, -6), Vector2(0, -9),
		])
		heart.add_child(outline)
		_hearts.append(heart)
	_sacrifice_label = Label.new()
	_sacrifice_label.name = "SacrificeLabel"
	_sacrifice_label.position = Vector2(-4, 20)
	_sacrifice_label.size = Vector2(190, 20)
	_sacrifice_label.add_theme_font_size_override("font_size", 12)
	_sacrifice_label.add_theme_color_override("font_color", Color(0.64, 0.70, 0.62, 0.9))
	_sacrifice_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_sacrifice_label.add_theme_constant_override("shadow_offset_x", 1)
	_sacrifice_label.add_theme_constant_override("shadow_offset_y", 1)
	var font := load(FONT_PATH) as Font
	if font != null:
		_sacrifice_label.add_theme_font_override("font", font)
	anchor.add_child(_sacrifice_label)
	_toast_label = Label.new()
	_toast_label.name = "PickupToast"
	_toast_label.position = Vector2(-4, -30)
	_toast_label.size = Vector2(240, 20)
	_toast_label.modulate = Color(1, 1, 1, 0.0)
	_toast_label.add_theme_font_size_override("font_size", 12)
	_toast_label.add_theme_color_override("font_color", Color(0.82, 0.90, 0.76, 1.0))
	_toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_toast_label.add_theme_constant_override("shadow_offset_x", 1)
	_toast_label.add_theme_constant_override("shadow_offset_y", 1)
	if font != null:
		_toast_label.add_theme_font_override("font", font)
	anchor.add_child(_toast_label)

func _process(delta: float) -> void:
	refresh()
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		if _toast_timer <= 0.0:
			_toast_label.modulate.a = 0.0
		elif _toast_timer < 0.45:
			_toast_label.modulate.a = _toast_timer / 0.45

func refresh() -> void:
	if _sacrifice_label == null:
		return
	_sacrifice_label.text = "献祭 %d" % GameManager.sacrifice_count
	var player := _get_player()
	var hp := MAX_HEARTS
	var max_hp := MAX_HEARTS
	if player != null:
		hp = int(player.get("hp"))
		var raw: Variant = player.get("MAX_HP")
		if raw != null:
			max_hp = int(raw)
	hp = clampi(hp, 0, max_hp)
	if hp != _last_hp:
		_last_hp = hp
		for i in range(_hearts.size()):
			_hearts[i].color = Color(0.68, 0.20, 0.22, 0.95) if i < hp else Color(0.13, 0.15, 0.14, 0.9)

func get_filled_hearts() -> int:
	var count := 0
	for heart in _hearts:
		if heart.color.r > 0.4:
			count += 1
	return count

func get_toast_text() -> String:
	return _toast_label.text if _toast_label != null else ""

func _on_item_picked(item_id: String, _count: int) -> void:
	if _toast_label == null:
		return
	_toast_label.text = "拾取：%s" % _item_name(item_id)
	_toast_label.modulate.a = 1.0
	_toast_timer = TOAST_TIME

func _item_name(item_id: String) -> String:
	match item_id:
		"iron_sword":
			return "铁剑"
		"monster_limb":
			return "怪物肢体"
		"origin_relic":
			return "旧骨片"
	return item_id

func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player
