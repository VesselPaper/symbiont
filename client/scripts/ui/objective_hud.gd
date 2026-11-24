extends CanvasLayer
## 教学目标提示（P0 反馈改版：从"刻在地图上的句子"改成屏幕底部的实时提醒）
##
## 旧版把每一环的目标句钉在世界坐标上，做完也不消失，当作地图路标。
## 反馈：这些字挂在背景里像 UI 糊在场景上，而且玩家其实只在当前这一步需要看。
## 现在：
##   - 整块提示固定在屏幕底部居中（CanvasLayer，不随地图滚动、不吃相机缩放）；
##   - 只显示当前这一环的一句，做完立刻换成下一句，教程结束就收起；
##   - 出现时机仍由 tutorial.gd 掌握：开场对话播完 → MOVE 提示自动出现，
##     玩家走过移动点 → 收起并换 JUMP —— 即"落地、对话结束才提示，做出动作就消失"。
##
## 与 tutorial.gd 的契约（duck typing，ui_path 留空则只走逻辑不显示）：
##   show_objective(step, text, world_pos)  world_pos 只为兼容旧契约保留，已不使用
##   set_active_step(step)                  -1 = 教程结束，收起提示
##   show_bubble(text) / hide_bubble()      临时提示（获得铁剑 / 教程完成）
##   set_bubble_position(global_pos)        旧契约兼容，临时提示同样固定在屏幕上

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
## 屏幕提示字号（旧版刻在世界里的字只有 10，跟着 zoom 一起缩；这里固定在屏幕上，18 才读得清）
const FONT_SIZE := 18
const HINT_COLOR := Color(0.82, 0.94, 0.89, 0.95)
const FLASH_COLOR := Color(0.92, 0.92, 0.72, 1.0)
const OUTLINE_COLOR := Color(0.015, 0.03, 0.034, 0.85)
const OUTLINE_SIZE := 4
const FADE_TIME := 0.18
## 提示条距屏幕底边的高度（屏幕坐标，负值 = 从下往上）
const HINT_BOTTOM := -116.0
## 临时提示在目标提示上方再让 42px，避免两句叠在一起
const BUBBLE_BOTTOM := -158.0

var _hint: Label
var _bubble: Label
var _active_step := -1
## 旧契约里临时提示的锚点，现在不参与排版，只存着不报错
var _bubble_anchor := Vector2.ZERO
var _hint_tween: Tween
var _bubble_tween: Tween
var _font: Font

func _ready() -> void:
	_font = load(FONT_PATH) as Font
	if _font == null:
		push_error("objective_hud: 加载中文字体失败 %s" % FONT_PATH)
	_hint = get_node_or_null("Hint") as Label
	if _hint == null:
		_hint = _make_label("Hint", HINT_BOTTOM, HINT_COLOR)
	_bubble = get_node_or_null("Bubble") as Label
	if _bubble == null:
		_bubble = _make_label("Bubble", BUBBLE_BOTTOM, FLASH_COLOR)
	_apply_style(_hint, HINT_COLOR)
	_apply_style(_bubble, FLASH_COLOR)
	_hint.text = ""
	_bubble.text = ""
	_hint.modulate.a = 0.0
	_bubble.modulate.a = 0.0

## 进入某环：把这一条提示换成新一句。旧的一句随文本替换一起消失（只剩当前这一句）。
func show_objective(step: int, text: String, _world_pos: Vector2) -> void:
	if text.strip_edges() == "":
		# 空文案 = 这一环不提示：把上一条收掉，别让上一环的要求留在屏幕上
		_active_step = -1
		_fade(_hint, 0.0, false)
		return
	_active_step = step
	_hint.text = text
	_fade(_hint, 1.0, true)

## 切换当前环：step = -1（教程结束）时收起提示。
func set_active_step(step: int) -> void:
	_active_step = step
	if step < 0:
		_fade(_hint, 0.0, false)

## 临时提示（获得铁剑 / 教程完成）。显隐计时由调用方掌握，见 tutorial.gd。
func show_bubble(text: String) -> void:
	if _bubble == null or not is_instance_valid(_bubble):
		return
	_bubble.text = text
	_fade(_bubble, 1.0, true)

func hide_bubble() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		_fade(_bubble, 0.0, false)

## 旧契约兼容：临时提示现在也固定在屏幕上，锚点不再参与排版。
func set_bubble_position(global_pos: Vector2) -> void:
	_bubble_anchor = global_pos

## 当前提示文案；只有正在显示的那一环有内容（给测试和截图脚本查）
func get_objective_text(step: int) -> String:
	if step != _active_step or _hint == null:
		return ""
	return _hint.text

## 屏幕上当前有几条目标提示（0 或 1；新版不再把做过的句子留在背景里）
func get_objective_count() -> int:
	if _hint == null or _active_step < 0 or _hint.text.strip_edges() == "":
		return 0
	return 1

# ---- 内部 ----

## 淡入淡出：同一层提示复用一条 Tween，连续推进时不会叠出两条动画抢 alpha
func _fade(label: Label, target: float, show: bool) -> void:
	if label == null or not is_instance_valid(label):
		return
	var old := _hint_tween if label == _hint else _bubble_tween
	if old != null and old.is_valid():
		old.kill()
	if show:
		visible = true
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", target, FADE_TIME)
	if label == _hint:
		_hint_tween = tween
	else:
		_bubble_tween = tween

## 兜底：场景里没有 Hint/Bubble 节点时在屏幕底部按锚点建一个
func _make_label(node_name: String, bottom: float, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.anchor_left = 0.5
	label.anchor_top = 1.0
	label.anchor_right = 0.5
	label.anchor_bottom = 1.0
	label.offset_left = -420.0
	label.offset_top = bottom
	label.offset_right = 420.0
	label.offset_bottom = bottom + 36.0
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_apply_style(label, color)
	return label

func _apply_style(label: Label, color: Color) -> void:
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
