extends SceneTree
## 钟绳物理范围回归（M4-12，M4-18 钟厅重排后重写）
##
## 旧测试直接 bell.set("_in_range", true)，把“玩家到底站不站得进范围”绕过去了。
## 这里把玩家真的放到钟下，验证钟体左右都能提示/按 K；同时验证 M4-18 的改动：
##   1. 旁白在播时，绳子上不再显示“继续旁白/跳过本句”，只写“K 拉钟绳”；
##   2. 旁白在播时 K 归对话，绳子不许抢（不拉响、不挡按键）；
##   3. 守钟人挪到钟左边以后，站到守钟人脚下不能被钟绳判定区盖住。

const SCENE := "res://scenes/world/floor1.tscn"
const DialogueLocator := preload("res://components/dialogue_locator.gd")
const PROMPT_TEXT := "K 拉钟绳"

var _level: Node
var _player: Node2D
var _bell: Node
var _dialogue: Node
var _gate: Node
var _watchman: Node
var _bell_x := 0.0
var _watchman_x := 0.0
var _frames := 0
var _phase := 0
var _failed := false
var _quit_wait := 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 4:
		# queue_free 后至少再走几帧，让场景/子弹/音效节点真正退出树再 quit；
		# 同帧 quit 会在窗口模式留下 ObjectDB/resource 泄漏告警（测试夹具问题）。
		_quit_wait += 1
		if _quit_wait < 8:
			return false
		print("[bell_range] %s" % ("FAIL" if _failed else "PASS"))
		quit(1 if _failed else 0)
		return true
	if _phase == 0 and _frames == 3:
		_build()
		return false
	if _phase == 0 and _frames >= 40:
		_place_player(_bell_x - 150.0)
		_phase = 1
		return false
	if _phase == 1 and _frames >= 85:
		_check_in_range("钟体左侧", _bell_x - 150.0)
		_place_player(_bell_x)
		_phase = 2
		return false
	if _phase == 2 and _frames >= 130:
		_check_in_range("钟体正下", _bell_x)
		_check_dialogue_at_rope()
		_place_player(_bell_x + 150.0)
		_phase = 3
		return false
	if _phase == 3 and _frames >= 175:
		_check_in_range("钟体右侧", _bell_x + 150.0)
		# 反向：走到守钟人脚下时不能被钟绳抢 K（他站在钟左边 300px）
		_player.global_position = Vector2(_watchman_x, 730)
		_bell.call("_process", 0.0)
		_check(not bool(_bell.get("_in_range")), "站在守钟人位置仍被钟绳判定区覆盖")
		_place_player(_bell_x + 150.0)
		_bell.call("_process", 0.0)
		_finish_dialogue()
		_bell.call("_process", 0.0)
		var prompt := _bell.get_node_or_null("Prompt") as Label
		_check(prompt != null and prompt.visible and prompt.text == PROMPT_TEXT,
			"旁白结束后钟下没有出现「%s」" % PROMPT_TEXT)
		_press_k()
		var gm := root.get_node("/root/GameManager")
		_check(bool(gm.call("has_flag", "floor1_bell_rung")), "钟下按 K 没有拉响")
		_check(bool(_gate.call("is_open")), "拉响后骨门没有开")
		_check(prompt != null and not prompt.visible, "拉响之后「K 拉钟绳」还挂在画面上")
		# 回归切第二层那一帧：对话节点先被 free，旧钟绳还在 process
		if is_instance_valid(_dialogue):
			_dialogue.free()
		_bell.call("_process", 0.0)
		_begin_finish()
		_phase = 4
		return false
	return false

