extends Area2D
## 第二层阵营 NPC（M3-01）
##
## 两个人各说各的：第一次按 K 听提议，第二次按 K 才算把命押在一边。
## 选择提交给关卡脚本，NPC 自己不写 GameManager，方便测试和以后换地图。

const INTERACT_ACTION := "interact"
const DialogueLocator := preload("res://components/dialogue_locator.gd")
const InteractionPrompt := preload("res://components/interaction_prompt.gd")

@export var faction := "engineer"
@export var display_name := "工程师"
@export var offer_id := "floor2_engineer_offer"
@export var confirm_id := "floor2_engineer_confirm"
@export var after_id := "floor2_engineer_after"

var controller: Node

var _dialogue: Node
var _in_range := false
var _heard := false
var _confirm_ready := false
var _choice := ""
var _prompt: Label
var _visual: Node2D
var _time := 0.0

func _ready() -> void:
	add_to_group("faction_npc")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_dialogue = DialogueLocator.resolve(self, controller)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	_build_visual()
	_build_prompt()
	_prompt.visible = false
	_choice = _current_faction()

## 第一次提议播完才允许“确认”：否则同一记 K 既关对话又提交选择。
## 延后一帧再武装，避免 Dialogue 先收到 K 结束对话、NPC 又在同一事件里看到“已结束”。
func _on_dialogue_finished(dialogue_id: String) -> void:
	if dialogue_id == offer_id and _choice == "":
		call_deferred("_arm_confirm")

func _arm_confirm() -> void:
	if _choice == "":
		_confirm_ready = true

func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var shadow := Polygon2D.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.34)
	shadow.polygon = PackedVector2Array([
		Vector2(-22, 7), Vector2(-12, 1), Vector2(0, -1),
		Vector2(13, 1), Vector2(22, 7), Vector2(10, 11), Vector2(-10, 11),
	])
	_visual.add_child(shadow)
	if faction == "engineer":
		_build_engineer()
	else:
		_build_heretic()

