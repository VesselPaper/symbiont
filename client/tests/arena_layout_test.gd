extends SceneTree
## 教学关留白回归（M4-19）
##
## 组长反馈“教学关每个项目都挤在一起，剧情/玩家没有缓冲”。这条测试守三件事：
##   1. 八个教学环从左到右排开，相邻两环的横向距离不少于 MIN_GAP；
##   2. 五扇教学门都落在两环之间的缝里，既压不到光点，也踩在自己那块地面上；
##   3. 场景里真正摆出来的地形/道具和 STAGE 表一致（表改了、场景没跟上就会红）。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/arena_layout_test.gd

const SCENE := "res://scenes/world/test_arena.tscn"
## 相邻教学环的最小横向留白。一屏约 747 宽，300 大约是半屏：看完一个目标走一段路才撞见下一个。
const MIN_GAP := 300.0
## 门和光点、道具之间的最小横向距离（门宽 34，留 40 保证光点不会被门身压住）
const MIN_CLEARANCE := 40.0
const GROUND_TOP := 659.0

var _level: Node
var _frames := 0
var _failed := false
var _stage: Dictionary

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_stage = _level.get_script().get_script_constant_map()["STAGE"]
		return false
	if _frames < 10:
		return false
	_check_order()
	_check_gaps()
	_check_gates()
	_check_hint_text_clear_of_gates()
	_check_terrain()
	_check_targets_match()
	print("[arena_layout] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[arena_layout] " + msg)
		_failed = true

# ---------- 一、顺序与间距 ----------

## 八个教学环的横坐标（含终点层门）。顺序错了说明光点/道具又挤回一起了。
func _beats() -> Array:
	return [
		{"label": "出生", "x": float(_stage["spawn"].x)},
		{"label": "移动光点", "x": float(_stage["move_mark"].x)},
		{"label": "跳跃光点", "x": float(_stage["jump_mark"].x)},
		{"label": "拿剑", "x": float(_stage["sword"].x)},
		{"label": "打木桩", "x": float(_stage["dummy_a"].x)},
		{"label": "下劈台", "x": float(_stage["pogo_mark"].x)},
		{"label": "战斗区", "x": float(_stage["combat_mark"].x)},
		{"label": "祭坛", "x": float(_stage["altar"].x)},
		{"label": "宝箱", "x": float(_stage["chest"].x)},
		{"label": "层门", "x": float(_stage["door"].x)},
	]

func _check_order() -> void:
	var beats := _beats()
	for i in range(1, beats.size()):
		_check(float(beats[i]["x"]) > float(beats[i - 1]["x"]),
			"%s 没排在 %s 右边" % [beats[i]["label"], beats[i - 1]["label"]])

func _check_gaps() -> void:
	var beats := _beats()
	for i in range(1, beats.size()):
		var gap := float(beats[i]["x"]) - float(beats[i - 1]["x"])
		print("[arena_layout] %-6s → %-6s %5.0f px" % [beats[i - 1]["label"], beats[i]["label"], gap])
		_check(gap >= MIN_GAP, "%s 到 %s 只有 %.0fpx，太挤" % [beats[i - 1]["label"], beats[i]["label"], gap])

# ---------- 二、门落在缝里 ----------

## 五扇门：id → 踩在哪个面上（地面/跳台/祭坛台）
func _gate_floors() -> Array:
	return [
		{"id": "move", "floor": GROUND_TOP},
		{"id": "jump", "floor": float(_stage["ledge"].position.y)},
		{"id": "attack", "floor": float(_stage["ledge"].position.y)},
		{"id": "pogo", "floor": GROUND_TOP},
		{"id": "combat", "floor": GROUND_TOP},
	]

func _check_gates() -> void:
	var heights: Dictionary = _level.get_script().get_script_constant_map()["TUTORIAL_GATE_HEIGHTS"]
	var targets: Array = _level.get_node("Tutorial").get("_anchors")
	for item in _gate_floors():
		var gate_id: String = item["id"]
		var pos: Vector2 = _stage["%s_gate" % gate_id]
		var h: float = float(heights[gate_id])
		var bottom := pos.y + h * 0.5
		# 门站在地面上：底边必须和它那块地形齐平
		_check(absf(bottom - float(item["floor"])) < 1.0,
			"%s 门底 y=%.1f，应落在 %.1f" % [gate_id, bottom, float(item["floor"])])
		# 门不能压住任何提示锚点（文字埋在栅栏里就读不清）
		for i in range(targets.size()):
			var t: Vector2 = targets[i]
			if absf(t.x - pos.x) < MIN_CLEARANCE and absf(t.y - pos.y) < h * 0.5 + 40.0:
				_check(false, "%s 门压住了第 %d 个提示锚点 %s" % [gate_id, i, str(t)])
		# 门要真的挡在“下一环”前面：门右边必须有东西可做
		_check(_gate_blocks_something(gate_id, pos.x),
			"%s 门 %.0f 右边没有下一环，门没有意义" % [gate_id, pos.x])

## 门是分区的：每扇门右边不远处都要有下一环的目标
func _gate_blocks_something(gate_id: String, gate_x: float) -> bool:
	var next_x := 1.0e9
	for item in _beats():
		if float(item["x"]) > gate_x + MIN_CLEARANCE:
			next_x = minf(next_x, float(item["x"]))
	return next_x < 1.0e9

