extends SceneTree
## 地图内目标文字回归（M4-01 初版 / M4-22 组长定稿：做完不消失）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/objective_hud_test.gd
##
## 验收三件事：
##   1. 目标文字是世界坐标（固定在锚点上方），随地图滚动，玩家走过去它不动；
##   2. 每环一句刻上去就留着 —— 推进到下一环后，上一句还在，只是变暗（组长 M4-22 反馈）；
##   3. 临时提示（获得铁剑 / 教程完成）才是会收的那一句，hide_bubble 只收它，不藏整块文字。

const SCENE := "res://scenes/world/test_arena.tscn"
## 当前环比做完的句子亮多少：完成态 alpha 0.30，当前态 0.94，差得远才不会看错
const MIN_ACTIVE_ALPHA := 0.80
const MAX_DONE_ALPHA := 0.45

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var level: Node = load(SCENE).instantiate()
	root.add_child(level)
	await process_frame
	var hud := level.get_node_or_null("ObjectiveHUD") as Node2D
	var player := level.get_node_or_null("Player") as Node2D
	_check(hud != null, "缺少 ObjectiveHUD")
	var old_bubble := level.get_node_or_null("TutorialBubble")
	_check(old_bubble == null, "旧 TutorialBubble 还在，会继续跟玩家")
	if hud != null:
		_check(hud.get_parent() == level, "目标文字不应挂在玩家或其它节点下")
		_check(hud.z_index >= 4 and hud.z_index <= 8, "目标文字层级不对，会被道具挡住: z=%d" % hud.z_index)
		var consts: Dictionary = hud.get_script().get_script_constant_map()
		var offset: Vector2 = consts.get("TEXT_OFFSET", Vector2.ZERO)
		_check(offset.y <= -80.0, "目标文字离锚点太近，会压住地形: %s" % offset)
		var flash := hud.get_node_or_null("Label") as Label
		_check(flash != null, "缺少临时提示 Label")
		_check(player != null, "缺少玩家")
		_check_objectives_stay(hud, player)
		_check_flash_only(hud)
	print("[objective_hud] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 二、三：每环刻字留着、当前环更亮、位置不跟玩家走
func _check_objectives_stay(hud: Node2D, player: Node2D) -> void:
	hud.call("show_objective", 0, "走到前面（A/D）", Vector2(406, 585))
	await process_frame
	var first := str(hud.call("get_objective_text", 0))
	_check(first == "走到前面（A/D）", "第一句没刻上去: %s" % first)
	var label0 := hud.get_node_or_null("Objective0") as Label
	_check(label0 != null, "第一句没有自己的 Label 节点")
	_check(hud.visible, "刻了目标文字后 HUD 还不可见")
	var pos0 := label0.global_position if label0 != null else Vector2.ZERO
	var want := Vector2(406, 585) + Vector2(0, -88)
	# Label 原点是左上角，这里看“文字中心”是不是锚点上方 88px
	var center0 := label0.get_global_rect().get_center() if label0 != null else Vector2.ZERO
	_check(center0.distance_to(want) < 1.0, "第一句中心没挂在锚点上方 88px: %s" % center0)

	if player != null:
		player.global_position.x += 220.0
		await process_frame
	if label0 != null and label0.global_position.distance_to(pos0) > 0.5:
		_check(false, "玩家移动把目标文字带走了")

	# 推进到第二环：第一句必须还在（组长 M4-22：做完不消失）
	hud.call("set_active_step", 1)
	hud.call("show_objective", 1, "跳上平台（空格）", Vector2(900, 500))
	await process_frame
	_check(hud.get_node_or_null("Objective0") != null, "推进到第二环后，第一句被删掉了")
	_check(str(hud.call("get_objective_text", 0)) == "走到前面（A/D）", "第一句的文案被改掉了")
	_check(str(hud.call("get_objective_text", 1)) == "跳上平台（空格）", "第二句没刻上去")
	_check(int(hud.call("get_objective_count")) == 2, "目标文字数量应为 2，实际 %d" % int(hud.call("get_objective_count")))
	var label1 := hud.get_node_or_null("Objective1") as Label
	var a0 := _alpha(label0)
	var a1 := _alpha(label1)
	print("[objective_hud] 第一句 alpha=%.2f（做完） 第二句 alpha=%.2f（当前）" % [a0, a1])
	_check(a1 >= MIN_ACTIVE_ALPHA, "当前那环不够亮: %.2f" % a1)
	_check(a0 <= MAX_DONE_ALPHA, "做完的那句没变暗: %.2f" % a0)

	# 教程结束（set_active_step(-1)）：全部变暗，但一句都不许消失
	hud.call("set_active_step", -1)
	await process_frame
	_check(int(hud.call("get_objective_count")) == 2, "结束态把刻字删掉了")
	_check(_alpha(label0) <= MAX_DONE_ALPHA and _alpha(label1) <= MAX_DONE_ALPHA, "结束态还有句子是亮的")

## 三：临时提示只收自己
func _check_flash_only(hud: Node2D) -> void:
	hud.call("set_bubble_position", Vector2(900, 500))
	hud.call("show_bubble", "获得铁剑")
	await process_frame
	var flash := hud.get_node_or_null("Label") as Label
	_check(flash != null and flash.text == "获得铁剑", "临时提示文案没写进 Label")
	hud.call("hide_bubble")
	await process_frame
	_check(int(hud.call("get_objective_count")) == 2, "收临时提示时把目标刻字一起清掉了")
	_check(hud.visible, "收临时提示后整块目标文字被藏起来了")

## Label 当前正文字色 alpha（在做/做完只差这个）
func _alpha(label: Label) -> float:
	if label == null:
		return -1.0
	return label.get_theme_color("font_color").a

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[objective_hud] " + msg)
		_failed = true
