extends Node2D
## 地图内目标文字（M4-01 初版 / M4-22 组长试玩定稿）
##
## 组长两条反馈合成这一版：
##   ① 开头 A/D 那句压在骨栅门上读不清 → 锚点整句左移（数值在 test_arena 的 STAGE 表）
##   ② 每环提示做完要留在地图上当地标，不要消失 → 从“一句话的临时气泡”改成“每环一枚刻字”：
##      走到哪环，哪环那句亮起来；做过的留在原地变暗，玩家回头还看得见自己走过的要求。
##
## 文字画在世界坐标（z_index=6，压在地形/道具前面），随地图滚动，不跟玩家走。
##
## 与 tutorial.gd 的契约（duck typing，ui_path 留空就只走逻辑不显示）：
##   show_objective(step, text, world_pos)  第 step 环刻一句；重复调用原地改字
##   set_active_step(step)                  当前环亮、其余暗；-1 = 没有当前环（教程结束）
##   show_bubble(text) / hide_bubble()      临时提示（获得铁剑 / 教程完成），由调用方计时
##   set_bubble_position(global_pos)        临时提示挂在哪个锚点上方
## 旧契约保持可用（objective_hud_test 与截图脚本还在用），只是 hide_bubble 现在只收临时提示，
## 不再把整块目标文字一起藏掉 —— 那是组长明确不要的行为。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
## 目标文字底边大致在锚点上方 88px（不压地形亮边，也离玩家头顶够远）
const TEXT_OFFSET := Vector2(0, -88)
## 临时提示再往上让 30px，避免和那一环的刻字叠在一起
const FLASH_OFFSET := Vector2(0, -30)
## 每句话的版心：520 宽、60 高，居中排版，长的目标句会自动折行
const LABEL_SIZE := Vector2(520, 60)
const FONT_SIZE := 20

## 当前环：亮一点（比完成态高出一倍多，扫一眼就知道现在该干什么）
const ACTIVE_COLOR := Color(0.80, 0.95, 0.90, 0.96)
## 做过的：留在地图上但退到背景里，不抢当前目标；alpha 别压太低，
## 深色背景上 0.30 基本看不见，玩家会以为提示被删了（M4-22 组长要的是“还看得见的路标”）
const DONE_COLOR := Color(0.66, 0.78, 0.76, 0.45)
## 临时提示用偏暖的骨色，和任务刻字的冷青区分开
const FLASH_COLOR := Color(0.88, 0.90, 0.74, 1.0)

var _objectives: Dictionary = {}   # step(int) → Label
var _active_step := -1
var _flash: Label
var _flash_anchor := Vector2.ZERO
var _tween: Tween
var _font: Font

func _ready() -> void:
	_font = load(FONT_PATH) as Font
	if _font == null:
		push_error("objective_hud: 加载中文字体失败 %s" % FONT_PATH)
	_flash = get_node_or_null("Label") as Label
	if _flash == null:
		_flash = _make_label("Label")
	_flash.modulate.a = 0.0
	visible = false

## 第 step 环刻一句：没有就新建，有了原地改字。位置钉在世界坐标，不跟玩家走。
func show_objective(step: int, text: String, world_pos: Vector2) -> void:
	if text.strip_edges() == "":
		return
	var label := _objective_label(step)
	label.text = text
	_center_at(label, world_pos + TEXT_OFFSET)
	# 刚刻出来的这一环就是当前环，颜色按当前态画；set_active_step 随后会再统一上色
	_paint(label, step == _active_step)
	visible = true

## 切换“当前环”：那一句亮，别的（做完的/还没轮到的）一律退到背景色。
## step = -1 时全部变暗（教程结束，地图上只剩刻字，不再指示下一步）。
func set_active_step(step: int) -> void:
	_active_step = step
	for key in _objectives.keys():
		var label: Label = _objectives[key]
		if label != null and is_instance_valid(label):
			_paint(label, int(key) == step)

## 临时提示挂在哪个锚点上方（tutorial 每步传自己那环的锚点）
func set_bubble_position(global_pos: Vector2) -> void:
	_flash_anchor = global_pos
	if _flash != null and is_instance_valid(_flash):
		_center_at(_flash, _flash_anchor + TEXT_OFFSET + FLASH_OFFSET)

## 弹一句临时提示（获得铁剑 / 教程完成）。显隐计时由调用方掌握，见 tutorial.gd。
func show_bubble(text: String) -> void:
	if _flash == null or not is_instance_valid(_flash):
		return
	_flash.text = text
	_flash.add_theme_color_override("font_color", FLASH_COLOR)
	set_bubble_position(_flash_anchor)
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_flash.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_flash, "modulate:a", 1.0, 0.20)

## 只收临时提示；目标刻字留着（M4-22 组长：做完不消失）
func hide_bubble() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _flash != null and is_instance_valid(_flash):
		_flash.modulate.a = 0.0

## 某一环的刻字有没有、文字是什么（给测试和截图脚本查）
func get_objective_text(step: int) -> String:
	var label: Label = _objectives.get(step)
	return label.text if label != null and is_instance_valid(label) else ""

func get_objective_count() -> int:
	return _objectives.size()

# ---- 内部 ----

func _objective_label(step: int) -> Label:
	var label: Label = _objectives.get(step)
	if label != null and is_instance_valid(label):
		return label
	label = _make_label("Objective%d" % step)
	_objectives[step] = label
	return label

func _make_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = Vector2(-LABEL_SIZE.x * 0.5, -LABEL_SIZE.y * 0.5)
	label.size = LABEL_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.035, 0.038, 0.72))
	label.add_theme_constant_override("outline_size", 3)
	if _font != null:
		label.add_theme_font_override("font", _font)
	add_child(label)
	return label

## 当前态/完成态只差颜色：字号不动，免得“做完的句子缩水”像被删掉一截
func _paint(label: Label, is_active: bool) -> void:
	label.add_theme_color_override("font_color", ACTIVE_COLOR if is_active else DONE_COLOR)

## Label 的原点是左上角，这里按“文字中心”摆：控制台/测试量出来的坐标才和锚点对得上
func _center_at(label: Label, world_center: Vector2) -> void:
	label.global_position = world_center - LABEL_SIZE * 0.5
