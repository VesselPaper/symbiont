extends Node2D
## 终章 · 深渊里的精神鏖战
##
## 剧情接在"异化结局"之后：你以为游戏结束了，可灵魂没有消散，
## 坠进比苏醒之地更深的深渊 —— 寄生物的本心禁地。底部万籁俱寂，只有一颗心脏在缓慢搏动。
##
## 玩法：没有平台、没有攻击判定，只有"心智对抗"。
## 心跳每跳一次，画面收紧一次；玩家在它收缩到底之前按下交互键顶回去。
## 顶过 REQUIRED_HITS 次，寄生物的心智崩解 → 你夺回身体 → 真结局。
## 按错时机（心跳间隙乱按）会掉一点"意识"，掉光就退回异化结局。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const SOUL_FLAME := preload("res://components/soul_flame.gd")
const REQUIRED_HITS := 7
const MAX_MISSTAKES := 4
const BEAT_PERIOD := 1.65

var _heart: Node2D
var _heart_core: Polygon2D
var _player_wisp: Node2D
var _label: Label
var _hits_label: Label
var _ui: CanvasLayer
var _time := 0.0
var _beat_phase := 0.0
var _hits := 0
var _mistakes := 0
var _window_open := false
var _finished := false
var _fade: ColorRect
var _camera_shake := 0.0

func _ready() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	EventBus.log_event("abyss_enter", {"hits": _hits})
	_build_world()
	_build_ui()
	_show_text("深渊底部万籁俱寂。\n只有一颗心脏，在缓慢搏动。", 3.4)

func _build_world() -> void:
	var dark := CanvasModulate.new()
	dark.name = "Dark"
	dark.color = Color(0.10, 0.06, 0.09, 1.0)
	add_child(dark)

	# 心跳的光源：整片深渊只有它亮
	_heart = Node2D.new()
	_heart.name = "Heart"
	_heart.position = Vector2(640, 360)
	add_child(_heart)
	var glow := PointLight2D.new()
	glow.texture = _radial_texture()
	glow.texture_scale = 4.2
	glow.energy = 1.1
	glow.color = Color(0.95, 0.42, 0.48)
	_heart.add_child(glow)
	_build_anatomical_heart()
	# 伸出来的寄生物触须
	for i in range(7):
		var a := TAU * float(i) / 7.0
		var tendril := Line2D.new()
		tendril.width = 2.4
		tendril.default_color = Color(0.42, 0.16, 0.32, 0.5)
		var p1 := Vector2(cos(a), sin(a)) * 74.0
		var p2 := Vector2(cos(a + 0.32), sin(a + 0.32)) * 132.0
		var p3 := Vector2(cos(a - 0.18), sin(a - 0.18)) * 196.0
		tendril.points = PackedVector2Array([p1, p2, p3])
		_heart.add_child(tendril)

	# 你的心智：一小团冷白色的光，绕着心脏
	_player_wisp = Node2D.new()
	_player_wisp.name = "Wisp"
	_player_wisp.position = Vector2(640, 610)
	add_child(_player_wisp)
	var wisp := Polygon2D.new()
	wisp.color = Color(0.82, 0.86, 0.90, 0.95)
	wisp.polygon = PackedVector2Array([
		Vector2(0, -18), Vector2(7, -8), Vector2(8, 4),
		Vector2(3, 13), Vector2(-3, 13), Vector2(-8, 4), Vector2(-7, -8),
	])
	_player_wisp.add_child(wisp)
	# 你的心智也在一点点消散：头顶同样挂一层火焰状的白色火舌
	var flame := SOUL_FLAME.new()
	flame.name = "WispFlame"
	flame.position = Vector2(0, -14)
	_player_wisp.add_child(flame)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_ui.layer = 3
	add_child(_ui)
	var font := load(FONT_PATH) as Font

	_label = Label.new()
	_label.name = "Narration"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.position = Vector2(140, 640)
	_label.size = Vector2(1000, 60)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.80, 0.95))
	if font != null:
		_label.add_theme_font_override("font", font)
	_ui.add_child(_label)

	_hits_label = Label.new()
	_hits_label.name = "Hits"
	_hits_label.position = Vector2(40, 30)
	_hits_label.size = Vector2(400, 30)
	_hits_label.add_theme_font_size_override("font_size", 16)
	_hits_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.58, 0.85))
	if font != null:
		_hits_label.add_theme_font_override("font", font)
	_ui.add_child(_hits_label)
	_update_hits()

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.6)

