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

	return failed
