extends SceneTree
## 主菜单回归（M1-06）：标题/按钮、无存档时隐藏继续、开始新游戏进教学关。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/main_menu_test.gd

const MAIN := "res://scenes/main/main.tscn"

var _menu: Node
var _gm: Node
var _save: Node
var _elapsed := 0.0
var _phase := 0
var _failed := false
var _start_presses := 0

func _process(delta: float) -> bool:
	if _menu == null:
		_gm = root.get_node("/root/GameManager")
		_save = root.get_node("/root/SaveSystem")
		_gm.set("flags", {})
		_gm.set("sacrifice_count", 0)
		_gm.set("state", 0)
		_menu = load(MAIN).instantiate()
		root.add_child(_menu)
		return false
	_elapsed += delta
	if _phase == 0 and _elapsed >= 0.5:
		_check_menu()
		_menu.call("_on_start_pressed")
		_start_presses += 1
		# 立刻再按一次：_leaving 挡住重复切场景
		_menu.call("_on_start_pressed")
		_start_presses += 1
		_phase = 1
	elif _phase == 1 and _elapsed >= 1.3:
		_check_entered()
		print("[main_menu] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[main_menu] " + msg)
		_failed = true

func _check_menu() -> void:
	var title := _menu.get_node_or_null("MenuUI/Menu/Title") as Label
	_check(title != null and title.text == "共生之缚", "主菜单标题不对")
	var start := _menu.get_node_or_null("MenuUI/Menu/StartButton") as Button
	_check(start != null and start.text == "开始新游戏", "缺少开始新游戏按钮")
	var quit_button := _menu.get_node_or_null("MenuUI/Menu/QuitButton") as Button
	_check(quit_button != null and quit_button.text == "退出", "缺少退出按钮")
	var cont := _menu.get_node_or_null("MenuUI/Menu/ContinueButton") as Button
	_check(cont != null, "缺少继续游戏按钮")
	if cont != null:
		var expected := false
		for slot in range(int(_save.get("MAX_SLOTS"))):
			if bool(_save.call("has_save", slot)):
				expected = true
		_check(cont.visible == expected, "继续按钮显隐与本地存档不一致")
	_check(int(_gm.get("state")) == 1, "主菜单没把 GameManager 置为 MAIN_MENU")

func _check_entered() -> void:
	# 开始新游戏先演序章（灵魂苏醒 → 触碰本心 → 获得躯体），不再直接进教学关
	_check(root.get_node_or_null("Prologue") != null, "开始新游戏没进序章")
	_check(int(_gm.get("state")) == 2, "开始新游戏后 GameManager 没进 PLAYING")
	_check((_gm.get("flags") as Dictionary).is_empty(), "开始新游戏没清空旗标")
	_check(_start_presses == 2, "测试没有按两次开始")
