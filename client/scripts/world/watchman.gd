extends Area2D
## 守钟人（M2-06）
##
## 设定：上一批献祭失败后被锁在钟下的容器，割断钟绳阻止钟声。
## 不是凭空出现的活人，模型是半埋的锁链躯干；靠近按 K 可反复对话。
## 敲钟后自动切到 floor1_watchman_after，台词反映钟声已响。

const INTERACT_ACTION := "interact"
const DialogueLocator := preload("res://components/dialogue_locator.gd")
const InteractionPrompt := preload("res://components/interaction_prompt.gd")
const DIALOGUE_ID := "floor1_watchman"
const AFTER_DIALOGUE_ID := "floor1_watchman_after"

@export var dialogue_path: NodePath

var _dialogue: Node
var _in_range := false
var _after := false
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
	var shadow := Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.36)
	shadow.polygon = PackedVector2Array([
		Vector2(-24, 8), Vector2(-15, 2), Vector2(0, 0),
		Vector2(16, 2), Vector2(24, 8), Vector2(12, 12), Vector2(-12, 12),
	])
	_visual.add_child(shadow)
	# 跪坐/半埋的斗篷躯干，轮廓压低，不抢钟的剪影
	var cloak := Polygon2D.new()
	cloak.color = Color(0.085, 0.105, 0.110, 0.96)
	cloak.polygon = PackedVector2Array([
		Vector2(-22, 4), Vector2(-17, -18), Vector2(-8, -28),
		Vector2(4, -27), Vector2(14, -17), Vector2(22, 3),
		Vector2(15, 11), Vector2(-14, 11),
	])
	_visual.add_child(cloak)
	var hood := Polygon2D.new()
	hood.color = Color(0.055, 0.070, 0.078, 0.98)
	hood.polygon = PackedVector2Array([
		Vector2(-12, -22), Vector2(-6, -34), Vector2(5, -34),
		Vector2(12, -23), Vector2(7, -12), Vector2(-6, -13),
	])
	_visual.add_child(hood)
	var face := Polygon2D.new()
	face.color = Color(0.16, 0.17, 0.16, 1.0)
	face.polygon = PackedVector2Array([
		Vector2(-6, -25), Vector2(6, -25), Vector2(5, -15), Vector2(-5, -15),
	])
	_visual.add_child(face)
	var eye := Polygon2D.new()
	eye.color = Color(0.72, 0.84, 0.66, 0.85)
	eye.position = Vector2(2, -20)
	eye.polygon = PackedVector2Array([
		Vector2(-2, -1), Vector2(0, -2), Vector2(2, 0), Vector2(0, 2),
	])
	_visual.add_child(eye)
	# 断臂与锁链：告诉玩家他是被锁住的，不是普通路人
	var stump := Polygon2D.new()
	stump.color = Color(0.12, 0.09, 0.10, 0.9)
	stump.position = Vector2(18, -4)
	stump.polygon = PackedVector2Array([
		Vector2(-4, -4), Vector2(5, -2), Vector2(4, 5), Vector2(-5, 3),
	])
	_visual.add_child(stump)
	for i in range(3):
		var chain := Line2D.new()
		chain.width = 2.0
		chain.default_color = Color(0.30, 0.32, 0.30, 0.75)
		chain.points = PackedVector2Array([
			Vector2(-20 + i * 4, -8),
			Vector2(-32 + i * 5, 2 + i * 4),
			Vector2(-38 + i * 5, 15 + i * 3),
		])
		_visual.add_child(chain)
	# 钟绳的断头挂在他腰边：视觉上把 NPC 和钟厅机关连起来
	var rope := Line2D.new()
	rope.width = 2.4
	rope.default_color = Color(0.34, 0.27, 0.18, 0.7)
	rope.points = PackedVector2Array([
		Vector2(20, -10), Vector2(27, 1), Vector2(24, 14), Vector2(18, 18),
	])
	_visual.add_child(rope)

func _build_prompt() -> void:
	# 守钟人靠墙站，头顶提示容易被钟架/披风挡住，抬到道具之上
	_prompt = InteractionPrompt.create(
		self, "K 对话 · 守钟人", Vector2(-72, -64), Vector2(144, 24),
		14, Color(0.86, 0.90, 0.80, 0.95), 2, 5
	)

func _process(delta: float) -> void:
	_time += delta
	if _visual != null:
		# 呼吸很轻：他是半死的，不是站着的活人
		_visual.position.y = sin(_time * 1.3) * 0.7
	_prompt.visible = _in_range and not DialogueLocator.is_playing(_dialogue)

func _unhandled_input(event: InputEvent) -> void:
	if not _in_range or not DialogueLocator.is_dialogue(_dialogue):
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if DialogueLocator.is_playing(_dialogue):
		return
	_dialogue.call("play", AFTER_DIALOGUE_ID if _after else DIALOGUE_ID)
	_prompt.visible = false

func mark_bell_rung() -> void:
	_after = true

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = false
		if _prompt != null:
			_prompt.visible = false
