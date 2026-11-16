extends SceneTree
## 文档截图探针：把每个场景摆到能看清的位置，存成 client/shots/doc/*.png。
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/doc_shots.gd
##
## 四条规矩，缺一个截图就不对：
##   ① 角色一律**落到地面再拍**：先往下打射线找脚下的地面，把人放到地面上方一点，
##      等两三个物理帧让它自己站住，再把物理关掉 —— 手填 y 的话，关卡一改角色就悬空；
##   ② 镜头按游戏里的构图摆：cam = 角色 + (0, -28)，再按 limit 夹一次，
##      这样角色落在屏幕中线偏下，和真玩的时候一样；
##   ③ 教学关的开场黑幕会把整张图压黑，截之前关掉；
##   ④ 取图前 await RenderingServer.frame_post_draw，否则 get_image() 拿到的是上一帧。
## 生成文档用 tools/report/make_scene_doc.py。

const OUT_DIR := "res://shots/doc"
const CAM_OFFSET_Y := 28.0     # 和 camera_follow.gd 的 player_screen_offset 一致
const HALF_HEIGHT := 13.0      # 角色碰撞盒 14×26，脚底在原点下方 13
## 史莱姆用运行时 load：写在这里的 preload 会在自动单例之前编译，解析期就报 Identifier not found
const SLIME_PATH := "res://scenes/entities/slime.tscn"

const SHOTS := [
	{"name": "01_menu", "scene": "res://scenes/main/main.tscn", "x": -1.0, "wait": 2.4},
	{"name": "03_arena_spawn", "scene": "res://scenes/world/test_arena.tscn", "x": 320.0},
	{"name": "04_arena_ledge", "scene": "res://scenes/world/test_arena.tscn", "x": 4200.0},
	{"name": "05_arena_pogo", "scene": "res://scenes/world/test_arena.tscn", "x": 11300.0},
	{"name": "06_arena_pit", "scene": "res://scenes/world/test_arena.tscn", "x": 14000.0, "slime": 280.0},
	{"name": "07_arena_altar", "scene": "res://scenes/world/test_arena.tscn", "x": 21420.0},
	{"name": "08_arena_campfire", "scene": "res://scenes/world/test_arena.tscn", "x": 16420.0},
	{"name": "09_arena_chasm", "scene": "res://scenes/world/test_arena.tscn", "x": 18940.0},
	{"name": "10_arena_door", "scene": "res://scenes/world/test_arena.tscn", "x": 22050.0},
	{"name": "12_floor1_hall", "scene": "res://scenes/world/floor1.tscn", "x": 1600.0},
	{"name": "13_floor2_forge", "scene": "res://scenes/world/floor2.tscn", "x": 1400.0},
	{"name": "15_floor3_hall", "scene": "res://scenes/world/floor3.tscn", "x": 3200.0},
	{"name": "16_floor3_boss", "scene": "res://scenes/world/floor3.tscn", "x": 3600.0},
]

var _scene: Node

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run(0)

func _run(index: int) -> void:
	if index >= SHOTS.size():
		print("[doc] 全部完成")
		quit(0)
		return
	var spec: Dictionary = SHOTS[index]
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		await process_frame
		await process_frame
	var packed := load(str(spec["scene"])) as PackedScene
	if packed == null:
		print("[doc] 读不到 %s" % str(spec["scene"]))
		_run(index + 1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	await create_timer(0.8).timeout
	await _dismiss_dialogue()
	_hide_masks()
	await create_timer(float(spec["wait"]) if spec.has("wait") else 2.0)
	await _dismiss_dialogue()
	_hide_masks()

	if float(spec["x"]) >= 0.0:
		await _stand_player(float(spec["x"]))
		if spec.has("slime"):
			await _drop_slime(float(spec["x"]) + float(spec["slime"]))
		_frame_camera()

	await create_timer(0.4)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, str(spec["name"])])
	var p := _find_player(_scene)
	var c := _find_camera(_scene)
	print("[doc] %s 已存 角色=(%.0f, %.0f) 镜头=(%.0f, %.0f)" % [
		str(spec["name"]),
		p.global_position.x if p != null else -1, p.global_position.y if p != null else -1,
		c.global_position.x if c != null else -1, c.global_position.y if c != null else -1])
	_run(index + 1)

## 把角色放到 x 处的地面上：射线找地面 → 放高一点 → 等它落地 → 关掉物理
func _stand_player(x: float) -> void:
	var player := _find_player(_scene)
	if player == null:
		return
	player.visible = true
	player.modulate = Color(1, 1, 1, 1)
	player.set("_input_locked", false)
	player.set_physics_process(true)
	var surface := _ground_y(x)
	player.global_position = Vector2(x, surface - HALF_HEIGHT - 6.0)
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO
	# 让重力把它放到地面上（不靠手填 y）
	for _i in range(90):
		await physics_frame
		if player is CharacterBody2D and (player as CharacterBody2D).is_on_floor():
			break
	player.global_position = Vector2(x, player.global_position.y)
	player.set_physics_process(false)