func _build_engineer() -> void:
	# 矮壮、围裙、护目镜：一眼和瘦高的祭司分开
	for dx in [-7.0, 7.0]:
		var leg := Polygon2D.new()
		leg.color = Color(0.12, 0.10, 0.085, 1)
		leg.polygon = PackedVector2Array([
			Vector2(dx - 5, 0), Vector2(dx + 5, 0), Vector2(dx + 4, 10), Vector2(dx - 4, 10),
		])
		_visual.add_child(leg)
	var body := Polygon2D.new()
	body.color = Color(0.19, 0.16, 0.13, 1)
	body.polygon = PackedVector2Array([
		Vector2(-15, -25), Vector2(13, -25), Vector2(17, 1),
		Vector2(9, 6), Vector2(-11, 5), Vector2(-18, 0),
	])
	_visual.add_child(body)
	var apron := Polygon2D.new()
	apron.color = Color(0.33, 0.25, 0.16, 0.95)
	apron.polygon = PackedVector2Array([
		Vector2(-11, -18), Vector2(10, -18), Vector2(13, 4),
		Vector2(1, 7), Vector2(-13, 3),
	])
	_visual.add_child(apron)
	var head := Polygon2D.new()
	head.color = Color(0.40, 0.32, 0.25, 1)
	head.polygon = PackedVector2Array([
		Vector2(-10, -37), Vector2(8, -38), Vector2(12, -30),
		Vector2(8, -23), Vector2(-7, -23), Vector2(-12, -30),
	])
	_visual.add_child(head)
	var beard := Polygon2D.new()
	beard.color = Color(0.20, 0.17, 0.15, 1)
	beard.polygon = PackedVector2Array([
		Vector2(-7, -26), Vector2(7, -26), Vector2(4, -15),
		Vector2(0, -12), Vector2(-5, -17),
	])
	_visual.add_child(beard)
	# 护目镜：两道暖琥珀光，工作间里最醒目的点
	for dx in [-5.0, 6.0]:
		var lens := Polygon2D.new()
		lens.color = Color(1.0, 0.68, 0.25, 0.95)
		lens.position = Vector2(dx, -32)
		lens.polygon = PackedVector2Array([
			Vector2(-4, -3), Vector2(4, -3), Vector2(4, 3), Vector2(-4, 3),
		])
		_visual.add_child(lens)
	var strap := Line2D.new()
	strap.width = 1.4
	strap.default_color = Color(0.12, 0.11, 0.10, 0.9)
	strap.points = PackedVector2Array([Vector2(-10, -33), Vector2(10, -33)])
	_visual.add_child(strap)
	# 背后的锅炉和铜管：蒸汽工程师的身份，不用文字说明
	var tank := Polygon2D.new()
	tank.color = Color(0.24, 0.25, 0.22, 1)
	tank.polygon = PackedVector2Array([
		Vector2(-22, -24), Vector2(-12, -26), Vector2(-11, -2), Vector2(-21, 0),
	])
	_visual.add_child(tank)
	var pipe := Line2D.new()
	pipe.width = 3.0
	pipe.default_color = Color(0.42, 0.32, 0.20, 0.9)
	pipe.points = PackedVector2Array([
		Vector2(-18, -26), Vector2(-18, -38), Vector2(-5, -43), Vector2(12, -41),
	])
	_visual.add_child(pipe)
	var valve := Polygon2D.new()
	valve.color = Color(0.48, 0.36, 0.22, 1)
	valve.position = Vector2(-18, -36)
	valve.polygon = _ring_points(5.0, 8)
	_visual.add_child(valve)
	# 机械右臂：比左臂粗一圈，末端握扳手
	var arm := Polygon2D.new()
	arm.color = Color(0.30, 0.28, 0.24, 1)
	arm.polygon = PackedVector2Array([
		Vector2(12, -21), Vector2(21, -18), Vector2(26, -4),
		Vector2(21, 1), Vector2(15, -8),
	])
	_visual.add_child(arm)
	var wrench := Line2D.new()
	wrench.width = 3.0
	wrench.default_color = Color(0.55, 0.46, 0.32, 1)
	wrench.points = PackedVector2Array([
		Vector2(24, 0), Vector2(31, 10), Vector2(33, 18),
	])
	_visual.add_child(wrench)

func _build_heretic() -> void:
	# 瘦高、长袍、骨面具：轮廓往上收，和工程师的横向体块相反
	var robe := Polygon2D.new()
	robe.color = Color(0.105, 0.070, 0.130, 1)
	robe.polygon = PackedVector2Array([
		Vector2(-9, -34), Vector2(8, -35), Vector2(15, -8),
		Vector2(19, 12), Vector2(6, 9), Vector2(0, 13),
		Vector2(-8, 9), Vector2(-19, 12), Vector2(-14, -8),
	])
	_visual.add_child(robe)
	var robe_rim := Line2D.new()
	robe_rim.width = 1.3
	robe_rim.default_color = Color(0.34, 0.24, 0.42, 0.8)
	robe_rim.points = PackedVector2Array([
		Vector2(-9, -33), Vector2(-14, -7), Vector2(-19, 11),
	])
	_visual.add_child(robe_rim)
	var stole := Polygon2D.new()
	stole.color = Color(0.28, 0.12, 0.34, 0.9)
	stole.polygon = PackedVector2Array([
		Vector2(-6, -25), Vector2(0, -27), Vector2(2, 4),
		Vector2(-3, 7), Vector2(-5, 1),
	])
	_visual.add_child(stole)
	var hood := Polygon2D.new()
	hood.color = Color(0.075, 0.050, 0.095, 1)
	hood.polygon = PackedVector2Array([
		Vector2(-13, -32), Vector2(-9, -47), Vector2(0, -52),
		Vector2(9, -46), Vector2(13, -32), Vector2(7, -25), Vector2(-7, -25),
	])
	_visual.add_child(hood)
	var mask := Polygon2D.new()
	mask.color = Color(0.60, 0.56, 0.44, 1)
	mask.polygon = PackedVector2Array([
		Vector2(-7, -34), Vector2(6, -35), Vector2(9, -29),
		Vector2(5, -23), Vector2(0, -21), Vector2(-6, -23), Vector2(-9, -29),
	])
	_visual.add_child(mask)
	for dx in [-3.5, 4.0]:
		var eye := Polygon2D.new()
		eye.color = Color(0.86, 0.46, 1.0, 1)
		eye.position = Vector2(dx, -29)
		eye.polygon = PackedVector2Array([
			Vector2(-2, -1), Vector2(1, -2), Vector2(2, 1), Vector2(-1, 2),
		])
		_visual.add_child(eye)
	var mask_line := Line2D.new()
	mask_line.width = 1.2
	mask_line.default_color = Color(0.22, 0.18, 0.15, 0.8)
	mask_line.points = PackedVector2Array([Vector2(-4, -24), Vector2(4, -24)])
	_visual.add_child(mask_line)
	# 骨杖：上端一个空心环，和封印门上的异教符文同形
	var staff := Line2D.new()
	staff.width = 3.4
	staff.default_color = Color(0.35, 0.29, 0.20, 1)
	staff.points = PackedVector2Array([Vector2(20, 14), Vector2(23, -28), Vector2(20, -58)])
	_visual.add_child(staff)
	var staff_ring := Line2D.new()
	staff_ring.width = 2.0
	staff_ring.default_color = Color(0.62, 0.42, 0.80, 0.9)
	var ring := PackedVector2Array()
	for i in range(13):
		var a := TAU * float(i) / 12.0
		ring.append(Vector2(20 + cos(a) * 9.0, -60 + sin(a) * 9.0))
	staff_ring.points = ring
	_visual.add_child(staff_ring)

