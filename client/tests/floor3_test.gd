extends SceneTree
## 第三层回归（M3-02）：地图、Boss、出口门、双结局判定和结局画面。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/floor3_test.gd

const SCENE := "res://scenes/world/floor3.tscn"

var _level: Node
var _failed := false
var _gm: Node

func _process(_delta: float) -> bool:
	if _level == null:
		_gm = root.get_node("/root/GameManager")
		_gm.set("flags", {})
		_gm.set("sacrifice_count", 1)
		_gm.set("has_weapon", true)
		_gm.set("state", 2)
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		return false
	_check_map()
	_check_boss()
	_check_ending_rules()
	print("[floor3] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[floor3] " + msg)
		_failed = true

func _check_map() -> void:
	var terrain := _level.get_node("Terrain")
	# M4-09：Boss 厅前加一段 500px 断兵回廊，总地形 8、可站地面 6
	_check(terrain.get_child_count() == 8, "第三层地形数量不是 8")
	var floors: Array[StaticBody2D] = []
	for child in terrain.get_children():
		var body := child as StaticBody2D
		if body == null:
			continue
		var rect := (body.get_node("CollisionShape2D").shape as RectangleShape2D).size
		if rect.x > 100.0:
			floors.append(body)
	_check(floors.size() == 6, "可站地面应是 6 块，实际 %d" % floors.size())
	var backdrop := _level.get_node("Backdrop")
	_check(float(backdrop.get("world_width")) >= 4200.0, "第三层地图宽度没加到 4200")
	var camera := _level.get_node("Camera2D") as Camera2D
	_check(camera.limit_right >= 4300, "第三层相机右限幅没跟上新地图")
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
	_check(prev_right >= 4200.0, "最后一块地面没盖住出口门")
	_check(_level.get_node_or_null("BossHolder/Gatekeeper") != null, "缺少守门者")
	var boss_node := _level.get_node("BossHolder/Gatekeeper") as Node2D
	_check(boss_node.global_position.x >= 3500.0, "守门者没跟着 Boss 厅右移")
	var bounds: Vector2 = boss_node.call("get_arena_bounds")
	_check(bounds.x >= 2900.0 and bounds.y >= 4050.0, "守门者活动范围没覆盖右移后的 Boss 厅")
	_check(_level.get_node_or_null("Mechanisms/BossExitDoor") != null, "缺少 Boss 出口门")
	_check(_level.get_node_or_null("Triggers/ArenaTrigger") != null, "缺少 Boss 触发区")
	# M4-02：第三层进场/死亡复活后不能丢剑
	var player := _level.get_node("Player")
	_check(bool(player.get("has_weapon")), "带剑进第三层后玩家空手")
	player.call("_respawn")
	_check(bool(player.get("has_weapon")), "第三层复活后玩家丢剑")
	_check(_level.get_node_or_null("Triggers/EndingTrigger") != null, "缺少结局触发区")
	_check(_level.get_node_or_null("BossHUD") != null, "缺少 Boss 血条层")
	_check(_level.get_node_or_null("ReturnShaftHolder/ReturnShaft") != null, "缺少回起点货梯")
	# 反向：Boss 没死时货梯不能把人送回起点
	_level.call("return_to_start")
	_check(not bool(_gm.call("has_flag", "true_he_return")), "Boss 没死货梯就写回头旗标")
	var door := _level.get_node("Mechanisms/BossExitDoor")
	_check(not bool(door.call("is_open")), "Boss 未死前出口门不应打开")
	var col := door.get_node("CollisionShape2D") as CollisionShape2D
	_check(not col.disabled, "Boss 未死前出口门应挡住玩家")

func _check_boss() -> void:
	var boss := _level.get_node("BossHolder/Gatekeeper")
	_check(int(boss.call("get_max_hp")) == 24, "Boss 血量没从数据表读成 24")
	boss.call("activate")
	# 先打掉一半，确认进二阶段
	var half := int(boss.call("get_max_hp")) / 2
	for i in range(half):
		boss.call("take_damage", 1)
	_check(bool(boss.call("is_phase2")), "Boss 半血后没有进二阶段")
	_check(not bool(boss.call("is_dead")), "Boss 半血就死了")
	# 再打掉剩下的
	for i in range(half):
		boss.call("take_damage", 1)
	_check(bool(boss.call("is_dead")), "Boss 血量归零后没死")
	_check(int(boss.call("get_hp")) == 0, "Boss 血量不是 0")
	_check(bool(_gm.call("has_flag", "boss_defeated")), "Boss 死后缺少 boss_defeated 旗标")
	var door := _level.get_node("Mechanisms/BossExitDoor")
	_check(bool(door.call("is_open")), "Boss 死后出口门没打开")
	var col := door.get_node("CollisionShape2D") as CollisionShape2D
	_check(col.disabled, "Boss 死后出口门碰撞没关闭")

func _check_ending_rules() -> void:
	_check(str(_level.call("resolve_ending_id", 1)) == "human", "献祭 1 次应走人类结局")
	_check(str(_level.call("resolve_ending_id", 3)) == "transformed", "献祭 3 次应走异化结局")
	var db := root.get_node("/root/DataDB")
	for id in ["floor3_enter", "floor3_boss_intro", "floor3_after_boss"]:
		var row: Dictionary = db.get_dialogue(id)
		_check(not row.is_empty(), "缺少第三层对话 %s" % id)
		_check((row.get("lines", []) as Array).size() >= 2, "第三层对话 %s 太短" % id)
	for id in ["human", "transformed"]:
		var ending: Dictionary = db.call("get_ending", id)
		_check(not ending.is_empty(), "缺少结局 %s" % id)
	# 人类结局画面：标题来自 endings 表，不是脚本写死
	_level.call("_show_ending")
	_check(_level.get_node_or_null("EndingScreen") != null, "没生成结局画面")
	_check(int(_gm.get("state")) == 4, "结局时 GameManager 没进 ENDING 状态")
	var ending_layer := _level.get_node("EndingScreen")
	var vbox := ending_layer.get_child(1) as VBoxContainer
	var title := vbox.get_child(1) as Label
	_check(title != null and title.text == "人类结局", "结局标题不是 DataDB 的人类结局")
	_check(vbox.get_node_or_null("ContinueHint") == null, "结局画面不应复用对话 UI")
	# 真 HE 旗标优先于献祭数（正常流程在祭坛结算，这里只验证兜底判定）
	_gm.call("set_flag", "true_he_unlocked")
	_check(str(_level.call("resolve_ending_id", 1)) == "true_he", "真 HE 旗标没有优先于献祭数")
	_check(str(_level.call("resolve_ending_id", 3)) == "true_he", "真 HE 旗标没有优先于异化线")
	_gm.get("flags").erase("true_he_unlocked")
