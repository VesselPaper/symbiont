extends SceneTree
## 真 HE 回归（M3-03）：二周目起点、骨片拾取、祭坛归还、结局优先级。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/true_he_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _level: Node
var _gm: Node
var _elapsed := 0.0
var _phase := 0
var _failed := false
var _sacrifice_before := 0

func _process(delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_gm.set("flags", {})
		_gm.set("faction", "")
		_gm.set("sacrifice_count", 2)
		_gm.set("monster_limb_count", 0)
		_gm.set("state", 2)
		_gm.call("set_flag", "boss_defeated")
		_gm.call("set_flag", "true_he_return")
		_sacrifice_before = int(_gm.get("sacrifice_count"))
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if _phase == 0 and _elapsed >= 0.6:
		_check_setup()
		_phase = 1
	elif _phase == 1 and _elapsed >= 0.8:
		_pick_relic()
		_phase = 2
	elif _phase == 2 and _elapsed >= 1.0:
		_check_pickup()
		var altar := _level.get_node("Altar")
		var ok := bool(altar.call("try_restore"))
		_check(ok, "有骨片时祭坛应接受归还")
		_phase = 3
	elif _phase == 3 and _elapsed >= 3.6:
		_check_ending()
		_press_restart()
		_phase = 4
	elif _phase == 4 and _elapsed >= 4.0:
		_check_restart()
		print("[true_he] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[true_he] " + msg)
		_failed = true

func _check_setup() -> void:
	var tutorial := _level.get_node("Tutorial")
	_check(tutorial.process_mode == Node.PROCESS_MODE_DISABLED, "二周目 Tutorial 没被停用")
	var hud := _level.get_node("ObjectiveHUD") as Node2D
	_check(not hud.visible, "二周目教学目标文字还显示")
	var player := _level.get_node("Player")
	_check(bool(player.get("has_weapon")), "二周目玩家没带剑")
	_check(_level.get_node_or_null("WeaponPickup") == null, "二周目地上的剑还在")
	var relic := _level.get_node_or_null("TrueHEProps/OriginRelic")
	_check(relic != null, "二周目起点没生成骨片")
	if relic != null:
		_check(absf(relic.global_position.x - 430.0) < 2.0, "骨片没放在起点平台上")
	for spec in [
		"move", "jump", "attack", "pogo", "combat",
	]:
		var gate := _level.get_node_or_null("TutorialGates/Gate_%s" % spec)
		_check(gate == null or bool(gate.call("is_open")), "二周目教学门 %s 没开" % spec)
	var db := root.get_node("/root/DataDB")
	for id in ["true_he_return", "true_he_relic_pickup"]:
		var row: Dictionary = db.get_dialogue(id)
		_check(not row.is_empty(), "缺少真 HE 对话 %s" % id)
		_check((row.get("lines", []) as Array).size() >= 2, "真 HE 对话 %s 太短" % id)
	var ending: Dictionary = db.call("get_ending", "true_he")
	_check(not ending.is_empty(), "结局表缺少 true_he")

func _pick_relic() -> void:
	var relic := _level.get_node_or_null("TrueHEProps/OriginRelic")
	if relic == null:
		return
	var player := _level.get_node("Player")
	relic.call("_on_body_entered", player)

func _check_pickup() -> void:
	_check(bool(_gm.call("has_flag", "true_he_relic")), "拾取骨片没写 true_he_relic")
	_check(int(_gm.get("sacrifice_count")) == _sacrifice_before, "拾取骨片误加了献祭数")

func _check_ending() -> void:
	_check(bool(_gm.call("has_flag", "true_he_unlocked")), "归还后没写 true_he_unlocked")
	_check(not bool(_gm.call("has_flag", "true_he_relic")), "归还后骨片旗标没清掉")
	_check(bool(_gm.call("has_flag", "true_he_returned")), "缺少 true_he_returned 旗标")
	_check(int(_gm.get("sacrifice_count")) == _sacrifice_before, "归还被算成一次献祭")
	_check(int(_gm.get("state")) == 4, "真 HE 没把 GameManager 切到 ENDING")
	var screen := _level.get_node_or_null("EndingScreen")
	_check(screen != null, "真 HE 没生成结局画面")
	if screen != null:
		var vbox := screen.get_child(1) as VBoxContainer
		var title := vbox.get_child(1) as Label
		_check(title != null and title.text == "真结局 HE", "真 HE 标题没从 endings 表读")
		_check(bool(screen.call("is_ui_ready")), "真 HE 结局画面没进入可操作状态")

func _press_restart() -> void:
	var screen := _level.get_node_or_null("EndingScreen")
	if screen == null:
		return
	var event := InputEventKey.new()
	event.keycode = KEY_K
	event.physical_keycode = KEY_K
	event.pressed = true
	screen.call("_unhandled_input", event)

func _check_restart() -> void:
	_check(int(_gm.get("state")) == 2, "按 K 后 GameManager 没回 PLAYING")
	_check((_gm.get("flags") as Dictionary).is_empty(), "按 K 后真 HE 旗标没清")
	_check(str(_gm.get("current_floor")) == "floor_1", "按 K 后没回默认楼层")
