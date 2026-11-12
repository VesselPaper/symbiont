extends SceneTree
## 跨层读档回归（M1-05）：在第二层存档，切到第一层后从暂停菜单读档，
## 必须真的切回第二层，并把玩家落到存档位置；不能把位置套给即将释放的第一层玩家。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/cross_floor_load_test.gd

const FLOOR1 := "res://scenes/world/floor1.tscn"
const FLOOR2 := "res://scenes/world/floor2.tscn"
const PAUSE_MENU := "res://scenes/ui/pause_menu.tscn"

var _phase := 0
var _wait := 0
var _gm: Node
var _save: Node
var _floor2: Node
var _floor1: Node
var _saved_pos := Vector2.ZERO
var _failed := false
var _menu: CanvasLayer

func _process(_delta: float) -> bool:
	_wait += 1
	if _phase == 0:
		if _wait == 1:
			_gm = root.get_node("/root/GameManager")
			_save = root.get_node("/root/SaveSystem")
			_gm.set("flags", {})
			_gm.set("state", 2)
			_floor2 = load(FLOOR2).instantiate()
			root.add_child(_floor2)
			return false
		if _wait < 8:
			return false
		var player := _floor2.get_node("Player") as Node2D
		# 必须等玩家真的落地再取样：出生点在空中，抓一个下落中的坐标去存档，
		# 读档后那 20 帧还会继续往下掉，“落在存档位置”就成了看机器快慢的假失败
		if not (player as CharacterBody2D).is_on_floor() and _wait < 120:
			return false
		_saved_pos = player.global_position
		_gm.set("current_floor", "floor_2")
		_gm.call("set_flag", "floor1_unlocked")
		_save.call("save", 0)
		_check(bool(_save.call("has_save", 0)), "第二层存档没写出来")
		# 立刻移除旧层，避免 player 组里残留第二层玩家导致暂停菜单认错当前层
		root.remove_child(_floor2)
		_floor2.free()
		_floor1 = load(FLOOR1).instantiate()
		root.add_child(_floor1)
		_phase = 1
		_wait = 0
		return false
	if _phase == 1 and _wait >= 8:
		_check(_floor1 != null and _floor1.scene_file_path == FLOOR1, "测试没切到第一层")
		_menu = load(PAUSE_MENU).instantiate() as CanvasLayer
		_floor1.add_child(_menu)
		_phase = 2
		_wait = 0
		return false
	if _phase == 2 and _wait >= 3:
		_menu.call("_on_load_pressed")
		_phase = 3
		_wait = 0
		return false
	if _phase == 3 and _wait >= 20:
		var target: Node = null
		for child in root.get_children():
			if child.scene_file_path == FLOOR2:
				target = child
				break
		_check(target != null, "跨层读档没切回第二层")
		if target != null:
			var player := target.get_node("Player") as Node2D
			_check(player != null, "第二层没有玩家")
			if player != null:
				_check(player.global_position.distance_to(_saved_pos) < 2.0, "读档后玩家没落在第二层存档位置")
		_check((_save.get("pending_player") as Dictionary).is_empty(), "读档后 pending_player 没清空")
		_check(int(_gm.get("state")) == 2, "读档后状态不是 PLAYING")
		_save.call("delete_slot", 0)
		_check(not bool(_save.call("has_save", 0)), "测试存档没删干净")
		print("[cross_floor_load] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[cross_floor_load] " + msg)
		_failed = true