func _build() -> void:
	var gm := root.get_node("/root/GameManager")
	gm.set("flags", {})
	# 故意保持 MAIN_MENU：组长常用 F6 直接开 floor1 测关卡，
	# 钟绳不能依赖“先从主菜单开始游戏”才给按 K（旧 _input 加过这个锁，回归过）。
	gm.set("state", 1)
	gm.set("current_floor", "floor_1")
	gm.set("has_weapon", true)
	gm.set("monster_limb_count", 0)
	_level = load(SCENE).instantiate()
	# 略过进场旁白，别让 0.6s 的 floor1_enter 抢 K
	_level.set("_played", {"intro": true})
	root.add_child(_level)
	_player = _level.get_node("Player") as Node2D
	_bell = _level.get_node("Mechanisms/BellMechanism")
	_watchman = _level.get_node("Mechanisms/Watchman")
	_dialogue = _level.get_node("Dialogue")
	_gate = _level.get_node("Mechanisms/BoneGate")
	# 坐标从关卡常量读：钟厅位置以后还会调，测试不抄数字
	var consts: Dictionary = _level.get_script().get_script_constant_map()
	_bell_x = float(consts.get("BELL_X", 1600.0))
	_watchman_x = float(consts.get("WATCHMAN_X", 1778.0))
	# 回归：钟绳曾经把 AudioDirector/Bgm 当成对话组件（AudioStreamPlayer 也有
	# play/is_playing），导致 BGM 一直播时永远显示“K 继续旁白”，K 拉不响。
	for pair in [
		["钟绳", _bell],
		["守钟人", _watchman],
		["调查点", _level.get_node("InspectPoints/AltarInspect")],
	]:
		var who: String = pair[0]
		var node: Node = pair[1]
		var bound = node.get("_dialogue")
		_check(is_instance_valid(bound) and str(bound.get_path()) == str(_dialogue.get_path()),
			"%s没有绑定关卡 Dialogue，实际绑到 %s" % [
				who, str(bound.get_path()) if is_instance_valid(bound) else "<invalid>"])
	var bgm := root.get_node_or_null("GameManager/AudioDirector/Bgm")
	_check(not DialogueLocator.is_dialogue(bgm), "AudioDirector/Bgm 仍被当成对话组件")

## 旁白播放中：绳子不显示“继续旁白”，而且 K 归对话、不拉钟
func _check_dialogue_at_rope() -> void:
	_dialogue.call("play", "floor1_bell")
	_bell.call("_process", 0.0)
	var prompt := _bell.get_node_or_null("Prompt") as Label
	_check(prompt != null, "钟绳缺少提示标签")
	if prompt == null:
		return
	_check(not prompt.visible, "旁白播放中钟绳还显示着提示")
	_check(prompt.text == PROMPT_TEXT, "钟绳提示被改成了「%s」，应固定是「%s」" % [prompt.text, PROMPT_TEXT])
	_check(not bool(_bell.get("_rung")), "刚进范围就把钟拉了")
	var line_before := int(_dialogue.get("_line_index"))
	var done_before := bool(_dialogue.get("_line_done"))
	# 反向：其它键 / K 抬起 / K 长按 echo 都不能推进旁白
	_route(KEY_J)
	_route(KEY_K, false)
	_route(KEY_K, true, true)
	_bell.call("_process", 0.0)
	_check(int(_dialogue.get("_line_index")) == line_before and bool(_dialogue.get("_line_done")) == done_before,
		"非 K 按下沿（J/抬起/echo）推进了旁白")
	_route(KEY_K)
	_bell.call("_process", 0.0)
	var line_after := int(_dialogue.get("_line_index"))
	var done_after := bool(_dialogue.get("_line_done"))
	_check(line_after > line_before or (done_after and not done_before),
		"钟下按 K 没有推进旁白（line %d→%d done %s→%s）" % [
			line_before, line_after, str(done_before), str(done_after)])
	_check(not bool(_bell.get("_rung")), "旁白没播完就把钟拉了")
	# 第一下可能只是把打字机快进完；再按一下必须进入下一句，证明 K 真的归对话
	_route(KEY_K)
	_bell.call("_process", 0.0)
	_check(int(_dialogue.get("_line_index")) > line_after,
		"旁白已显示完整后再按 K 没有翻到下一句（line %d→%d）" % [line_after, int(_dialogue.get("_line_index"))])

func _place_player(x: float) -> void:
	_player.global_position = Vector2(x, 730)
	_player.set("velocity", Vector2.ZERO)

func _check_in_range(label: String, x: float) -> void:
	_check(bool(_bell.get("_in_range")), "玩家站在 %s（x=%.0f），钟绳没有进入范围" % [label, x])

func _finish_dialogue() -> void:
	if _dialogue != null and bool(_dialogue.call("is_playing")):
		_dialogue.call("_finish")

## 走真实 Viewport 输入链，而不是直接 call，顺便验证 _input 不会被别的 K 处理器吃掉
func _route(code: Key, pressed := true, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)

func _press_k() -> void:
	_route(KEY_K)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error("[bell_range] " + message)

func _begin_finish() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
