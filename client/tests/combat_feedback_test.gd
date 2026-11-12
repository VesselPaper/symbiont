extends SceneTree
## 命中反馈 / 互相击退 / 武器跨实例保留回归（M4-02）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/combat_feedback_test.gd

const ARENA := "res://scenes/world/test_arena.tscn"
const SLIME := "res://scenes/entities/slime.tscn"
const BOSS := "res://scenes/entities/gatekeeper_boss.tscn"
const PLAYER := "res://scenes/player/player.tscn"

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var gm := root.get_node("/root/GameManager")
	# 1) 武器跨实例/复活保留：只把状态放 Player 里会丢
	gm.set("has_weapon", true)
	var lone: Node2D = load(PLAYER).instantiate()
	root.add_child(lone)
	await process_frame
	_check(bool(lone.get("has_weapon")), "GameManager 带剑时新玩家没继承铁剑")
	lone.call("_respawn")
	await process_frame
	_check(bool(lone.get("has_weapon")), "复活后玩家丢了铁剑")
	_check(lone.get_node("Body").get_node("ArmPivot/SwordPivot").visible, "复活后剑的视觉没恢复")
	lone.queue_free()

	# 2) 横砍：怪被推开、玩家被反推、双方都有硬直
	var level: Node = load(ARENA).instantiate()
	root.add_child(level)
	await process_frame
	var tutorial := level.get_node("Tutorial")
	tutorial.process_mode = Node.PROCESS_MODE_DISABLED
	var dbox := level.get_node_or_null("DialogueBox")
	if dbox != null:
		dbox.visible = false
	var player := level.get_node("Player") as CharacterBody2D
	var slime := load(SLIME).instantiate() as CharacterBody2D
	level.add_child(slime)
	player.global_position = Vector2(420, 646)
	slime.global_position = Vector2(480, 646)
	player.set("_facing", 1)
	player.set("has_weapon", true)
	await process_frame
	var slime_hp := int(slime.get("hp"))
	player.call("_apply_hit", slime)
	var slime_vx := slime.velocity.x
	var player_vx := player.velocity.x
	_check(int(slime.get("hp")) == slime_hp - 1, "横砍没扣血")
	_check(slime_vx > 0.0, "史莱姆没被向右击退: %.1f" % slime_vx)
	_check(player_vx < 0.0, "玩家没被反推向左: %.1f" % player_vx)
	_check(float(slime.get("_stun_timer")) > 0.0, "史莱姆没有受击硬直")
	_check(float(player.get("_hitstop_timer")) > 0.0, "横砍没有顿帧")
	# 同一次挥砍重复命中不能二次扣血（防止判定框每帧重复调用）
	player.call("_apply_hit", slime)
	_check(int(slime.get("hp")) == slime_hp - 1, "同一次挥砍重复扣血")

	# 3) 下劈：向上反弹 + 强顿帧，且史莱姆被反向推开
	player.set("_hit_this_swing", [])
	player.global_position = Vector2(480, 600)
	player.velocity = Vector2(0, 120)
	player.set("_pogo_active", true)
	player.call("_start_pogo")
	player.call("_pogo_bounce_on", slime)
	_check(player.velocity.y < 0.0, "下劈命中后没有向上反弹")
	_check(float(player.get("_hitstop_timer")) >= 0.05, "下劈顿帧过短")
	_check(slime.velocity.x < 0.0, "下劈没把史莱姆反向推开")

	# 4) 重量差：Boss 被推得少，玩家被反推得多
	var boss := load(BOSS).instantiate() as CharacterBody2D
	level.add_child(boss)
	boss.global_position = Vector2(560, 620)
	boss.call("activate")
	await process_frame
	player.set("_hit_this_swing", [])
	player.set("_pogo_active", false)
	var boss_vx := 0.0
	var boss_recoil := 0.0
	player.call("_apply_hit", boss)
	boss_vx = absf(boss.velocity.x)
	boss_recoil = absf(player.velocity.x)
	_check(boss_vx < absf(slime_vx), "Boss 被推得比史莱姆还远")
	_check(boss_recoil > 195.0, "打重怪时玩家反作用力没有增加")
	print("[combat_feedback] slime_vx=%.1f boss_vx=%.1f player_recoil=%.1f" % [
		slime_vx, boss_vx, boss_recoil])
	print("[combat_feedback] %s" % ("PASS" if not _failed else "FAIL"))
	gm.set("has_weapon", false)
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failed = true
		push_error("[combat_feedback] " + msg)
