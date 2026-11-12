extends SceneTree
## 守门者 Boss 行为回归（M3-02）
## 单独摆一块地板和假玩家，验证激活、远距离蓄力冲撞、半血二阶段和死亡广播。

const BOSS_SCENE := "res://scenes/entities/gatekeeper_boss.tscn"

var _boss: Node
var _dummy: Node2D
var _floor: StaticBody2D
var _elapsed := 0.0
var _started := false
var _failed := false
var _boss_defeated_count := 0
var _saw_attack := false
var _done := false
var _exit_wait := 0

func _process(delta: float) -> bool:
	if _done:
		_exit_wait += 1
		if _exit_wait < 10:
			return false
		quit(0 if not _failed else 1)
		return true
	if not _started:
		_started = true
		_floor = StaticBody2D.new()
		_floor.position = Vector2(3000, 60)
		var shape_node := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(2400, 60)
		shape_node.shape = shape
		_floor.add_child(shape_node)
		root.add_child(_floor)
		_dummy = Node2D.new()
		_dummy.add_to_group("player")
		_dummy.position = Vector2(2800, -2)
		root.add_child(_dummy)
		_boss = load(BOSS_SCENE).instantiate()
		# M4-09：Boss 厅已右移到 2800~4200，测试也得把假战场搬过去，
		# 否则旧测试坐标会被新活动范围夹到假玩家身边，远距离冲撞测不出来
		_boss.position = Vector2(3500, -1)
		root.add_child(_boss)
		var bus := root.get_node("/root/EventBus")
		bus.boss_defeated.connect(func(_id: String) -> void: _boss_defeated_count += 1)
		_boss.call("activate")
		return false
	_elapsed += delta
	var state := str(_boss.call("get_state_name"))
	if state == "TELEGRAPH_CHARGE" or state == "CHARGE":
		_saw_attack = true
	if _elapsed < 2.6:
		return false
	_check(int(_boss.call("get_hp")) == int(_boss.call("get_max_hp")), "Boss 初始血量不对")
	_check(_saw_attack, "远距离没有进入蓄力冲撞")
	# 打掉一半，确认二阶段
	var half := int(_boss.call("get_max_hp")) / 2
	for i in range(half):
		_boss.call("take_damage", 1)
	_check(bool(_boss.call("is_phase2")), "半血没进二阶段")
	# 再打掉剩下，确认死亡广播
	for i in range(half):
		_boss.call("take_damage", 1)
	_check(bool(_boss.call("is_dead")), "血量归零没死")
	_check(_boss_defeated_count == 1, "boss_defeated 应只发一次，实际 %d" % _boss_defeated_count)
	print("[boss] %s" % ("PASS" if not _failed else "FAIL"))
	var gm := root.get_node_or_null("/root/GameManager")
	var audio := gm.get_node_or_null("AudioDirector") if gm != null else null
	if audio != null and audio.has_method("stop_all"):
		audio.call("stop_all")
	_done = true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[boss] " + msg)
		_failed = true
