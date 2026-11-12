extends SceneTree
## 试玩反馈回归（遮挡类）：
##   - 教学关拿剑处的尸体不能压住剑；
##   - 目标提示文字和引导光要画在道具之上，不能被祭坛/木桩挡住；
##   - 第一层不能在地上再放一把剑（玩家已经带着铁剑，重复）。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/visual_clarity_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"
const FLOOR1 := "res://scenes/world/floor1.tscn"

var _phase := 0
var _level: Node
var _failed := false
var _waited := 0

func _process(_delta: float) -> bool:
	if _level == null:
		_level = load(ARENA if _phase == 0 else FLOOR1).instantiate()
		root.add_child(_level)
		_waited = 0
		return false
	_waited += 1
	if _waited < 3:
		return false
	if _phase == 0:
		_check_arena()
		_level.queue_free()
		_level = null
		_phase = 1
		return false
	_check_floor1()
	print("[visual] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check_arena() -> void:
	var corpse := _level.get_node_or_null("Corpse") as Node2D
	var sword := _level.get_node_or_null("WeaponPickup") as Node2D
	_check(corpse != null, "缺少尸体")
	_check(sword != null, "缺少铁剑拾取物")
	if corpse != null and sword != null:
		# 尸体横躺约 60px 宽，剑身约 50px；两者中心至少拉开 60px 才不会叠在一起
		var gap := absf(corpse.global_position.x - sword.global_position.x)
		print("[visual] 尸体与剑水平间距 %.1fpx" % gap)
		_check(gap >= 60.0, "尸体离剑太近，会挡住剑（%.1fpx）" % gap)
	if corpse != null:
		_check_corpse_model(corpse)
	var hud := _level.get_node_or_null("ObjectiveHUD")
	_check(hud != null, "缺少目标提示")
	if hud != null:
		_check(int(hud.z_index) >= 4, "目标提示还在道具后面 z=%d" % hud.z_index)
		var consts: Dictionary = hud.get_script().get_script_constant_map()
		var offset: Vector2 = consts.get("TEXT_OFFSET", Vector2.ZERO)
		_check(offset.y <= -80.0, "目标提示离引导光太近，容易叠在一起")
	# M4-21 组长要求删掉引导光：场景里不该再有 guide_mark，也别让“光点”再被谁引用回来
	_check(_level.get_node_or_null("guide_mark") == null, "教学关还留着引导光 guide_mark")
	# “K 献祭 / K 调查”这类靠近提示也属于 UI，不能缩在祭坛模型后面
	var altar := _level.get_node_or_null("Altar")
	var altar_hint: Label = altar.get_node_or_null("HintLabel") if altar != null else null
	_check(altar_hint != null, "祭坛缺少按 K 提示")
	if altar_hint != null:
		_check(int(altar_hint.z_index) >= 4, "祭坛提示被祭坛模型挡住 z=%d" % altar_hint.z_index)

func _check_floor1() -> void:
	_check(_level.get_node_or_null("WeaponPickup") == null,
		"第一层复活点不该再放一把地上的剑，和手持剑重复")
	# 第一层祭坛调查点的“K 调查”也必须压在道具上
	var inspect := _level.get_node_or_null("InspectPoints/AltarInspect")
	var inspect_prompt: Label = inspect.get_node_or_null("Prompt") if inspect != null else null
	_check(inspect_prompt != null, "第一层祭坛调查点缺少提示")
	if inspect_prompt != null:
		_check(int(inspect_prompt.z_index) >= 4, "调查提示被道具挡住 z=%d" % inspect_prompt.z_index)
	for path in ["Mechanisms/Watchman", "Mechanisms/BellMechanism"]:
		var holder := _level.get_node_or_null(path)
		var prompt: Label = holder.get_node_or_null("Prompt") if holder != null else null
		_check(prompt != null, "%s 缺少靠近提示" % path)
		if prompt != null:
			_check(int(prompt.z_index) >= 4, "%s 提示被道具挡住 z=%d" % [path, prompt.z_index])

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[visual] " + msg)
		_failed = true

## 尸体建模回归（M4-21）：组长说原来只是“一个黄色矩形”。
## 这条不判美术好不好看，只防它退化成一条：部件数量、整体宽高、头骨是不是圆的。
func _check_corpse_model(corpse: Node2D) -> void:
	var parts := corpse.get_children()
	_check(parts.size() >= 8, "尸体只有 %d 个部件，还是几块方块" % parts.size())
	_check(corpse.get_node_or_null("Skull") != null, "尸体没有头骨")
	_check(corpse.get_node_or_null("Cloak") != null, "尸体没有斗篷")
	_check(corpse.get_node_or_null("Arm") != null, "尸体没有伸出去的手臂")
	var skull := corpse.get_node_or_null("Skull") as Polygon2D
	if skull != null:
		_check(skull.polygon.size() >= 10, "头骨是个方块（%d 个顶点），不像圆的" % skull.polygon.size())
	# 整体包围盒：老版本是 52×10 的一条，这里要求又宽又高
	var rect := _corpse_bbox(corpse)
	print("[visual] 尸体包围盒 %.0fx%.0f" % [rect.size.x, rect.size.y])
	_check(rect.size.x >= 80.0, "尸体太短（%.0fpx），不像横躺的人" % rect.size.x)
	_check(rect.size.y >= 16.0, "尸体太扁（%.0fpx），还是一根条" % rect.size.y)

func _corpse_bbox(root: Node2D) -> Rect2:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for child in root.get_children():
		var pts := PackedVector2Array()
		if child is Polygon2D:
			var poly := child as Polygon2D
			for p in poly.polygon:
				pts.append(p + poly.position + root.position)
		elif child is Line2D:
			var line := child as Line2D
			for p in line.points:
				pts.append(p + line.position + root.position)
		for p in pts:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn)
