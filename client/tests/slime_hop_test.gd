## 史莱姆跳跃移动（M4-15）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/slime_hop_test.gd
##
## 组长反馈：“一直锁定玩家走，然后平移太僵硬”。改成一段一段地蹦：
## 地上停 → 下蹲蓄力 → 腾空（不转向）→ 落地压扁。
## 验四件事：地面上不再平移；巡逻确实靠跳；玩家进圈会追、且腾空方向朝玩家；玩家跑远会退出。

extends SceneTree

const LEVEL := "res://scenes/world/floor1.tscn"
const SLIME := "res://scenes/entities/slime.tscn"

const REST_PHASE := 0

var _level: Node
var _slime: CharacterBody2D
var _player: CharacterBody2D
var _frame := 0
var _fail := 0

var _slide_frames := 0
var _air_frames := 0
var _toward := 0
var _away := 0
var _chased := false

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok  ", msg)
	else:
		_fail += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	print("[slime_hop] 开始")

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_level = (load(LEVEL) as PackedScene).instantiate()
		root.add_child(_level)
		var dbox := _level.get_node_or_null("Dialogue")
		if dbox != null:
			_level.remove_child(dbox)
			dbox.free()
		_player = _level.get_node("Player") as CharacterBody2D
		_slime = (load(SLIME) as PackedScene).instantiate() as CharacterBody2D
		_level.add_child(_slime)
		_player.global_position = Vector2(120, 646)
		_slime.global_position = Vector2(480, 646)
		return false
	if _slime == null:
		return false

	# 1) 巡逻 4 秒：地面上出现持续平移就是回归失败
	if _frame < 250:
		if _slime.is_on_floor() and int(_slime.get("_hop_phase")) == REST_PHASE:
			if absf(_slime.velocity.x) > 25.0:
				_slide_frames += 1
		if not _slime.is_on_floor():
			_air_frames += 1
		return false

	if _frame == 250:
		_check(_slide_frames == 0, "地面上没有持续平移（异常采样 %d 帧）" % _slide_frames)
		_check(_air_frames > 20, "巡逻是跳着走的（腾空采样 %d 帧）" % _air_frames)

	# 2) 追击 5 秒：玩家保持在史莱姆左侧 150px，逐帧同步高度
	if _frame < 550:
		_player.global_position = Vector2(_slime.global_position.x - 150.0, _slime.global_position.y)
		if bool(_slime.get("_is_chasing")):
			_chased = true
		if not _slime.is_on_floor() and absf(_slime.velocity.x) > 1.0:
			var toward_player := float(_player.global_position.x - _slime.global_position.x)
			if signf(_slime.velocity.x) == signf(toward_player):
				_toward += 1
			else:
				_away += 1
		return false

	if _frame == 550:
		_check(_chased, "玩家进圈后进入追击")
		_check(_toward > _away, "腾空方向整体朝着玩家（向 %d / 背 %d）" % [_toward, _away])

	# 3) 撤退：玩家跑到 600px 外，必须退出追击
	if _frame < 760:
		_player.global_position = Vector2(_slime.global_position.x - 600.0, _slime.global_position.y)
		return false

	if _frame == 760:
		_check(not bool(_slime.get("_is_chasing")), "玩家跑远后退出追击")
		_level.queue_free()
		if _fail == 0:
			print("[slime_hop] PASS")
			quit(0)
		else:
			printerr("[slime_hop] FAIL %d 项" % _fail)
			quit(1)
		return true
	return false
