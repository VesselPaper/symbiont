extends CanvasLayer
## 暂停菜单（M1-05）
##
## Esc 打开：保存到槽位 1、读取槽位 1、返回游戏。
## 暂停时整棵树暂停（敌人/玩家/计时器都停），本层 PROCESS_MODE_ALWAYS 仍收输入。
## 读档后如果存档在别的层，先解除暂停再切场景；同层则原地恢复位置/血量。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const TEST_ARENA := "res://scenes/world/test_arena.tscn"
const FLOOR1 := "res://scenes/world/floor1.tscn"
const FLOOR2 := "res://scenes/world/floor2.tscn"
const FLOOR3 := "res://scenes/world/floor3.tscn"
const SAVE_SLOT := 0

var _panel: Panel
var _status: Label
var _save_button: Button
var _load_button: Button
var _bgm_slider: HSlider
var _sfx_slider: HSlider
var _bgm_value: Label
var _sfx_value: Label
var _save_timer: Timer
var _volume_touched := false

func _ready() -> void:
	name = "PauseMenu"
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.005, 0.007, 0.007, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var font := load(FONT_PATH) as Font
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.position = Vector2(450, 150)
	_panel.size = Vector2(380, 420)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.058, 0.060, 0.98)
	style.border_color = Color(0.42, 0.56, 0.48, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var title := Label.new()
	title.name = "Title"
	title.text = "暂停"
	title.position = Vector2(0, 20)
	title.size = Vector2(380, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.84, 0.82, 0.70, 1.0))
	if font != null:
		title.add_theme_font_override("font", font)
	_panel.add_child(title)

	_save_button = _make_button("保存", "SaveButton", 62)
	_save_button.pressed.connect(_on_save_pressed)
	_panel.add_child(_save_button)
	_load_button = _make_button("读档", "LoadButton", 122)
	_load_button.pressed.connect(_on_load_pressed)
	_panel.add_child(_load_button)
	var back := _make_button("返回游戏", "ResumeButton", 182)
	back.pressed.connect(close)
	_panel.add_child(back)

	var audio_heading := Label.new()
	audio_heading.name = "AudioHeading"
	audio_heading.text = "声音"
	audio_heading.position = Vector2(0, 232)
	audio_heading.size = Vector2(380, 22)
	audio_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_heading.add_theme_font_size_override("font_size", 14)
	audio_heading.add_theme_color_override("font_color", Color(0.58, 0.68, 0.62, 0.95))
	if font != null:
		audio_heading.add_theme_font_override("font", font)
	_panel.add_child(audio_heading)

	_bgm_value = _make_volume_label("BgmValue", 256, "背景音乐")
	_panel.add_child(_bgm_value)
	_bgm_slider = _make_slider("BgmSlider", 280, Settings.bgm_volume)
	_bgm_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_bgm_volume(v)
		_update_volume_labels()
		_mark_volume_changed()
	)
	_bgm_slider.drag_ended.connect(func(_changed: bool) -> void: _flush_volume_save())
	_bgm_slider.focus_exited.connect(_flush_volume_save)
	_panel.add_child(_bgm_slider)

	_sfx_value = _make_volume_label("SfxValue", 304, "音效")
	_panel.add_child(_sfx_value)
	_sfx_slider = _make_slider("SfxSlider", 328, Settings.sfx_volume)
	_sfx_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_sfx_volume(v)
		_update_volume_labels()
		_mark_volume_changed()
	)
	_sfx_slider.drag_ended.connect(func(_changed: bool) -> void: _flush_volume_save())
	_sfx_slider.focus_exited.connect(_flush_volume_save)
	_panel.add_child(_sfx_slider)
	_update_volume_labels()

	# 键盘方向键也会改滑条，但不会发 drag_ended；用短延时兜底，关暂停时再强制落盘
	_save_timer = Timer.new()
	_save_timer.name = "SaveTimer"
	_save_timer.wait_time = 0.35
	_save_timer.one_shot = true
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer.timeout.connect(_flush_volume_save)
	add_child(_save_timer)

	_status = Label.new()
	_status.name = "Status"
	_status.position = Vector2(0, 360)
	_status.size = Vector2(380, 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.62, 0.72, 0.64, 0.95))
	if font != null:
		_status.add_theme_font_override("font", font)
	_panel.add_child(_status)

func _make_volume_label(node_name: String, y: float, title: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = Vector2(70, y)
	label.size = Vector2(240, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.72, 0.95))
	var font := load(FONT_PATH) as Font
	if font != null:
		label.add_theme_font_override("font", font)
	label.set_meta("title", title)
	return label

