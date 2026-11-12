extends SceneTree
## 继续游戏回归（M1-05/M1-06）：主菜单读最近存档、按 current_floor 回教学关、玩家位置/血量恢复。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/continue_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"
const MAIN := "res://scenes/main/main.tscn"

var _gm: Node
var _save: Node
var _arena: Node
var _menu: Node
var _elapsed := 0.0
var _phase := 0
var _failed := false
var _saved_pos := Vector2(300, 646)

func _process(delta: float) -> bool:
	if _gm == null:
		_gm = root.get_node("/root/GameManager")
		_save = root.get_node("/root/SaveSystem")
		_gm.set("flags", {})
		_gm.set("sacrifice_count", 0)
		_gm.set("current_floor", "start")
		_gm.set("state", 2)
		_arena = load(ARENA).instantiate()
		root.add_child(_arena)
		return false
	_elapsed += delta
	if _phase == 0 and _elapsed >= 0.4:
		var player := _arena.get_node("Player")
		player.global_position = _saved_pos
		player.set("hp", 4)
		_save.call("save", 0)
		_check(bool(_save.call("has_save", 0)), "测试存档没写成功")
		root.remove_child(_arena)
		_arena.free()
		_arena = null
		_menu = load(MAIN).instantiate()
		root.add_child(_menu)
		_phase = 1
		_elapsed = 0.0
	elif _phase == 1 and _elapsed >= 0.5:
		var cont := _menu.get_node_or_null("MenuUI/Menu/ContinueButton") as Button
		_check(cont != null and cont.visible, "有存档时继续按钮没显示")
		_menu.call("_on_continue_pressed")
		_phase = 2
		_elapsed = 0.0
	elif _phase == 2 and _elapsed >= 1.2:
		var player := root.get_node_or_null("TestArena/Player") as Node2D
		_check(player != null, "继续游戏没回到教学关")
		if player != null:
			print("[continue] player=%s saved=%s" % [player.global_position, _saved_pos])
			_check(player.global_position.distance_to(_saved_pos) < 2.0, "继续游戏没恢复位置")
			_check(int(player.get("hp")) == 4, "继续游戏没恢复血量")
		_check(int(_gm.get("state")) == 2, "继续游戏后没进 PLAYING")
		_save.call("delete_slot", 0)
		_check(not bool(_save.call("has_save", 0)), "测试存档没删干净")
		print("[continue] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[continue] " + msg)
		_failed = true
