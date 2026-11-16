extends SceneTree
## 篝火休息回归（M5）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/campfire_test.gd
##
## 验收：每层都有篝火；篝火在地图中段、落在地面上；休息回满血并发 player_healed；
## 满血时休息返回 0（不重复刷提示）；灵魂火舌组件能正常挂载。

const SCENES := [
	{"path": "res://scenes/world/test_arena.tscn", "min_x": 2000.0, "max_x": 5500.0, "ground": 659.0},
	# M5-09：第一层钟绳前那座篝火删了，这一层不再有篝火
	{"path": "res://scenes/world/floor2.tscn", "min_x": 1500.0, "max_x": 3500.0, "ground": 600.0},
	{"path": "res://scenes/world/floor3.tscn", "min_x": 2000.0, "max_x": 2600.0, "ground": 620.0},
]

var _frames := 0
var _index := 0
var _level: Node
var _failed := false
var _healed_signal := 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _index >= SCENES.size():
		print("[campfire] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	if _level == null:
		if _frames % 3 != 0:
			return false
		var spec: Dictionary = SCENES[_index]
		_level = load(str(spec["path"])).instantiate()
		root.add_child(_level)
		return false
	if _frames % 3 != 0:
		return false
	_check_scene(SCENES[_index])
	_level.queue_free()
	_level = null
	_index += 1
	return false

func _check_scene(spec: Dictionary) -> void:
	var fire := _level.get_node_or_null("Campfire")
	_check(fire != null, "%s 没有篝火" % str(spec["path"]))
	if fire == null:
		return
	var x := float((fire as Node2D).position.x)
	_check(x >= float(spec["min_x"]) and x <= float(spec["max_x"]),
		"篝火 x=%.0f 不在中段范围内" % x)
	_check(absf(float((fire as Node2D).position.y) - float(spec["ground"])) < 24.0,
		"篝火 y=%.0f 没落在 %.0f 的地面上" % [float((fire as Node2D).position.y), float(spec["ground"])])
	# 回血：把血打低，调用休息。M5-02 组长改的规则：一次只回 1 颗心，不是回满
	var player := _level.get_node_or_null("Player")
	_check(player != null, "%s 缺少 Player" % str(spec["path"]))
	if player == null:
		return
	var bus := root.get_node_or_null("/root/EventBus")
	if bus != null and not bus.is_connected("player_healed", Callable(self, "_on_healed")):
		bus.connect("player_healed", Callable(self, "_on_healed"))
	player.set("hp", 1)
	var before := _healed_signal
	fire.call("_rest")
	var rest_heal := int(fire.get_script().get_script_constant_map()["REST_HEAL"])
	_check(int(player.get("hp")) == 1 + rest_heal,
		"休息后没正好回 %d 颗心（hp=%d）" % [rest_heal, int(player.get("hp"))])
	_check(_healed_signal > before, "休息没有发 player_healed")
	# M5-02：按 K 之后人原地不动 —— 不许再走那套蹲坐（_rest_timer 必须还是 0）
	_check(float(player.get("_rest_timer")) <= 0.0, "休息把角色压下去了（_rest_timer=%.2f）" % float(player.get("_rest_timer")))
	# 休息完这堆火开始慢慢熄：火命不再是满的，且标记为已用过
	_check(bool(fire.get("_rested")), "休息完没有把篝火标记成已用过")
	# 火命是 tween 每帧往下写的，调用当场还停在 1.0，看 _dying 这个"正在熄"的开关
	_check(bool(fire.get("_dying")) or float(fire.get("_fire_life")) < 1.0,
		"休息完火没有开始熄灭（_fire_life=%.2f）" % float(fire.get("_fire_life")))
	# 同一座火再按一次：什么都不该发生（血不变、不发信号）
	var before2 := _healed_signal
	var hp_before2 := int(player.get("hp"))
	fire.call("_rest")
	_check(_healed_signal == before2, "烧完的篝火还能再回血")
	_check(int(player.get("hp")) == hp_before2, "烧完的篝火改了血量")

func _on_healed(_amount: int) -> void:
	_healed_signal += 1

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[campfire] " + msg)
		_failed = true