func _make_slider(node_name: String, y: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.position = Vector2(70, y)
	slider.size = Vector2(240, 20)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.focus_mode = Control.FOCUS_ALL
	slider.mouse_entered.connect(func() -> void: GameManager.play_sfx("ui_hover", -12.0))
	slider.focus_entered.connect(func() -> void: GameManager.play_sfx("ui_hover", -12.0))
	return slider

func _update_volume_labels() -> void:
	if _bgm_value != null:
		_bgm_value.text = "%s %d%%" % [str(_bgm_value.get_meta("title")), int(round(Settings.bgm_volume * 100.0))]
	if _sfx_value != null:
		_sfx_value.text = "%s %d%%" % [str(_sfx_value.get_meta("title")), int(round(Settings.sfx_volume * 100.0))]

func _mark_volume_changed() -> void:
	_volume_touched = true
	if _save_timer != null:
		_save_timer.start()

func _flush_volume_save() -> void:
	if _save_timer != null:
		_save_timer.stop()
	if _volume_touched:
		_volume_touched = false
		Settings.save_settings()

func _make_button(text: String, node_name: String, y: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = Vector2(70, y)
	button.size = Vector2(240, 46)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 17)
	var font := load(FONT_PATH) as Font
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_color_override("font_color", Color(0.80, 0.82, 0.76, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.94, 0.92, 0.80, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.08, 0.08, 0.9)
	normal.border_color = Color(0.30, 0.38, 0.35, 0.6)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.16, 0.15, 0.95)
	hover.border_color = Color(0.58, 0.72, 0.58, 0.85)
	button.add_theme_stylebox_override("hover", hover)
	button.mouse_entered.connect(func() -> void: GameManager.play_sfx("ui_hover", -10.0))
	button.focus_entered.connect(func() -> void: GameManager.play_sfx("ui_hover", -12.0))
	button.pressed.connect(func() -> void: GameManager.play_sfx("ui", -2.0))
	return button

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if key.keycode != KEY_ESCAPE:
		return
	if visible:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()

func open() -> void:
	if GameManager.state == GameManager.GameState.ENDING:
		return
	visible = true
	get_tree().paused = true
	GameManager.state = GameManager.GameState.PAUSED
	GameManager.play_sfx("pause", -2.0)
	_status.text = ""
	_volume_touched = false
	_bgm_slider.set_value_no_signal(Settings.bgm_volume)
	_sfx_slider.set_value_no_signal(Settings.sfx_volume)
	_update_volume_labels()
	_load_button.disabled = not SaveSystem.has_save(SAVE_SLOT)
	_save_button.grab_focus()

func close() -> void:
	# 用 Esc 关暂停时立即落盘，避免键盘调完音量马上退出丢掉
	_flush_volume_save()
	visible = false
	get_tree().paused = false
	GameManager.state = GameManager.GameState.PLAYING
	GameManager.play_sfx("ui", -3.0)

func _on_save_pressed() -> void:
	SaveSystem.save(SAVE_SLOT)
	GameManager.play_sfx("checkpoint", -2.0)
	_status.text = "已保存到槽位 1"
	_load_button.disabled = not SaveSystem.has_save(SAVE_SLOT)

func _on_load_pressed() -> void:
	if not SaveSystem.has_save(SAVE_SLOT):
		_status.text = "槽位 1 没有存档"
		return
	SaveSystem.load(SAVE_SLOT)
	GameManager.state = GameManager.GameState.PLAYING
	var target := _scene_for_floor()
	var current := _current_scene_path()
	if current != "" and target != current:
		# 跨层：pending_player 留给新场景 _ready 落地，别套到即将释放的旧玩家
		get_tree().paused = false
		get_tree().change_scene_to_file(target)
	else:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			SaveSystem.apply_pending_player(player)
		close()
		_status.text = "已读档"

## --script 无头测试里 current_scene 可能为空；退回玩家父节点，保证跨层判断仍成立。
func _current_scene_path() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			scene = player.get_parent()
	return scene.scene_file_path if scene != null else ""

func _scene_for_floor() -> String:
	match str(GameManager.current_floor):
		"floor_3":
			return FLOOR3
		"floor_2":
			return FLOOR2
		"floor_1":
			if GameManager.has_flag("floor1_unlocked"):
				return FLOOR1
	return TEST_ARENA
