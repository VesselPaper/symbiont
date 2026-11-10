extends CharacterBody2D
## 玩家控制器（M1-01）
##
## 职责：水平移动、跳跃（coyote time + jump buffer，固定跳高）、
## 地面横砍 / 空中下砍（pogo：加速下落+踩敌反弹）、受击无敌帧与击退、死亡重生。
## 视觉是代码拼的兜帽剪影（Polygon2D 分件 + 一点眼光），不依赖贴图；
## 待机时轻微上下起伏、移动时颤步，朝向靠 Body.scale.x 翻转。
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
const SIDE_HITBOX_OFFSET := Vector2(32, -14)  # 横砍判定框：64宽×56高（4×角色宽16 × 2×角色高28），从头顶上方到身前（面朝右时 x:0→64, y:-42→+14）
const POGO_HITBOX_OFFSET := Vector2(32, 14)   # 下砍判定框：64宽×28高（前方4×宽16 × 下方1×高28），面朝右时 x:0→64, y:0→28
const POGO_FALL_SPEED := 700.0       # 下砍时强制下落速度（加速下落）
const POGO_BOUNCE_VELOCITY := -650.0 # 命中实体后的向上反弹初速（≈83px 高，可调）
const POGO_RETRIGGER_COOLDOWN := 0.1 # 反弹后可再次下砍的最小间隔（支持多段踩跳）
const POGO_END_LAG := 0.2        # 下砍结束后的后摇：期间按 J 不触发攻击（防落地瞬间秒横砍）
const POGO_MIN_FALL_DISTANCE := 20.0  # 下砍需已下落的距离阈值（刚起跳/刚出边缘/贴地时不触发）

# ---- 生命 / 受击 ----
const MAX_HP := 5
const INVINCIBLE_TIME := 0.5    # 受击无敌时长（期间闪烁表现）
const KNOCKBACK_HORIZONTAL := 260.0
const KNOCKBACK_UPWARD := -220.0

# ---- 动画时长（表现层，不影响手感数值）----
const ATTACK_ANIM_TIME := 0.28  # 一次挥砍的完整动作时长（判定仍只有 0.12s）
const HURT_ANIM_TIME := 0.25    # 受击缩身时长
const DEATH_ANIM_TIME := 0.85  # 倒地到复活的总时长
const REVIVE_ANIM_TIME := 0.4   # 复活起身时长
const WEAPON_FLASH_TIME := 0.35 # 刚捡到剑时的亮一下

var hp := MAX_HP
var has_weapon := false                    # M1-10：是否已拾取铁剑；没武器时按 J 静默无效
var _facing := 1                            # 1 面朝右，-1 面朝左
var _attack_dir := 1                        # 攻击锁定朝向：出手那一刻固定，攻击中按反方向键不改判定方向
var _is_dead := false
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _pogo_active := false
var _pogo_end_lag_timer := 0.0  # 下砍后摇计时
var _pogo_requested := false    # 下砍请求：按下 J 后从按下点下落超过阈值才真正触发（防贴地触发）
var _pogo_request_y := 0.0      # 按下 J 时的位置 y
var _attack_cooldown_timer := 0.0
var _attack_active_timer := 0.0
var _hit_this_swing: Array[Node2D] = []     # 本次挥砍已命中的目标，防止同一判定框重复扣血
var _invincible_timer := 0.0
var _input_locked := false      # 对话期间锁输入：不能移动/跳跃/攻击/下砍（见 _on_dialogue_*）
var _spawn_point := Vector2.ZERO
var _anim_time := 0.0           # 视觉动画时钟（待机起伏 / 走步颤步），与物理无关
var _attack_anim_timer := 0.0   # 挥砍动作剩余时间（表现，不影响 0.12s 判定）
var _attack_anim_kind := 0      # 0 = 横砍，1 = 下劈
var _hurt_timer := 0.0          # 受击缩身剩余时间
var _death_timer := 0.0         # 倒地剩余时间，走完才复活
var _revive_timer := 0.0        # 复活起身剩余时间
var _weapon_flash_timer := 0.0  # 捡剑亮光

