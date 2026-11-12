extends Area2D
## 祭坛（M1-04）
##
## 玩家把"怪物肢体"拿到祭坛按 K 献祭：消耗 GameManager.monster_limb_count 一个，
## 调 record_sacrifice("generic") 广播 sacrifice_done，献祭计数 +1，教程借此推进。
## 占位视觉：暗紫台座（Polygon2D）+ 顶部石台；世界空间 Label 显示操作提示。
## 对话期间（玩家 _input_locked）按 K 不响应，防止与对话的 K 键冲突。
## 献祭逻辑抽成公开方法 try_sacrifice()，便于无头测试直接调用。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const INTERACT_ACTION := "interact"
const SACRIFICE_ID := "generic"

## 反馈提示（献祭成功 / 无肢体）的停留时长（秒），到点恢复"按 K 献祭"
const FEEDBACK_DURATION := 1.2

const HINT_IN_RANGE := "献上肢体（K）"
const HINT_REFUSE := "献上肢体（K） / 拒绝（R）"
const HINT_SUCCESS := "献祭已成"
const HINT_NO_LIMB := "你手上没有肢体"
const HINT_CORRUPTED := "寄生体：第一道馈赠，收下了"
const HINT_RESTORE := "把骨片放回去（K）"
const HINT_RESTORED := "骨片归位了"

## M1-07：只有新手教学阶段开启“拒绝”；第二/三层祭坛不提供这个出口。
signal refuse_requested
var allow_refuse := false

@onready var _hint_label: Label = $HintLabel
@onready var _visual: Node2D = $Visual
@onready var _glow: Sprite2D = $Visual/Glow
@onready var _flame_left: Polygon2D = $Visual/FlameLeft
@onready var _flame_right: Polygon2D = $Visual/FlameRight

var _player_in_range := false
var _feedback_timer := 0.0
var _anim_time := 0.0
var _sequence_active := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 中文必须用 Noto Sans CJK，否则渲染成方块（同 dialogue_box / tutorial_bubble 的写法）
	var font := load(FONT_PATH) as Font
	if font == null:
		push_error("altar: 加载中文字体失败 %s" % FONT_PATH)
	else:
		_hint_label.add_theme_font_override("font", font)
	_hide_hint()

func _process(delta: float) -> void:
	# 反馈提示倒计时：到点恢复基准提示（范围内"按 K 献祭"，离开则隐藏）
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0:
			_update_hint()
	# 祭坛呼吸光 + 烛火抖动（纯表现，不影响献祭逻辑）
	_anim_time += delta
	if _glow != null:
		_glow.modulate.a = 0.30 + sin(_anim_time * 1.6) * 0.05
	var flicker := sin(_anim_time * 17.0) * 0.12 + sin(_anim_time * 29.0) * 0.06
	for flame in [_flame_left, _flame_right]:
		if flame != null:
			flame.scale = Vector2(1.0 + flicker * 0.4, 1.0 + flicker)

func _unhandled_input(event: InputEvent) -> void:
	# 反向测试（规范第 6 条）：只有 interact(K) 的按下沿才触发献祭，
	# 抬起 / 长按重复(echo) / 其它按键一律忽略，防止自动献祭
	if not _player_in_range:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	# R 只在新手教学祭坛可用；是否真的结束由关卡再判断一次（有没有肢体/是否已完成）
	if allow_refuse and (_keycode_is_r(key) and not key.is_action_pressed(INTERACT_ACTION)):
		if not _player_input_locked():
			refuse_requested.emit()
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if _player_input_locked():
		return
	try_sacrifice()

func _keycode_is_r(key: InputEventKey) -> bool:
	return key.keycode == KEY_R or key.physical_keycode == KEY_R

## 关卡在进入教学关时打开；真 HE/其它层保持关闭。
func set_refuse_allowed(enabled: bool) -> void:
	allow_refuse = enabled
	_update_hint()

## 拒绝也需要手里有肢体；没有时给一行反馈，避免 R 像坏键。
func show_no_limb() -> void:
	_show_feedback(HINT_NO_LIMB)

## 公开献祭入口（可测性）：成功消耗一个肢体并记录献祭，返回 true；
## 没有肢体（或 GameManager 不可用）返回 false，失败同样给反馈提示。
func try_sacrifice() -> bool:
	if _sequence_active:
		return false
	# 真 HE：骨片在手时祭坛只认“归还”，不再吃肢体
	if GameManager.has_flag("true_he_relic"):
		return try_restore()
	if not GameManager.try_consume_monster_limb():
		_show_feedback(HINT_NO_LIMB)
		return false
	GameManager.record_sacrifice(SACRIFICE_ID)
	_show_feedback(HINT_SUCCESS)
	_play_sacrifice_sequence()
	return true

