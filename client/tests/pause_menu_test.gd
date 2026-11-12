extends SceneTree
## 存档/暂停回归（M1-05）：Esc 暂停、保存到槽位 1、改状态后读档恢复。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/pause_menu_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _level: Node
var _gm: Node
var _save: Node
var _elapsed := 0.0
var _phase := 0
var _failed := false
var _original_pos := Vector2.ZERO

func _process(delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_save = root.get_node("/root/SaveSystem")
		_gm.set("flags", {})
		_gm.set("sacrifice_count", 0)
		_gm.set("state", 2)
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if _phase == 0 and _elapsed >= 0.45:
		var pause := _level.get_node_or_null("GameHUD/PauseMenu")
		_check(pause != null, "HUD 里没挂暂停菜单")
		if pause == null:
			_finish()
			return true
		_check(not pause.visible, "暂停菜单初始不该显示")
		var player := _level.get_node("Player")
		_original_pos = player.global_position
		_gm.set("sacrifice_count", 1)
		_gm.set("monster_limb_count", 2)
		_gm.set("current_floor", "start")
		pause.call("open")
		_check(paused, "打开暂停没暂停场景树")
		_check(int(_gm.get("state")) == 3, "暂停没把 GameManager 置 PAUSED")
		pause.call("_on_save_pressed")
		_check(bool(_save.call("has_save", 0)), "保存后槽位 1 不存在")
		var status := pause.get_node_or_null("Panel/Status") as Label
		_check(status != null and status.text.contains("已保存"), "保存后没有提示")
		player.global_position = Vector2(760, 590)
		player.set("hp", 2)
		_gm.set("sacrifice_count", 0)
		_gm.set("monster_limb_count", 0)
		_gm.set("current_floor", "floor_3")
		pause.call("close")
		_check(not paused, "关闭暂停没恢复场景树")
		_check(int(_gm.get("state")) == 2, "关闭暂停没回 PLAYING")
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		pause.call("_unhandled_input", esc)
		_check(paused and pause.visible, "Esc 没重新打开暂停")
		pause.call("_on_load_pressed")
		_check(player.global_position.distance_to(_original_pos) < 2.0, "读档没恢复玩家位置")
		_check(int(player.get("hp")) == 5, "读档没恢复玩家血量")
		_check(int(_gm.get("sacrifice_count")) == 1, "读档没恢复献祭数")
		_check(int(_gm.get("monster_limb_count")) == 2, "读档没恢复肢体数")
		_check(str(_gm.get("current_floor")) == "start", "读档没恢复楼层")
		_check(not paused, "读档后场景树仍在暂停")
		_check(int(_gm.get("state")) == 2, "读档后没回 PLAYING")
		_save.call("delete_slot", 0)
		_check(not bool(_save.call("has_save", 0)), "测试存档没删干净")
		_finish()
		return true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[pause_menu] " + msg)
		_failed = true

func _finish() -> void:
	print("[pause_menu] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
