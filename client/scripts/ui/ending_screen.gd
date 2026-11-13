extends CanvasLayer
## 结局画面（M3-02 抽取 / M3-03 复用）
##
## 只负责黑场、结局名/说明/引语和“按 K 重新开始”，不碰 GameManager 状态。
## 第三层和真 HE 都复用这一份，避免两套结局 UI 慢慢长歪。

signal restart_requested

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const INPUT_DELAY := 0.85

var _active := false
var _ui_ready := false
var _input_delay := 0.0
var _rect: ColorRect
var _vbox: VBoxContainer

func _ready() -> void:
	layer = 5
	set_process_unhandled_input(true)

func show_ending(ending_id: String) -> void:
	if _active:
		return
	_active = true
	_input_delay = INPUT_DELAY
	var data: Dictionary = DataDB.get_ending(ending_id)
	if data.is_empty():
		push_warning("ending_screen: 结局 %s 不在数据表里，用占位文案" % ending_id)
	_build(ending_id, data)

func is_active() -> bool:
	return _active

func is_ui_ready() -> bool:
	return _ui_ready

func _process(delta: float) -> void:
	if _active and _input_delay > 0.0:
		_input_delay = maxf(_input_delay - delta, 0.0)

func _build(ending_id: String, data: Dictionary) -> void:
	_rect = ColorRect.new()
	_rect.name = "Fade"
	_rect.color = Color(0.005, 0.005, 0.006, 1.0)
	_rect.modulate = Color(1, 1, 1, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

	_vbox = VBoxContainer.new()
	_vbox.name = "Content"
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_vbox.position = Vector2(-300, -170)
	_vbox.size = Vector2(600, 340)
	_vbox.modulate = Color(1, 1, 1, 0.0)
	_vbox.add_theme_constant_override("separation", 18)
	add_child(_vbox)

	var font := load(FONT_PATH) as Font
	var kicker := Label.new()
	kicker.text = "结局"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", 16)
	kicker.add_theme_color_override("font_color", Color(0.52, 0.63, 0.60, 0.85))
	if font != null:
		kicker.add_theme_font_override("font", font)
	_vbox.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.text = str(data.get("name", "未知结局"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.86, 0.84, 0.70, 1.0))
	if font != null:
		title.add_theme_font_override("font", font)
	_vbox.add_child(title)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(280, 1)
	rule.color = Color(0.42, 0.52, 0.48, 0.55)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vbox.add_child(rule)

	var desc := Label.new()
	desc.text = str(data.get("desc", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.78, 0.79, 0.74, 0.92))
	if font != null:
		desc.add_theme_font_override("font", font)
	_vbox.add_child(desc)

	var quote := Label.new()
	quote.text = _ending_quote(ending_id)
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.add_theme_font_size_override("font_size", 16)
	quote.add_theme_color_override("font_color", Color(0.58, 0.48, 0.66, 0.9))
	if font != null:
		quote.add_theme_font_override("font", font)
	_vbox.add_child(quote)

	var hint := Label.new()
	# 异化结局是"假结局"：按 K 会坠入深渊打终章，不是重开
	hint.text = "按 K 坠入深渊" if ending_id == "transformed" else "按 K 重新开始"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.52, 0.60, 0.58, 0.85))
	if font != null:
		hint.add_theme_font_override("font", font)
	_vbox.add_child(hint)

	var tween := create_tween()
	tween.tween_property(_rect, "modulate:a", 1.0, 0.8)
	tween.parallel().tween_property(_vbox, "modulate:a", 1.0, 1.0)
	tween.tween_interval(0.2)
	tween.tween_callback(func() -> void: _ui_ready = true)

func _ending_quote(ending_id: String) -> String:
	match ending_id:
		"human":
			return "“你只欠过一次。那一次，是为了活。剩下的路，是你自己走的。”"
		"transformed":
			return "“你数了数献出去的东西，已经凑不成一个人。门外的光认不出你。”"
		"true_he":
			return "“你把伸进胸口的那只手反过来握住了。”"
		"refuse_die":
			# 取自 refuse_die 数据台词，避免结局画面独有一行空白
			return "“你拒绝了献祭。生命一点点流逝……黑暗吞没了你。”"
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if not _active or not _ui_ready or _input_delay > 0.0:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed("interact"):
		return
	restart_requested.emit()
