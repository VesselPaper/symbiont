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
## 低血量阈值（M5-05 组长要求）：只剩这么多颗心时，屏幕四周开始冒黑雾 + 冒出"血量危险"
const DANGER_HP := 1
## 黑雾的呼吸频率/基础浓度：慢一点，才像"视线在变窄"，不像报警灯
const DANGER_PULSE := 2.2
const DANGER_BASE := 0.42
const DANGER_SWING := 0.12

## 边缘黑雾：只压四周、中间不动，血越少越往里收
const DANGER_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform vec4 mist : source_color = vec4(0.015, 0.012, 0.020, 1.0);
void fragment() {
	vec2 p = UV - vec2(0.5);
	// 竖着收一点、横向再拉开：屏幕是宽的，纯圆形会让上下先黑
	float d = length(p * vec2(1.25, 1.55)) * 1.35;
	COLOR = vec4(mist.rgb, clamp(d - 0.35, 0.0, 1.0) * strength);
}
"""

var _hearts: Array[Polygon2D] = []
var _sacrifice_label: Label
var _toast_label: Label
var _toast_timer := 0.0
var _last_hp := -1
var _player: Node
var _danger_rect: ColorRect
var _danger_mat: ShaderMaterial
var _danger_label: Label
var _danger_t := 0.0
## 最近一次刷新读到的心数（黑雾按它判断"低血"）
var _cur_hp := MAX_HEARTS

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
	_build_danger()
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
	_update_danger(delta)
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		if _toast_timer <= 0.0:
			_toast_label.modulate.a = 0.0
		elif _toast_timer < 0.45:
			_toast_label.modulate.a = _toast_timer / 0.45

## 低血量的黑雾和警告字。放在心数条下面一层（先 add，后画的东西盖在上面），
## 这样血条本身永远看得清，被压黑的是画面。
func _build_danger() -> void:
	_danger_rect = ColorRect.new()
	_danger_rect.name = "DangerMist"
	_danger_rect.color = Color(1, 1, 1, 1)
	_danger_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = DANGER_SHADER
	_danger_mat = ShaderMaterial.new()
	_danger_mat.shader = sh
	_danger_mat.set_shader_parameter("strength", 0.0)
	_danger_rect.material = _danger_mat
	add_child(_danger_rect)
	_danger_label = Label.new()
	_danger_label.name = "DangerLabel"
	_danger_label.size = Vector2(220, 24)
	_danger_label.position = Vector2(HUD_POS.x - 4, HUD_POS.y - 34)
	_danger_label.add_theme_font_size_override("font_size", 14)
	_danger_label.add_theme_color_override("font_color", Color(0.92, 0.28, 0.26, 0.95))
	_danger_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_danger_label.add_theme_constant_override("shadow_offset_x", 1)
	_danger_label.add_theme_constant_override("shadow_offset_y", 1)
	var font := load(FONT_PATH) as Font
	if font != null:
		_danger_label.add_theme_font_override("font", font)
	_danger_label.text = "血量危险"
	_danger_label.visible = false
	add_child(_danger_label)

## 每一帧只按"还剩几颗心"推两件事：黑雾浓度（带呼吸）和警告字闪不闪。
## 满血时强度归零，画面完全不受影响。
func _update_danger(delta: float) -> void:
	if _danger_mat == null or _danger_label == null:
		return
	_danger_t += delta
	var low := _cur_hp <= DANGER_HP
	var strength := 0.0
	if low:
		strength = DANGER_BASE + sin(_danger_t * DANGER_PULSE) * DANGER_SWING
	_danger_mat.set_shader_parameter("strength", maxf(strength, 0.0))
	_danger_label.visible = low
	_danger_label.modulate.a = 0.65 + sin(_danger_t * DANGER_PULSE) * 0.35 if low else 0.0

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
	_cur_hp = hp
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
