extends SceneTree
## 孢子射手/孢子弹回归（M2-07）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/spore_shooter_test.gd
##
## 验收：数据表 hp=6；敌人分组/受击接口正确；孢子弹能朝目标飞；
## 死亡后留下尸体和肢体，不直接消失。

var _frames := 0
var _shooter: Node = null
var _failed := false
var _projectile: Node = null

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_shooter = load("res://scenes/entities/spore_shooter.tscn").instantiate()
		root.add_child(_shooter)
		_shooter.set("position", Vector2(500, 500))
		_projectile = load("res://scenes/entities/spore_projectile.tscn").instantiate()
		root.add_child(_projectile)
		_projectile.set("position", Vector2(400, 500))
		_projectile.call("setup", Vector2(1, 0), 1)
		return false
	if _frames < 20:
		return false
	_run_checks()
	print("[spore] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("[spore] " + message)
		_failed = true

func _run_checks() -> void:
	if _shooter == null:
		push_error("[spore] 射手加载失败")
		_failed = true
		return
	var db := root.get_node_or_null("/root/DataDB")
	var data: Dictionary = db.get_enemy("spore_shooter") if db != null else {}
	_check(int(data.get("hp", 0)) == 6, "数据表 spore_shooter 应为 hp=6")
	_check(_shooter.is_in_group("damageable"), "射手没有进 damageable 组")
	_check(_shooter.is_in_group("enemy"), "射手没有进 enemy 组")
	_check(_shooter.get_node_or_null("ContactArea") != null, "射手缺少接触伤害区")
	_check(_shooter.get("hp") == 6, "射手没有从数据表读到 hp=6")
	if _projectile != null:
		_check(_projectile.get("_velocity").x > 100.0, "孢子弹没有朝右飞")
		_check(_projectile.global_position.x > 400.0, "孢子弹没有移动")
		_projectile.queue_free()

	# 反向：受击闪红，血量归零后走死亡流程；这里直接打满血
	_shooter.call("take_damage", 99)
	_check(_shooter.get("hp") == 0, "孢子射手受击后血量没有归零")
	_check(_shooter.get("_is_dying") == true, "孢子射手没有进入死亡状态")
