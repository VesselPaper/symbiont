extends CharacterBody2D
## 玩家控制器（M1-01）
##
## 职责：水平移动、跳跃（coyote time + jump buffer，固定跳高）、
## 横砍 / 空中下劈判定、受击无敌帧与击退、死亡重生。
## 视觉为占位方块（Polygon2D），美术资源到位后替换节点即可。
##
## 数值先用脚本顶部常量占位，M2 迁入数据文件（见 docs/02 §2.3）。

# ---- 水平移动 ----
const RUN_SPEED := 300.0        # 最大跑速 px/s
const ACCELERATION := 1800.0    # 有方向输入时的加速（地面/空中一致，手感更跟手）
const FRICTION := 1600.0        # 地面无输入时的减速
const AIR_FRICTION := 300.0     # 空中无输入时只轻微减速，保留跳跃飘动感

# ---- 垂直移动 ----
const GRAVITY := 2550
const MAX_FALL_SPEED := 900.0
const CHARACTER_HEIGHT := 28.0    # 角色视觉身高（Body Polygon2D 高 28px）
const JUMP_VELOCITY := -727.0     # 跳跃初速：√(2×2550×3.7×28)≈727 → 跳高≈3.7 倍身高（D-009）
const COYOTE_TIME := 0.1        # 离开平台边缘后仍可起跳的宽容时间
const JUMP_BUFFER_TIME := 0.15  # 落地前提前按跳的输入缓冲

# ---- 攻击 ----
const ATTACK_DAMAGE := 1
const ATTACK_COOLDOWN := 0.25
const ATTACK_ACTIVE_TIME := 0.12   # 判定框单次启用时长（一次挥砍只命中一次）
const SIDE_HITBOX_OFFSET := Vector2(16, 2)  # 横砍判定框相对玩家中心的位置（面朝右时）
const DOWN_HITBOX_OFFSET := Vector2(0, 18)  # 下劈判定框（玩家脚下方）

# ---- 生命 / 受击 ----
const MAX_HP := 5
const INVINCIBLE_TIME := 0.5    # 受击无敌时长（期间闪烁表现）
const KNOCKBACK_HORIZONTAL := 260.0
const KNOCKBACK_UPWARD := -220.0

enum AttackKind { SIDE, DOWN_STRIKE }

var hp := MAX_HP
var _facing := 1                            # 1 面朝右，-1 面朝左
var _is_dead := false
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _attack_kind := AttackKind.SIDE
var _attack_cooldown_timer := 0.0
var _attack_active_timer := 0.0
var _hit_this_swing: Array[Node2D] = []     # 本次挥砍已命中的目标，防止同一判定框重复扣血
var _invincible_timer := 0.0
var _spawn_point := Vector2.ZERO

@onready var _body: Polygon2D = $Body
@onready var _hitbox_side: Area2D = $HitboxSide
@onready var _hitbox_down: Area2D = $HitboxDown
@onready var _hitbox_side_visual: Polygon2D = $HitboxSide/Visual
@onready var _hitbox_down_visual: Polygon2D = $HitboxDown/Visual

func _ready() -> void:
	# 出生点取场景摆放位置：死亡重生回这里
	_spawn_point = global_position
	_hitbox_side.body_entered.connect(_on_hitbox_side_body_entered)
	_hitbox_down.body_entered.connect(_on_hitbox_down_body_entered)

