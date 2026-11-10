extends SceneTree
## 教学关流程回归：不靠手动跑图，按状态机顺序触发每一步，确认指引光停点和剧情推进。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/tutorial_flow_test.gd
##
## 只用 EventBus / 直调受击，不测试实际手柄手感；目的是防止以后改光点坐标或
## 对话/教程顺序时把流程改断。

const SCENE := "res://scenes/world/test_arena.tscn"
const MOVE_TARGET := Vector2(475, 628)
const JUMP_TARGET := Vector2(750, 528)
const WEAPON_TARGET := Vector2(830, 528)
const ATTACK_TARGET := Vector2(940, 508)
const POGO_TARGET := Vector2(1180, 404)
const COMBAT_TARGET := Vector2(1870, 552)
const SACRIFICE_TARGET := Vector2(2221, 498)

var _level: Node
var _player: CharacterBody2D
var _tutorial: Node
var _marker: Node2D
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
	_marker = _level.get_node("guide_mark") as Node2D
	_dialogue = _level.get_node("Dialogue")
	_bus = root.get_node("/root/EventBus")
	await create_timer(0.9).timeout
	# 开场低语正常在 0.5s 启动；直接结束它，等价于玩家按 K 看完第一段
	if bool(_dialogue.get("_active")):
		_dialogue.call("_finish")
	else:
		_bus.dialogue_finished.emit("intro_parasite_1")
	await create_timer(0.15).timeout
	_expect(0, "MOVE")
	await _touch(MOVE_TARGET)
	_expect(1, "JUMP")
	await _touch(JUMP_TARGET)
	_expect(2, "WEAPON")
	_player.set("has_weapon", true)
	_bus.item_picked.emit("iron_sword", 1)
	await create_timer(1.4).timeout
	_expect(3, "ATTACK")
	(_level.get_node("DummyA") as Node).call("take_damage", 1)
	await create_timer(0.12).timeout
	_expect(4, "POGO")
	(_level.get_node("DummyB") as Node).call("take_damage", 1)
	await create_timer(0.12).timeout
	_expect(5, "COMBAT")
	_bus.enemy_killed.emit(_level, Vector2(1870, 600))
	await create_timer(0.12).timeout
	_expect(6, "PICKUP")
	_bus.item_picked.emit("monster_limb", 1)
	await create_timer(0.12).timeout
	_expect(7, "SACRIFICE")
	_bus.sacrifice_done.emit("generic", 1)
	await create_timer(0.7).timeout
	_expect(8, "DONE")
	if not _marker.visible:
		print("[tutorial_flow] PASS 光点已淡出")
		quit(0)
	else:
		push_error("[tutorial_flow] FAIL DONE 后光点仍可见")
		quit(1)

func _touch(pos: Vector2) -> void:
	_player.global_position = pos
	await create_timer(0.8).timeout

func _expect(expected_step: int, label: String) -> void:
	var step := int(_tutorial.get("_step"))
	if step != expected_step:
		push_error("[tutorial_flow] FAIL 期望 %s(%d)，实际 step=%d" % [label, expected_step, step])
		quit(1)
		return
	print("[tutorial_flow] %s step=%d marker=%s" % [label, step, str(_marker.global_position)])
