extends Area2D
## 可重复调查点（M2-05）
##
## 第一层原来的剧情是 Area2D 一次性触发：走进去播一次，之后再也看不到。
## 这里做成玩家主动按 K 的"调查点"：
##   - 靠近才显示物件上方的小提示，不挂玩家头顶
##   - 按 K 播放 dialogue_id；播完还能再按，不写 GameManager 旗标
##   - 对话进行中不抢 K，提示自动隐藏
##
## 视觉是代码生成的小符文/眼睛，不依赖贴图；提示用 Noto Sans CJK。

const INTERACT_ACTION := "interact"
const DialogueLocator := preload("res://components/dialogue_locator.gd")
const InteractionPrompt := preload("res://components/interaction_prompt.gd")
const PROMPT_OFFSET := Vector2(0, -54)

## 要播放的对话 id（floor1_bell / floor1_altar / ...）
@export var dialogue_id := ""
## 物件上方的提示文字，默认"调查"
@export var prompt_text := "调查"
## 对话组件；不配则退化为找场景里第一个有 play() 的 Dialogue 节点
@export var dialogue_path: NodePath

var _player_in_range := false
var _dialogue: Node
var _prompt: Label
var _visual: Node2D
var _time := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_dialogue = DialogueLocator.resolve(self, null, dialogue_path)
	_build_visual()
	_build_prompt()
	_prompt.visible = false

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var glow := Sprite2D.new()
	glow.texture = _radial_texture()
	glow.modulate = Color(0.55, 0.86, 0.82, 0.10)
	glow.scale = Vector2(0.75, 0.75)
	_visual.add_child(glow)
	var rune := Polygon2D.new()
	rune.name = "Rune"
	rune.color = Color(0.34, 0.62, 0.58, 0.55)
	rune.polygon = PackedVector2Array([
		Vector2(0, -17), Vector2(9, 0), Vector2(0, 17), Vector2(-9, 0),
	])
	_visual.add_child(rune)
	var inner := Polygon2D.new()
	inner.color = Color(0.070, 0.105, 0.100, 0.95)
	inner.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(5, 0), Vector2(0, 10), Vector2(-5, 0),
	])
	_visual.add_child(inner)
	var eye := Line2D.new()
	eye.width = 1.2
	eye.default_color = Color(0.72, 0.95, 0.88, 0.75)
	eye.points = PackedVector2Array([Vector2(-5, 0), Vector2(0, -4), Vector2(5, 0)])
	_visual.add_child(eye)

func _build_prompt() -> void:
	# 试玩反馈“提示被挡住”：调查点是纯 UI 提示，画在祭坛/壁龛等道具之上
	_prompt = InteractionPrompt.create(
		self, "K 调查 · " + prompt_text, PROMPT_OFFSET + Vector2(-70, -12), Vector2(140, 24),
		14, Color(0.72, 0.88, 0.85, 0.95), 2, 5
	)

func _process(delta: float) -> void:
	_time += delta
	if _visual != null:
		_visual.modulate.a = 0.78 + sin(_time * 2.2) * 0.12
	_prompt.visible = _player_in_range and not DialogueLocator.is_playing(_dialogue)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or not DialogueLocator.is_dialogue(_dialogue):
		return
	# 反向测试：只认 K 的按下沿，抬起 / 长按 echo / 其它键都不触发
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if DialogueLocator.is_playing(_dialogue):
		return
	_dialogue.call("play", dialogue_id)
	_prompt.visible = false

func _on_body_entered(body: Node2D) -> void:
	# collision_mask=2 只探测玩家；用分组兜底，避免把尸体/肢体当玩家
	if body.is_in_group("player"):
		_player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _prompt != null:
			_prompt.visible = false

func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex
