extends SceneTree
## 目标任务提示回归（P0 改版：从背景刻字改为屏幕底部的实时提醒）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/objective_hud_test.gd
##
## 验收四件事：
##   1. 提示挂在 CanvasLayer 上，固定在屏幕底部居中，不随地图/相机滚动，也不跟玩家走；
##   2. 只显示当前这一环的一句：换到下一环时上一句直接消失，背景里不留残影；
##   3. 教程结束（set_active_step(-1)）后提示收起；
##   4. 临时提示（获得铁剑 / 教程完成）单独一层，收它不会把目标提示一起藏掉。

const SCENE := "res://scenes/world/test_arena.tscn"
## 提示条中心距屏幕底边的高度：HINT_BOTTOM(-116) + 高度 36 的一半
const HINT_CENTER_FROM_BOTTOM := 98.0

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var level: Node = load(SCENE).instantiate()
	root.add_child(level)
	await process_frame
	var hud := level.get_node_or_null("ObjectiveHUD")
	var player := level.get_node_or_null("Player") as Node2D
	_check(hud is CanvasLayer, "目标提示应该是屏幕空间的 CanvasLayer")
	_check(hud != null and hud.get_parent() == level, "目标提示不应挂在玩家或其它节点下")
	if hud is CanvasLayer:
		_check(int(hud.layer) >= 1, "目标提示图层太低，会被场景/对话盖住: layer=%d" % int(hud.layer))
	_check(player != null, "缺少玩家")
	if hud != null:
		await _check_single_hint(hud, player)
		await _check_flash_only(hud)
	print("[objective_hud] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 一、二、三：屏幕固定、只留当前一句、结束收起
func _check_single_hint(hud: Node, player: Node2D) -> void:
	hud.call("show_objective", 0, "按 A 或 D 走一段", Vector2(406, 585))
	await create_timer(0.3).timeout
	var hint := hud.get_node_or_null("Hint") as Label
	_check(hint != null, "缺少目标提示 Label（Hint）")
	if hint == null:
		return
	_check(hint.text == "按 A 或 D 走一段", "当前提示文案不对: %s" % hint.text)
	_check(hint.modulate.a >= 0.8, "提示没有淡入（alpha=%.2f）" % hint.modulate.a)
	_check(int(hud.call("get_objective_count")) == 1, "屏幕上应只有 1 条提示")
	# 屏幕固定：文字中心在底部居中，且玩家移动后不动
	var vp := hud.get_viewport().get_visible_rect().size
	var center := hint.get_global_rect().get_center()
	_check(absf(center.x - vp.x * 0.5) < 2.0,
		"提示没有水平居中: %.1f / %.1f" % [center.x, vp.x * 0.5])
	_check(absf(center.y - (vp.y - HINT_CENTER_FROM_BOTTOM)) < 2.0,
		"提示不在屏幕底部: y=%.1f" % center.y)
	var pos_before := hint.global_position
	if player != null:
		player.global_position.x += 260.0
	await process_frame
	_check(hint.global_position.distance_to(pos_before) < 0.5, "玩家移动把提示带走了")

	# 推进到下一环：上一句必须被换掉，背景里不能留下旧字
	hud.call("set_active_step", 1)
	hud.call("show_objective", 1, "跳上这块台子", Vector2(900, 500))
	await create_timer(0.3).timeout
	_check(str(hud.call("get_objective_text", 0)) == "", "上一环的提示还留着")
	_check(str(hud.call("get_objective_text", 1)) == "跳上这块台子", "第二句没显示")
	_check(int(hud.call("get_objective_count")) == 1, "换句后屏幕上出现了多条提示")

	# 教程结束：提示收起
	hud.call("set_active_step", -1)
	await create_timer(0.3).timeout
	_check(int(hud.call("get_objective_count")) == 0, "教程结束后提示没收起")
	_check(hint.modulate.a <= 0.05, "教程结束后提示没有淡出（alpha=%.2f）" % hint.modulate.a)

## 四：临时提示独立一层
func _check_flash_only(hud: Node) -> void:
	hud.call("show_objective", 6, "捡起肢体", Vector2(5250, 575))
	hud.call("show_bubble", "获得铁剑")
	await create_timer(0.3).timeout
	var bubble := hud.get_node_or_null("Bubble") as Label
	if bubble == null:
		_check(false, "缺少临时提示 Bubble")
		return
	_check(bubble.text == "获得铁剑", "临时提示文案没写进 Bubble")
	hud.call("hide_bubble")
	await create_timer(0.3).timeout
	_check(int(hud.call("get_objective_count")) == 1, "收临时提示时把目标提示一起清掉了")
	_check(bubble.modulate.a <= 0.05, "临时提示没有淡出（alpha=%.2f）" % bubble.modulate.a)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[objective_hud] " + msg)
		_failed = true
