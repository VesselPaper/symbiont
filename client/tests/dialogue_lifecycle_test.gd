extends SceneTree
## M4-13 对话事件闭环回归（无头）
##
## 这次钟绳事故的根因之一：交互组件各写各的，锁/临时状态没有统一的结束路径。
## 本测试专门压 dialogue.gd 的 started / finished 配对：
##   - 正常 abort 解锁玩家
##   - 重复 abort 不重复发 finished
##   - 播放中重播先收上一段，再起新一段
##   - 节点在播放中被 free（切场景/释放）也必须发 finished，不能把 _input_locked 留在 true
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/dialogue_lifecycle_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _player: Node
var _dialogue: Node
var _frames := 0
var _phase := 0
var _failed := false
var _quit_wait := 0
var _starts: Array[String] = []
var _finishes: Array[String] = []

func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames == 3:
		_build()
		_phase = 1
		return false
	if _phase == 1 and _frames >= 12 and (_player.is_on_floor() or _frames >= 60):
		_run_checks()
		_phase = 2
		return false
	if _phase == 2 and _frames >= 20:
		_begin_finish()
		_phase = 3
		return false
	if _phase == 3:
		_quit_wait += 1
		if _quit_wait >= 8:
			print("[dialogue_lifecycle] %s starts=%d finishes=%d" % [
				"FAIL" if _failed else "PASS", _starts.size(), _finishes.size()])
			quit(1 if _failed else 0)
			return true
	return false

func _build() -> void:
	var gm := root.get_node("/root/GameManager")
	gm.set("flags", {})
	gm.set("state", 2)
	gm.set("current_floor", "floor_1")
	gm.set("has_weapon", true)
	_level = load(SCENE).instantiate()
	# 跳过进场旁白，避免它和本测试手动 play() 抢 started/finished
	_level.set("_played", {"intro": true})
	root.add_child(_level)
	_player = _level.get_node("Player")
	# 出生点在平台上方 60px，要落几帧才着地；而 dialogue.play() 在玩家离地时会挂起，
	# 不立刻发 started。本测试压的就是 started/finished 配对，所以直接把人放到地面上，
	# 再等 is_on_floor() 为真才开始（否则跑快了会变成“一个事件都没有”的假失败）。
	_player.global_position = Vector2(140, 615)
	_dialogue = _level.get_node("Dialogue")
	var bus := root.get_node("/root/EventBus")
	bus.connect("dialogue_started", _on_started)
	bus.connect("dialogue_finished", _on_finished)

func _run_checks() -> void:
	_check(not bool(_dialogue.call("is_playing")), "初始状态不应在播对话")
	_check(not bool(_player.get("_input_locked")), "初始状态玩家不应被锁输入")

	# 1. 正常开始 → abort：必须发 finished 并解锁
	_dialogue.call("play", "floor1_bell")
	_check(_starts.size() == 1 and _starts[0] == "floor1_bell", "play 没有发 started")
	_check(bool(_player.get("_input_locked")), "对话开始没有锁玩家输入")
	_dialogue.call("abort")
	_check(_finishes.size() == 1 and _finishes[0] == "floor1_bell", "abort 没有发 finished")
	_check(not bool(_dialogue.call("is_playing")), "abort 后仍显示在播")
	_check(not bool(_player.get("_input_locked")), "abort 后玩家仍被锁输入")

	# 2. 重复 abort：不能空发/重复发 finished
	_dialogue.call("abort")
	_check(_finishes.size() == 1, "重复 abort 重复发了 finished")

	# 3. 播放中重播：上一段先 finished，再发新 started，配对不能断
	_dialogue.call("play", "floor1_bell")
	_dialogue.call("play", "floor1_watchman")
	_check(_finishes.size() == 2, "重播没有先收上一段 finished")
	_check(_starts.size() == 3 and _starts[2] == "floor1_watchman", "重播没有发新 started")
	_check(bool(_dialogue.call("is_playing")), "重播后没有在播")
	_check(bool(_player.get("_input_locked")), "重播后玩家没有重新锁输入")
	_dialogue.call("abort")
	_check(_finishes.size() == 3, "重播段 abort 没有发 finished")
	_check(not bool(_player.get("_input_locked")), "重播段 abort 后玩家仍被锁")

	# 4. 播放中节点被 free（切场景/释放）：_exit_tree 必须收尾
	_dialogue.call("play", "floor1_bell")
	_check(_starts.size() == 4 and _starts[3] == "floor1_bell", "释放前没有发 started")
	_dialogue.free()
	_check(_finishes.size() == 4, "播放中 free 没有发 finished")
	_check(not bool(_player.get("_input_locked")), "播放中 free 后玩家仍被锁输入")

func _on_started(dialogue_id: String) -> void:
	_starts.append(dialogue_id)

func _on_finished(dialogue_id: String) -> void:
	_finishes.append(dialogue_id)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error("[dialogue_lifecycle] " + message)

func _begin_finish() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
