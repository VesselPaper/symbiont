extends Node2D
## 主菜单（M1-06）
##
## 启动先到这里：开始新游戏 / 有存档时显示继续 / 退出。
## 背景全部代码绘制，走冷灰石廊 + 微光的空洞骑士式简洁感，不依赖图片素材。
## 开始新游戏只重置 GameManager 再切教学关；继续则读最近一个本地存档，按 current_floor 回对应层。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const TEST_ARENA := "res://scenes/world/test_arena.tscn"
const FLOOR1 := "res://scenes/world/floor1.tscn"
const FLOOR2 := "res://scenes/world/floor2.tscn"
const FLOOR3 := "res://scenes/world/floor3.tscn"

var _leaving := false
var _start_button: Button
var _continue_button: Button
var _quit_button: Button
var _title: Label
var _subtitle: Label
var _ui: CanvasLayer

func _ready() -> void:
	GameManager.state = GameManager.GameState.MAIN_MENU
	EventBus.log_event("boot", {"state": "main_menu"})
	_build_backdrop()
	_build_ui()
	queue_redraw()

func _draw() -> void:
	var view := get_viewport_rect().size
	# 底色：冷灰石廊，向下更暗
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.032, 0.040, 0.043, 1.0))
	for i in range(12):
		var t := float(i) / 12.0
		draw_rect(
			Rect2(0, view.y * t, view.x, view.y / 12.0 + 1),
			Color(0.055 + 0.020 * (1.0 - t), 0.068 + 0.020 * (1.0 - t), 0.070 + 0.018 * (1.0 - t), 0.16)
		)
	# 远处尖拱：只留轮廓，像被雾吃掉一半
	for x in [90.0, 210.0, 1070.0, 1190.0]:
		var arch := PackedVector2Array([
			Vector2(x - 54, 720), Vector2(x - 54, 300), Vector2(x - 38, 210),
			Vector2(x - 14, 160), Vector2(x, 140), Vector2(x + 14, 160),
			Vector2(x + 38, 210), Vector2(x + 54, 300), Vector2(x + 54, 720),
		])
		draw_polyline(arch, Color(0.15, 0.18, 0.18, 0.45), 2.0)
		draw_line(Vector2(x - 44, 720), Vector2(x - 44, 320), Color(0.07, 0.09, 0.09, 0.6), 6.0)
		draw_line(Vector2(x + 44, 720), Vector2(x + 44, 320), Color(0.07, 0.09, 0.09, 0.6), 6.0)
	# 中央骨环/寄生体轮廓：标题后面的暗纹
	var center := Vector2(view.x * 0.5, 252)
	draw_circle(center, 190, Color(0.28, 0.46, 0.40, 0.035))
	draw_arc(center, 168, 0, TAU, 96, Color(0.46, 0.58, 0.48, 0.12), 1.2)
	draw_arc(center, 206, 0, TAU, 96, Color(0.34, 0.28, 0.42, 0.10), 1.0)
	for i in range(8):
		var a := TAU * i / 8.0 + 0.3
		var p1 := center + Vector2(cos(a), sin(a)) * 168
		var p2 := center + Vector2(cos(a), sin(a)) * 226
		draw_line(p1, p2, Color(0.42, 0.52, 0.44, 0.07), 1.0)
	# 从上方垂下的旧链/藤：细、疏，不抢标题
	for spec in [
		{"x": 300.0, "len": 250.0, "phase": 0.0},
		{"x": 382.0, "len": 170.0, "phase": 1.0},
		{"x": 902.0, "len": 210.0, "phase": 2.0},
		{"x": 1010.0, "len": 280.0, "phase": 3.0},
	]:
		var x := float(spec["x"])
		var length := float(spec["len"])
		var points := PackedVector2Array()
		for i in range(12):
			var t := float(i) / 11.0
			points.append(Vector2(x + sin(t * 6.0 + float(spec["phase"])) * 3.0, t * length))
		draw_polyline(points, Color(0.16, 0.22, 0.20, 0.55), 1.2)
	# 地面雾气：几条横向低透明度带
	for i in range(5):
		var y := 596.0 + i * 22.0
		draw_rect(Rect2(0, y, view.x, 18), Color(0.30, 0.42, 0.38, 0.020 + i * 0.006))
	draw_line(Vector2(0, 698), Vector2(view.x, 698), Color(0.38, 0.46, 0.40, 0.20), 1.0)

