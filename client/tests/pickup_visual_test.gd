extends SceneTree
## 剑插地与拾取动画回归（M2-05）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/pickup_visual_test.gd
##
## 验收：铁剑场景有反向补偿的地面层、阴影、裂纹；碰到后不会当帧消失，
## 至少经过上浮淡出动画再 queue_free。反向：GroundFX 只给铁剑，不给肢体。
## 用真实计时器而不是帧数：无头模式帧率不稳定，动画要按时间验。

const SWORD_SCENE := "res://scenes/items/weapon_pickup.tscn"
const LIMB_SCENE := "res://scenes/items/limb_pickup.tscn"

var _sword: Area2D
var _limb: Area2D
var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	_sword = load(SWORD_SCENE).instantiate()
	root.add_child(_sword)
	_limb = load(LIMB_SCENE).instantiate()
	root.add_child(_limb)
	await process_frame

	_check_ground_fx()
	var fake_target := FakeTarget.new()
	_sword.call("_on_body_entered", fake_target)
	fake_target.free()
	await create_timer(0.05).timeout
	_check(is_instance_valid(_sword), "拾取动画播放中节点被提前销毁")
	if is_instance_valid(_sword):
		var visual: Node2D = _sword.get_node_or_null("Visuals") as Node2D
		_check(visual != null, "缺少剑视觉节点")
		if visual != null:
			_check(visual.modulate.a < 1.0, "拾取时没有开始淡出")
	_check(_limb.get_node_or_null("GroundFX") == null, "肢体不应生成剑的地面层")

	await create_timer(0.55).timeout
	_check(not is_instance_valid(_sword), "拾取动画结束后剑没有销毁")
	print("[pickup_visual] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check_ground_fx() -> void:
	_check(is_instance_valid(_sword), "剑场景没有加载")
	if not is_instance_valid(_sword):
		return
	var ground: Node2D = _sword.get_node_or_null("GroundFX") as Node2D
	_check(ground != null, "缺少 GroundFX 地面层")
	if ground != null:
		_check(is_equal_approx(ground.rotation, -_sword.rotation), "地面层没有反向补偿剑的旋转")
		_check(ground.get_node_or_null("Shadow") != null, "缺少剑的地面阴影")
		_check(ground.get_node_or_null("Crack") != null, "缺少剑尖裂纹")
		_check(ground.get_node_or_null("Dust") != null, "缺少插地尘粒")
	_check(not _limb.has_node("GroundFX"), "肢体不应有 GroundFX")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[pickup_visual] " + message)
		_failed = true

class FakeTarget extends Node2D:
	func take_damage(_amount: int) -> void:
		pass
