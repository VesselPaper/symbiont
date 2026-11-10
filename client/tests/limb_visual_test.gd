extends SceneTree
## 肢体拾取物建模回归：不能退回一个 12px 方块，必须有断口/骨片/指节等可见分件。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/limb_visual_test.gd

const SCENE := "res://scenes/items/limb_pickup.tscn"

var _pickup: Area2D
var _failed := false

func _process(_delta: float) -> bool:
	if _pickup == null:
		_pickup = load(SCENE).instantiate() as Area2D
		root.add_child(_pickup)
		return false
	_check_visual()
	print("[limb_visual] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[limb_visual] " + msg)
		_failed = true

func _check_visual() -> void:
	var visual := _pickup.get_node_or_null("Visual") as Node2D
	_check(visual != null, "肢体缺少 Visual 节点")
	if visual == null:
		return
	_check(visual.get_child_count() >= 10, "肢体分件太少：%d" % visual.get_child_count())
	for name in ["Flesh", "Cut", "Bone", "Shadow", "Glow"]:
		_check(visual.get_node_or_null(name) != null, "缺少分件 %s" % name)
	var flesh := visual.get_node("Flesh") as Polygon2D
	_check(flesh.polygon.size() >= 8, "主肢轮廓仍是方块")
	var bone := visual.get_node("Bone") as Polygon2D
	_check(bone != null and bone.polygon.size() >= 4, "骨片没有建模")
	var collider := _pickup.get_node("CollisionShape2D") as CollisionShape2D
	_check(collider != null and (collider.shape as RectangleShape2D).size.x >= 12.0, "拾取判定被改小")
