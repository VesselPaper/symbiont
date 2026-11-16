extends SceneTree
## 教学提示锚点净空 + 位置判定回归（M4-21 改写，原来的“指引光停点净空”）。
##
## 组长定稿删掉了引导光点，气泡文字还在，所以这一张现在管两件事：
##   1) 气泡锚点不能埋在墙体里，且下方 90px 内能踩到地面（文字压在地形上就读不清）；
##      锚点还要离地/台面 60px 以上 —— 组长反馈“A/D 那句和石墙重合了”就是这条。
##   2) 位置判定要真能用：`player_on_platform` 站在台上算通过、站在台边/空中不算；
##      `player_reached` 走过线算通过、没到不算（反向断言，防止判定退化成“永远为真”）。
## 坐标一律从场景的 STAGE 表经 Tutorial 生效锚点读，不在这儿抄数字。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/marker_clearance_test.gd

const SCENE := "res://scenes/world/test_arena.tscn"
const NAMES := ["MOVE", "JUMP", "WEAPON", "ATTACK", "POGO", "COMBAT", "PICKUP", "SACRIFICE"]
## 气泡底边离地形顶面的最小距离（世界像素）
const MIN_TEXT_LIFT := 60.0
## 组长 M5-25 定的规则：文字中心 = 落脚面往上 3 个角色身高（角色 28px）
const TEXT_HEIGHT := 84.0

var _level: Node2D
var _tutorial: Node
var _player: CharacterBody2D
var _stage: Dictionary
var _failed := false
var _frame := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	_level = load(SCENE).instantiate() as Node2D
	root.add_child(_level)
	_tutorial = _level.get_node("Tutorial")
	_player = _level.get_node("Player") as CharacterBody2D
	_stage = _level.get_script().get_script_constant_map()["STAGE"]
	await create_timer(0.6).timeout
	_check_anchors()
	await _check_position_checks()
	print("[marker] %s" % ("FAIL" if _failed else "PASS 提示锚点净空、位置判定正反向都对"))
	quit(1 if _failed else 0)

## 一、8 个气泡锚点：不在墙里、下方有地、且离地 60px 以上
func _check_anchors() -> void:
	var anchors: Array = _tutorial.get("_anchors")
	if anchors.size() != NAMES.size():
		_fail("锚点应为 %d 个，实际 %d 个" % [NAMES.size(), anchors.size()])
		return
	var space := _level.get_world_2d().direct_space_state
	for i in range(anchors.size()):
		var pos: Vector2 = anchors[i]
		var point := PhysicsPointQueryParameters2D.new()
		point.position = pos
		point.collision_mask = 1   # 地形静态体
		point.collide_with_bodies = true
		point.collide_with_areas = false
		var hits := space.intersect_point(point, 8)
		var ray := PhysicsRayQueryParameters2D.create(pos, pos + Vector2(0, 120), 1)
		var floor_hit := space.intersect_ray(ray)
		var clear := hits.is_empty()
		var has_floor := not floor_hit.is_empty()
		var lift := 0.0
		if has_floor:
			# M5-25：组长定的新规则是"文字中心 = 落脚面往上 3 个角色身高（28×3=84）"，
			# 所以这里量"锚点离它脚下那层地面多远"，正例要正好 84；
			# POGO 那一环故意写在方台**下方**（人还在地上就要能看见），不按这条算。
			var ray_up := PhysicsRayQueryParameters2D.create(pos, pos + Vector2(0, -260), 1)
			var above := space.intersect_ray(ray_up)
			var surface: float = float(floor_hit["position"].y)
			var ceiling: float = float(above["position"].y) if not above.is_empty() else pos.y - 260.0
			lift = surface - pos.y
			# 文字上沿别顶到台底/墙：留 12px 就够（字高 10）
			if ceiling > pos.y - 12.0:
				_fail("%s 锚点上方空间不够，文字会顶到墙/台子" % NAMES[i])
		print("[marker] %-9s pos=%s clear=%s floor=%s lift=%.0fpx" % [
			NAMES[i], str(pos), str(clear), str(floor_hit.get("position", "none")), lift])
		if not clear:
			_fail("%s 锚点埋在墙体里" % NAMES[i])
		if not has_floor:
			_fail("%s 锚点下方 120px 内没有地面" % NAMES[i])
		elif lift < MIN_TEXT_LIFT:
			_fail("%s 锚点离地只有 %.0fpx（要 ≥%.0f，不然文字贴着石墙）" % [NAMES[i], lift, MIN_TEXT_LIFT])
		elif absf(lift - TEXT_HEIGHT) > 2.0:
			# 八环都一样：文字中心离落脚面正好 3 个角色身高（POGO 也一样，只是挪到方块左边）
			_fail("%s 文字离地 %.0fpx，应正好 %.0fpx（3 个角色身高）" % [NAMES[i], lift, TEXT_HEIGHT])

## 二、位置判定：站在台上通过、站在台边/空中不通过；走过线通过、没到不通过
func _check_position_checks() -> void:
	var ledge: Rect2 = _stage["ledge"]
	var pogo: Rect2 = _stage["pogo"]
	var move_mark: Vector2 = _stage["move_mark"]

	# 站上跳台：正
	await _teleport(Vector2(ledge.position.x + 200.0, ledge.position.y - 13.0))
	_assert(_level.call("player_on_platform", "ledge", _player), "站在跳台上应判定通过")
	# 空中同高度：反（还没落地）
	_player.global_position = Vector2(ledge.position.x + 200.0, ledge.position.y - 200.0)
	await process_frame
	_assert(not bool(_level.call("player_on_platform", "ledge", _player)), "空中不该判定站上平台")
	# 台上但探出左边缘：反（横向在矩形外）
	await _teleport(Vector2(ledge.position.x - 20.0, 646.0))
	_assert(not bool(_level.call("player_on_platform", "ledge", _player)), "站在台子左边的地面上不该算站上平台")

	# 站上下劈方台：正（组长要的“下劈成功=站上平台”）
	await _teleport(Vector2(pogo.position.x + pogo.size.x * 0.5, pogo.position.y - 13.0))
	_assert(_level.call("player_on_platform", "pogo", _player), "站在下劈方台上应判定通过")
	# 站在方台旁边的跳台上：反
	await _teleport(Vector2(pogo.position.x - 60.0, ledge.position.y - 13.0))
	_assert(not bool(_level.call("player_on_platform", "pogo", _player)), "站在跳台（不在方台上）不该算下劈成功")

	# 走过移动点：正
	await _teleport(Vector2(move_mark.x + 20.0, 646.0))
	_assert(_level.call("player_reached", "move_mark", _player), "走过移动点应判定通过")
	# 没走到：反
	await _teleport(Vector2(move_mark.x - 60.0, 646.0))
	_assert(not bool(_level.call("player_reached", "move_mark", _player)), "还没走到移动点不该算学会走路")

## 把玩家放到某处并等它落地
func _teleport(target: Vector2) -> void:
	_player.global_position = target
	for _i in range(90):
		await process_frame
		if _player.is_on_floor():
			break
	await create_timer(0.05).timeout

func _assert(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _fail(msg: String) -> void:
	push_error("[marker] " + msg)
	_failed = true
