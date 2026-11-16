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

	arena.queue_free()
	await process_frame
	print("[terrain_layer] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[terrain_layer] " + msg)
		_failed = true