func _physics_process(delta: float) -> void:
	_update_jump_timers(delta)
	_handle_jump()
	_try_start_attack()
	_apply_horizontal_movement(delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_facing()
	_update_attack_state(delta)
	_update_hitbox_pose()

func _process(delta: float) -> void:
	_update_invincibility(delta)

# ---- 水平移动 ----

func _apply_horizontal_movement(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * RUN_SPEED, ACCELERATION * delta)
	else:
		var friction := FRICTION if is_on_floor() else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

func _update_facing() -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		_facing = 1 if direction > 0.0 else -1

# ---- 跳跃 ----

func _update_jump_timers(delta: float) -> void:
	# 着地时持续刷新 coyote 窗口；离开平台后开始倒计时
	_coyote_timer = COYOTE_TIME if is_on_floor() else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	# coyote 与 buffer 同时满足才起跳，两者都是给操作留的宽容窗口
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
	# 固定跳高：起跳速度与重力恒定，无论按多久，跳跃高度一致（见决策日志 D-008）

# ---- 攻击 ----

func _try_start_attack() -> void:
	if _attack_cooldown_timer > 0.0:
		return
	# 必须按下攻击键(J)才挥砍，否则冷却一结束就会无限自动攻击
	if not Input.is_action_just_pressed("attack"):
		return
	# 空中按住下 + J → 下劈；其余情况横砍
	var is_down_strike := not is_on_floor() and Input.is_action_pressed("move_down")
	_attack_kind = AttackKind.DOWN_STRIKE if is_down_strike else AttackKind.SIDE
	_attack_cooldown_timer = ATTACK_COOLDOWN
	_attack_active_timer = ATTACK_ACTIVE_TIME
	_hit_this_swing.clear()
	_hitbox_side.monitoring = _attack_kind == AttackKind.SIDE
	_hitbox_down.monitoring = _attack_kind == AttackKind.DOWN_STRIKE

func _update_attack_state(delta: float) -> void:
	_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)
	if _attack_active_timer <= 0.0:
		return
	_attack_active_timer -= delta
	if _attack_active_timer <= 0.0:
		_end_attack()

func _end_attack() -> void:
	_attack_active_timer = 0.0
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = false
	_hit_this_swing.clear()

func _update_hitbox_pose() -> void:
	# 横砍判定框随面朝方向左右翻转；下劈固定朝下
	_hitbox_side.position = Vector2(SIDE_HITBOX_OFFSET.x * _facing, SIDE_HITBOX_OFFSET.y)
	_hitbox_down.position = DOWN_HITBOX_OFFSET
	# 占位阶段把判定框可视层与开关绑定，便于在编辑器中观察攻击范围
	_hitbox_side_visual.visible = _hitbox_side.monitoring
	_hitbox_down_visual.visible = _hitbox_down.monitoring

func _on_hitbox_side_body_entered(body: Node2D) -> void:
	_apply_hit(body)

func _on_hitbox_down_body_entered(body: Node2D) -> void:
	_apply_hit(body)

func _apply_hit(body: Node2D) -> void:
	if not body.is_in_group("damageable"):
		return
	if _hit_this_swing.has(body):
		return
	_hit_this_swing.append(body)
	if body.has_method("take_damage"):
		body.take_damage(ATTACK_DAMAGE)

# ---- 受击 / 死亡 ----

func take_damage(amount: int, source: Node = null) -> void:
	if _invincible_timer > 0.0 or _is_dead:
		return
	hp = maxi(hp - amount, 0)
	EventBus.player_hurt.emit(amount, source)
	_invincible_timer = INVINCIBLE_TIME
	# 击退方向：远离攻击来源；来源未知则朝面朝的反方向
	var knock_dir := -float(_facing)
	if source is Node2D:
		var source_dir := signf(position.x - (source as Node2D).global_position.x)
		if source_dir != 0.0:
			knock_dir = source_dir
	velocity.x = knock_dir * KNOCKBACK_HORIZONTAL
	velocity.y = KNOCKBACK_UPWARD
	if hp <= 0:
		_die()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	EventBus.player_died.emit()
	# 测试切片：死亡立即回出生点满血复活（正式死亡/游戏结束流程在 M2 定稿）
	_respawn()

func _respawn() -> void:
	global_position = _spawn_point
	velocity = Vector2.ZERO
	hp = MAX_HP
	_is_dead = false
	_attack_cooldown_timer = 0.0
	_attack_active_timer = 0.0
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = false
	_hit_this_swing.clear()
	# 复活给满无敌时长，避免卡在受击点原地连续掉血
	_invincible_timer = INVINCIBLE_TIME
	_body.visible = true

func _update_invincibility(delta: float) -> void:
	if _invincible_timer <= 0.0:
		return
	_invincible_timer -= delta
	if _invincible_timer <= 0.0:
		_invincible_timer = 0.0
		_body.visible = true
		return
	# 无敌期间每 0.08s 切换一次可见性形成闪烁
	_body.visible = int(_invincible_timer / 0.08) % 2 == 0
