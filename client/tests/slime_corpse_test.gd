extends SceneTree
## 史莱姆尸体回归（M2-05）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/slime_corpse_test.gd
##
## 验收：史莱姆死亡后不直接消失，留下 SlimeCorpse；尸体无碰撞、
## 不进入 damageable，肢体在旁边错开；数秒后尸体才淡出。

var _frames := 0
var _slime: Node2D
var _failed := false
var _killed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_slime = load("res://scenes/entities/slime.tscn").instantiate()
		root.add_child(_slime)
		_slime.position = Vector2(240, 520)
		return false
	if _frames == 8 and not _killed:
		_killed = true
		_slime.call("take_damage", 999)
		return false
	if _frames < 60:
		return false
	_run_checks()
	print("[slime_corpse] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _run_checks() -> void:
	_check(not is_instance_valid(_slime), "史莱姆本体没有按死亡动画销毁")
	var corpse: Node2D = root.get_node_or_null("SlimeCorpse") as Node2D
	_check(corpse != null, "死亡后没有生成 SlimeCorpse")
	if corpse == null:
		return
	_check(corpse.z_index < 0, "尸体应压在角色后面")
	_check(corpse.get_child_count() >= 8, "尸体分件太少，不能辨认")
	_check(not corpse.is_in_group("damageable"), "尸体不应再被攻击")
	var collision := corpse.get_node_or_null("CollisionShape2D")
	_check(collision == null, "尸体不应有碰撞")
	var pickup: Node2D = root.get_node_or_null("LimbPickup") as Node2D
	_check(pickup != null, "尸体旁没有肢体拾取物")
	if pickup != null:
		_check(absf(pickup.global_position.x - corpse.global_position.x) >= 6.0,
			"肢体与尸体模型叠在一起")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[slime_corpse] " + message)
		_failed = true
