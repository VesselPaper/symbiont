extends SceneTree
## M4-18 钟厅重排回归（无头）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/bell_hall_test.gd
##
## 组长反馈：“守钟人应该在钟的前面，钟在后面；那里不要有怪；
##            继续剧情不用显示在钟绳上；走到钟下按 K 拉绳，右边的墙才开；
##            东西太紧凑了，水平距离要加大。”
##
## 这张测试把上面每一条都量成数字：
##   顺序   断绳旁白 → 守钟人 → 钟 → 骨门墙（x 严格从小到大）
##   留白   四段之间各留出足够走路的距离，整段钟厅至少有 1400px
##   无怪   钟厅范围内不许有敌人
##   拉绳   骨门初始挡路、只在钟下能拉、拉完才开
##   前后   守钟人画在钟的前面（Mechanisms z 高于 Props）

const SCENE := "res://scenes/world/floor1.tscn"
## 各段之间至少要走这么久（世界 px）：旁白结束到守钟人、守钟人到钟、钟到墙
const MIN_TRIGGER_TO_WATCHMAN := 400.0
const MIN_WATCHMAN_TO_BELL := 250.0
const MIN_BELL_TO_GATE := 300.0
const MIN_HALL_WIDTH := 1400.0

var _level: Node
var _checks := 0
var _failed := false

