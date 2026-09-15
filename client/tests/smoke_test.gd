extends SceneTree
## 无头冒烟测试 —— CI 用：
##   godot --headless --path client --script res://tests/smoke_test.gd
## 退出码 0 = 通过，非 0 = 失败。
##
## 注意：--script 模式下 autoload 不作为全局标识符注入编译作用域，
## 必须通过 root.get_node("/root/<名称>") 访问。

var _frames := 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false   # 等 autoload 全部就绪

	var failed := _run_checks()
	print("[smoke] %s" % ("PASS" if not failed else "FAIL"))
	quit(0 if not failed else 1)
	return true

func _run_checks() -> bool:
	var failed := false

	# 1) autoload 单例齐全
	var autoload_names := ["EventBus", "GameManager", "DataDB", "SaveSystem", "Settings", "Network"]
	var nodes := {}
	for autoload_name in autoload_names:
		var node := root.get_node_or_null("/root/%s" % autoload_name)
		if node == null:
			push_error("[smoke] 缺失 autoload: %s" % autoload_name)
			failed = true
		else:
			nodes[autoload_name] = node
	if failed:
		return true

	# 2) GameManager 基础状态机
	var gm: Node = nodes["GameManager"]
	if gm.state != gm.GameState.MAIN_MENU:
		push_error("[smoke] GameManager 初始状态错误: %s" % gm.state)
		failed = true
	gm.start_new_game()
	if gm.sacrifice_count != 0:
		push_error("[smoke] start_new_game 未重置元进度")
		failed = true
	gm.record_sacrifice()
	if gm.sacrifice_count != 1:
		push_error("[smoke] record_sacrifice 计数错误: %d" % gm.sacrifice_count)
		failed = true

	# 2.5) 怪物肢体计数（M1-04：拾取记账 / 献祭消耗）
	gm.add_monster_limb(1)
	if gm.monster_limb_count != 1:
		push_error("[smoke] add_monster_limb 计数错误: %d" % gm.monster_limb_count)
		failed = true
	if not gm.try_consume_monster_limb():
		push_error("[smoke] 有肢体时 try_consume_monster_limb 应返回 true")
		failed = true
	if gm.monster_limb_count != 0:
		push_error("[smoke] 消耗后肢体计数应为 0: %d" % gm.monster_limb_count)
		failed = true
	if gm.try_consume_monster_limb():
		push_error("[smoke] 无肢体时 try_consume_monster_limb 应返回 false")
		failed = true

	# 3) DataDB 数据表加载（M0 允许空表，但结构须可用）
	var data_db: Node = nodes["DataDB"]
	for table_name in ["items", "enemies", "endings"]:
		var rows = data_db.table(table_name)
		if not rows is Dictionary:
			push_error("[smoke] DataDB.table(%s) 类型错误: %s" % [table_name, typeof(rows)])
			failed = true

	# 4) 引擎版本
	var v: Dictionary = Engine.get_version_info()
	if int(v.get("major", 0)) != 4:
		push_error("[smoke] 引擎大版本非 4：%s" % str(v))
		failed = true

	# 5) 攀升竖井（M1-15）纯逻辑断言
	if _run_climb_shaft_checks():
		failed = true

	return failed

## 攀升竖井的纯逻辑断言：速度曲线（10s→5s）、生成可达性、生存目标。
## 只加载脚本（不实例化场景），避免 --script 模式下 autoload 全局不可用的问题。
func _run_climb_shaft_checks() -> bool:
	var failed := false
	var shaft_script = load("res://scripts/world/climb_shaft.gd")
	if shaft_script == null:
		push_error("[smoke] 无法加载 climb_shaft.gd")
		return true

	# 速度曲线：progress 0 → 可视高度/10，progress 1 → 可视高度/5，且末速 > 初速
	var v0: float = shaft_script.fall_speed_for_progress(0.0)
	var v1: float = shaft_script.fall_speed_for_progress(1.0)
	var expect0: float = shaft_script.VISIBLE_HEIGHT / shaft_script.FALL_TIME_START
	var expect1: float = shaft_script.VISIBLE_HEIGHT / shaft_script.FALL_TIME_END
	if not is_equal_approx(v0, expect0):
		push_error("[smoke] 攀升初速错误: %f != %f" % [v0, expect0])
		failed = true
	if not is_equal_approx(v1, expect1):
		push_error("[smoke] 攀升末速错误: %f != %f" % [v1, expect1])
		failed = true
	if v1 <= v0:
		push_error("[smoke] 攀升速度未随时间加快: %f -> %f" % [v0, v1])
		failed = true

	# 可达性：间距上限必须小于安全跳高
	if shaft_script.PLATFORM_GAP_MAX > shaft_script.SAFE_JUMP_HEIGHT:
		push_error("[smoke] 攀升平台间距超过安全跳高")
		failed = true

	# 生成规则：随机 1000 次，间距与水平偏移都在约束内
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var prev_x := 0.0
	for i in range(1000):
		var gap: float = shaft_script.random_gap(rng)
		if gap < shaft_script.PLATFORM_GAP_MIN or gap > shaft_script.PLATFORM_GAP_MAX:
			push_error("[smoke] 攀升间距越界: %f" % gap)
			failed = true
			break
		var next_x: float = shaft_script.random_next_x(prev_x, rng)
		if absf(next_x - prev_x) > shaft_script.PLATFORM_H_SPAN + 0.001:
			push_error("[smoke] 攀升水平偏移越界: %f" % absf(next_x - prev_x))
			failed = true
			break
		prev_x = next_x

	# 生存目标
	if not is_equal_approx(shaft_script.SURVIVE_TIME, 30.0):
		push_error("[smoke] 攀升生存目标应为 30s: %f" % shaft_script.SURVIVE_TIME)
		failed = true

	return failed