@onready var _body: Node2D = $Body
@onready var _cloak: Polygon2D = $Body/Cloak
@onready var _cape: Polygon2D = $Body/Cape
@onready var _arm: Node2D = $Body/ArmPivot
@onready var _sword: Node2D = $Body/ArmPivot/SwordPivot
@onready var _slash: Line2D = $Body/SlashArc
@onready var _slash_down: Line2D = $Body/SlashDown
@onready var _hitbox_side: Area2D = $HitboxSide
@onready var _hitbox_down: Area2D = $HitboxDown
@onready var _hitbox_side_visual: Polygon2D = $HitboxSide/Visual
@onready var _hitbox_down_visual: Polygon2D = $HitboxDown/Visual
var _hitbox_down_shape: RectangleShape2D  # 下劈命中查询用（M1-13，见 _query_pogo_target）

func _ready() -> void:
	# 出生点取场景摆放位置：死亡重生回这里
	_spawn_point = global_position
	_hitbox_side.body_entered.connect(_on_hitbox_side_body_entered)
	_hitbox_down.body_entered.connect(_on_hitbox_down_body_entered)
	# M1-13：下劈命中查询用的 shape 引用（HitboxDown 的 CollisionShape2D）
	var hb_shape_node := $HitboxDown/CollisionShape2D as CollisionShape2D
	if hb_shape_node != null:
		_hitbox_down_shape = hb_shape_node.shape as RectangleShape2D
	# 挥砍残影的弧线点一次算好，后面只改透明度和显隐（每帧重算没必要）
	_slash.points = _make_arc(Vector2.ZERO, 26.0, 10.0, -1.7, 0.95, 10)
	_slash_down.points = _make_arc(Vector2.ZERO, 24.0, 8.0, 0.15, 2.95, 8)
	_sword.visible = has_weapon
	# 对话开始锁输入、整段播完解锁（对话期间角色不能操作）
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	# M1-10：拾取铁剑解锁攻击（没武器时按 J 静默无效，见 _try_start_attack）
	EventBus.item_picked.connect(_on_item_picked)

func _physics_process(delta: float) -> void:
	_update_jump_timers(delta)
	# 倒地 / 复活起身期间不接受操作，只保留重力与碰撞（表现走完再交还控制权）
	if _is_dead or _revive_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_update_attack_state(delta)
		_update_hitbox_pose()
		return
	if _input_locked:
		# 对话锁输入：不响应移动/跳跃/攻击/下砍，只保留重力与碰撞（角色正常站立/落地）
		if _pogo_active:
			_end_pogo()
		_apply_gravity(delta)
		move_and_slide()
		_update_attack_state(delta)
		_update_hitbox_pose()
		return
	_handle_jump()
	_try_start_attack()
	_apply_horizontal_movement(delta)
	_apply_gravity(delta)
	_update_pogo_state()
	move_and_slide()
	_update_facing()
	_update_attack_state(delta)
	_update_hitbox_pose()

func _on_dialogue_started(_dialogue_id: String) -> void:
	_input_locked = true

func _on_dialogue_finished(_dialogue_id: String) -> void:
	_input_locked = false

## M1-10：拾取铁剑后解锁攻击（武器剧情：开场对话引导玩家先捡剑再学攻击）
func _on_item_picked(item_id: String, _count: int) -> void:
	if item_id == "iron_sword":
		has_weapon = true
		_sword.visible = true
		_weapon_flash_timer = WEAPON_FLASH_TIME

func _process(delta: float) -> void:
	_update_invincibility(delta)
	_update_anim_timers(delta)
	_update_visual_anim(delta)

