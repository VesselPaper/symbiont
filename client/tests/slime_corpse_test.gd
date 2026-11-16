extends SceneTree
## 史莱姆尸体回归（M2-05 / M5-17）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/slime_corpse_test.gd
##
## 验收：史莱姆死亡后不直接消失，留下 SlimeCorpse；尸体无碰撞、
## 不进入 damageable，肢体在旁边错开；数秒后尸体才淡出。
## M5-17（组长反馈"空中被打死时尸体和掉落物停在半空"）：
##   ① 在空中被打死、下面有地 → 尸体和肢体要**落到地面**上（不能停在死亡点）；
##   ② 下面没地（悬崖/无底坑）→ 干脆不生成，跟着一起掉下去消失（不能浮在半空）。

const SLIME := "res://scenes/entities/slime.tscn"
const GROUND_TOP := 540.0

var _failed := false
var _ground: StaticBody2D

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	# 地面只铺左半边（0..600），右边 600..1200 是没底的坑
	_ground = StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(600, 90)
	col.shape = shape
	_ground.add_child(col)
	_ground.position = Vector2(300, GROUND_TOP + 45.0)
	root.add_child(_ground)

	# ---- ① 悬空处死、下面有地：尸体和肢体都要落到地面 ----
	var first: Node = await _kill_over(Vector2(240, GROUND_TOP - 80.0))
	_check(not is_instance_valid(first), "史莱姆本体没有按死亡动画销毁")
	var corpse: Node2D = root.get_node_or_null("SlimeCorpse") as Node2D
	_check(corpse != null, "死亡后没有生成 SlimeCorpse")
	if corpse != null:
		_check(absf(corpse.global_position.y - (GROUND_TOP - 4.0)) <= 10.0,
			"尸体没有落到地面（y=%.1f，地面 %.0f）" % [corpse.global_position.y, GROUND_TOP])
		_check(corpse.z_index < 0, "尸体应压在角色后面")
		_check(corpse.get_child_count() >= 8, "尸体分件太少，不能辨认")
		_check(not corpse.is_in_group("damageable"), "尸体不应再被攻击")
		_check(corpse.get_node_or_null("CollisionShape2D") == null, "尸体不应有碰撞")
	var pickup: Node2D = root.get_node_or_null("LimbPickup") as Node2D
	_check(pickup != null, "尸体旁没有肢体拾取物")
	if pickup != null and corpse != null:
		_check(absf(pickup.global_position.x - corpse.global_position.x) >= 6.0,
			"肢体与尸体模型叠在一起")
		_check(absf(pickup.global_position.y - (GROUND_TOP - 6.0)) <= 10.0,
			"肢体没有落到地面（y=%.1f）" % pickup.global_position.y)
	# 清场：第二段要判断"这张图上没有尸体/肢体"，得先把上一段的收走
	if corpse != null:
		corpse.queue_free()
	if pickup != null:
		pickup.queue_free()
	await physics_frame
	await physics_frame

	# ---- ② 反向：悬在没底的坑上方死，尸体和肢体都不该生成（否则就是浮在半空那一批）----
	var second: Node = await _kill_over(Vector2(900, GROUND_TOP - 80.0))
	_check(not is_instance_valid(second), "坑上那只史莱姆没销毁")
	_check(root.get_node_or_null("SlimeCorpse") == null, "死在悬崖上方还生成了尸体（会浮在半空）")
	_check(root.get_node_or_null("LimbPickup") == null, "死在悬崖上方还掉了肢体（会浮在半空）")

	_ground.queue_free()
	await process_frame
	print("[slime_corpse] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 在 point 放一只史莱姆、等它站稳、打死它，再等尸体生成（或确认没有）
func _kill_over(point: Vector2) -> Node:
	var slime: Node2D = load(SLIME).instantiate()
	root.add_child(slime)
	slime.global_position = point
	for _i in range(60):
		await physics_frame
	slime.call("take_damage", 999)
	for _i in range(180):
		await physics_frame
		if not is_instance_valid(slime):
			break
	return slime

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[slime_corpse] " + message)
		_failed = true
