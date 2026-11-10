extends SceneTree
## 指引光停点净空回归：每个目标点必须不在墙体里，且下方 80px 内能踩到地面。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/marker_clearance_test.gd

const SCENE := "res://scenes/world/test_arena.tscn"
## 与 components/tutorial.gd 的 MARKER_TARGETS 保持一致；改那边时这里也要同步，
## 测试故意写死，避免"测试和实现一起改错"。
const TARGETS := [
	{"name": "MOVE", "pos": Vector2(475, 628)},
	{"name": "JUMP", "pos": Vector2(750, 528)},
	{"name": "WEAPON", "pos": Vector2(830, 528)},
	{"name": "ATTACK", "pos": Vector2(940, 508)},
	{"name": "POGO", "pos": Vector2(1180, 404)},
	{"name": "COMBAT", "pos": Vector2(1870, 552)},
	{"name": "SACRIFICE", "pos": Vector2(2221, 498)},
]

var _level: Node2D

func _process(_delta: float) -> bool:
	if _level == null:
		_level = load(SCENE).instantiate() as Node2D
		root.add_child(_level)
		return false
	var space := _level.get_world_2d().direct_space_state
	var failed := false
	for item in TARGETS:
		var pos: Vector2 = item["pos"]
		var point := PhysicsPointQueryParameters2D.new()
		point.position = pos
		point.collision_mask = 1   # 地形静态体
		point.collide_with_bodies = true
		point.collide_with_areas = false
		var hits := space.intersect_point(point, 8)
		var ray := PhysicsRayQueryParameters2D.create(pos, pos + Vector2(0, 90), 1)
		var floor_hit := space.intersect_ray(ray)
		var clear := hits.is_empty()
		var has_floor := not floor_hit.is_empty()
		print("[marker] %-9s pos=%s clear=%s hits=%d floor=%s" % [
			item["name"], str(pos), str(clear), hits.size(),
			str(floor_hit.get("position", "none"))])
		if not clear or not has_floor:
			failed = true
	if failed:
		push_error("[marker] FAIL 有光点停在墙体里或下方没有地面")
		quit(1)
	else:
		print("[marker] PASS 全部目标点净空且下方有地面")
		quit(0)
	return true