## 从上方往下打射线，找 x 处的地面高度。
## 只认地形，门框、道具、怪这些"站在上面的东西"不算 —— 不然角色会被放到门框顶上，看着就是悬空。
## 各地形节点命名不统一（教学关叫 GroundLeft / JumpPlatform，各层是 Plat00 这类），
## 所以这里用**排除法**：名字里带这些词的一律跳过，其余的第一块当地面。
const NOT_TERRAIN := ["Gate", "Door", "Dummy", "Campfire", "Altar", "Weapon",
	"Chest", "Relic", "Player", "Slime", "Hud", "Shockwave"]

func _ground_y(x: float) -> float:
	var space: PhysicsDirectSpaceState2D = _scene.get_world_2d().direct_space_state
	var from := Vector2(x, -200.0)
	var exclude: Array[RID] = []
	for _i in range(6):
		var ray := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 2000.0), 1)
		ray.exclude = exclude
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			break
		var collider := hit.get("collider") as Node
		if collider != null and not _not_terrain(str(collider.name)):
			return float(hit["position"].y)
		if collider is CollisionObject2D:
			exclude.append((collider as CollisionObject2D).get_rid())
		from = Vector2(x, float(hit["position"].y) + 4.0)
	return 659.0

func _not_terrain(name: String) -> bool:
	for word in NOT_TERRAIN:
		if name.findn(word) >= 0:
			return true
	return false

## 需要拍到敌人的那张，先放一只史莱姆在它自己的地面上
func _drop_slime(x: float) -> void:
	var packed_slime := load(SLIME_PATH) as PackedScene
	if packed_slime == null:
		return
	var slime := packed_slime.instantiate() as Node2D
	sprite_position(slime, x)
	_scene.add_child(slime)
	await create_timer(0.5)
	await physics_frame

func sprite_position(node: Node2D, x: float) -> void:
	node.position = Vector2(x, _ground_y(x) - 10.0)

## 按游戏里的构图摆镜头：角色 + (0,-28)，再夹到 limit 里
func _frame_camera() -> void:
	var cam := _find_camera(_scene)
	var player := _find_player(_scene)
	if cam == null or player == null:
		return
	cam.set_physics_process(false)
	cam.position_smoothing_enabled = false
	cam.offset = Vector2.ZERO
	var view := Vector2(root.get_visible_rect().size)
	var half_w := (view.x * 0.5) / cam.zoom.x
	var half_h := (view.y * 0.5) / cam.zoom.y
	var want_x := player.global_position.x
	var want_y := player.global_position.y - CAM_OFFSET_Y
	var l := float(cam.limit_left) + half_w
	var r := float(cam.limit_right) - half_w
	var t := float(cam.limit_top) + half_h
	var b := float(cam.limit_bottom) - half_h
	cam.global_position = Vector2(
		clampf(want_x, minf(l, r), maxf(l, r)),
		clampf(want_y, minf(t, b), maxf(t, b)))
	cam.make_current()
	cam.reset_smoothing()

## 关掉开场黑幕、淡入黑幕、转场黑幕（只影响截图，不改游戏逻辑）
func _hide_masks() -> void:
	for key in ["_intro_blackout", "_intro_spot", "_fade_rect", "_transition_rect"]:
		if key in _scene:
			var item := _scene.get(key) as CanvasItem
			if item != null:
				item.visible = false
	for n in _all_nodes(_scene):
		if n is CanvasItem and (str(n.name).begins_with("Fade") or str(n.name) == "Black"):
			(n as CanvasItem).visible = false

## 逐句翻掉正在播的对话（等价于玩家一直按 K）
func _dismiss_dialogue() -> void:
	for node in _all_nodes(_scene):
		if node.has_method("is_playing") and bool(node.call("is_playing")):
			for _i in range(30):
				if not bool(node.call("is_playing")):
					break
				node.call("_finish")
				await process_frame

func _find_player(node: Node) -> Node2D:
	var fallback: Node2D = node.get_node_or_null("Player") as Node2D
	for n in _all_nodes(node):
		if n is Node2D and n.is_in_group("player") and str(n.name) == "Player":
			return n as Node2D
	return fallback

func _find_camera(node: Node) -> Camera2D:
	for n in _all_nodes(node):
		if n is Camera2D:
			return n as Camera2D
	return null

func _all_nodes(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for child in n.get_children():
			stack.append(child)
	return out
