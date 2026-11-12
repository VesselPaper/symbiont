extends Camera2D
## 2D 摄像机跟随（M1-09 / 本轮按试玩反馈再调）——水平前瞻 + 落地回正
##
## 试玩反馈：跳上高台后镜头停在上面，角色跑到屏幕中线偏上；前方下面出现平台时，
## 平台已经掉到画面底边外。要求角色大多数时间待在屏幕中间偏下（默认位置）。
##
## 现在的规则：
##   - 水平：向"角色 x + 速度前瞻"平滑跟随，跑动时多看一截前方
##   - 着地：镜头总是缓动回 角色 y - player_screen_offset，角色回到中线下方。
##     跳上高台落地后镜头会跟上来，不会把角色永久留在画面上半屏。
##   - 空中：镜头 y 基本不动（普通跳跃高度约 104px < vertical_deadzone，不抽镜头）；
##     只有角色快冲出画面顶部才上跟；下落超过 air_down_deadzone 就立刻下跟，
##     这样低处平台在坠落时能尽快进入画面。
##   - 瞬移/复活：水平差 > snap_x，或复活起身时垂直差 > snap_y，直接吸附
##
## 数值都是可调参数（场景节点上改，或改这里默认值）。

@export var target_path: NodePath          # 玩家节点
@export var follow_speed := 10.0           # 水平跟随速度（越大越跟手）
## 角色在屏幕中的基准位置（世界 px，正值=中线下方）：越大角色越靠下。
## 56 时角色屏幕 y≈456（720 高的 63%），是试玩要求的“中间偏下”。
@export var player_screen_offset := 56.0
@export var look_ahead := 60.0             # 水平前瞻最大距离（按速度比例取）
@export var vertical_speed := 9.0          # 着地回正 / 空中下跟速度
## 空中向上安全带：必须大于一次正常跳跃（≈104px），否则平地跳仍会推镜头。
@export var vertical_deadzone := 128.0
## 空中向下安全带：下落超过这个距离镜头就跟着下去，别让低处平台卡在画面外。
@export var air_down_deadzone := 28.0
@export var snap_x := 480.0                # 水平差超过该值直接吸附（复活/传送）
@export var snap_y := 120.0                # 复活起身时垂直差超过该值直接吸附

var _target: Node2D
var _shake_time := 0.0
var _shake_duration := 0.0
var _shake_strength := 0.0

func _ready() -> void:
	add_to_group("camera")
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node2D
	# 相机初始对准：把角色放在屏幕中线下方 player_screen_offset 处（下半屏，地面可见）
	if _target != null:
		_snap_to_target()
	make_current()

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# 瞬移/复活：水平差距太大就不平滑，直接吸附到角色，避免镜头从旧位置慢慢飘。
	# 垂直只在复活起身期间吸附；普通下落不吸附，否则高速坠落时镜头会突然跳一下。
	var dx := absf(_target.global_position.x - global_position.x)
	var dy := absf(_target.global_position.y - global_position.y)
	var revive_left = _target.get("_revive_timer")
	var reviving := revive_left != null and float(revive_left) > 0.0
	if dx > snap_x or (reviving and dy > snap_y):
		_snap_to_target()
		return
	var vx := 0.0
	var grounded := false
	if _target is CharacterBody2D:
		vx = (_target as CharacterBody2D).velocity.x
		grounded = (_target as CharacterBody2D).is_on_floor()
	# 水平：按速度给一点前瞻，跑动时能看到前方落点/障碍。
	# 0.20 让满速 300px/s 正好吃满 60px 前瞻；0.14 时实际只有 42px。
	var lead_x := clampf(vx * 0.20, -look_ahead, look_ahead)
	var target_x := _target.global_position.x + lead_x
	global_position.x = lerpf(global_position.x, target_x, 1.0 - exp(-follow_speed * delta))
	# 垂直：着地时无条件缓动回“角色中线偏下”的默认构图；空中才用安全带，
	# 普通跳跃镜头完全不动，落差大的下落则立刻下跟。
	var target_y := _target.global_position.y - player_screen_offset
	var goal_y := global_position.y
	if grounded:
		goal_y = target_y
	else:
		if target_y < global_position.y - vertical_deadzone:
			goal_y = target_y + vertical_deadzone
		elif target_y > global_position.y + air_down_deadzone:
			goal_y = target_y - air_down_deadzone
	# 下行比上行稍快，落地/掉坑时不会让角色贴到屏幕底边
	var rate := vertical_speed * (1.35 if goal_y > global_position.y else 1.0)
	global_position.y = lerpf(global_position.y, goal_y, 1.0 - exp(-rate * delta))
	_clamp_to_limits()
	_update_shake(delta)

## 命中震屏：只在 offset 上抖，不改跟随目标 / 不暂停场景；
## 调用方传强度和时长，默认给普通横砍一个短促的 3.6px / 0.12s。
func shake(strength: float = 3.6, duration: float = 0.12) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time = maxf(_shake_time, duration)

func _update_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		offset = Vector2.ZERO
		return
	_shake_time = maxf(_shake_time - delta, 0.0)
	var fade := _shake_time / maxf(_shake_duration, 0.001)
	offset = Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-0.7, 0.7)
	) * _shake_strength * fade
	if _shake_time <= 0.0:
		offset = Vector2.ZERO

func _snap_to_target() -> void:
	global_position = _target.global_position + Vector2(0, -player_screen_offset)
	_clamp_to_limits()

## 限制相机中心不超出 limit（考虑 zoom：half = 视口/2 ÷ zoom）
func _clamp_to_limits() -> void:
	var half_w := (get_viewport_rect().size.x / 2.0) / zoom.x
	var half_h := (get_viewport_rect().size.y / 2.0) / zoom.y
	var l := limit_left + half_w
	var r := limit_right - half_w
	var t := limit_top + half_h
	var b := limit_bottom - half_h
	global_position.x = clampf(global_position.x, minf(l, r), maxf(l, r))
	global_position.y = clampf(global_position.y, minf(t, b), maxf(t, b))
