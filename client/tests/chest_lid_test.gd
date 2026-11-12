## 宝箱盖子（M4-17）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/chest_lid_test.gd
##
## 组长反馈“宝箱的盖子最初就在地上”。
## 原因是盖子节点放在 (0,0)、盖子的多边形画在 y=0..-16，正好压在箱身下半截。
## 这里断言盖子在箱身上沿（y=-24 以上）、关着时角度为 0、开箱后转到立起来的角度。

extends SceneTree

const CHEST := "res://scenes/items/steam_boots_chest.tscn"

var _chest: Area2D
var _frame := 0
var _fail := 0
var _lid: Node2D

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok  ", msg)
	else:
		_fail += 1
		printerr("  FAIL ", msg)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_chest = (load(CHEST) as PackedScene).instantiate() as Area2D
		root.add_child(_chest)
		return false
	if _frame == 4:
		_lid = _chest.get_node_or_null("Lid") as Node2D
		_check(_lid != null, "盖子节点存在")
		if _lid == null:
			quit(1)
			return true
		_check(_lid.position.y <= -20.0, "盖子挂在箱身上沿（y=%.1f，箱身上沿 −24）" % _lid.position.y)
		_check(absf(_lid.rotation) < 0.001, "初始是关着的（rotation=%.2f）" % _lid.rotation)
		# 盖子的每个顶点都要在箱身上沿之上，不能压在箱身下半截
		var lowest := _lowest_point_local(_lid)
		_check(lowest <= -20.0, "盖子最低点在 y=%.1f，没有掉到箱子下半截" % lowest)
		# 盖子横向要盖住箱身（±27），不能只盖一半
		var bounds := _x_bounds_local(_lid)
		_check(bounds.x <= -20.0 and bounds.y >= 20.0, "盖子在 x=%.1f..%.1f 之间，盖住箱口" % [bounds.x, bounds.y])
		return false
	if _frame < 12:
		return false
	# 开箱：转开的角度要够（否则又像“盖子躺在地上”），而且铰链位置不动
	_chest.set("_opened", false)
	_chest.set("_player_near", true)
	_chest.call("_open")
	if _frame < 40:
		return false
	_check(_lid.rotation < -0.8, "开箱后盖子立起来（rotation=%.2f）" % _lid.rotation)
	_check(absf(_lid.position.y - (-24.0)) < 0.5, "开箱时铰链位置没被挪走（y=%.1f）" % _lid.position.y)
	_chest.queue_free()
	if _fail == 0:
		print("[chest_lid] PASS")
		quit(0)
	else:
		printerr("[chest_lid] FAIL %d 项" % _fail)
		quit(1)
	return true

## 把盖子子节点的顶点换算回宝箱局部坐标，取最低点
func _lowest_point_local(node: Node2D) -> float:
	var lowest := 0.0
	for child in node.get_children():
		if not (child is Node2D):
			continue
		var child2d := child as Node2D
		var points := PackedVector2Array()
		if child2d is Polygon2D:
			points = (child2d as Polygon2D).polygon
		elif child2d is Line2D:
			points = (child2d as Line2D).points
		for p in points:
			var local := node.transform * (child2d.transform * p)
			lowest = minf(lowest, local.y)
	return lowest

func _x_bounds_local(node: Node2D) -> Vector2:
	var lo := 0.0
	var hi := 0.0
	for child in node.get_children():
		if not (child is Node2D):
			continue
		var child2d := child as Node2D
		var points := PackedVector2Array()
		if child2d is Polygon2D:
			points = (child2d as Polygon2D).polygon
		elif child2d is Line2D:
			points = (child2d as Line2D).points
		for p in points:
			var local := node.transform * (child2d.transform * p)
			lo = minf(lo, local.x)
			hi = maxf(hi, local.x)
	return Vector2(lo, hi)
