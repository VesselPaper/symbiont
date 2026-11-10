extends SceneTree
## 回归：横砍动作时长、白色弧线半径和 64px 判定框要对得上，不能"看得短、打得远"。
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/slash_visual_test.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _player: CharacterBody2D
var _frames := 0
var _started := false
var _shot_checked := false
var _failed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_player = load(PLAYER_SCENE).instantiate() as CharacterBody2D
		root.add_child(_player)
		_player.set("has_weapon", true)
		return false
	if _frames < 8:
		return false
	if not _started:
		_started = true
		var slash: Line2D = _player.get_node("Body/SlashArc")
		var hitbox: Area2D = _player.get_node("HitboxSide")
		var hitbox_shape := (hitbox.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
		var consts: Dictionary = _player.get_script().get_script_constant_map()
		var anim_time := float(consts.get("ATTACK_ANIM_TIME", 0.0))
		var max_x := 0.0
		for p in slash.points:
			max_x = maxf(max_x, p.x)
		print("[slash] anim=%.2fs radius_points=%.1f hitbox_w=%.1f line_w=%.1f color=%s" % [
			anim_time, max_x, hitbox_shape.size.x,
			slash.width, str(slash.default_color)])
		if anim_time < 0.40:
			push_error("[slash] FAIL 挥砍动作仍太短")
			_failed = true
		if max_x < 40.0:
			push_error("[slash] FAIL 白色弧线没有伸到判定框边缘")
			_failed = true
		if hitbox_shape.size.x < 60.0:
			push_error("[slash] FAIL 横砍判定框被意外改小")
			_failed = true
		if slash.width < 5.0:
			push_error("[slash] FAIL 刀光太细")
			_failed = true
		# 不依赖帧数：把动作放到挥砍中段，直接刷新一次视觉，检查弧线确实亮起
		_player.set("_attack_anim_timer", 0.25)
		_player.set("_attack_anim_kind", 0)
		_player.call("_update_visual_anim", 0.0)
		_started = true
		return false
	if not _shot_checked:
		_shot_checked = true
		var slash: Line2D = _player.get_node("Body/SlashArc")
		print("[slash] 挥砍中 visible=%s alpha=%.2f pos=%s" % [
			str(slash.visible), slash.modulate.a, str(slash.position)])
		if not slash.visible or slash.modulate.a < 0.4:
			push_error("[slash] FAIL 挥砍时白色弧线没有显示")
			_failed = true
		print("[slash] %s" % ("PASS" if not _failed else "FAIL"))
		quit(0 if not _failed else 1)
		return true
	return false