## 提示文字是整句宽度，不是锚点一个点：M4-22 组长说的“A/D 提示压在骨栅门上”，
## 就是锚点让开了、字却还横穿门身。这里按真实字宽把每句话的矩形和门矩形比一遍。
func _check_hint_text_clear_of_gates() -> void:
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font == null:
		_check(false, "加载中文字体失败，量不了提示文字宽度")
		return
	var tutorial := _level.get_node("Tutorial")
	var consts: Dictionary = tutorial.get_script().get_script_constant_map()
	var texts: Array = consts["OBJECTIVE_TEXTS"]
	var hud := _level.get_node("ObjectiveHUD")
	var offset: Vector2 = hud.get_script().get_script_constant_map()["TEXT_OFFSET"]
	var anchors: Array = tutorial.get("_anchors")
	var heights: Dictionary = _level.get_script().get_script_constant_map()["TUTORIAL_GATE_HEIGHTS"]
	for i in range(anchors.size()):
		var text: String = str(texts[i])
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var center: Vector2 = anchors[i] + offset
		# 20px 字号一行，字形高度按 26 算；左右各半句宽，就是那行字的实际占地
		var rect := Rect2(center - Vector2(width, 26.0) * 0.5, Vector2(width, 26.0))
		for gate_id in heights.keys():
			var gate_pos: Vector2 = _stage["%s_gate" % str(gate_id)]
			var h: float = float(heights[gate_id])
			var gate_rect := Rect2(gate_pos - Vector2(17.0, h * 0.5), Vector2(34.0, h))
			if rect.intersects(gate_rect):
				_check(false, "第 %d 句「%s」压住了 %s 门（字 %.0f×26 在 %s）" % [
					i, text, str(gate_id), width, str(rect)])
		print("[arena_layout] %-3d「%s」字宽 %.0f，中心 %s" % [i, text, width, str(center)])

# ---------- 三、场景和表对上了 ----------

func _check_terrain() -> void:
	var world_w: float = float(_stage["world_width"])
	var ground := _level.get_node("GroundLeft") as StaticBody2D
	var ground_shape := (ground.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	_check(absf(ground_shape.size.x - world_w) < 1.0, "地面宽 %.0f，地图宽 %.0f" % [ground_shape.size.x, world_w])
	_check(absf(ground.position.y - (GROUND_TOP + 30.0)) < 1.0, "地面顶不是 %.0f" % GROUND_TOP)
	var wall := _level.get_node("WallRight") as Node2D
	_check(absf(wall.position.x - world_w) < 1.0, "右墙没有钉在地图尽头")
	var camera := _level.get_node("Camera2D") as Camera2D
	_check(camera.limit_right == int(world_w), "相机右限幅 %d，地图宽 %.0f" % [camera.limit_right, world_w])
	var art := _level.get_node("BackdropArt") as Node
	# 美术脚本挂不上（改坏了/拼错了）不会让任何几何断言失败，但整张地图会变成空墙，
	# 所以单独盯一句：脚本必须在
	_check(art.get_script() != null, "背景美术脚本没挂上，整段背景装饰会消失")
	_check(absf(float(art.get("world_width")) - world_w) < 1.0, "背景没跟着地图加宽")

	# 三块平台的顶面和左右边界
	_platform("JumpPlatform", _stage["ledge"])
	_platform("PogoPlatform", _stage["pogo"])
	_platform("AltarPlatform", _stage["altar_hall"])

	# 道具/玩家全都站到表里的位置（M4-21 起没有引导光，guide_mark 已删）
	_placed("Player", _stage["spawn"])
	_placed("Corpse", _stage["corpse"])
	_placed("WeaponPickup", _stage["sword"])
	_placed("DummyA", _stage["dummy_a"])
	_placed("DummyB", _stage["dummy_b"])
	_placed("Altar", _stage["altar"])
	_placed("SteamBootsChest", _stage["chest"])

## 平台原点在中心：按碰撞盒反推左上角，和 rect 比
func _platform(node_name: String, rect: Rect2) -> void:
	var body := _level.get_node(node_name) as StaticBody2D
	var shape := (body.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var left := body.position.x - shape.size.x * 0.5
	var top := body.position.y - shape.size.y * 0.5
	_check(absf(left - rect.position.x) < 1.0, "%s 左边 %.0f，应 %.0f" % [node_name, left, rect.position.x])
	_check(absf(top - rect.position.y) < 1.0, "%s 顶面 %.0f，应 %.0f" % [node_name, top, rect.position.y])
	_check(absf(shape.size.x - rect.size.x) < 1.0, "%s 宽 %.0f，应 %.0f" % [node_name, shape.size.x, rect.size.x])

## 横向必须精确（留白全靠 x），纵向允许浮动：玩家会落地、引导光会上下浮，
## 所以只要求它们没离开自己那块地（40px 以内）。
func _placed(node_name: String, expected: Vector2) -> void:
	var node := _level.get_node_or_null(node_name) as Node2D
	_check(node != null, "缺少 %s" % node_name)
	if node != null:
		_check(absf(node.position.x - expected.x) < 1.0,
			"%s 在 x=%.1f，应 x=%.1f" % [node_name, node.position.x, expected.x])
		_check(absf(node.position.y - expected.y) <= 40.0,
			"%s 在 y=%.1f，应 y=%.1f 附近" % [node_name, node.position.y, expected.y])

## Tutorial 自己的默认锚点（没场景注入时用）必须和 STAGE 表一致，
## 不然单挂 Tutorial 的时候提示会飘到老坐标上。
func _check_targets_match() -> void:
	var tutorial := _level.get_node("Tutorial")
	var default_targets: Array = tutorial.get_script().get_script_constant_map()["STEP_ANCHORS"]
	var targets: Array = tutorial.get("_anchors")
	_check(default_targets.size() == targets.size(), "Tutorial 默认锚点数量不对")
	for i in range(mini(default_targets.size(), targets.size())):
		_check(default_targets[i] == targets[i],
			"Tutorial 默认锚点第 %d 个 %s 和 STAGE 表 %s 不一致" % [i, str(default_targets[i]), str(targets[i])])
