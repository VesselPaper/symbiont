extends SceneTree
## 刀光碎屑回归（M4-38）：挥砍时溅出、0.3s 内自己消失，不能一直堆在场景里。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/slash_sparks_test.gd

const SCENE := "res://scenes/world/test_arena.tscn"

var _level: Node2D
var _player: CharacterBody2D
var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.25).timeout
	_level = load(SCENE).instantiate() as Node2D
	root.add_child(_level)
	_player = _level.get_node("Player") as CharacterBody2D
	await create_timer(0.4).timeout
	_player.set("has_weapon", true)
	var dlg := _level.get_node_or_null("Dialogue")
	if dlg != null:
		dlg.call("abort")
	_player.set("_input_locked", false)
	await _frames(4)

	var sparks := _player.get_node_or_null("Body/SlashSparks")
	_check(sparks != null, "玩家身上没有 SlashSparks 节点")
	if sparks == null:
		_finish()
		return

	_check(int(sparks.call("alive_count")) == 0, "还没挥砍就有碎屑")

	Input.action_press("attack")
	await physics_frame
	await physics_frame
	Input.action_release("attack")
	await physics_frame

	var after := int(sparks.call("alive_count"))
	_check(after > 0, "挥砍后没有产生碎屑（%d 条）" % after)

	await _wait(0.4)
	var later := int(sparks.call("alive_count"))
	_check(later == 0, "碎屑没有按时消失，还剩 %d 条" % later)

	print("[sparks] %s（生成 %d 条）" % ["PASS" if not _failed else "FAIL", after])
	_finish()

func _finish() -> void:
	quit(0 if not _failed else 1)

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await physics_frame
		t += 1.0 / 60.0

func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[sparks] " + msg)
		_failed = true
