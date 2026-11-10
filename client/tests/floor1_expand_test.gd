extends SceneTree
## 扩建回归：第一层必须比旧版长、断桥/遗物廊/层门厅都在，且平台断口仍可跳。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/floor1_expand_test.gd

const SCENE := "res://scenes/world/floor1.tscn"

var _level: Node
var _failed := false

func _process(_delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_check_map()
	print("[floor1_expand] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[floor1_expand] " + msg)
		_failed = true

func _check_map() -> void:
	var terrain := _level.get_node("Terrain")
	_check(terrain.get_child_count() == 12, "地形数量不是 12")
	var floors: Array[StaticBody2D] = []
	for child in terrain.get_children():
		var body := child as StaticBody2D
		if body == null:
			continue
		var col := body.get_node("CollisionShape2D") as CollisionShape2D
		var rect := (col.shape as RectangleShape2D).size
		# 左右边界墙宽 80，其它是脚能踩的地面；按 PLATFORMS 顺序前 10 块是地面
		if rect.x > 100.0:
			floors.append(body)
	_check(floors.size() == 10, "可站地面应是 10 块，实际 %d" % floors.size())
	var prev_right := -99999.0
	var prev_top := 0.0
	for i in range(floors.size()):
		var body := floors[i]
		var rect := (body.get_node("CollisionShape2D").shape as RectangleShape2D).size
		var left := body.global_position.x - rect.x * 0.5
		var right := body.global_position.x + rect.x * 0.5
		var top := body.global_position.y - rect.y * 0.5
		if i > 0:
			var gap := left - prev_right
			var height := absf(top - prev_top)
			_check(gap <= 150.0, "第 %d 块到第 %d 块断口 %.0fpx 太宽" % [i, i + 1, gap])
			_check(height <= 100.0, "第 %d 块到第 %d 块落差 %.0fpx 太大" % [i, i + 1, height])
		prev_right = right
		prev_top = top
	# 新场景物件/剧情
	var props := _level.get_node("Props")
	_check(props.get_node_or_null("GateFrame") != null, "缺少层门")
	_check((props.get_node("GateFrame") as Node2D).position.x > 4300.0, "层门没有移到扩建后的末端")
	var triggers := _level.get_node("Triggers")
	_check(triggers.get_node_or_null("BridgeTrigger") != null, "缺少断桥触发器")
	_check(triggers.get_node_or_null("RelicTrigger") != null, "缺少遗物廊触发器")
	var db := root.get_node("/root/DataDB")
	for id in ["floor1_bridge", "floor1_relic"]:
		var row: Dictionary = db.get_dialogue(id)
		_check(not row.is_empty(), "缺少对话 %s" % id)
		_check((row.get("lines", []) as Array).size() >= 3, "对话 %s 太短" % id)
	# 地图总长（右边界墙位置）
	var wall := terrain.get_child(terrain.get_child_count() - 1) as StaticBody2D
	_check(wall.position.x >= 4500.0, "右边界没有随扩建后移")