func _process(delta: float) -> void:
	if _finished:
		return
	_time += delta
	_beat_phase += delta
	if _beat_phase >= BEAT_PERIOD:
		_beat_phase -= BEAT_PERIOD
		_start_beat()
	# 心跳收缩：快跳到窗口前放大，窗口内收紧
	var shrink := clampf(_beat_phase / BEAT_PERIOD, 0.0, 1.0)
	var beat_scale := 1.0 + 0.22 * (1.0 - shrink)
	if _window_open:
		beat_scale = 0.86
	# 整体放大 1.35 倍：心脏要占住画面中心，太小会读成模糊一团
	beat_scale *= 1.35
	_heart.scale = Vector2(beat_scale, beat_scale)
	_heart_core.color = Color(0.64, 0.16, 0.22) if _window_open else Color(0.48, 0.10, 0.16)
	if _camera_shake > 0.0:
		_camera_shake = maxf(_camera_shake - delta * 3.0, 0.0)
		position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _camera_shake * 8.0
	# 心念绕心脏缓慢移动
	var a := _time * 0.9
	_player_wisp.position = Vector2(640, 360) + Vector2(cos(a), sin(a) * 0.35) * 210.0

## 心跳进入"可反击窗口"：窗口持续到本拍结束前 0.45 秒
func _start_beat() -> void:
	_window_open = true
	_camera_shake = 0.6
	get_tree().create_timer(maxf(BEAT_PERIOD - 0.45, 0.2)).timeout.connect(func() -> void:
		_window_open = false
	)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo() or _finished:
		return
	if not key.is_action_pressed("interact"):
		return
	if _window_open:
		_hit()
	else:
		_miss()

func _hit() -> void:
	_hits += 1
	_heart_core.color = Color(1.0, 0.85, 0.86)
	_update_hits()
	_camera_shake = 1.2
	var tw := create_tween()
	tw.tween_property(_heart, "scale", Vector2(0.72, 0.72), 0.10)
	tw.tween_property(_heart, "scale", Vector2(1.0, 1.0), 0.22)
	if _hits >= REQUIRED_HITS:
		_win()

func _miss() -> void:
	_mistakes += 1
	_update_hits()
	_show_text("时机错了 —— 它的心念顺着缝隙钻进来。", 1.4)
	if _mistakes >= MAX_MISSTAKES:
		_lose()

func _update_hits() -> void:
	_hits_label.text = "心念 %d / %d    失手 %d / %d" % [_hits, REQUIRED_HITS, _mistakes, MAX_MISSTAKES]

func _show_text(text: String, hold: float) -> void:
	if _label == null:
		return
	_label.text = text
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", 1.0, 0.3)
	tw.tween_interval(maxf(hold, 0.5))
	tw.tween_property(_label, "modulate:a", 0.35, 0.5)

func _win() -> void:
	if _finished:
		return
	_finished = true
	_show_text("它的心跳乱了。\n你听见自己的呼吸。", 2.6)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_heart, "scale", Vector2(0.05, 0.05), 2.2)
	tw.parallel().tween_property(_heart, "modulate:a", 0.0, 2.2)
	tw.tween_callback(func() -> void:
		_show_text("畸变一寸寸退去。\n你重新变回一个普通人。", 3.2)
	)
	tw.tween_interval(3.6)
	tw.tween_callback(_show_true_ending)
	tw.parallel().tween_property(_fade, "color:a", 1.0, 1.2)

func _lose() -> void:
	if _finished:
		return
	_finished = true
	_show_text("你的意识被那一下吞掉了。", 2.4)
	create_tween().tween_property(_fade, "color:a", 1.0, 1.6)
	get_tree().create_timer(2.2).timeout.connect(_show_transformed_ending)

func _show_true_ending() -> void:
	GameManager.set("state", GameManager.GameState.ENDING)
	EventBus.ending_reached.emit("true_he")
	EventBus.log_event("ending_reached", {"ending": "true_he", "abyss_hits": _hits})
	_show_ending("true_he")

func _show_transformed_ending() -> void:
	GameManager.set("state", GameManager.GameState.ENDING)
	EventBus.ending_reached.emit("transformed")
	EventBus.log_event("ending_reached", {"ending": "transformed", "abyss_hits": _hits})
	_show_ending("transformed")

func _show_ending(ending_id: String) -> void:
	var screen := load("res://scenes/ui/ending_screen.tscn").instantiate() as CanvasLayer
	add_child(screen)
	screen.restart_requested.connect(func() -> void:
		GameManager.start_new_game()
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	)
	screen.call("show_ending", ending_id)

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

