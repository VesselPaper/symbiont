extends SceneTree
## 文档截图探针：把每个场景摆到能看清的位置，存成 client/shots/doc/*.png。
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/doc_shots.gd
##
## 三件必须做的事，缺一个就截不对：
##   ① 教学关的开场黑幕（只有角色周围一圈可见）会把整张图压黑，截之前关掉；
##   ② 镜头跟随写在物理帧里，瞬移玩家之后未必跟得上，截之前把镜头物理关掉、直接摆到
##      和游戏里一样的构图（cam = 玩家 + (0, -28)，必要时另给 cam_x 取景）；
##   ③ 取图前必须 await RenderingServer.frame_post_draw，否则 get_image() 拿到的是上一帧
##      （角色和镜头都还在旧位置，截出来是空的）。
## 生成文档用 tools/report/make_scene_doc.py。

const OUT_DIR := "res://shots/doc"
## 史莱姆用运行时 load：写在类顶部的 preload 会在自动单例（GameManager）加载之前编译，
## 那段脚本里引用了 GameManager，会在解析期报 "Identifier not found"。
const SLIME_PATH := "res://scenes/entities/slime.tscn"

const SHOTS := [
	{"name": "01_menu", "scene": "res://scenes/main/main.tscn", "x": -1.0, "y": -1.0, "cam_y": -1.0, "wait": 2.4},
	{"name": "03_arena_spawn", "scene": "res://scenes/world/test_arena.tscn", "x": 300.0, "y": 646.0, "cam_y": 552.0},
	{"name": "04_arena_ledge", "scene": "res://scenes/world/test_arena.tscn", "x": 1500.0, "y": 558.0, "cam_y": 530.0},
	{"name": "05_arena_pogo", "scene": "res://scenes/world/test_arena.tscn", "x": 3150.0, "y": 558.0, "cam_y": 530.0},
	{"name": "06_arena_pit", "scene": "res://scenes/world/test_arena.tscn", "x": 4120.0, "y": 646.0, "cam_y": 552.0, "slime": Vector2(4360.0, 646.0)},
	{"name": "07_arena_altar", "scene": "res://scenes/world/test_arena.tscn", "x": 7050.0, "y": 646.0, "cam_y": 552.0},
	{"name": "08_arena_campfire", "scene": "res://scenes/world/test_arena.tscn", "x": 5640.0, "y": 646.0, "cam_y": 552.0, "cam_x": 5700.0},
	{"name": "09_arena_chasm", "scene": "res://scenes/world/test_arena.tscn", "x": 5790.0, "y": 646.0, "cam_y": 552.0},
	{"name": "10_arena_door", "scene": "res://scenes/world/test_arena.tscn", "x": 7300.0, "y": 646.0, "cam_y": 552.0},
	{"name": "12_floor1_hall", "scene": "res://scenes/world/floor1.tscn", "x": 1600.0, "y": 747.0, "cam_y": 719.0},
	{"name": "13_floor2_forge", "scene": "res://scenes/world/floor2.tscn", "x": 1400.0, "y": 627.0, "cam_y": 599.0},
	{"name": "15_floor3_hall", "scene": "res://scenes/world/floor3.tscn", "x": 3200.0, "y": 587.0, "cam_y": 559.0},
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
	await create_timer(float(spec["wait"]) if spec.has("wait") else 2.2)
	# 需要拍到敌人的那张，就先放一只（游戏里也是这一环才生成）
	if spec.has("slime"):
		var packed_slime := load(SLIME_PATH) as PackedScene
		if packed_slime != null:
			var slime := packed_slime.instantiate() as Node2D
			slime.position = spec["slime"]
			_scene.add_child(slime)
			await create_timer(0.8)
	await _dismiss_dialogue()
	_hide_masks()

	if float(spec["x"]) >= 0.0:
		var player := _find_player(_scene)
		if player != null:
			player.visible = true
			player.modulate = Color(1, 1, 1, 1)
			player.global_position = Vector2(float(spec["x"]), float(spec["y"]))
			player.set_physics_process(false)
			player.set("_input_locked", false)
		var cam := _find_camera(_scene)
		if cam != null and float(spec["cam_y"]) >= 0.0:
			cam.set_physics_process(false)
			cam.position_smoothing_enabled = false
			cam.offset = Vector2.ZERO
			var cam_x := float(spec["cam_x"]) if spec.has("cam_x") else float(spec["x"])
			cam.global_position = Vector2(cam_x, float(spec["cam_y"]))
			cam.make_current()
			cam.reset_smoothing()

	await create_timer(0.45)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, str(spec["name"])])
	print("[doc] %s 已存" % str(spec["name"]))
	_run(index + 1)

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