func _build_backdrop() -> void:
	# 飘尘：慢慢往上，像地牢里浮着的孢子
	var dust := CPUParticles2D.new()
	dust.name = "Dust"
	dust.amount = 22
	dust.lifetime = 8.0
	dust.preprocess = 4.0
	dust.position = Vector2(640, 700)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(660, 18)
	dust.direction = Vector2(0, -1)
	dust.spread = 24.0
	dust.gravity = Vector2(0, -6)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 8.0
	dust.scale_amount_min = 0.4
	dust.scale_amount_max = 1.1
	dust.color = Color(0.68, 0.82, 0.72, 0.30)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.8))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 8
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	dust.texture = tex
	add_child(dust)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "MenuUI"
	_ui.layer = 1
	add_child(_ui)
	var font := load(FONT_PATH) as Font

	var vbox := VBoxContainer.new()
	vbox.name = "Menu"
	vbox.position = Vector2(440, 150)
	vbox.size = Vector2(400, 470)
	vbox.add_theme_constant_override("separation", 10)
	_ui.add_child(vbox)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "共生之缚"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 54)
	_title.add_theme_color_override("font_color", Color(0.86, 0.84, 0.70, 1.0))
	_title.add_theme_color_override("font_shadow_color", Color(0.10, 0.20, 0.16, 0.75))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	if font != null:
		_title.add_theme_font_override("font", font)
	vbox.add_child(_title)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.text = "S Y M B I O N T"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", Color(0.55, 0.68, 0.62, 0.85))
	if font != null:
		_subtitle.add_theme_font_override("font", font)
	vbox.add_child(_subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(gap)

	_start_button = _make_button("开始新游戏", "StartButton", true)
	_start_button.pressed.connect(_on_start_pressed)
	vbox.add_child(_start_button)

	_continue_button = _make_button("继续游戏", "ContinueButton", false)
	_continue_button.pressed.connect(_on_continue_pressed)
	_continue_button.visible = _latest_save_slot() >= 0
	vbox.add_child(_continue_button)

	_quit_button = _make_button("退出", "QuitButton", false)
	_quit_button.pressed.connect(_on_quit_pressed)
	vbox.add_child(_quit_button)

	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "课程设计 · 2 组 · 2026"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(0, 660)
	footer.size = Vector2(1280, 24)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.44, 0.50, 0.47, 0.7))
	if font != null:
		footer.add_theme_font_override("font", font)
	_ui.add_child(footer)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Enter 确认 · 鼠标点击"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, 625)
	hint.size = Vector2(1280, 20)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.44, 0.54, 0.50, 0.65))
	if font != null:
		hint.add_theme_font_override("font", font)
	_ui.add_child(hint)

	_start_button.grab_focus()

func _make_button(text: String, node_name: String, primary: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(300, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 19)
	var font := load(FONT_PATH) as Font
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_color_override("font_color", Color(0.80, 0.82, 0.76, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.94, 0.92, 0.80, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.72, 0.78, 0.68, 1.0))
	button.add_theme_color_override("font_focus_color", Color(0.94, 0.92, 0.80, 1.0))
	var bg := Color(0.055, 0.070, 0.072, 0.72) if not primary else Color(0.075, 0.105, 0.095, 0.85)
	var border := Color(0.36, 0.52, 0.44, 0.65) if primary else Color(0.30, 0.36, 0.34, 0.55)
	button.add_theme_stylebox_override("normal", _button_style(bg, border, 1))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.16, 0.15, 0.92), Color(0.58, 0.74, 0.60, 0.85), 2))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.04, 0.06, 0.06, 0.95), Color(0.72, 0.84, 0.66, 0.9), 1))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.09, 0.13, 0.12, 0.88), Color(0.58, 0.72, 0.58, 0.85), 2))
	button.mouse_entered.connect(func() -> void: GameManager.play_sfx("ui_hover", -10.0))
	button.focus_entered.connect(func() -> void: GameManager.play_sfx("ui_hover", -12.0))
	button.pressed.connect(func() -> void: GameManager.play_sfx("ui", -2.0))
	return button

func _button_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _latest_save_slot() -> int:
	for slot in range(SaveSystem.MAX_SLOTS - 1, -1, -1):
		if SaveSystem.has_save(slot):
			return slot
	return -1

func _on_start_pressed() -> void:
	if _leaving:
		return
	GameManager.start_new_game()
	_enter_scene(TEST_ARENA)

func _on_continue_pressed() -> void:
	if _leaving:
		return
	var slot := _latest_save_slot()
	if slot < 0:
		return
	SaveSystem.load(slot)
	GameManager.state = GameManager.GameState.PLAYING
	_enter_scene(_scene_for_progress())

func _scene_for_progress() -> String:
	match str(GameManager.current_floor):
		"floor_3":
			return FLOOR3
		"floor_2":
			return FLOOR2
		"floor_1":
			if GameManager.has_flag("floor1_unlocked"):
				return FLOOR1
			return TEST_ARENA
	return TEST_ARENA

func _on_quit_pressed() -> void:
	get_tree().quit()

func _enter_scene(path: String) -> void:
	_leaving = true
	_start_button.disabled = true
	_continue_button.disabled = true
	_quit_button.disabled = true
	var layer := CanvasLayer.new()
	layer.name = "MenuTransition"
	layer.layer = 4
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.005, 0.007, 0.007, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 1.0, 0.40)
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_file(path)
	)
