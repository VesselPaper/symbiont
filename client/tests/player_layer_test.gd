## 肢体图层与跑砍动作（M4-16）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/player_layer_test.gd
##
## 两件事：
## 1) 组长说“角色上面的肢体和角色不在一个图层，背景会挡肢体但不挡角色”。
##    原来的实现把寄生体/阵营外观/蒸汽靴都设成 z_index = -1（挂在 Body 下），
##    有效层级就成了 −1，背景（0 层）自然把它们盖住。这里断言它们和身体同一层。
## 2) 走路时点攻击要能区分“跑砍 / 站砍”：跑砍保留冲量，站砍把脚钉住。

extends SceneTree

const PLAYER := "res://scenes/player/player.tscn"

var _player: CharacterBody2D
var _frame := 0
var _fail := 0

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok  ", msg)
	else:
		_fail += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	print("[player_layer] 开始")

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		# 先铺一层地板：跑砍/站砍是靠 is_on_floor 判断的
		var floor_body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(600, 40)
		shape.shape = rect
		floor_body.add_child(shape)
		floor_body.position = Vector2(0, 0)
		root.add_child(floor_body)
		_player = (load(PLAYER) as PackedScene).instantiate() as CharacterBody2D
		root.add_child(_player)
		_player.global_position = Vector2(0, -70)
		_player.set("has_weapon", true)
		_player.call("apply_faction", "heretic")
		_player.call("_build_corruption")
		return false
	if _frame == 40:
		var body := _player.get_node("Body") as Node2D
		var limbs := {
			"Corruption": _player.get("_corruption"),
			"FactionVisual": _player.get("_faction_visual"),
		}
		for key: String in ["Corruption", "FactionVisual"]:
			var node: Node = limbs[key]
			if node == null:
				_check(false, "%s 没生成" % key)
				continue
			_check(int(node.get("z_index")) == 0, "%s 的 z_index 是 0（不再是 -1）" % key)
			_check(bool(node.get("show_behind_parent")), "%s 仍然画在身体后面" % key)
			_check(int(_effective_z(node)) == int(_effective_z(body)),
				"%s 与身体同一有效层级（%d vs %d）" % [key, _effective_z(node), _effective_z(body)])
		# 刀光柔光层是故意压在身体下面的，别被顺手改掉
		var glow := _player.get("_slash_glow") as Line2D
		_check(int(glow.get("z_index")) == -1, "刀光柔光仍然是 −1（没被误改）")

	# 3) 跑砍：给一个超过阈值速度再出手，应该保留冲量并进入跑砍动作
	if _frame == 46:
		_player.set("_attack_cooldown_timer", 0.0)
		_player.velocity.x = 150.0
		_player.set("_facing", 1)
		_player.call("_start_side_slash")
		_check(bool(_player.get("_attack_running")), "高速出手判定为跑砍")
		_check(_player.velocity.x > 150.0, "跑砍保留并补了一口前冲（vx=%.1f）" % _player.velocity.x)
		_check(float(_player.get("_attack_root_timer")) <= 0.0, "跑砍不钉脚")
		var slash := _player.get_node("Body/SlashArc") as Line2D
		_check(absf(slash.rotation) > 0.2, "跑砍的刀弧压低（rot=%.2f）" % slash.rotation)
		return false
	if _frame < 52:
		return false

	# 4) 站砍：速度为 0 时出手，应该钉住脚、刀弧不歪
	_player.set("_attack_cooldown_timer", 0.0)
	_player.velocity.x = 0.0
	_player.call("_start_side_slash")
	_check(not bool(_player.get("_attack_running")), "静止出手判定为站砍")
	_check(float(_player.get("_attack_root_timer")) > 0.0, "站砍把脚钉住")
	var slash2 := _player.get_node("Body/SlashArc") as Line2D
	_check(absf(slash2.rotation) < 0.01, "站砍刀弧回正（rot=%.2f）" % slash2.rotation)

	_player.queue_free()
	if _fail == 0:
		print("[player_layer] PASS")
		quit(0)
	else:
		printerr("[player_layer] FAIL %d 项" % _fail)
		quit(1)
	return true

## 有效层级：沿父链把 z_index 累加（Godot 默认 z_as_relative = true）
func _effective_z(node: Node) -> int:
	var total := 0
	var cur: Node = node
	while cur != null and cur is CanvasItem:
		if bool(cur.get("z_as_relative")) or cur == node:
			total += int(cur.get("z_index"))
		cur = cur.get_parent()
	return total