## 表现层计时：挥砍 / 受击 / 捡剑亮光 / 倒地到复活
func _update_anim_timers(delta: float) -> void:
	_attack_anim_timer = maxf(_attack_anim_timer - delta, 0.0)
	_hurt_timer = maxf(_hurt_timer - delta, 0.0)
	_weapon_flash_timer = maxf(_weapon_flash_timer - delta, 0.0)
	_revive_timer = maxf(_revive_timer - delta, 0.0)
	if _death_timer > 0.0:
		_death_timer -= delta
		if _death_timer <= 0.0:
			_death_timer = 0.0
			_respawn()

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
	# 镜像在 _update_visual_anim 里和缩放一起设：这里只记朝向，
	# 否则会覆盖走路/倒地动画的 scale

## 视觉动画：按状态摆姿势（全部是代码拼件，不动物理）
##   地面站立 → 呼吸起伏；跑动 → 颠步 + 摆臂；空中 → 披风后掀；
##   横砍 → 抬臂蓄力再甩下去 + 弧线残影；下劈 → 剑指地 + 竖弧；
##   受击 → 缩身抖一下；倒地 → 侧倒淡出；复活 → 从地上撑起来。
func _update_visual_anim(delta: float) -> void:
	_anim_time += delta
	if _body == null:
		return
	var body_y := 0.0
	var body_rot := 0.0
	var body_scale := Vector2(1.0, 1.0)
	var arm_rot := 0.55
	var sword_rot := 0.35
	var cloak_rot := 0.0
	var tint := Color(1, 1, 1, 1)
	_slash.visible = false
	_slash_down.visible = false

	if _death_timer > 0.0:
		# 倒地：前 40% 快速侧倒，后面保持，等计时结束复活
		var p := 1.0 - _death_timer / DEATH_ANIM_TIME
		var fall := minf(1.0, p * 2.2)
		fall = fall * fall
		body_rot = 1.5 * fall
		body_y = 5.0 * fall
		body_scale = Vector2(1.0 + 0.10 * fall, 1.0 - 0.08 * fall)
		arm_rot = 1.1
		sword_rot = 1.35
		tint = Color(1, 1, 1, 1.0 - 0.35 * fall)
	elif _revive_timer > 0.0:
		# 复活：从侧倒姿态回正，先蹲一下再站直
		var p := 1.0 - _revive_timer / REVIVE_ANIM_TIME
		var up := p * p
		body_rot = 1.5 * (1.0 - up)
		body_y = 5.0 * (1.0 - up) - 6.0 * sin(p * PI)
		body_scale = Vector2(0.9 + 0.1 * up, 0.85 + 0.15 * up)
		arm_rot = lerpf(1.1, 0.55, up)
		sword_rot = lerpf(1.35, 0.35, up)
		tint = Color(1, 1, 1, up)
	else:
		if _pogo_active:
			# 下劈：剑尖朝地，身体略前倾；弧线只在判定窗口内亮，之后收掉
			arm_rot = 1.45
			sword_rot = 1.55
			_slash_down.visible = _attack_anim_timer > 0.0
			_slash_down.modulate = Color(1, 1, 1, 0.7 * minf(1.0, _attack_anim_timer / 0.2))
		elif _attack_anim_timer > 0.0:
			var p := 1.0 - _attack_anim_timer / ATTACK_ANIM_TIME
			if _attack_anim_kind == 1:
				# 下劈动作（判定已结束也把动作收完）
				arm_rot = 1.45
				sword_rot = 1.55
				_slash_down.visible = p < 0.7
				_slash_down.modulate = Color(1, 1, 1, maxf(0.0, 0.75 - p))
			elif p < 0.28:
				# 蓄力：手臂抬到脑后
				var q := p / 0.28
				arm_rot = lerpf(0.55, -1.15, q)
				sword_rot = lerpf(0.35, -0.70, q)
			elif p < 0.60:
				# 挥出：手臂从后上方甩到身前，同时亮出弧线残影
				var q := (p - 0.28) / 0.32
				var swing := q * q
				arm_rot = lerpf(-1.15, 0.95, swing)
				sword_rot = lerpf(-0.70, 0.60, swing)
				_slash.visible = true
				_slash.modulate = Color(1, 1, 1, sin(q * PI) * 0.9)
			else:
				# 收招：慢慢回到持剑站姿
				var q := (p - 0.60) / 0.40
				arm_rot = lerpf(0.95, 0.55, q)
				sword_rot = lerpf(0.60, 0.35, q)
				_slash.visible = true
				_slash.modulate = Color(1, 1, 1, (1.0 - q) * 0.5)
		elif not is_on_floor():
			# 跳跃上行：手向后收，披风向上掀；下落：手略前伸
			if velocity.y < 0.0:
				arm_rot = -0.40
				sword_rot = -0.10
				body_scale.y = 1.05
				cloak_rot = -0.18
			else:
				arm_rot = 0.30
				sword_rot = 0.55
				body_scale.y = 0.96
				cloak_rot = 0.12
		elif absf(velocity.x) > 30.0:
			# 走路：颠步 + 手臂前后摆，披风滞后
			var step := sin(_anim_time * 12.0)
			body_y = -absf(step) * 1.4
			arm_rot = 0.55 + step * 0.22
			cloak_rot = -0.10 + step * 0.05
		else:
			# 待机：呼吸起伏，剑尖轻晃
			var breath := sin(_anim_time * 2.0)
			body_y = breath * 0.8
			arm_rot = 0.55 + breath * 0.04
			sword_rot = 0.35 + breath * 0.03
		# 受击：短暂缩身 + 泛红，叠加在其它状态上
		if _hurt_timer > 0.0:
			var k := _hurt_timer / HURT_ANIM_TIME
			body_rot += sin(_hurt_timer * 45.0) * 0.18 * k
			tint = tint.lerp(Color(1.0, 0.62, 0.62, 1.0), 0.5 * k)

	_body.position = Vector2(0, body_y)
	_body.rotation = body_rot
	_body.scale = Vector2(float(_facing) * body_scale.x, body_scale.y)
	_body.modulate = tint
	_arm.rotation = arm_rot
	_sword.rotation = sword_rot
	_cloak.rotation = cloak_rot
	_cape.rotation = cloak_rot * 1.4
	# 没武器就空手：手里不画剑；刚捡到时亮一下
	_sword.visible = has_weapon
	if _weapon_flash_timer > 0.0:
		_sword.modulate = Color(1.8, 1.9, 1.6, 1.0)
	else:
		_sword.modulate = Color(1, 1, 1, 1)

