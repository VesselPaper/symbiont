extends SceneTree
## 教学关流程回归：按状态机顺序触发每一步，确认每一步的判定都能推进。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/tutorial_flow_test.gd
##
## M4-21 起没有引导光点，MOVE/JUMP/POGO 三环改成“人真的走到/站上去”：
##   MOVE = 把玩家挪到移动点右边（横向过线）
##   JUMP = 把玩家放到跳台上、等它落地
##   POGO = 把玩家放上下劈方台、等它落地（组长定稿：站上去才算过，不是挥出下劈）
## 其余环仍用 EventBus/直调受击推进。坐标一律从场景的 STAGE 表读，不在这儿抄数字。

const SCENE := "res://scenes/world/test_arena.tscn"

var _level: Node
var _player: CharacterBody2D
var _tutorial: Node
var _dialogue: Node
var _bus: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	# --script 模式要等 autoload 全部挂到 /root 后再实例化场景
	await create_timer(0.2).timeout
	_level = load(SCENE).instantiate()
	root.add_child(_level)
	_player = _level.get_node("Player") as CharacterBody2D
	_tutorial = _level.get_node("Tutorial")
	_dialogue = _level.get_node("Dialogue")
	_bus = root.get_node("/root/EventBus")
	var stage: Dictionary = _level.get_script().get_script_constant_map()["STAGE"]
	await create_timer(0.9).timeout
	# 开场低语正常在 0.5s 启动；直接结束它，等价于玩家按 K 看完第一段
	if bool(_dialogue.get("_active")):
		_dialogue.call("_finish")
	else:
		_bus.dialogue_finished.emit("intro_parasite_1")
	await create_timer(0.15).timeout
	_expect(0, "MOVE")
	# MOVE：走到移动点右边（地面同高，直接挪过去就行）
	await _stand_at(Vector2(float(stage["move_mark"].x) + 30.0, 646.0))
	_expect(1, "JUMP")
	# M4-22 组长定稿：做完的那句不消失，留在地图上当路标（只是变暗）
	_check_objective_kept(0, "走到前面（A/D）")
	# JUMP：站上跳台（顶 571 → 站好后身体中心 558）
	var ledge: Rect2 = stage["ledge"]
	await _stand_at(Vector2(ledge.position.x + 120.0, ledge.position.y - 13.0))
	_expect(2, "WEAPON")
	_player.set("has_weapon", true)
	_bus.item_picked.emit("iron_sword", 1)
	await create_timer(1.4).timeout
	_expect(3, "ATTACK")
	(_level.get_node("DummyA") as Node).call("take_damage", 1)
	await create_timer(0.12).timeout
	_expect(4, "POGO")
	# POGO：站上下劈方台（顶 440 → 身体中心 427）
	var pogo: Rect2 = stage["pogo"]
	await _stand_at(Vector2(pogo.position.x + pogo.size.x * 0.5, pogo.position.y - 13.0))
	_expect(5, "COMBAT")
	_bus.enemy_killed.emit(_level, Vector2(2660, 600))
	await create_timer(0.12).timeout
	_expect(6, "PICKUP")
	_bus.item_picked.emit("monster_limb", 1)
	await create_timer(0.12).timeout
	_expect(7, "SACRIFICE")
	_bus.sacrifice_done.emit("generic", 1)
	await create_timer(0.7).timeout
	_expect(8, "DONE")
	# 八句话全刻在地图上，一句都不许收：组长要的是“路标”，不是弹一次就没
	var hud := _level.get_node_or_null("ObjectiveHUD")
	if hud == null:
		push_error("[tutorial_flow] FAIL 缺少 ObjectiveHUD")
		quit(1)
		return
	var count := int(hud.call("get_objective_count"))
	if count != 8:
		push_error("[tutorial_flow] FAIL 教程结束只剩 %d 句刻字，应 8 句" % count)
		quit(1)
		return
	# 场景里不该再有任何引导光点（M4-21 组长要求删掉）
	var stray := _level.get_node_or_null("guide_mark")
	if stray != null:
		push_error("[tutorial_flow] FAIL 场景里还留着 guide_mark")
		quit(1)
		return
	print("[tutorial_flow] PASS 无光点，八环全部按位置/事件推进")
	quit(0)

## 把玩家放到某处并等它落地（位置判定要求 is_on_floor，空中不算）
func _stand_at(target: Vector2) -> void:
	_player.global_position = target
	for _i in range(90):
		await process_frame
		if _player.is_on_floor():
			break
	await create_timer(0.2).timeout

func _expect(expected_step: int, label: String) -> void:
	var step := int(_tutorial.get("_step"))
	if step != expected_step:
		push_error("[tutorial_flow] FAIL 期望 %s(%d)，实际 step=%d" % [label, expected_step, step])
		quit(1)
		return
	print("[tutorial_flow] %s step=%d" % [label, step])

## 某一环的刻字必须还在、文案没被改（M4-22：做完不消失）
func _check_objective_kept(step: int, text: String) -> void:
	var hud := _level.get_node_or_null("ObjectiveHUD")
	if hud == null:
		push_error("[tutorial_flow] FAIL 缺少 ObjectiveHUD")
		quit(1)
		return
	var label := hud.get_node_or_null("Objective%d" % step)
	if label == null:
		push_error("[tutorial_flow] FAIL 第 %d 环的提示不见了" % step)
		quit(1)
		return
	var now := str(label.get("text"))
	if now != text:
		push_error("[tutorial_flow] FAIL 第 %d 环提示被改成「%s」" % [step, now])
		quit(1)
		return
	print("[tutorial_flow] 第 %d 环提示留着：%s" % [step, now])
