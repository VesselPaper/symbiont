extends SceneTree
## 教学关后段回归（M4-07 加长廊，M4-19 改成读站位表）
## 检查：后段阶梯齐全、位置和 test_arena.gd 的 STAGE 表一致、相邻台阶落差在单跳高度内、
## 层门贴着地图右缘（走廊最后一段不能是空跑道）。
## 坐标一律从 STAGE 表读，不再抄数字：改布局只改表，这里跟着走。

const SCENE := "res://scenes/world/test_arena.tscn"
## 单跳高度 ≈ 3.7 倍角色身高（28px）≈ 103.6，留一点余量按 104 判
const MAX_STEP_DROP := 104.0

var _level: Node
var _frames := 0
var _failed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	if _frames < 10:
		return false
	_check_gallery()
	print("[gallery] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[gallery] " + msg)
		_failed = true

func _check_gallery() -> void:
	var stage: Dictionary = _level.get_script().get_script_constant_map()["STAGE"]
	_check(_level.get_node_or_null("CorridorGallery") != null, "缺少后段阶梯分组")

	var door := _level.get_node_or_null("NextFloorDoor") as Node2D
	_check(door != null, "缺少下一层门")
	if door != null:
		var door_x: float = float(stage["door"].x)
		_check(absf(door.global_position.x - door_x) < 1.0, "门不在站位表的层门位置 %.1f" % door_x)
		var wall := _level.get_node("WallRight") as Node2D
		_check(wall.global_position.x - door.global_position.x <= 160.0,
			"门离右墙 %.1f，走廊最后一段成了空跑道" % (wall.global_position.x - door.global_position.x))

	var gallery: Array = stage["gallery"]
	_check(gallery.size() == 4, "站位表的阶梯应为 4 段，实际 %d" % gallery.size())
	var tops: Array[float] = []
	for i in range(gallery.size()):
		var rect: Rect2 = gallery[i]
		var node := _level.get_node_or_null("CorridorGallery/GalleryStep%d" % (i + 1))
		_check(node != null, "缺少 GalleryStep%d" % (i + 1))
		if node != null:
			_check(absf(node.global_position.x - (rect.position.x + rect.size.x * 0.5)) < 1.0,
				"GalleryStep%d x 和站位表不一致" % (i + 1))
		tops.append(rect.position.y)
	# 相邻台阶的落差必须在单跳可达范围内
	for i in range(1, tops.size()):
		_check(absf(tops[i - 1] - tops[i]) <= MAX_STEP_DROP,
			"第 %d 段台阶落差 %.1f 超过单跳高度" % [i + 1, absf(tops[i - 1] - tops[i])])
	# 台阶之间要留缝，不能连成一条斜坡（连起来就不叫“可选高台”了）
	for i in range(1, gallery.size()):
		var prev: Rect2 = gallery[i - 1]
		var cur: Rect2 = gallery[i]
		_check(cur.position.x - prev.position.x - prev.size.x >= 40.0,
			"第 %d、%d 段台阶之间没有缝" % [i, i + 1])