## 真 HE 的归还入口：骨片不进“献祭计数”，只开 true_he 旗标并通知关卡。
func try_restore() -> bool:
	if _sequence_active or not GameManager.has_flag("true_he_relic"):
		return false
	if GameManager.has_flag("true_he_unlocked"):
		return false
	_show_feedback(HINT_RESTORE)
	GameManager.play_sfx("altar", -1.0)
	_play_restore_sequence()
	return true

## 献祭演出：肢体从玩家身上飞进石碗，紫雾/触须收拢，祭坛亮一下，再淡掉。
## 逻辑在 record_sacrifice 时已经完成，动画只负责让玩家看见“交出去了什么”。
func _play_sacrifice_sequence() -> void:
	_sequence_active = true
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var start := Vector2(0, -50)
	if player != null:
		start = player.global_position - global_position + Vector2(0, -18)
	var limb_script := load("res://scripts/items/limb_visual.gd")
	var limb := Node2D.new()
	limb.name = "OfferingLimb"
	limb.set_script(limb_script)
	limb.position = start
	limb.z_index = 2
	_visual.add_child(limb)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(limb, "position", Vector2(0, -48), 0.55)
	tw.parallel().tween_property(limb, "scale", Vector2(0.72, 0.72), 0.55)
	tw.parallel().tween_property(limb, "rotation", TAU * 1.3, 0.55)
	tw.tween_property(limb, "modulate:a", 0.0, 0.30)
	tw.tween_callback(limb.queue_free)
	# 石碗上方的紫色触须：从碗口向外抓一下，再收回
	var tendrils: Array[Line2D] = []
	for i in range(3):
		var tendril := Line2D.new()
		tendril.width = 2.2 - i * 0.4
		tendril.default_color = Color(0.58, 0.36, 0.72, 0.0)
		var x := -10.0 + i * 10.0
		tendril.points = PackedVector2Array([
			Vector2(0, -46), Vector2(x, -60), Vector2(x * 1.8, -78), Vector2(x * 2.2, -98),
		])
		_visual.add_child(tendril)
		tendrils.append(tendril)
		var tt := create_tween()
		tt.tween_property(tendril, "default_color:a", 0.72, 0.18)
		tt.tween_interval(0.32)
		tt.tween_property(tendril, "default_color:a", 0.0, 0.26)
		tt.tween_callback(tendril.queue_free)
	var glow_tw := create_tween()
	glow_tw.tween_property(_glow, "modulate:a", 0.82, 0.20)
	glow_tw.tween_property(_glow, "modulate:a", 0.30, 0.55)
	_spawn_sacrifice_flash()
	var finish := create_tween()
	finish.tween_interval(1.05)
	finish.tween_callback(_finish_sacrifice_sequence)

## 归还演出：白色骨片从玩家身上飞回石碗，紫触须这次是缩回去，不是抓过来。
func _play_restore_sequence() -> void:
	_sequence_active = true
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var start := Vector2(0, -50)
	if player != null:
		start = player.global_position - global_position + Vector2(0, -18)
	var shard := Node2D.new()
	shard.name = "ReturnedShard"
	shard.position = start
	shard.z_index = 2
	var bone := Polygon2D.new()
	bone.color = Color(0.86, 0.82, 0.66, 1)
	bone.polygon = PackedVector2Array([
		Vector2(-13, -4), Vector2(-5, -8), Vector2(8, -6),
		Vector2(14, 0), Vector2(7, 4), Vector2(-8, 5),
	])
	shard.add_child(bone)
	var vein := Line2D.new()
	vein.width = 1.2
	vein.default_color = Color(1.0, 0.86, 0.46, 0.95)
	vein.points = PackedVector2Array([Vector2(-11, -2), Vector2(0, -1), Vector2(11, -3)])
	shard.add_child(vein)
	_visual.add_child(shard)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shard, "position", Vector2(0, -48), 0.55)
	tw.parallel().tween_property(shard, "scale", Vector2(0.62, 0.62), 0.55)
	tw.parallel().tween_property(shard, "rotation", -TAU * 1.1, 0.55)
	tw.tween_property(shard, "modulate:a", 0.0, 0.30)
	tw.tween_callback(shard.queue_free)
	# 触须从碗口缩回玩家方向：和献祭时“抓出来”正好相反
	for i in range(3):
		var tendril := Line2D.new()
		tendril.width = 2.0 - i * 0.3
		tendril.default_color = Color(0.72, 0.86, 0.74, 0.0)
		var x := -10.0 + i * 10.0
		tendril.points = PackedVector2Array([
			Vector2(0, -46), Vector2(x, -60), Vector2(x * 1.6, -78), Vector2(x * 2.0, -96),
		])
		_visual.add_child(tendril)
		var tt := create_tween()
		tt.tween_property(tendril, "default_color:a", 0.55, 0.18)
		tt.tween_interval(0.20)
		tt.tween_property(tendril, "default_color:a", 0.0, 0.26)
		tt.tween_callback(tendril.queue_free)
	var glow_tw := create_tween()
	glow_tw.tween_property(_glow, "modulate", Color(0.85, 1.0, 0.82, 0.85), 0.20)
	glow_tw.tween_property(_glow, "modulate", Color(1, 1, 1, 0.30), 0.55)
	_spawn_restore_flash()
	var finish := create_tween()
	finish.tween_interval(1.05)
	finish.tween_callback(_finish_restore_sequence)

