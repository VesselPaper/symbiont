extends SceneTree
## 第二层回归（M3-01）：地图、两个阵营 NPC、封印门、选择落库和玩家外观。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/floor2_test.gd

const SCENE := "res://scenes/world/floor2.tscn"

var _level: Node
var _failed := false
var _gm: Node

func _process(_delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_gm.set("faction", "")
		_gm.set("flags", {})
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_check_map()
	_check_npcs()
	_check_choice()
	print("[floor2] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[floor2] " + msg)
		_failed = true

func _check_map() -> void:
	var terrain := _level.get_node("Terrain")
	# M4-09 后段加长：封印门后多两段断阶，总地形 11、可站地面 9
	_check(terrain.get_child_count() == 11, "第二层地形数量不是 11")
	var floors: Array[StaticBody2D] = []
	for child in terrain.get_children():
		var body := child as StaticBody2D
		if body == null:
			continue
		var rect := (body.get_node("CollisionShape2D").shape as RectangleShape2D).size
		if rect.x > 100.0:
			floors.append(body)
	_check(floors.size() == 9, "可站地面应是 9 块，实际 %d" % floors.size())
	var backdrop := _level.get_node("Backdrop")
	_check(float(backdrop.get("world_width")) >= 5200.0, "第二层地图宽度没加到 5200")
	var camera := _level.get_node("Camera2D") as Camera2D
	_check(camera.limit_right >= 5300, "第二层相机右限幅没跟上新地图")
	var gate := _level.get_node_or_null("Props/GateFrame") as Node2D
	_check(gate != null and gate.global_position.x >= 5000.0, "第三层门没移到新后段")
	var entry := _level.get_node_or_null("Floor3Entry") as Node2D
	_check(entry != null and entry.global_position.x >= 5100.0, "第三层入口没跟着门右移")
	var prev_right := -99999.0
	var prev_top := 0.0
	for i in range(floors.size()):
		var body := floors[i]
		var rect := (body.get_node("CollisionShape2D").shape as RectangleShape2D).size
		var left := body.global_position.x - rect.x * 0.5
		var right := body.global_position.x + rect.x * 0.5
		var top := body.global_position.y - rect.y * 0.5
		if i > 0:
			_check(left - prev_right <= 150.0, "第 %d 块到第 %d 块断口太宽" % [i, i + 1])
			_check(absf(top - prev_top) <= 100.0, "第 %d 块到第 %d 块落差太大" % [i, i + 1])
		prev_right = right
		prev_top = top
	var props := _level.get_node("Props")
	_check(props.get_node_or_null("Boiler") != null, "缺少铸炉")
	_check(props.get_node_or_null("GateFrame") != null, "缺少第三层层门")
	var npc_holder := _level.get_node("FactionNPCs")
	_check(npc_holder.get_child_count() == 2, "阵营 NPC 不是 2 个")

func _check_npcs() -> void:
	var engineer := _level.get_node("FactionNPCs/Engineer")
	var heretic := _level.get_node("FactionNPCs/HereticPriest")
	_check(engineer.get("faction") == "engineer", "工程师阵营字段错误")
	_check(heretic.get("faction") == "heretic", "祭司阵营字段错误")
	_check(engineer.get("controller") == _level, "NPC 没有挂到关卡控制器")
	_check(heretic.get("controller") == _level, "NPC 没有挂到关卡控制器")
	# M4-13：两个 NPC 必须绑定第二层 Dialogue，不能全局抓到 AudioDirector/Bgm
	var dialogue := _level.get_node("Dialogue")
	for pair in [["工程师", engineer], ["祭司", heretic]]:
		var bound = pair[1].get("_dialogue")
		_check(is_instance_valid(bound) and str(bound.get_path()) == str(dialogue.get_path()),
			"%s没有绑定第二层 Dialogue，实际绑到 %s" % [
				pair[0], str(bound.get_path()) if is_instance_valid(bound) else "<invalid>"])
	var seal := _level.get_node("Mechanisms/FactionSeal")
	_check(seal != null and seal.has_method("is_open"), "缺少封印门")
	_check(not bool(seal.call("is_open")), "没选阵营前封印门不应打开")
	var col := seal.get_node("CollisionShape2D") as CollisionShape2D
	_check(col != null and not col.disabled, "没选阵营前封印门碰撞应启用")
	# 反向：提议结束的同一帧不能立刻武装“确认”，否则一记 K 会既关对话又选边
	_check(not bool(engineer.get("_confirm_ready")), "提议没播就允许确认")
	engineer.call("_on_dialogue_finished", "floor2_engineer_offer")
	_check(not bool(engineer.get("_confirm_ready")), "提议结束当帧就武装了确认")

func _check_choice() -> void:
	var engineer := _level.get_node("FactionNPCs/Engineer") as Node2D
	var heretic := _level.get_node("FactionNPCs/HereticPriest") as Node2D
	var seal := _level.get_node("Mechanisms/FactionSeal")
	var player := _level.get_node("Player")
	_check(bool(_level.call("choose_faction", "engineer")), "选工程师应成功")
	_check(str(_gm.get("faction")) == "engineer", "GameManager.faction 没写工程师")
	_check(bool(_gm.call("has_flag", "floor2_faction_chosen")), "缺少阵营选择旗标")
	_check(bool(_gm.call("has_flag", "floor2_faction_engineer")), "缺少工程师分支旗标")
	_check(bool(seal.call("is_open")), "选完阵营封印门应打开")
	var col := seal.get_node("CollisionShape2D") as CollisionShape2D
	_check(col.disabled, "选完阵营封印门碰撞应关闭")
	_check(player.get_node_or_null("Body/FactionVisual") != null, "玩家没有蒸汽靴外观")
	_check(engineer.modulate.a > 0.9, "被选中的工程师不应变暗")
	_check(heretic.modulate.a < 0.9, "没被选的祭司应变暗")
	_check(not bool(_level.call("choose_faction", "heretic")), "已经选过还能改阵营")
	_check(str(_gm.get("faction")) == "engineer", "改阵营把 GameManager 改坏了")
	var db := root.get_node("/root/DataDB")
	for id in [
		"floor2_enter", "floor2_engineer_offer", "floor2_engineer_confirm",
		"floor2_engineer_after", "floor2_heretic_offer", "floor2_heretic_confirm",
		"floor2_heretic_after", "floor2_gate",
	]:
		var row: Dictionary = db.get_dialogue(id)
		_check(not row.is_empty(), "缺少第二层对话 %s" % id)
		_check((row.get("lines", []) as Array).size() >= 2, "第二层对话 %s 太短" % id)
