extends SceneTree
## 道具落地回归（M5-31）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/prop_grounding_test.gd
##
## 组长："加了这些折痕之后，原本在墙上或地面上的东西要精准地在墙上或地面上，不要陷进去或者浮空。"
## 所以这条测试量两件事：
##   ① 摆在台面上的东西（祭坛、火堆、尸体、铁剑、木桩甲）：视觉最低点 = 脚下地面（误差 ≤1px）；
##   ② 木桩乙是例外：它必须**悬空**（悬在方台前的下劈踏板），离地至少 40px。

const ARENA := "res://scenes/world/test_arena.tscn"
const GROUNDED := ["Altar", "Campfire", "Corpse", "WeaponPickup", "DummyA"]
const TOLERANCE := 1.0
const PEDAL := "DummyB"
const PEDAL_MIN_LIFT := 40.0

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var arena: Node2D = load(ARENA).instantiate()
	root.add_child(arena)
	await create_timer(1.2).timeout
	var space := arena.get_world_2d().direct_space_state

	for name in GROUNDED:
		var node := arena.get_node_or_null(str(name)) as Node2D
		_check(node != null, "缺少道具 %s" % str(name))
		if node == null:
			continue
		var bottom := _visual_bottom(node)
		var surface := _surface_at(space, node)
		var diff := bottom - surface
		print("[grounding] %-13s 视觉底 %.1f 地面 %.1f 差 %.1f" % [str(name), bottom, surface, diff])
		_check(absf(diff) <= TOLERANCE,
			"%s 没有精确落在台面上（视觉底比地面%s %.1fpx）" % [
				str(name), "低" if diff > 0.0 else "高", absf(diff)])

	var pedal := arena.get_node_or_null(PEDAL) as Node2D
	_check(pedal != null, "缺少木桩乙（下劈踏板）")
	if pedal != null:
		var lift := _surface_at(space, pedal) - _visual_bottom(pedal)
		print("[grounding] %-13s 离地 %.1f（应悬空）" % [PEDAL, lift])
		_check(lift >= PEDAL_MIN_LIFT,
			"木桩乙离地只有 %.1fpx，落地之后下劈就够不着方台顶了" % lift)

	arena.queue_free()
	await process_frame
	print("[grounding] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 道具脚下那层的顶面（从道具上方 160px 往下打射线）
func _surface_at(space: PhysicsDirectSpaceState2D, node: Node2D) -> float:
	var from := Vector2(node.global_position.x, node.global_position.y - 160.0)
	var ray := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 400.0), 1)
	var hit := space.intersect_ray(ray)
	return float(hit["position"].y) if not hit.is_empty() else NAN

## 一个节点（含所有子节点）在世界坐标下的最低点
func _visual_bottom(root: Node2D) -> float:
	var worst := -1.0e9
	var stack: Array = [[root, root.global_transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform2D = item[1]
		for child in n.get_children():
			var t := xf
			if child is Node2D:
				t = xf * (child as Node2D).transform
			if child is Polygon2D:
				for p in (child as Polygon2D).polygon:
					worst = maxf(worst, (t * p).y)
			elif child is Line2D:
				for p in (child as Line2D).points:
					worst = maxf(worst, (t * p).y)
			elif child is Sprite2D:
				var sp := child as Sprite2D
				if sp.texture != null:
					var sz := sp.texture.get_size() * sp.scale
					var top_left := sp.position if not sp.centered else sp.position - sz * 0.5
					worst = maxf(worst, (t * (top_left + Vector2(0.0, sz.y))).y)
			if child.get_child_count() > 0:
				stack.append([child, t])
	return worst

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[grounding] " + msg)
		_failed = true