## 生成一条弧线（残影用）：圆心 + 半径 + 起止角 + 分段数
func _make_arc(center: Vector2, radius: float, width: float, from_angle: float, to_angle: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := lerpf(from_angle, to_angle, t)
		var r := radius - width * 0.5 * sin(t * PI)
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	return pts

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
	# M1-10：没武器不能攻击（静默返回，不弹任何提示；武器剧情见 seed.sql intro_parasite_1）
	if not has_weapon:
		return
	if _attack_cooldown_timer > 0.0:
		return
	# 下砍后摇期间不触发任何攻击（防落地瞬间秒横砍）
	if _pogo_end_lag_timer > 0.0:
		return
	# 必须按下攻击键(J)才攻击，否则冷却一结束就会无限自动挥砍
	if not Input.is_action_just_pressed("attack"):
		return
	if is_on_floor():
		_start_side_slash()
	elif velocity.y > 0.0:
		# 空中下落按 J → 记录下砍请求（从按下点下落超过阈值才真正触发，见 _update_pogo_state）
		if not _pogo_requested:
			_pogo_requested = true
			_pogo_request_y = position.y

# 地面：普通横砍（0.12s 短暂判定，一次挥砍只命中一次）
func _start_side_slash() -> void:
	_attack_dir = _facing  # 锁定出手朝向
	_attack_cooldown_timer = ATTACK_COOLDOWN
	_attack_active_timer = ATTACK_ACTIVE_TIME
	_attack_anim_timer = ATTACK_ANIM_TIME
	_attack_anim_kind = 0
	_hit_this_swing.clear()
	_hitbox_side.monitoring = true
	_hitbox_down.monitoring = false
	_pogo_active = false

# 空中：下砍（pogo）—— 加速下落 + 身前下方持续判定，直到落地或命中实体
func _start_pogo() -> void:
	_attack_dir = _facing  # 锁定出手朝向
	_pogo_active = true
	_attack_anim_timer = ATTACK_ANIM_TIME + 0.1
	_attack_anim_kind = 1
	_hit_this_swing.clear()
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = true
	_attack_cooldown_timer = POGO_RETRIGGER_COOLDOWN
	velocity.y = POGO_FALL_SPEED
	EventBus.log_event("pogo_start", {})

func _update_pogo_state() -> void:
	# 下砍请求：按下 J 后需从按下点下落超过阈值才真正触发；先落地则取消（防贴地触发）
	if _pogo_requested:
		if is_on_floor():
			_pogo_requested = false
		elif position.y - _pogo_request_y >= POGO_MIN_FALL_DISTANCE:
			_pogo_requested = false
			_start_pogo()
	if not _pogo_active:
		return
	# 持续强制下落（加速下落）
	velocity.y = POGO_FALL_SPEED
	# M1-13：下劈命中改为"每帧查询 hitbox 区域内的可受击实体"。
	# 原因：下劈下落很快（vy=700），hitbox 每帧位置大幅移动，body_entered 信号在
	# monitoring 刚开启的那帧重叠信息未更新、下一帧 hitbox 已穿过目标，导致踩跳
	# 木桩/敌人经常漏判。查询用 hitbox 上一帧位置（此时正好覆盖目标），稳定命中。
	var target := _query_pogo_target()
	if target != null:
		_pogo_bounce_on(target)
		return
	# 碰到地面/墙（普通地形）结束下劈
	if is_on_floor() or is_on_wall():
		_end_pogo()

## 查询 hitbox_down 区域内是否有可受击实体（damageable 且有 take_damage）。
## 注意：查询区域用"玩家当前位置"直接计算，且**向上扩展**覆盖下落路径——下劈
## 下落很快（vy 可达 700+），触发/下一物理步之间玩家可能已从目标上方落到下方，
## 只查 hitbox 原位会漏判；扩展后覆盖"玩家上方 30px → 下方 50px"一段。
func _query_pogo_target() -> Node2D:
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var qshape := RectangleShape2D.new()
	qshape.size = Vector2(64, 80)
	q.shape = qshape
	q.transform = Transform2D(0.0, global_position + Vector2(_attack_dir * 32.0, 10.0))
	q.collision_mask = _hitbox_down.collision_mask
	q.exclude = [self]
	for r in space.intersect_shape(q, 8):
		var collider: Object = r.get("collider")
		if collider is Node2D and collider.is_in_group("damageable") and collider.has_method("take_damage"):
			return collider as Node2D
	return null

## 下劈命中实体：伤害 + 固定向上反弹（踩跳），逻辑与 _on_hitbox_down_body_entered 一致
func _pogo_bounce_on(target: Node2D) -> void:
	_apply_hit(target)
	velocity.y = POGO_BOUNCE_VELOCITY
	_end_pogo()
	_attack_cooldown_timer = POGO_RETRIGGER_COOLDOWN
	EventBus.log_event("pogo_bounce", {"target": target.name})

func _end_pogo() -> void:
	if not _pogo_active:
		return
	_pogo_active = false
	_pogo_end_lag_timer = POGO_END_LAG  # 开始后摇
	# 命中敌人时 _end_pogo 会在 body_entered 信号回调里被调用，直接改 monitoring 会被 Godot
	# 拦截报 "Function blocked during in/out signal"，必须 set_deferred 延后（规范第 7 条）
	_hitbox_down.set_deferred("monitoring", false)
	_hit_this_swing.clear()

func _update_attack_state(delta: float) -> void:
	_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)
	_pogo_end_lag_timer = maxf(_pogo_end_lag_timer - delta, 0.0)
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
	# 横砍/下砍判定框按"攻击锁定朝向"定位：攻击中按反方向键只改移动，不改变已出手的攻击方向
	_hitbox_side.position = Vector2(SIDE_HITBOX_OFFSET.x * _attack_dir, SIDE_HITBOX_OFFSET.y)
	_hitbox_down.position = Vector2(POGO_HITBOX_OFFSET.x * _attack_dir, POGO_HITBOX_OFFSET.y)
	# 占位阶段把判定框可视层与开关绑定，便于在编辑器中观察攻击范围
	_hitbox_side_visual.visible = _hitbox_side.monitoring
	_hitbox_down_visual.visible = _hitbox_down.monitoring

