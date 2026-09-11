extends Camera2D
## 2D 摄像机跟随（M1-09）——水平平滑跟随 + 垂直死区
##
## 目标：地面探索时相机垂直稳定（下方地面始终可见），只有角色跳得足够高
## （超过死区上沿）相机才上移；落回低位不会立刻下移（保留上方视野）。
##
## 垂直规则（以"角色相对相机中心"的偏移判断）：
##   dy = 玩家y - 相机中心y（负 = 角色在屏幕上方）
##   相机初始把角色放在屏幕偏下位置（见 DEADZONE_TOP 对齐逻辑）；
##   当角色升到相机中心上方超过 deadzone_top  → 相机上移（把角色拉回上沿）
##   当角色落到相机中心下方超过 deadzone_bottom → 相机下移（拉回下沿）
##   死区内：相机 y 不动，只有水平跟随。
## 数值都是可调参数（场景节点上改，或改这里默认值）。

@export var target_path: NodePath          # 玩家节点
@export var follow_speed := 10.0           # 水平跟随速度（越大越跟手）
## 垂直死区（世界 px，与 zoom 相关：当前视野高约 420px）：
@export var deadzone_top := 120.0          # 角色升到相机中心上方超过此值，相机才上移
@export var deadzone_bottom := 140.0       # 角色落到相机中心下方超过此值，相机才下移
## 角色在屏幕中的默认位置（世界 px，正值=中线下方）：初始对准用，让角色待在下半屏
@export var player_screen_offset := 84.0

var _target: Node2D

func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node2D
	# 相机初始对准：把角色放在屏幕中线下方 player_screen_offset 处（下半屏，地面可见）
	if _target != null:
		global_position = _target.global_position + Vector2(0, -player_screen_offset)
	make_current()

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# 水平：平滑跟随
	var tx := _target.global_position.x
	global_position.x = lerpf(global_position.x, tx, 1.0 - exp(-follow_speed * delta))
	# 垂直：死区判定（角色相对相机中心的垂直偏移）
	var dy := _target.global_position.y - global_position.y
	if dy > deadzone_bottom:
		global_position.y += dy - deadzone_bottom   # 角色太低 → 相机下移
	elif dy < -deadzone_top:
		global_position.y += dy + deadzone_top      # 角色太高 → 相机上移
	# 死区内：相机 y 不动（地面探索时镜头稳定，跳上矮平台也不动）
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