func _ring_points(radius: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts

func _build_prompt() -> void:
	_prompt = InteractionPrompt.create(
		self, "K 交谈 · " + display_name, Vector2(-80, -78), Vector2(160, 24),
		14, Color(0.90, 0.88, 0.74, 0.96), 2, 5
	)

func _process(delta: float) -> void:
	_time += delta
	if _visual != null:
		_visual.position.y = sin(_time * 1.1 + (0.0 if faction == "engineer" else 1.7)) * 0.8
	if _prompt == null:
		return
	if _choice != "" and _choice != faction:
		_prompt.visible = false
		return
	_prompt.visible = _in_range and not DialogueLocator.is_playing(_dialogue)
	if _choice == faction and _heard:
		_prompt.text = "K 对话 · %s" % display_name
	elif _choice == "" and _confirm_ready:
		_prompt.text = "K 确认 · %s" % display_name
	else:
		_prompt.text = "K 交谈 · %s" % display_name

func _unhandled_input(event: InputEvent) -> void:
	if not _in_range:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if not DialogueLocator.is_dialogue(_dialogue):
		return
	if DialogueLocator.is_playing(_dialogue):
		return
	var chosen := _current_faction()
	if chosen != "" and chosen != faction:
		return
	if chosen == faction:
		_dialogue.call("play", after_id)
		_prompt.visible = false
		return
	if not _heard:
		_heard = true
		_confirm_ready = false
		_dialogue.call("play", offer_id)
		_prompt.visible = false
		return
	if not _confirm_ready:
		return
	# 第二次 K 才是真的选边：提交后关卡会打开封印门、改玩家外观
	if controller != null and controller.has_method("choose_faction"):
		var ok := bool(controller.call("choose_faction", faction))
		if ok:
			_choice = faction
			_confirm_ready = false
			_dialogue.call("play", confirm_id)
			_prompt.visible = false

func mark_choice(chosen_faction: String) -> void:
	_choice = chosen_faction
	if chosen_faction != faction:
		modulate = Color(0.55, 0.55, 0.58, 0.78)
	else:
		modulate = Color(1, 1, 1, 1)

func _current_faction() -> String:
	if controller != null and controller.has_method("get_faction"):
		return str(controller.call("get_faction"))
	return ""

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_in_range = false
		if _prompt != null:
			_prompt.visible = false
