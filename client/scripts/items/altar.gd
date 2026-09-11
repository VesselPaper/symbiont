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
const HINT_SUCCESS := "献祭已成"
const HINT_NO_LIMB := "你手上没有肢体"

@onready var _hint_label: Label = $HintLabel

var _player_in_range := false
var _feedback_timer := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 中文必须用 Noto Sans CJK，否则渲染成方块（同 dialogue_box / tutorial_hint 的写法）
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

func _unhandled_input(event: InputEvent) -> void:
	# 反向测试（规范第 6 条）：只有 interact(K) 的按下沿才触发献祭，
	# 抬起 / 长按重复(echo) / 其它按键一律忽略，防止自动献祭
	if not _player_in_range:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if _player_input_locked():
		return
	try_sacrifice()

## 公开献祭入口（可测性）：成功消耗一个肢体并记录献祭，返回 true；
## 没有肢体（或 GameManager 不可用）返回 false，失败同样给反馈提示。
func try_sacrifice() -> bool:
	if not GameManager.try_consume_monster_limb():
		_show_feedback(HINT_NO_LIMB)
		return false
	GameManager.record_sacrifice(SACRIFICE_ID)
	_show_feedback(HINT_SUCCESS)
	return true

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
	_hint_label.text = HINT_IN_RANGE
	_hint_label.visible = true

func _hide_hint() -> void:
	_hint_label.visible = false
