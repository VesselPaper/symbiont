extends SceneTree
## 教学关流程回归：按状态机顺序触发每一步，确认每一步的判定都能推进。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/tutorial_flow_test.gd
##
## M4-21 起没有引导光点，MOVE/JUMP/POGO 三环改成“人真的走到/站上去”：
##   MOVE = 按下 A/D 即算学会（P0 反馈：提示随按键一起收掉）
##   JUMP = 走近跳台才提示"按空格"，按下空格即收；站上平台才算过
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
	# 对话最后一句被 K 取消后，A/D 提示应当已经出现
	_check_hint_now(0, "按 A 或 D 往右走，走一段它自己就熟了。")
	# MOVE：按下 A/D 就说明会走了 —— 提示收掉、门打开，不用再挪到 move_mark
	Input.action_press("move_right")
	await create_timer(0.08).timeout
	Input.action_release("move_right")
	await create_timer(0.1).timeout
	_expect(1, "JUMP")
	# 离第一个跳跃点还远：屏幕上不该有提示
	_check_no_hint()
	var ledge: Rect2 = stage["ledge"]
	# 走近跳台左缘（台下平地）→ "按空格进行跳跃" 出现
	await _stand_at(Vector2(ledge.position.x - 190.0, 646.0))
	_check_hint_now(1, "按空格进行跳跃。")
	# 按下空格 = 做出反应：提示立刻收起，人还站在附近也不许重弹
	Input.action_press("jump")
	await create_timer(0.08).timeout
	Input.action_release("jump")
	await create_timer(0.15).timeout
	_check_no_hint()
	# JUMP：站上跳台（顶 571 → 站好后身体中心 558）
	await _stand_at(Vector2(ledge.position.x + 120.0, ledge.position.y - 13.0))
	_expect(2, "WEAPON")
	# P0 反馈：目标类提示"走近才出现"。刚跳上台时离剑还远，屏幕上不该有字
	_check_no_hint()
	# 走到剑附近（在拾取圈之外）→ 提示出现；退开 → 收起；再走近 → 重新出现
	var sword_x := float(stage["sword"].x)
	await _stand_at(Vector2(sword_x - 150.0, 558.0))
	_check_hint_now(2, "把地上那把铁器捡起来，走近了按 K。")
	await _stand_at(Vector2(sword_x - 420.0, 558.0))
	_check_no_hint()
	await _stand_at(Vector2(sword_x - 150.0, 558.0))
	_check_hint_now(2, "把地上那把铁器捡起来，走近了按 K。")
	_player.set("has_weapon", true)
	_bus.item_picked.emit("iron_sword", 1)
	# "获得铁剑"是操作后的提示，统一播 2 秒再进下一环
	await create_timer(2.3).timeout
	_expect(3, "ATTACK")
	# P0 反馈「获得铁剑一直播放」：气泡只该活 2 秒，进 ATTACK 时必须已经淡掉，
	# 不能因为换环时没人调 hide_bubble 就永久挂在屏幕上
	_check_bubble_hidden()
	# 进攻击环时人还在剑那边（离木桩 900px），提示先不出现；走近木桩才弹
	_check_no_hint()
	await _stand_at(Vector2(float(stage["dummy_a"].x) - 150.0, 558.0))
	_check_hint_now(3, "对着草人按 J，砍一下试试手感。")
	(_level.get_node("DummyA") as Node).call("take_damage", 1)
	await create_timer(0.12).timeout
	_expect(4, "POGO")
	# 打中即成功：提示随动作一起消失（下劈目标还在远处，所以屏幕上应为空）
	_check_no_hint()
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
	# P0 改版：教程结束后提示收起，屏幕上不残留任何目标句
	var hud := _level.get_node_or_null("ObjectiveHUD")
	if hud == null:
		push_error("[tutorial_flow] FAIL 缺少 ObjectiveHUD")
		quit(1)
		return
	var count := int(hud.call("get_objective_count"))
	if count != 0:
		push_error("[tutorial_flow] FAIL 教程结束还留着 %d 条提示，应 0 条" % count)
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

## 屏幕上当前显示的是不是某一环的那句话（P0 改版：提示只在当前环存在）
func _check_hint_now(step: int, text: String) -> void:
	var hud := _level.get_node_or_null("ObjectiveHUD")
	if hud == null:
		push_error("[tutorial_flow] FAIL 缺少 ObjectiveHUD")
		quit(1)
		return
	var now := str(hud.call("get_objective_text", step))
	if now != text:
		push_error("[tutorial_flow] FAIL 第 %d 环提示应为「%s」，实际「%s」" % [step, text, now])
		quit(1)
		return
	if int(hud.call("get_objective_count")) != 1:
		push_error("[tutorial_flow] FAIL 屏幕上应只有当前这一条提示")
		quit(1)
		return
	print("[tutorial_flow] 第 %d 环提示：%s" % [step, now])

## 屏幕上不应有任何目标提示（做完动作 / 该环不提示）
func _check_no_hint() -> void:
	var hud := _level.get_node_or_null("ObjectiveHUD")
	if hud == null:
		push_error("[tutorial_flow] FAIL 缺少 ObjectiveHUD")
		quit(1)
		return
	if int(hud.call("get_objective_count")) != 0:
		push_error("[tutorial_flow] FAIL 做完动作后屏幕上还留着提示")
		quit(1)
		return
	print("[tutorial_flow] 屏幕上无残留提示")

## 临时气泡（获得铁剑）到点后必须淡出，否则会一直挂在屏幕上
## 只查 alpha：hide_bubble 只做淡出，文案留着不影响显示（再显示时会覆盖）
func _check_bubble_hidden() -> void:
	var hud := _level.get_node_or_null("ObjectiveHUD")
	var bubble := hud.get_node_or_null("Bubble") as Label if hud != null else null
	if bubble == null:
		push_error("[tutorial_flow] FAIL 缺少临时气泡 Bubble")
		quit(1)
		return
	if bubble.modulate.a > 0.05:
		push_error("[tutorial_flow] FAIL 「获得铁剑」气泡没有按时收起：alpha=%.2f" % bubble.modulate.a)
		quit(1)
		return
	print("[tutorial_flow] 获得铁剑气泡已按时收起")
