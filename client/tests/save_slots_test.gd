extends SceneTree
## 存档位回归（M5-06）：单存档默认开、多存档可选、存档可以起名
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/save_slots_test.gd
##
## 组长要求：「选存档点继续游戏，单存档默认开，多存档可选，玩家可命名。」
## 钉住四件事：
##   ① 默认（Settings.multi_save=false）只有一个槽位，新游戏永远落 1 号槽；
##   ② 打开多存档后槽位变 3 个，新游戏挑空槽；
##   ③ 存档名写进档里，自动存档（不给名字）不会把名字洗掉；
##   ④ 暂停菜单有"返回主菜单"按钮；单存档时存档位按钮点不动。
## 反向：同一份名字不重复生效、关掉多存档后槽位立刻收回 1。

const ARENA := "res://scenes/world/test_arena.tscn"

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var save := root.get_node("SaveSystem")
	var settings := root.get_node("Settings")
	var was_multi := bool(settings.get("multi_save"))
	settings.call("set_multi_save", false)
	# 先把三个槽清干净：这台机器上可能留着上一次跑测试/试玩写的档
	for slot in range(3):
		save.call("delete_slot", slot)

	# ① 单存档：只有 1 个槽，新游戏落 0 号
	_check(int(save.call("slot_count")) == 1, "默认不是单存档")
	_check(int(save.call("pick_new_slot")) == 0, "单存档模式新游戏没落 1 号槽")

	# ② 起名 + 自动存档保留名字
	save.call("save", 0, "第一层的手感")
	_check(str(save.call("slot_name", 0)) == "第一层的手感",
		"存档名没写进去（读到 %s）" % str(save.call("slot_name", 0)))
	var summary := str(save.call("slot_summary", 0))
	_check(summary.contains("第一层的手感"), "摘要里没有存档名（%s）" % summary)
	save.call("save", 0)
	_check(str(save.call("slot_name", 0)) == "第一层的手感",
		"自动存档把名字洗掉了（读到 %s）" % str(save.call("slot_name", 0)))

	# ③ 多存档：3 个槽，0 号已占 → 新游戏挑 1 号
	settings.call("set_multi_save", true)
	_check(int(save.call("slot_count")) == 3, "多存档没有 3 个槽")
	_check(int(save.call("pick_new_slot")) == 1, "0 号已占时没挑 1 号槽")
	save.call("save", 1, "第二层的打法")
	_check(str(save.call("slot_name", 1)) == "第二层的打法", "2 号槽没存住名字")
	# 两个槽各自独立，不会串
	_check(str(save.call("slot_name", 0)) == "第一层的手感", "两个槽的名字串了")

	# ④ 关掉多存档：立刻收回 1 个槽，0 号档还在
	settings.call("set_multi_save", false)
	_check(int(save.call("slot_count")) == 1, "关掉多存档后槽位没收回")
	_check(bool(save.call("has_save", 0)), "关掉多存档把 1 号档弄丢了")

	# ⑤ 暂停菜单：有返回主菜单按钮；单存档时存档位按钮不可点
	var arena: Node2D = load(ARENA).instantiate()
	root.add_child(arena)
	await process_frame
	await process_frame
	var hud := arena.get_node_or_null("GameHUD")
	_check(hud != null, "教学关没挂 HUD")
	var pause := hud.get_node_or_null("PauseMenu") if hud != null else null
	_check(pause != null, "HUD 里没挂暂停菜单")
	if pause != null:
		pause.call("open")
		_check(pause.get_node_or_null("Panel/MainMenuButton") != null, "暂停菜单没有「返回主菜单」")
		var slot_button := pause.get_node_or_null("Panel/SlotButton") as Button
		_check(slot_button != null, "暂停菜单没有存档位按钮")
		if slot_button != null:
			_check(slot_button.disabled, "单存档模式下存档位按钮还能点")
		var toggle := pause.get_node_or_null("Panel/MultiSaveToggle") as CheckButton
		_check(toggle != null, "暂停菜单没有多存档开关")
		pause.call("close")
	arena.queue_free()
	await process_frame

	# 清场：删掉测试写的档，恢复玩家原来的设置
	for slot in range(3):
		save.call("delete_slot", slot)
	settings.call("set_multi_save", was_multi)

	print("[save_slots] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[save_slots] " + msg)
		_failed = true
