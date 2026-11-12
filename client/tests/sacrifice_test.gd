extends SceneTree
## 献祭演出/后果回归（M2-09）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/sacrifice_test.gd
##
## 验收：有肢体才献祭；成功后计数 +1、祭坛演出节点存在、玩家长出寄生组织；
## 没有肢体时不进演出。

const SCENE := "res://scenes/world/test_arena.tscn"

var _frames := 0
var _arena: Node = null
var _failed := false
var _done := false
var _exit_wait := 0

func _process(_delta: float) -> bool:
	if _done:
		_exit_wait += 1
		if _exit_wait < 10:
			return false
		quit(0 if not _failed else 1)
		return true
	_frames += 1
	if _frames == 3:
		_arena = load(SCENE).instantiate()
		root.add_child(_arena)
		return false
	if _frames < 12:
		return false
	_run_checks()
	print("[sacrifice] %s" % ("PASS" if not _failed else "FAIL"))
	var gm := root.get_node_or_null("/root/GameManager")
	var audio := gm.get_node_or_null("AudioDirector") if gm != null else null
	if audio != null and audio.has_method("stop_all"):
		audio.call("stop_all")
	_done = true
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[sacrifice] " + message)
		_failed = true

func _run_checks() -> void:
	var gm := root.get_node_or_null("/root/GameManager")
	var altar := _arena.get_node_or_null("Altar")
	var player := _arena.get_node_or_null("Player")
	_check(altar != null and player != null, "缺少祭坛或玩家")
	if altar == null or player == null or gm == null:
		return
	# 反向：没有肢体时献祭失败，不应进演出
	gm.set("monster_limb_count", 0)
	var fail_result: bool = bool(altar.call("try_sacrifice"))
	_check(not fail_result, "没有肢体也能献祭")
	_check(not bool(altar.get("_sequence_active")), "失败献祭不应启动演出")
	# 正向：给一个肢体，成功后计数 +1、演出启动、玩家长寄生组织
	gm.set("monster_limb_count", 1)
	var ok_result: bool = bool(altar.call("try_sacrifice"))
	_check(ok_result, "有肢体却献祭失败")
	_check(int(gm.get("sacrifice_count")) == 1, "献祭计数没有 +1")
	_check(bool(altar.get("_sequence_active")), "献祭演出没有启动")
	_check(altar.get_node_or_null("Visual/OfferingLimb") != null, "祭坛缺少飞入的肢体模型")
	var corruption := player.get_node_or_null("Body/Corruption") as Node2D
	_check(corruption != null, "玩家缺少寄生组织节点")
	if corruption != null:
		_check(corruption.visible, "献祭后玩家寄生组织没有显示")
	# 层间转场：教学关已经有一段黑场，floor1 也有淡入（节点存在即算）
	_check(_arena.get_node_or_null("FloorTransition/Fade") != null, "缺少教学关黑场")
