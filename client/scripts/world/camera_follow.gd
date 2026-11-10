extends Camera2D
## 2D 摄像机跟随（M1-09 / 本轮按试玩反馈重调）——水平前瞻 + 垂直平滑跟随
##
## 目标：地面探索时始终能看到角色前方和脚下的一段路；跳跃上升时镜头提前上移，
## 下落时镜头略微下压；复活/瞬移后镜头直接跟到新位置，不再从旧尸体处慢慢飘。
##
## 旧版用固定垂直死区（top 120 / bottom 140）：角色跳起来要上升 120px 镜头才动，
## 从高台往下走时又要等 140px 才下移，结果上方平台挡住去路、下方道路看不到。
## 现改为：
##   - 水平：向"角色 x + 速度前瞻"平滑跟随，跑动时多看一截前方
##   - 垂直：目标 = 角色 y - player_screen_offset（角色在屏幕偏下），
##     上升再抬高 look_up、下落再压低 look_down，用指数平滑跟过去
##   - 瞬移/复活：水平差 > snap_x，或复活起身时垂直差 > snap_y，直接吸附
##
## 数值都是可调参数（场景节点上改，或改这里默认值）。

@export var target_path: NodePath          # 玩家节点
@export var follow_speed := 10.0           # 水平跟随速度（越大越跟手）
## 角色在屏幕中的基准位置（世界 px，正值=中线下方）：越大，脚下路看得越多
@export var player_screen_offset := 56.0
@export var look_ahead := 26.0             # 水平前瞻最大距离（按速度比例取）
@export var look_up := 26.0                # 上升时镜头额外抬高，提前看到落点
@export var look_down := 12.0              # 下落时镜头额外下压，看到下方道路
@export var vertical_speed := 9.0          # 垂直跟随速度
@export var snap_x := 480.0                # 水平差超过该值直接吸附（复活/传送）
@export var snap_y := 120.0                # 复活起身时垂直差超过该值直接吸附

var _target: Node2D

func _ready() -> void:
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
	var vy := 0.0
	var grounded := false
	if _target is CharacterBody2D:
		vx = (_target as CharacterBody2D).velocity.x
		vy = (_target as CharacterBody2D).velocity.y
		grounded = (_target as CharacterBody2D).is_on_floor()
	# 水平：按速度给一点前瞻，跑动时能看到前方落点/障碍
	var lead_x := clampf(vx * 0.14, -look_ahead, look_ahead)
	var target_x := _target.global_position.x + lead_x
	global_position.x = lerpf(global_position.x, target_x, 1.0 - exp(-follow_speed * delta))
	# 垂直：基准是"角色偏下"，上升时镜头再抬高，下落时略下压
	var target_y := _target.global_position.y - player_screen_offset
	if not grounded:
		if vy < -40.0:
			target_y -= look_up
		elif vy > 60.0:
			target_y += look_down
	# 下行比上行稍快，落地/掉坑时不会让角色贴到屏幕底边
	var rate := vertical_speed * (1.35 if target_y > global_position.y else 1.0)
	global_position.y = lerpf(global_position.y, target_y, 1.0 - exp(-rate * delta))
	_clamp_to_limits()

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
