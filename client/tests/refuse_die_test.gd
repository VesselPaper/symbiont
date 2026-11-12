extends SceneTree
## 拒绝献祭结局回归（M1-07）：
## 反向：没有肢体时按拒绝不结束；正向：有肢体 → refuse_die 台词 → 黑场 → 结局表标题 → K 回主菜单。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/refuse_die_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _level: Node
var _gm: Node
var _elapsed := 0.0
var _phase := 0
var _failed := false
var _endings: Array[String] = []

func _process(delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_gm.set("flags", {})
		_gm.set("sacrifice_count", 0)
		_gm.set("monster_limb_count", 0)
		_gm.set("state", 2)
		root.get_node("/root/EventBus").ending_reached.connect(func(id: String) -> void: _endings.append(id))
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if _phase == 0 and _elapsed >= 0.35:
		var altar := _level.get_node("Altar")
		_check(bool(altar.get("allow_refuse")), "教学祭坛没开拒绝入口")
		altar.set("_player_in_range", true)
		altar.call("_update_hint")
		var base_hint := altar.get_node("HintLabel") as Label
		_check(base_hint.text == "献上肢体（K）", "没肢体时提前显示了拒绝提示")
		_press_r(altar)
		_phase = 1
		_elapsed = 0.0
	elif _phase == 1 and _elapsed >= 0.15:
		_check(not bool(_level.get("_refusing")), "没有肢体时拒绝误触发了结局")
		_check(int(_gm.get("state")) == 2, "没有肢体时状态被改掉了")
		var hint := _level.get_node("Altar/HintLabel") as Label
		_check(hint.text == "你手上没有肢体", "没有肢体按拒绝没有反馈")
		_gm.set("monster_limb_count", 1)
		var altar := _level.get_node("Altar")
		altar.call("_update_hint")
		_check((altar.get_node("HintLabel") as Label).text == "献上肢体（K） / 拒绝（R）", "有肢体时没显示拒绝提示")
		# 开场低语可能正锁着输入；先收掉它，再按 R 走真实的祭坛输入路径
		_level.get_node("Dialogue").call("_finish")
		_press_r(altar)
		_phase = 2
		_elapsed = 0.0
	elif _phase == 2 and _elapsed >= 0.35:
		_check(bool(_level.get("_refusing")), "有肢体时拒绝没有开始")
		_check(_level.get_node("Tutorial").process_mode == Node.PROCESS_MODE_DISABLED, "拒绝时教程没停")
		_check(not bool(_level.get_node("Altar").get("allow_refuse")), "拒绝后祭坛还能再拒绝")
		_level.get_node("Dialogue").call("_finish")
		_phase = 3
		_elapsed = 0.0
	elif _phase == 3 and _elapsed >= 2.4:
		_check(int(_gm.get("state")) == 4, "拒绝结局没切到 ENDING")
		_check(bool(_gm.call("has_flag", "refuse_die")), "没写 refuse_die 旗标")
		_check(_endings.has("refuse_die"), "没发 ending_reached(refuse_die)")
		var screen := _level.get_node_or_null("EndingScreen")
		_check(screen != null, "拒绝结局没生成结局画面")
		if screen != null:
			var vbox := screen.get_child(1) as VBoxContainer
			var title := vbox.get_child(1) as Label
			_check(title != null and title.text == "拒绝献祭（死）", "拒绝结局标题没从 endings 表读")
			var quote := vbox.get_child(4) as Label
			_check(quote != null and quote.text.contains("黑暗吞没了你"), "拒绝结局引语为空")
			_check(bool(screen.call("is_ui_ready")), "拒绝结局画面没进入可操作状态")
			screen.emit_signal("restart_requested")
		_phase = 4
		_elapsed = 0.0
	elif _phase == 4 and _elapsed >= 0.6:
		_check(root.get_node_or_null("Main") != null, "拒绝结局后没回主菜单")
		_check(int(_gm.get("state")) == 1, "回主菜单后状态不是 MAIN_MENU")
		_check(not bool(_gm.call("has_flag", "refuse_die")), "重新开始没清 refuse_die 旗标")
		print("[refuse_die] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _press_r(altar: Node) -> void:
	var r := InputEventKey.new()
	r.keycode = KEY_R
	r.pressed = true
	altar.call("_unhandled_input", r)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[refuse_die] " + msg)
		_failed = true
