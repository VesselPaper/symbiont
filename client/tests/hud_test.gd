extends SceneTree
## HUD 回归（M1-06）：生命骨片、献祭计数、拾取提示、上下限。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/hud_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"

var _level: Node
var _gm: Node
var _bus: Node
var _elapsed := 0.0
var _failed := false

func _process(delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_bus = root.get_node("/root/EventBus")
		_gm.set("flags", {})
		_gm.set("sacrifice_count", 0)
		_gm.set("state", 2)
		_level = load(ARENA).instantiate()
		root.add_child(_level)
		return false
	_elapsed += delta
	if _elapsed < 0.35:
		return false
	_check_hud()
	print("[hud] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[hud] " + msg)
		_failed = true

func _check_hud() -> void:
	var hud := _level.get_node_or_null("GameHUD")
	_check(hud != null, "教学关没挂 GameHUD")
	if hud == null:
		return
	var player := _level.get_node("Player")
	_check(int(hud.call("get_filled_hearts")) == 5, "满血时应显示 5 枚骨片")
	player.set("hp", 3)
	hud.call("refresh")
	_check(int(hud.call("get_filled_hearts")) == 3, "掉到 3 血时骨片数量不对")
	player.set("hp", -2)
	hud.call("refresh")
	_check(int(hud.call("get_filled_hearts")) == 0, "血量下限没有夹到 0")
	player.set("hp", 8)
	hud.call("refresh")
	_check(int(hud.call("get_filled_hearts")) == 5, "血量上限没有夹到 5")
	_gm.set("sacrifice_count", 2)
	hud.call("refresh")
	var label := hud.get_node_or_null("HUDAnchor/SacrificeLabel") as Label
	_check(label != null and label.text == "献祭 2", "献祭计数没同步到 HUD")
	_bus.emit_signal("item_picked", "origin_relic", 1)
	_check(hud.call("get_toast_text") == "拾取：旧骨片", "拾取提示文案不对")
	var toast := hud.get_node_or_null("HUDAnchor/PickupToast") as Label
	_check(toast != null and toast.modulate.a > 0.9, "拾取提示没有显示")