func _process(_delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_run_checks()
	print("[bell_hall] %s（%d 项）" % ["FAIL" if _failed else "PASS", _checks])
	quit(1 if _failed else 0)
	return true

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed = true
		push_error("[bell_hall] " + message)

func _run_checks() -> void:
	var consts: Dictionary = _level.get_script().get_script_constant_map()
	var hall_left := float(consts.get("BELL_HALL_LEFT", 0.0))
	var hall_width := float(consts.get("BELL_HALL_WIDTH", 0.0))
	var hall_floor := float(consts.get("BELL_HALL_FLOOR_Y", 760.0))
	var bell_x := float(consts.get("BELL_X", 0.0))
	var watchman_x := float(consts.get("WATCHMAN_X", 0.0))
	var gate_x := float(consts.get("BONE_GATE_X", 0.0))
	var hall_right := hall_left + hall_width

	# ---- 地形：钟厅地面真的加长了，而且是一整块平地 ----
	_check(hall_width >= MIN_HALL_WIDTH, "钟厅宽度只有 %.0fpx，没加长" % hall_width)
	var hall_plat := _level.get_node("Terrain/Plat02") as StaticBody2D
	_check(hall_plat != null, "钟厅地面节点不见了")
	if hall_plat != null:
		var rect := (hall_plat.get_node("CollisionShape2D").shape as RectangleShape2D).size
		var left := hall_plat.global_position.x - rect.x * 0.5
		var right := hall_plat.global_position.x + rect.x * 0.5
		var top := hall_plat.global_position.y - rect.y * 0.5
		_check(absf(left - hall_left) < 1.0 and absf(right - hall_right) < 1.0,
			"钟厅地面没从 %.0f 铺到 %.0f（实际 %.0f~%.0f）" % [hall_left, hall_right, left, right])
		_check(absf(top - hall_floor) < 1.0, "钟厅地面顶面 %.0f 应=%.0f" % [top, hall_floor])

	# ---- 顺序：旁白 → 守钟人 → 钟 → 骨门墙 ----
	var trigger := _level.get_node("Triggers/BellTrigger") as Node2D
	var watchman := _level.get_node("Mechanisms/Watchman") as Node2D
	var gate := _level.get_node("Mechanisms/BoneGate") as Node2D
	var bell := _level.get_node("Props/Bell") as Node2D
	_check(trigger != null and watchman != null and gate != null and bell != null, "钟厅节点不齐")
	if trigger == null or watchman == null or gate == null or bell == null:
		return
	# 常量与场景里的实际坐标必须一致，防止有人只改一边
	_check(absf(watchman.global_position.x - watchman_x) < 1.0, "守钟人实际 x=%.0f 与常量 %.0f 不一致" % [
		watchman.global_position.x, watchman_x])
	_check(absf(bell.global_position.x - bell_x) < 1.0, "吊钟实际 x=%.0f 与常量 %.0f 不一致" % [
		bell.global_position.x, bell_x])
	_check(absf(gate.global_position.x - gate_x) < 1.0, "骨门实际 x=%.0f 与常量 %.0f 不一致" % [
		gate.global_position.x, gate_x])
	_check(trigger.global_position.x < watchman_x, "断绳旁白触发点跑到守钟人右边了")
	_check(watchman_x < bell_x, "守钟人应在钟的左边（钟的前面）")
	_check(bell_x < gate_x, "骨门墙应在钟的右边")
	# 全都在钟厅地面以内，不能挂到断口上
	for pair in [["守钟人", watchman_x], ["吊钟", bell_x], ["骨门", gate_x]]:
		var who: String = pair[0]
		var x: float = pair[1]
		_check(x > hall_left + 100.0 and x < hall_right - 100.0, "%s 站到钟厅边缘上了 x=%.0f" % [who, x])
	# 钟必须挂在地面上方、玩家能从底下走过
	_check(bell.global_position.y > hall_floor - 160.0 and bell.global_position.y < hall_floor - 100.0,
		"吊钟离地高度不对 y=%.0f" % bell.global_position.y)

	# ---- 留白：四段之间的距离 ----
	_check(watchman_x - trigger.global_position.x >= MIN_TRIGGER_TO_WATCHMAN,
		"旁白到守钟人只有 %.0fpx，太挤" % (watchman_x - trigger.global_position.x))
	_check(bell_x - watchman_x >= MIN_WATCHMAN_TO_BELL,
		"守钟人到钟只有 %.0fpx，太挤" % (bell_x - watchman_x))
	_check(gate_x - bell_x >= MIN_BELL_TO_GATE,
		"钟到骨门墙只有 %.0fpx，拉完绳一步就到墙" % (gate_x - bell_x))
	# 钟绳判定区不能盖到守钟人身上，也不能盖到墙上
	var reach_right := float(_level.get_node("Mechanisms/BellMechanism").get_script()
		.get_script_constant_map().get("REACH_RIGHT", 110.0))
	_check(bell_x - reach_right > watchman_x, "钟绳判定区伸到了守钟人身上")
	_check(bell_x + reach_right < gate_x, "钟绳判定区伸到了骨门墙上")

	# ---- 钟厅里不许有怪 ----
	var enemies := _level.get_node_or_null("Enemies")
	_check(enemies != null, "缺少 Enemies")
	if enemies != null:
		for enemy in enemies.get_children():
			var ex := (enemy as Node2D).global_position.x
			var inside := ex > hall_left - 120.0 and ex < hall_right + 120.0
			_check(not inside, "钟厅范围内还有怪：%s x=%.0f" % [enemy.name, ex])

	# ---- 拉绳与墙：骨门初始挡路，还没拉绳的时候门不能是开的 ----
	var bell_mech := _level.get_node("Mechanisms/BellMechanism")
	_check(gate.collision_layer == 1, "骨门初始没有挡住玩家")
	_check(not bool(gate.call("is_open")), "骨门进场景就是开的")
	_check(not bool(bell_mech.get("_rung")), "进场景时钟绳就是拉过的状态")

	# ---- 守钟人画在钟的前面 ----
	var mech := _level.get_node("Mechanisms") as Node2D
	var props := _level.get_node("Props") as Node2D
	_check(int(mech.z_index) > int(props.z_index), "守钟人层 z=%d 没压在钟层 z=%d 前面" % [
		int(mech.z_index), int(props.z_index)])

	# ---- 加长后的钟厅要有东西看，不能是空跑道 ----
	var hall_props := props.get_node_or_null("BellHall")
	_check(hall_props != null, "钟厅没有补背景物件（空跑道）")
	if hall_props != null:
		_check(hall_props.get_node_or_null("BellNiche") != null, "钟没有石龛")
		_check(hall_props.get_node_or_null("GateLintel") != null, "骨门没有门楣")
		_check(hall_props.get_node_or_null("GateWall") != null, "骨门后面没有墙")
		# 门洞两侧的墙身必须落到地面，否则门洞左右会漏出背景，看着像两个窟窿
		for wing_name in ["GateWingLeft", "GateWingRight"]:
			var wing := hall_props.get_node_or_null(wing_name) as Polygon2D
			_check(wing != null, "门洞缺%s" % wing_name)
			if wing != null:
				var bottom := wing.position.y + wing.polygon[2].y
				_check(absf(bottom - hall_floor) < 1.0, "%s 没落到地面（底边 %.0f）" % [wing_name, bottom])
		_check(hall_props.get_node_or_null("HallSconce") != null, "缓冲段没有壁灯")
		_check(hall_props.get_child_count() >= 10, "钟厅背景物件只有 %d 个，太空" % hall_props.get_child_count())