func _on_hitbox_side_body_entered(body: Node2D) -> void:
	_apply_hit(body)

func _on_hitbox_down_body_entered(body: Node2D) -> void:
	# 下砍判定只在 pogo 状态下生效：命中实体 → 伤害 + 向上反弹（踩跳）
	if not _pogo_active:
		return
	if not body.is_in_group("damageable"):
		return
	_apply_hit(body)
	# 固定反弹高度（递减链已按组长反馈移除，节奏由"仅下落时触发"控制）
	velocity.y = POGO_BOUNCE_VELOCITY
	_end_pogo()
	# 反弹后可再按 J 连续下砍（需等转为下落）
	_attack_cooldown_timer = POGO_RETRIGGER_COOLDOWN
	EventBus.log_event("pogo_bounce", {"target": body.name})

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
	_hurt_timer = HURT_ANIM_TIME
	if hp <= 0:
		_die()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	# 先倒地、再复活：给表现留时间，不然死亡瞬间就闪回出生点看不见动作
	_death_timer = DEATH_ANIM_TIME
	# 死亡动作期间不要继承受击无敌的闪烁，否则倒地会一闪一闪
	_invincible_timer = 0.0
	_body.visible = true
	velocity = Vector2(0, -140.0)
	_pogo_active = false
	_pogo_requested = false
	_hitbox_side.set_deferred("monitoring", false)
	_hitbox_down.set_deferred("monitoring", false)
	_hit_this_swing.clear()
	EventBus.player_died.emit()

func _respawn() -> void:
	global_position = _spawn_point
	velocity = Vector2.ZERO
	hp = MAX_HP
	_is_dead = false
	_attack_cooldown_timer = 0.0
	_attack_active_timer = 0.0
	_attack_anim_timer = 0.0
	_pogo_active = false
	_pogo_end_lag_timer = 0.0
	_pogo_requested = false
	_input_locked = false
	_hurt_timer = 0.0
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = false
	_hit_this_swing.clear()
	# 复活给满无敌时长 + 起身动作，避免卡在受击点原地连续掉血
	_invincible_timer = INVINCIBLE_TIME
	_revive_timer = REVIVE_ANIM_TIME
	_body.visible = true

func _update_invincibility(delta: float) -> void:
	if _invincible_timer <= 0.0:
		return
	_invincible_timer -= delta
	# 复活起身期间不闪烁：本来是淡入动作，再闪两下会像鬼畜
	if _revive_timer > 0.0:
		_body.visible = true
		return
	if _invincible_timer <= 0.0:
		_invincible_timer = 0.0
		_body.visible = true
		return
	# 无敌期间每 0.08s 切换一次可见性形成闪烁
	_body.visible = int(_invincible_timer / 0.08) % 2 == 0