func _finish_restore_sequence() -> void:
	_sequence_active = false
	GameManager.flags.erase("true_he_relic")
	GameManager.set_flag("true_he_unlocked")
	GameManager.set_flag("true_he_returned")
	_show_feedback(HINT_RESTORED)
	var parent := get_parent()
	if parent != null and parent.has_method("show_true_he"):
		parent.call("show_true_he")

func _spawn_restore_flash() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RestoreFlash"
	layer.layer = 4
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.82, 0.94, 0.76, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.26, 0.18)
	tw.tween_property(rect, "color:a", 0.0, 0.30)
	tw.tween_callback(layer.queue_free)

func _spawn_sacrifice_flash() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SacrificeFlash"
	layer.layer = 4
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.32, 0.10, 0.46, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.22, 0.18)
	tw.tween_property(rect, "color:a", 0.0, 0.26)
	tw.tween_callback(layer.queue_free)

func _finish_sacrifice_sequence() -> void:
	_sequence_active = false
	_show_feedback(HINT_CORRUPTED)
	_update_hint_after_delay()
	# 演出后再补一句“后果”低语；第一次/第二次不同，让献祭不只是数值 +1
	var count := int(GameManager.sacrifice_count)
	var dialogue_id := "sacrifice_after_1" if count <= 1 else "sacrifice_after_2"
	var timer := get_tree().create_timer(0.55)
	timer.timeout.connect(_play_after_voice.bind(dialogue_id))

func _play_after_voice(dialogue_id: String) -> void:
	if not is_inside_tree():
		return
	var root := get_tree().current_scene
	if root == null:
		return
	var dialogue := root.find_child("Dialogue", true, false)
	if dialogue == null or not dialogue.has_method("play"):
		return
	if dialogue.has_method("is_playing") and bool(dialogue.call("is_playing")):
		return
	dialogue.call("play", dialogue_id)

## 献祭后的提示稍晚回到“按 K”，让“收下了”先停留；这里只重置计时，不抢玩家输入。
func _update_hint_after_delay() -> void:
	if _feedback_timer <= 0.0:
		_update_hint()

func _on_body_entered(body: Node2D) -> void:
	# mask=2 只探测玩家；has_method 兜底防御（只有玩家挂 take_damage，同 limb_pickup）
	if not body.has_method("take_damage"):
		return
	_player_in_range = true
	_update_hint()

func _on_body_exited(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	_player_in_range = false
	_update_hint()

## 对话期间锁输入：duck typing 读玩家 _input_locked（没有该属性视为未锁）
func _player_input_locked() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	return bool(player.get("_input_locked"))

func _show_feedback(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = true
	_feedback_timer = FEEDBACK_DURATION

## 基准提示：玩家在范围内显示"按 K 献祭"，离开隐藏
func _update_hint() -> void:
	if not _player_in_range:
		_hide_hint()
		return
	if GameManager.has_flag("true_he_relic"):
		_hint_label.text = HINT_RESTORE
	elif GameManager.has_flag("true_he_unlocked"):
		_hint_label.text = HINT_RESTORED
	elif allow_refuse and GameManager.monster_limb_count > 0:
		# 有肢体才把 R 摆出来；没肢体时先引导 K，避免提示一个按下去只会被拒绝的键
		_hint_label.text = HINT_REFUSE
	else:
		_hint_label.text = HINT_IN_RANGE
	_hint_label.visible = true

func _hide_hint() -> void:
	_hint_label.visible = false
