extends Node
## 对话组件（M1-03 · 寄生体低语）
##
## 纯流程逻辑，与 UI 解耦：
##   - 台词一律从 DataDB.get_dialogue() 读取（禁止写死在代码里）
##   - 打字机逐字显示；interact(K) 快进当前条（直接显示完整文本），再按进入下一条
##   - 支持 next_id 顺序链（intro_parasite_1 → intro_parasite_2，next_id 为空则结束）
##   - 广播 EventBus.dialogue_started / dialogue_finished
##   - M1-08：当前条完整显示后（打字机打完或玩家快进）通过 UI 契约
##     set_continue_hint(true) 提示"按 K 继续"；换条/结束时隐藏
##
## 挂载：作为场景子节点，export ui_path 指向对话 UI（scenes/ui/dialogue_box.tscn）。
## UI 契约（duck typing；ui_path 留空则只走逻辑不显示，便于无头测试）：
##   show_box() / hide_box() / set_speaker(name) / set_text(text) / set_continue_hint(show)
##
## 事件语义：play() 启动时 emit dialogue_started(入口 id)；整条链（含 next_id）
## 全部播完 emit dialogue_finished(入口 id)。next_id 链式衔接是内部流程，不重复
## 广播 started，保证 started / finished 成对，便于监听方配对。
##
## 输入锁：player.gd 监听 dialogue_started / dialogue_finished 自己锁和解锁，
## 对话组件不直接碰玩家输入。锁输入期间玩家水平速度归零，不会滑行。

const INTERACT_ACTION := "interact"

## 对话 UI 节点（dialogue_box）；留空则只走逻辑不显示
@export var ui_path: NodePath
## 玩家节点路径；留空则从 "player" 分组里找。空中触发时用它判断是否落地
@export var player_path: NodePath
## 打字机速度（字符/秒）
@export var type_chars_per_sec := 40.0

var _ui: Node
var _entry_dialogue_id := ""  # play() 入口对话 id，finished 信号携带它，保证与 started 配对
var _queue: Array = []        # 当前对话的台词行 [{speaker, text}]
var _next_id := ""            # 当前对话的 next_id（播完自动继续，链尾为空）
var _active := false
var _line_index := 0
var _visible_chars := 0.0     # 打字机已显示字符数
var _line_done := false       # 当前条是否已完整显示
var _pending_id := ""         # 空中触发时挂起的对话 id，落地后再播
var _player: Node2D

func _ready() -> void:
	if ui_path != NodePath(""):
		_ui = get_node_or_null(ui_path)
		if _ui == null:
			push_warning("dialogue: 找不到 ui_path=%s，本组件只走逻辑不显示" % ui_path)
	_player = _resolve_player()
	EventBus.player_died.connect(_on_player_died)

func _resolve_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Node2D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

func _on_player_died() -> void:
	# 玩家在挂起期间掉坑死亡：丢掉这次对话，别等复活后突然弹出来
	_pending_id = ""

func is_playing() -> bool:
	return _active or _pending_id != ""

## 播放一段对话（入口）。播放中再次调用视为重新开始。
func play(dialogue_id: String) -> void:
	# 空中触发先挂起：等玩家落地再开始，避免对话锁输入时角色还在坠落
	var p := _resolve_player()
	if p != null and not p.is_on_floor():
		_pending_id = dialogue_id
		return
	_pending_id = ""
	_entry_dialogue_id = dialogue_id
	_start(dialogue_id, true)

## 加载并开始显示 dialogue_id；emit_started=false 用于 next_id 链式衔接
func _start(dialogue_id: String, emit_started: bool) -> void:
	var data := DataDB.get_dialogue(dialogue_id)
	if not data.has("lines") or not data["lines"] is Array or (data["lines"] as Array).is_empty():
		push_warning("dialogue: '%s' 无台词（lines 为空），%s" % [
			dialogue_id, "结束当前对话" if _active else "跳过"])
		if _active:
			_finish()
		return
	_queue = (data["lines"] as Array).duplicate()
	_next_id = str(data.get("next_id", ""))
	_active = true
	if emit_started:
		EventBus.dialogue_started.emit(dialogue_id)
	_show_line(0)

func _show_line(index: int) -> void:
	_line_index = index
	_visible_chars = 0.0
	_line_done = false
	var line: Dictionary = _queue[index]
	if _ui != null:
		_ui.set_speaker(str(line.get("speaker", "")))
		_ui.show_box()
	# 换新一条：收起"按 K 继续"提示，等本条完整显示后再亮起
	_set_continue_hint(false)
	_refresh_text()

func _refresh_text() -> void:
	if _ui == null:
		return
	var line: Dictionary = _queue[_line_index]
	_ui.set_text(str(line.get("text", "")).left(int(_visible_chars)))

## M1-08：提示开关（对话 UI 契约扩展）。UI 没有该方法时静默跳过，保证旧 UI 兼容
func _set_continue_hint(show: bool) -> void:
	if _ui == null or not _ui.has_method("set_continue_hint"):
		return
	_ui.set_continue_hint(show)

func _process(delta: float) -> void:
	# 空中挂起的对话：玩家落地的那一帧开始播
	if _pending_id != "":
		var p := _resolve_player()
		if p != null and p.is_on_floor():
			var pending := _pending_id
			_pending_id = ""
			_entry_dialogue_id = pending
			_start(pending, true)
			return
	if not _active or _line_done:
		return
	var line: Dictionary = _queue[_line_index]
	var total := str(line.get("text", "")).length()
	_visible_chars = minf(_visible_chars + type_chars_per_sec * delta, float(total))
	if _visible_chars >= float(total):
		_line_done = true
		# 打字机打完：亮起"按 K 继续"
		_set_continue_hint(true)
	_refresh_text()

func _unhandled_input(event: InputEvent) -> void:
	# 反向测试（规范第 6 条）：只有 interact(K) 的按下沿才触发，
	# 其它按键 / 抬起 / 长按重复（echo）一律忽略，防止自动推进
	if not _active:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	if not key.is_action_pressed(INTERACT_ACTION):
		return
	if _line_done:
		_advance_line()
	else:
		# 快进当前条：直接显示完整文本（下一次按键才进入下一条）
		var line: Dictionary = _queue[_line_index]
		_visible_chars = float(str(line.get("text", "")).length())
		_line_done = true
		_set_continue_hint(true)
		_refresh_text()

func _advance_line() -> void:
	if _line_index + 1 < _queue.size():
		_show_line(_line_index + 1)
		return
	# 最后一条播完：优先走 next_id 链；链为空才结束
	if _next_id != "":
		_start(_next_id, false)
	else:
		_finish()

func _finish() -> void:
	_active = false
	_line_done = true
	# 对话结束：收起"按 K 继续"再隐藏对话框
	_set_continue_hint(false)
	if _ui != null:
		_ui.hide_box()
	EventBus.dialogue_finished.emit(_entry_dialogue_id)
