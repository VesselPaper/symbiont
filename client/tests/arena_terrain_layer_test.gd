extends SceneTree
## 教学关地形层次回归（M5-19 / M5-20）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/arena_terrain_layer_test.gd
##
## 组长反馈两条：
##   「文字右下方阶梯处有一团灰色矩形，无纹路且与碰撞体积不重合，导致玩家被覆盖」
##   「踩住借力跳高下方的平台两侧仅灰色矩形，无纹路」
## 这条钉两件事：
##   ① 运行时新建的地形（浅坑台阶 / 长廊台阶 / 悬崖右岸 / 骨栅）都必须画在玩家**后面**
##      （z_index <= -1），否则玩家走过去会被一整块灰盖住；
##   ② 厚平台（下劈方台这种）的侧面必须有真正的竖缝，不能只剩顶面那一条。

const ARENA := "res://scenes/world/test_arena.tscn"

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.4).timeout
	var arena: Node2D = load(ARENA).instantiate()
	root.add_child(arena)
	# 美术层是推迟一帧才铺装饰的，等它跑完再看
	await create_timer(1.2).timeout

	var player := arena.get_node("Player") as Node2D
	var player_z := player.z_index

	# ① 所有运行时地形组都不能盖在玩家身上
	for path in ["HollowSteps", "CorridorGallery", "TutorialGates", "GroundRight"]:
		var node := arena.get_node_or_null(path) as CanvasItem
		_check(node != null, "缺少地形节点 %s" % path)
		if node == null:
			continue
		_check(node.z_index < player_z,
			"%s 的 z_index=%d 不低于玩家（%d），走过去会被它盖住" % [path, node.z_index, player_z])

	# 台阶里的每一块也要在玩家后面（组内相对父节点是 0，父节点已经压后，这里只确认父节点生效）
	var steps := arena.get_node_or_null("HollowSteps")
	if steps != null:
		_check(steps.get_child_count() >= 2, "浅坑台阶数量不对")

	# ② 厚平台侧面要有竖缝：下劈方台（131 高）至少要有几条比"顶面那 9px"更深的缝
	var pogo := arena.get_node_or_null("PogoPlatform") as StaticBody2D
	_check(pogo != null, "缺少下劈方台")
	if pogo != null:
		var deepest := 0.0
		var seams := 0
		for child in pogo.get_children():
			if child is Line2D:
				var line := child as Line2D
				if line.name.begins_with("@"):   # 运行时 new 出来的都是匿名名
					for p in line.points:
						deepest = maxf(deepest, float(p.y))
					if line.points.size() >= 3:
						seams += 1
		print("[terrain_layer] 下劈方台最深缝 %.1fpx，多段竖缝 %d 条" % [deepest, seams])
		_check(deepest >= 40.0, "下劈方台侧面没有深缝（最深 %.1fpx），还是一块灰" % deepest)
		_check(seams >= 1, "下劈方台侧面没有多段竖缝")

	# ③ M5-25（组长反馈"坑两边那个多出来的一点没有碰撞体积"）：
	# 分两档查，因为两者的"允许量"不一样：
	#   Visual 这一块必须和碰撞盒严丝合缝（差 1px 都不能有，否则就是一块没碰撞的灰）；
	#   其它装饰（亮边、青苔、砖缝）允许最多 8px —— 草叶本来就会冒出地面一点点。
	for path in ["GroundLeft", "GroundRight", "JumpPlatform", "PogoPlatform", "AltarPlatform"]:
		var body := arena.get_node_or_null(path) as StaticBody2D
		_check(body != null, "缺少地形 %s" % path)
		if body == null:
			continue
		_check(_overshoot(body, true) <= 1.0,
			"%s 的 Visual 比碰撞盒大 %.1fpx（走上去是没有碰撞的灰块）" % [path, _overshoot(body, true)])
		_check(_overshoot(body, false) <= 8.0,
			"%s 有装饰画到碰撞盒外面 %.1fpx" % [path, _overshoot(body, false)])

	arena.queue_free()
	await process_frame
	print("[terrain_layer] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 画到碰撞盒外面的最大像素数（0 = 全在盒内）。only_visual=true 时只量 Visual 那一块。
func _overshoot(body: StaticBody2D, only_visual: bool) -> float:
	var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or col.shape == null:
		return 0.0
	var half := (col.shape as RectangleShape2D).size * 0.5
	var box := Rect2(col.position - half, half * 2.0)
	var worst := 0.0
	for child in body.get_children():
		if only_visual and str(child.name) != "Visual":
			continue
		# 子节点可能带 scale（平台的 Visual 就是靠 scale 缩到 rect 大小的），要乘进去
		var s: Vector2 = (child as Node2D).scale if child is Node2D else Vector2.ONE
		var pos: Vector2 = (child as Node2D).position if child is Node2D else Vector2.ZERO
		if child is Polygon2D:
			for p in (child as Polygon2D).polygon:
				worst = maxf(worst, _outside(box, pos + p * s))
		elif child is Line2D:
			for p in (child as Line2D).points:
				worst = maxf(worst, _outside(box, pos + p * s))
	return worst

func _outside(box: Rect2, p: Vector2) -> float:
	return maxf(maxf(box.position.x - p.x, p.x - box.end.x),
		maxf(box.position.y - p.y, p.y - box.end.y))

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[terrain_layer] " + msg)
		_failed = true