## 解剖学心脏：不是"心形图标"。左心室为主块，右边贴着右心室，顶部是左右心房，
## 再往上接主动脉弓、肺动脉干与上腔静脉，表面画几条冠状血管。
## _heart_core 指向主块，搏动时只改它的颜色。
func _build_anatomical_heart() -> void:
	var mass := Polygon2D.new()
	mass.name = "Core"
	mass.color = Color(0.48, 0.10, 0.16, 1.0)
	mass.polygon = PackedVector2Array([
		Vector2(-42, -16), Vector2(-26, -32), Vector2(-2, -36),
		Vector2(22, -30), Vector2(42, -10), Vector2(50, 14),
		Vector2(38, 42), Vector2(14, 64), Vector2(-10, 74),
		Vector2(-32, 60), Vector2(-46, 34), Vector2(-50, 4),
	])
	_heart.add_child(mass)
	_heart_core = mass
	var rim := Line2D.new()
	rim.width = 2.0
	rim.default_color = Color(1.0, 0.55, 0.55, 0.38)
	rim.points = mass.polygon
	rim.closed = true
	_heart.add_child(rim)

	# 右心室：贴在主块左侧，比左心室小一圈
	var rv := Polygon2D.new()
	rv.color = Color(0.38, 0.07, 0.12, 1.0)
	rv.polygon = PackedVector2Array([
		Vector2(-50, 0), Vector2(-44, -20), Vector2(-26, -28),
		Vector2(-14, -10), Vector2(-18, 22), Vector2(-30, 46),
		Vector2(-44, 38), Vector2(-52, 18),
	])
	_heart.add_child(rv)

	# 左心房（右上鼓包）
	var la := Polygon2D.new()
	la.color = Color(0.56, 0.16, 0.22, 1.0)
	la.polygon = PackedVector2Array([
		Vector2(4, -38), Vector2(26, -46), Vector2(44, -36),
		Vector2(42, -20), Vector2(22, -24), Vector2(6, -26),
	])
	_heart.add_child(la)

	# 右心房（左上鼓包）
	var ra := Polygon2D.new()
	ra.color = Color(0.52, 0.13, 0.19, 1.0)
	ra.polygon = PackedVector2Array([
		Vector2(-34, -40), Vector2(-12, -44), Vector2(-2, -28),
		Vector2(-16, -22), Vector2(-34, -26),
	])
	_heart.add_child(ra)

	# 主动脉弓：从顶部升起、向右弯再折回去
	var aorta := Polygon2D.new()
	aorta.color = Color(0.62, 0.22, 0.24, 1.0)
	aorta.polygon = PackedVector2Array([
		Vector2(-8, -42), Vector2(4, -42), Vector2(10, -74), Vector2(30, -86),
		Vector2(50, -78), Vector2(58, -60), Vector2(50, -58), Vector2(42, -68),
		Vector2(30, -72), Vector2(22, -60), Vector2(18, -40),
	])
	_heart.add_child(aorta)

	# 肺动脉干：从右心室顶部斜向左上，和主动脉交叉
	var pulmonary := Polygon2D.new()
	pulmonary.color = Color(0.44, 0.15, 0.19, 1.0)
	pulmonary.polygon = PackedVector2Array([
		Vector2(-28, -28), Vector2(-18, -32), Vector2(-22, -64), Vector2(-34, -76),
		Vector2(-46, -68), Vector2(-38, -60), Vector2(-32, -52), Vector2(-36, -28),
	])
	_heart.add_child(pulmonary)

	# 上腔静脉：右侧垂下来的粗管
	var vena := Polygon2D.new()
	vena.color = Color(0.40, 0.15, 0.23, 1.0)
	vena.polygon = PackedVector2Array([
		Vector2(26, -38), Vector2(38, -38), Vector2(40, -82), Vector2(30, -82),
	])
	_heart.add_child(vena)

	# 冠状血管：几条深色分支，让表面不是一块死红
	for pts in [
		PackedVector2Array([Vector2(-38, 22), Vector2(-20, 10), Vector2(-4, 22), Vector2(10, 44)]),
		PackedVector2Array([Vector2(30, -6), Vector2(20, 18), Vector2(26, 42), Vector2(14, 60)]),
		PackedVector2Array([Vector2(-44, 40), Vector2(-30, 34), Vector2(-20, 46)]),
	]:
		var vessel := Line2D.new()
		vessel.width = 1.6
		vessel.default_color = Color(0.26, 0.05, 0.10, 0.85)
		vessel.points = pts
		_heart.add_child(vessel)
