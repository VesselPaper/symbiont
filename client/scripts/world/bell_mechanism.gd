extends Area2D
## 锈钟绳（M2-06）
##
## 钟厅的机关入口：靠近按 K 拉绳，由 floor1.gd 统一执行 ring_bell()
## （钟摆动、开骨门、播 floor1_bell_ring）。这里只负责提示和“可拉”状态。

const INTERACT_ACTION := "interact"
const DialogueLocator := preload("res://components/dialogue_locator.gd")
const InteractionPrompt := preload("res://components/interaction_prompt.gd")
## 钟体宽约 148px；左右各给 170px，从哪边走到钟下都能拉。
## 守钟人已经挪到钟的左边 300px（M4-18），不用再为“别把提示铺到 NPC 脸上”做偏置。
const REACH_LEFT := 170.0
const REACH_RIGHT := 170.0
const REACH_Y := 170.0

@export var controller_path: NodePath

var controller: Node
var _dialogue: Node
var _in_range := false
var _rung := false
var _prompt: Label
var _visual: Node2D
var _rope: Line2D
var _handle: Polygon2D
var _time := 0.0

func _ready() -> void:
	# 显式开输入，别依赖节点默认状态；F6 直开场景时也要能收到 F3/K
	set_process_input(true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if controller_path != NodePath(""):
		controller = get_node_or_null(controller_path)
	if controller == null:
		controller = get_parent().get_parent()
	_dialogue = DialogueLocator.resolve(self, controller)
	_build_visual()
	_build_prompt()
	if _is_already_rung():
		_rung = true
		_prompt.visible = false

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	# 从钟腹垂下来的绳：上端伸进钟里，下端是玩家拉的结
	_rope = Line2D.new()
	_rope.width = 3.2
	_rope.default_color = Color(0.35, 0.29, 0.20, 0.92)
	_rope.points = PackedVector2Array([
		Vector2(0, -158), Vector2(2, -112), Vector2(-2, -62),
		Vector2(1, -18), Vector2(0, 18),
	])
	_visual.add_child(_rope)
	_handle = Polygon2D.new()
	_handle.color = Color(0.46, 0.36, 0.23, 0.95)
	_handle.polygon = PackedVector2Array([
		Vector2(-7, 12), Vector2(0, 20), Vector2(7, 12),
		Vector2(5, 22), Vector2(-5, 22),
	])
	_visual.add_child(_handle)
	var knot := Polygon2D.new()
	knot.color = Color(0.25, 0.20, 0.14, 0.9)
	knot.polygon = PackedVector2Array([
		Vector2(-5, 7), Vector2(5, 7), Vector2(4, 13), Vector2(-4, 13),
	])
	_visual.add_child(knot)
	# 绳边两缕断开的旧绳头：对应剧情“钟绳不是自己断的”
	for side in [-1.0, 1.0]:
		var old := Line2D.new()
		old.width = 1.6
		old.default_color = Color(0.26, 0.22, 0.17, 0.55)
		old.points = PackedVector2Array([
			Vector2(side * 8, -88), Vector2(side * 15, -78), Vector2(side * 11, -66),
		])
		_visual.add_child(old)

func _build_prompt() -> void:
	# 钟绳提示要压过钟架/吊梁，避免靠近时只剩半行字
	_prompt = InteractionPrompt.create(
		self, "K 拉钟绳", Vector2(-72, -16), Vector2(144, 26),
		15, Color(0.96, 0.91, 0.72, 1.0), 3, 5, false
	)

func _process(delta: float) -> void:
	_time += delta
	if _visual != null:
		_visual.rotation = sin(_time * 1.4) * 0.012
	_update_nearby_player()
	# 钟绳只负责“拉钟”这一件事（M4-18 组长反馈：别把翻旁白的提示挂在绳子上）。
	# 旁白在播时 K 归对话，绳子的提示就收起来，免得两处提示各说一句。
	_prompt.visible = _in_range and not _rung and not DialogueLocator.is_playing(_dialogue)

## body_entered 在传送、读档、出生点重叠时偶尔会漏；每帧按玩家实际距离再兜一层，
## 保证“人站在钟下”就一定进范围。范围仍限制在钟体附近，不覆盖守钟人。
func _update_nearby_player() -> void:
	var player := _resolve_player()
	if player == null:
		return
	var dx := player.global_position.x - global_position.x
	var dy := absf(player.global_position.y - global_position.y)
	var near := dx >= -REACH_LEFT and dx <= REACH_RIGHT and dy <= REACH_Y
	_in_range = near

## 优先认控制器场景里的 Player，别被切场景时残留的 player 分组节点带偏
func _resolve_player() -> Node2D:
	if controller != null:
		var direct := controller.get_node_or_null("Player") as Node2D
		if direct != null:
			return direct
	return get_tree().get_first_node_in_group("player") as Node2D

## 用 _input 而不是 _unhandled_input：钟绳是单点机关，不能被别的 K 处理器
## （对话/调查点/UI）先吃掉。对话播放中仍然让 K 归对话，不抢。
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not _in_range or _rung or controller == null:
		return
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if DialogueLocator.is_active(_dialogue):
		return
	if controller.has_method("ring_bell"):
		GameManager.play_sfx("chain", -3.0)
		controller.call("ring_bell")
		get_viewport().set_input_as_handled()

func mark_rung() -> void:
	_rung = true
	if _prompt != null:
		_prompt.visible = false

func _is_already_rung() -> bool:
	if controller != null and controller.has_method("has_flag"):
		return bool(controller.call("has_flag", "floor1_bell_rung"))
	return false

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = false
		if _prompt != null:
			_prompt.visible = false
