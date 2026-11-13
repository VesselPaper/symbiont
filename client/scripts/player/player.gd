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
const AIR_JUMP_VELOCITY := -640.0 # 二段跳略低于一段，避免拿靴后跳跃高度失控
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

# ---- 命中手感（M4-02）----
## 命中瞬间双方各停一拍，给刀“砍进去了”的顿挫；只停玩家物理，不改全局时间。
const HITSTOP_SIDE := 0.035
const HITSTOP_POGO := 0.060
## 小怪被横砍推开的初速；按 knockback_weight 反比缩放，大怪推得少。
const ENEMY_KNOCKBACK_SPEED := 420.0
## 玩家反作用力 = 基础 + 每点重量；怪越大，玩家被推得越远。
const PLAYER_RECOIL_BASE := 150.0
const PLAYER_RECOIL_PER_WEIGHT := 45.0
const PLAYER_RECOIL_MAX := 620.0
const RECOIL_TIME := 0.16
const RECOIL_FRICTION := 900.0

# ---- 生命 / 受击 ----
const MAX_HP := 5
const INVINCIBLE_TIME := 0.5    # 受击无敌时长（期间闪烁表现）
const KNOCKBACK_HORIZONTAL := 260.0
const KNOCKBACK_UPWARD := -220.0

# ---- 动画时长（表现层，不影响手感数值）----
const ATTACK_ANIM_TIME := 0.42  # 一次挥砍的完整动作时长（判定仍只有 0.12s；组长反馈 0.28 太短）
const HURT_ANIM_TIME := 0.25    # 受击缩身时长
const DEATH_ANIM_TIME := 0.85  # 倒地到复活的总时长
const REVIVE_ANIM_TIME := 0.4   # 复活起身时长
const WEAPON_FLASH_TIME := 0.35 # 刚捡到剑时的亮一下
## 横砍白色弧线的半径：判定框是 64px 宽，弧线视觉要接近边缘，不能只到 26px。
const SLASH_ARC_RADIUS := 48.0
const SLASH_DOWN_RADIUS := 34.0

# ---- 跑砍 / 站砍分家（组长反馈“走路时点攻击就直接播攻击动画，很僵硬”）----
# 处理办法：跑着砍保留冲量、换一套更贴地的动作；站着砍把脚钉住再抬手。
# 中间的“慢慢走”按停砍处理，不然会一边滑半步一边挥刀。
const RUN_SLASH_SPEED := 70.0        # 超过这个水平速度算“跑着砍”
const RUN_SLASH_LUNGE := 90.0        # 跑砍起手补一点前冲，位移和动作连起来
const RUN_SLASH_ROOT_TIME := 0.18    # 站砍时把脚钉住的时长
const RUN_SLASH_ROOT_FRICTION := 2200.0
const RUN_SLASH_ARC_ROT := -0.42     # 跑砍的刀弧压低向前扫，和站砍的横向弧分开

var hp := MAX_HP
var has_weapon := false                    # M1-10：是否已拾取铁剑；没武器时按 J 静默无效
var has_steam_boots := false               # M4-06：蒸汽靴；有靴子才允许二段跳
var _air_jumps_left := 0                   # 落地重置；每离地最多再跳一次
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
var _hitstop_timer := 0.0       # 命中顿帧：期间玩家不移动，给打击反馈留出阅读时间
var _recoil_timer := 0.0        # 攻击反作用力期间不响应移动输入，避免一帧就被拉回
var _input_locked := false      # 对话期间锁输入：不能移动/跳跃/攻击/下砍（见 _on_dialogue_*）
var _spawn_point := Vector2.ZERO
var _anim_time := 0.0           # 视觉动画时钟（待机起伏 / 走步颤步），与物理无关
var _attack_anim_timer := 0.0   # 挥砍动作剩余时间（表现，不影响 0.12s 判定）
var _attack_anim_kind := 0      # 0 = 横砍，1 = 下劈
var _attack_running := false    # 本次横砍是不是跑着砍（决定动作和是否保留冲量）
var _attack_root_timer := 0.0   # 站砍时把脚钉住的剩余时间
var _rest_timer := 0.0          # 篝火休息：坐姿剩余时间（期间压扁身体、停止动画覆盖）
var _rest_total := 0.0          # 本次休息的总时长，用来分段：放剑 / 坐 / 起身
var _rest_prop: Node2D          # 休息时放在身侧的剑
var _hurt_timer := 0.0          # 受击缩身剩余时间
var _death_timer := 0.0         # 倒地剩余时间，走完才复活
var _revive_timer := 0.0        # 复活起身剩余时间
var _weapon_flash_timer := 0.0  # 捡剑亮光
var _last_air_vy := 0.0         # 离地时的下落速度，用来判断落地扬尘的力度
var _land_impact_vy := 0.0       # 落地那一帧保留的冲击速度，供扬尘/落地声使用
var _step_timer := 0.0           # 石面脚步的间隔
var _was_on_floor := false
var _dust: CPUParticles2D       # 落地扬尘
var _spark: CPUParticles2D      # 命中火花
var _impact_ring: Line2D        # 命中扩散环
var _impact_tween: Tween
var _corruption: Node2D          # 献祭后在背上长出的寄生组织
var _corruption_count := 0
var _faction := ""               # 第二层阵营：engineer / heretic
var _faction_visual: Node2D      # 阵营外观：工程师蒸汽靴 / 祭司污化腿
var _slash_glow: Line2D         # 横砍外层柔光
var _slash_core: Line2D         # 横砍内层白芯
var _slash_down_glow: Line2D    # 下劈外层柔光
var _slash_down_core: Line2D    # 下劈内层白芯

@onready var _body: Node2D = $Body
@onready var _cloak: Polygon2D = $Body/Cloak
@onready var _cape: Polygon2D = $Body/Cape
@onready var _arm: Node2D = $Body/ArmPivot
@onready var _sword: Node2D = $Body/ArmPivot/SwordPivot
@onready var _slash: Line2D = $Body/SlashArc
@onready var _slash_down: Line2D = $Body/SlashDown
@onready var _hitbox_side: Area2D = $HitboxSide
@onready var _hitbox_down: Area2D = $HitboxDown
var _hitbox_down_shape: RectangleShape2D  # 下劈命中查询用（M1-13，见 _query_pogo_target）

func _ready() -> void:
	# 出生点取场景摆放位置：死亡重生回这里
	_spawn_point = global_position
	# 铁剑跨层/跨实例保留；否则进第二、三层或复活后手里是空的
	if GameManager.has_weapon:
		has_weapon = true
	# 蒸汽靴只买二段跳，不改角色外观（M4-20）：拿到靴子身上不挂任何东西
	if GameManager.has_steam_boots:
		has_steam_boots = true
	_hitbox_side.body_entered.connect(_on_hitbox_side_body_entered)
	_hitbox_down.body_entered.connect(_on_hitbox_down_body_entered)
	# M1-13：下劈命中查询用的 shape 引用（HitboxDown 的 CollisionShape2D）
	var hb_shape_node := $HitboxDown/CollisionShape2D as CollisionShape2D
	if hb_shape_node != null:
		_hitbox_down_shape = hb_shape_node.shape as RectangleShape2D
	# 挥砍残影的弧线点一次算好，后面只改透明度和显隐（每帧重算没必要）
	# 弧线中心略向前，半径 48，视觉末端接近 64px 横砍判定框边缘；线宽加粗成白色刀光
	_slash.position = Vector2(8, -6)
	_slash.width = 5.5
	_slash.default_color = Color(0.94, 1.0, 1.0, 0.95)
	_slash.points = _make_arc(Vector2.ZERO, SLASH_ARC_RADIUS, 12.0, -1.65, 1.0, 12)
	_slash_down.position = Vector2(5, 8)
	_slash_down.width = 4.0
	_slash_down.default_color = Color(0.94, 1.0, 1.0, 0.9)
	_slash_down.points = _make_arc(Vector2.ZERO, SLASH_DOWN_RADIUS, 9.0, 0.15, 2.95, 10)
	_build_slash_layers()
	_sword.visible = has_weapon
	_build_fx()
	_build_corruption()
	# 献祭后会长出寄生组织；先连信号，再按当前献祭数恢复（读档/重生不丢）
	EventBus.sacrifice_done.connect(_on_sacrifice_done)
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and int(gm.get("sacrifice_count")) > 0:
		_show_corruption(int(gm.get("sacrifice_count")))
	if gm != null:
		var saved_faction := str(gm.get("faction"))
		if saved_faction == "engineer" or saved_faction == "heretic":
			apply_faction(saved_faction)
	# 对话开始锁输入、整段播完解锁（对话期间角色不能操作）
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	# M1-10：拾取铁剑解锁攻击（没武器时按 J 静默无效，见 _try_start_attack）
	EventBus.item_picked.connect(_on_item_picked)

func _physics_process(delta: float) -> void:
	_recoil_timer = maxf(_recoil_timer - delta, 0.0)
	if _hitstop_timer > 0.0:
		# 顿帧期间完全冻结玩家物理；下劈的反弹速度先存着，顿完再走。
		_hitstop_timer = maxf(_hitstop_timer - delta, 0.0)
		_update_hitbox_pose()
		return
	_update_jump_timers(delta)
	# 记录离地时的下落速度：落地那一帧用来看要不要扬尘（轻落脚不扬）
	if is_on_floor():
		# 先保留上一帧的下落速度，再清零；否则落地声/扬尘永远读到 0
		_land_impact_vy = _last_air_vy
		_last_air_vy = 0.0
	else:
		_last_air_vy = maxf(_last_air_vy, velocity.y)
	# 倒地 / 复活起身期间不接受操作，只保留重力与碰撞（表现走完再交还控制权）
	if _is_dead or _revive_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_update_attack_state(delta)
		_update_hitbox_pose()
		return
	if _input_locked:
		# 对话锁输入：水平速度立刻归零，避免走路触发对话后角色继续滑行掉下悬崖；
		# 空中触发时只保留重力，落到地面就停住（对话组件会等落地再开始）
		velocity.x = 0.0
		if _pogo_active:
			_end_pogo()
		_apply_gravity(delta)
		move_and_slide()
		_update_attack_state(delta)
		_update_hitbox_pose()
		_update_visual_anim(delta)
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
		GameManager.has_weapon = true
		_sword.visible = true
		_weapon_flash_timer = WEAPON_FLASH_TIME
	elif item_id == "steam_boots":
		has_steam_boots = true
		GameManager.has_steam_boots = true

func _process(delta: float) -> void:
	_update_invincibility(delta)
	_update_anim_timers(delta)
	_update_landing_dust()
	_update_footsteps(delta)
	_update_visual_anim(delta)

## 表现层计时：挥砍 / 受击 / 捡剑亮光 / 倒地到复活
func _update_anim_timers(delta: float) -> void:
	_attack_anim_timer = maxf(_attack_anim_timer - delta, 0.0)
	_attack_root_timer = maxf(_attack_root_timer - delta, 0.0)
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
	# 站砍的起手：脚钉住，不然“边滑半步边挥刀”看着最僵
	if _attack_root_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, RUN_SLASH_ROOT_FRICTION * delta)
		return
	# 攻击反作用力期间不抢输入：让玩家真的被推离怪物，不能原地站定连砍。
	if _recoil_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, RECOIL_FRICTION * delta)
		return
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

## 横砍/下劈各做三层：外层柔光、主刀光、内层白芯。主刀光用渐变和宽度曲线，
## 中间亮、两端收细，比单根等宽线更像刀锋；层数只在 _ready 建一次。
func _build_slash_layers() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.55, 0.82, 1.0, 0.0))
	gradient.set_color(1, Color(0.55, 0.82, 1.0, 1.0))
	_slash.gradient = gradient
	_slash.width_curve = _make_width_curve(0.10, 1.0, 0.05)
	_slash_down.gradient = gradient
	_slash_down.width_curve = _make_width_curve(0.12, 0.9, 0.10)

	_slash_glow = Line2D.new()
	_slash_glow.name = "SlashGlow"
	_slash_glow.width = 15.0
	_slash_glow.default_color = Color(0.50, 0.80, 1.0, 0.34)
	_slash_glow.antialiased = true
	_slash_glow.points = _slash.points
	_slash_glow.position = _slash.position
	_slash_glow.z_index = -1
	_slash_glow.visible = false
	_body.add_child(_slash_glow)
	_body.move_child(_slash_glow, _slash.get_index())

	_slash_core = Line2D.new()
	_slash_core.name = "SlashCore"
	_slash_core.width = 1.8
	_slash_core.default_color = Color(1.0, 1.0, 1.0, 1.0)
	_slash_core.antialiased = true
	_slash_core.points = _slash.points
	_slash_core.position = _slash.position
	_slash_core.z_index = 1
	_slash_core.visible = false
	_body.add_child(_slash_core)

	_slash_down_glow = Line2D.new()
	_slash_down_glow.name = "SlashDownGlow"
	_slash_down_glow.width = 12.0
	_slash_down_glow.default_color = Color(0.55, 0.82, 1.0, 0.30)
	_slash_down_glow.antialiased = true
	_slash_down_glow.points = _slash_down.points
	_slash_down_glow.position = _slash_down.position
	_slash_down_glow.z_index = -1
	_slash_down_glow.visible = false
	_body.add_child(_slash_down_glow)
	_body.move_child(_slash_down_glow, _slash_down.get_index())

	_slash_down_core = Line2D.new()
	_slash_down_core.name = "SlashDownCore"
	_slash_down_core.width = 1.4
	_slash_down_core.default_color = Color(1.0, 1.0, 1.0, 0.95)
	_slash_down_core.antialiased = true
	_slash_down_core.points = _slash_down.points
	_slash_down_core.position = _slash_down.position
	_slash_down_core.z_index = 1
	_slash_down_core.visible = false
	_body.add_child(_slash_down_core)

func _make_width_curve(start: float, peak: float, end: float) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(0.35, peak))
	curve.add_point(Vector2(0.62, 0.72 * peak))
	curve.add_point(Vector2(1.0, end))
	return curve

## 横砍三层一起显隐；alpha 是主刀光的不透明度，外层柔光更淡、白芯更实。
func _set_side_slash(visible_now: bool, alpha: float) -> void:
	_slash.visible = visible_now
	_slash_glow.visible = visible_now
	_slash_core.visible = visible_now
	_slash.modulate = Color(1, 1, 1, alpha)
	_slash_glow.modulate = Color(1, 1, 1, alpha * 0.42)
	_slash_core.modulate = Color(1, 1, 1, minf(1.0, alpha * 1.15))

func _set_down_slash(visible_now: bool, alpha: float) -> void:
	_slash_down.visible = visible_now
	_slash_down_glow.visible = visible_now
	_slash_down_core.visible = visible_now
	_slash_down.modulate = Color(1, 1, 1, alpha)
	_slash_down_glow.modulate = Color(1, 1, 1, alpha * 0.40)
	_slash_down_core.modulate = Color(1, 1, 1, minf(1.0, alpha * 1.1))

func _hide_slash_layers() -> void:
	_set_side_slash(false, 0.0)
	_set_down_slash(false, 0.0)

## 视觉动画：按状态摆姿势（全部是代码拼件，不动物理）
##   地面站立 → 呼吸起伏；跑动 → 颠步 + 摆臂；空中 → 披风后掀；
##   横砍 → 抬臂蓄力再甩下去 + 弧线残影；下劈 → 剑指地 + 竖弧；
##   受击 → 缩身抖一下；倒地 → 侧倒淡出；复活 → 从地上撑起来。
func _update_visual_anim(delta: float) -> void:
	if _rest_timer > 0.0:
		# 篝火休息：放剑到身侧地上 → 蹲坐 → 抓剑、撑地起身；按方向键可随时中断
		if absf(Input.get_axis("move_left", "move_right")) > 0.1:
			_end_rest_pose()
			return
		_rest_timer = maxf(_rest_timer - delta, 0.0)
		var total := maxf(_rest_total, 1.6)
		var t := total - _rest_timer
		var stand_at := maxf(total - 0.95, 0.6)
		if t < 0.45:
			# ① 把剑放到身侧地上（手里那把先收起来）
			var p := t / 0.45
			_sword.visible = p < 0.55
			_ensure_ground_sword()
			_body.scale = Vector2(float(_facing), lerpf(1.0, 0.86, p))
			_body.position = Vector2(0, lerpf(0.0, 3.0, p))
			_body.rotation = 0.03 * float(_facing) * p
		elif t < stand_at:
			# ② 蹲坐着歇息：膝盖压低、身体前倾，剑就放在手边
			_sword.visible = false
			_ensure_ground_sword()
			_body.scale = Vector2(float(_facing) * 1.04, 0.60)
			_body.position = Vector2(0, 10)
			_body.rotation = 0.12 * float(_facing)
		else:
			# ③ 起身：先抓剑回手，再单手撑地站起来
			var q := clampf((t - stand_at) / maxf(total - stand_at, 0.01), 0.0, 1.0)
			var grab := clampf(q * 2.4, 0.0, 1.0)
			if grab >= 0.55:
				_free_ground_sword()
			_sword.visible = grab >= 0.5
			var rise := clampf((q - 0.35) / 0.65, 0.0, 1.0)
			_body.scale = Vector2(float(_facing), lerpf(0.60, 1.0, rise))
			_body.position = Vector2(0, lerpf(10.0, 0.0, rise) - 4.0 * sin(rise * PI))
			_body.rotation = 0.12 * float(_facing) * (1.0 - rise)
		return
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
	_hide_slash_layers()

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
			_set_down_slash(_attack_anim_timer > 0.0, 0.7 * minf(1.0, _attack_anim_timer / 0.2))
		elif _attack_anim_timer > 0.0:
			var p := 1.0 - _attack_anim_timer / ATTACK_ANIM_TIME
			if _attack_anim_kind == 1:
				# 下劈动作（判定已结束也把动作收完）
				arm_rot = 1.45
				sword_rot = 1.55
				_set_down_slash(p < 0.7, maxf(0.0, 0.75 - p))
			elif _attack_running:
				# 跑砍：不举过头顶，直接前倾压刀横扫。整体比站砍低一档，
				# 同时保留走路的颠步，免得人看着像“定在跑道上挥刀”。
				var step_run := sin(_anim_time * 12.0)
				body_y = -absf(step_run) * 1.4
				body_rot += 0.12
				body_scale = Vector2(1.04, 0.96)
				if p < 0.18:
					var q0 := p / 0.18
					arm_rot = lerpf(0.95, 0.45, q0)
					sword_rot = lerpf(-0.15, 0.20, q0)
				elif p < 0.74:
					var q1 := (p - 0.18) / 0.56
					var swing_run := q1 * q1
					arm_rot = lerpf(0.45, 1.15, swing_run)
					sword_rot = lerpf(0.20, 0.92, swing_run)
					_set_side_slash(true, sin(minf(q1, 0.9) * PI) * 0.95)
				else:
					var q2 := (p - 0.74) / 0.26
					arm_rot = lerpf(1.15, 0.55, q2)
					sword_rot = lerpf(0.92, 0.35, q2)
					_set_side_slash(true, (1.0 - q2) * 0.5)
			elif p < 0.26:
				# 蓄力：手臂抬到脑后
				var q := p / 0.26
				arm_rot = lerpf(0.55, -1.15, q)
				sword_rot = lerpf(0.35, -0.70, q)
			elif p < 0.78:
				# 挥出：手臂从后上方甩到身前，同时亮出弧线残影；
				# 弧线保留到收招前，避免动作加长后刀光只在开头闪一下
				var q := (p - 0.26) / 0.52
				var swing := q * q
				arm_rot = lerpf(-1.15, 0.95, swing)
				sword_rot = lerpf(-0.70, 0.60, swing)
				_set_side_slash(true, sin(minf(q, 0.9) * PI) * 0.95)
			else:
				# 收招：慢慢回到持剑站姿
				var q := (p - 0.78) / 0.22
				arm_rot = lerpf(0.95, 0.55, q)
				sword_rot = lerpf(0.60, 0.35, q)
				_set_side_slash(true, (1.0 - q) * 0.55)
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

	# 命中顿帧时压扁一点，让“停住”不是单纯的卡帧，而是有受力形变
	if _hitstop_timer > 0.0:
		body_scale = Vector2(body_scale.x * 1.10, body_scale.y * 0.88)
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

## 献祭后果：不是加数值，而是让寄生体真的在背上长出来。
## 第一次在肩后出现一小簇紫色菌丝/触须，第二次再向外爬一圈；只改外观。
func _build_corruption() -> void:
	_corruption = Node2D.new()
	_corruption.name = "Corruption"
	# 肢体和角色必须在同一个图层：原来的 z=-1 会被背景盖住，而角色本身没事。
	# 改成 0 + show_behind_parent：仍然画在身体后面，但不再掉到背景下面。
	_corruption.z_index = 0
	_corruption.show_behind_parent = true
	_corruption.visible = false
	_body.add_child(_corruption)
	# 背侧的三根短触须：从披风后面钻出来，不挡脸
	for i in range(3):
		var tendril := Line2D.new()
		tendril.width = 2.0 - i * 0.35
		tendril.default_color = Color(0.36, 0.16, 0.44, 0.86)
		tendril.points = PackedVector2Array([
			Vector2(-2 + i * 3, -14),
			Vector2(-15 - i * 5, -9 - i * 4),
			Vector2(-24 - i * 6, -18 - i * 6),
			Vector2(-20 - i * 7, -27 - i * 5),
		])
		_corruption.add_child(tendril)
	var bulb := Polygon2D.new()
	bulb.color = Color(0.46, 0.20, 0.54, 0.92)
	bulb.position = Vector2(-16, -15)
	bulb.polygon = PackedVector2Array([
		Vector2(-5, 0), Vector2(-1, -6), Vector2(5, -4),
		Vector2(6, 3), Vector2(1, 6), Vector2(-4, 4),
	])
	_corruption.add_child(bulb)
	var eye := Polygon2D.new()
	eye.color = Color(0.88, 0.92, 0.70, 0.9)
	eye.position = Vector2(-16, -15)
	eye.polygon = PackedVector2Array([
		Vector2(-2, -1), Vector2(1, -2), Vector2(2, 1), Vector2(-1, 2),
	])
	_corruption.add_child(eye)

## 第二层阵营外观：工程师给蒸汽靴和背罐，异教徒给污化腿。
## M3-01 只做身份可见，不在这里改跳跃数值——能力分叉留给下一张卡。
func apply_faction(faction: String) -> void:
	if faction != "engineer" and faction != "heretic":
		return
	if _faction == faction and _faction_visual != null:
		return
	_faction = faction
	if _faction_visual != null and is_instance_valid(_faction_visual):
		_faction_visual.queue_free()
	_faction_visual = Node2D.new()
	_faction_visual.name = "FactionVisual"
	# 肢体和角色必须在同一个图层：原来的 z=-1 会被背景盖住，而角色本身没事。
	# 改成 0 + show_behind_parent：仍然画在身体后面，但不再掉到背景下面。
	_faction_visual.z_index = 0
	_faction_visual.show_behind_parent = true
	_body.add_child(_faction_visual)
	if faction == "engineer":
		# 这是阵营身份（工程师一族的装束），和宝箱里那双“二段跳靴子”不是一回事：
		# 宝箱靴子只给能力、不改外观（M4-20），这里只有入了工程师阵营才会长出这双靴子
		_build_steam_boots(_faction_visual)
	else:
		_build_tainted_leg()

func get_faction() -> String:
	return _faction

## 蒸汽靴（工程师阵营外观用）：脚踝一圈黄铜护甲 + 小腿外侧的细管，背后再加一个小压力罐。
## 注意：宝箱拿到的二段跳靴子不走这个函数——组长定稿“开靴子不改外貌”，
## 拿到靴子后角色身上不出现任何新东西（M4-20）。
func _build_steam_boots(parent: Node2D) -> void:
	for dx in [-6.0, 7.0]:
		var boot := Polygon2D.new()
		boot.color = Color(0.48, 0.36, 0.20, 1)
		boot.polygon = PackedVector2Array([
			Vector2(dx - 6, 8), Vector2(dx + 5, 7), Vector2(dx + 7, 14),
			Vector2(dx - 7, 14), Vector2(dx - 8, 10),
		])
		parent.add_child(boot)
		var rim := Line2D.new()
		rim.width = 1.0
		rim.default_color = Color(0.92, 0.72, 0.36, 0.9)
		rim.points = PackedVector2Array([
			Vector2(dx - 7, 10), Vector2(dx + 6, 9),
		])
		parent.add_child(rim)
		var pipe := Line2D.new()
		pipe.width = 1.4
		pipe.default_color = Color(0.58, 0.42, 0.23, 0.9)
		pipe.points = PackedVector2Array([
			Vector2(dx + (4.0 if dx > 0 else -4.0), 3),
			Vector2(dx + (6.0 if dx > 0 else -6.0), 8),
		])
		parent.add_child(pipe)
	var tank := Polygon2D.new()
	tank.color = Color(0.25, 0.24, 0.20, 0.95)
	tank.polygon = PackedVector2Array([
		Vector2(-18, -12), Vector2(-10, -13), Vector2(-9, 0), Vector2(-17, 1),
	])
	parent.add_child(tank)
	var tank_rim := Line2D.new()
	tank_rim.width = 1.0
	tank_rim.default_color = Color(0.60, 0.46, 0.26, 0.8)
	tank_rim.points = PackedVector2Array([Vector2(-18, -11), Vector2(-10, -12)])
	parent.add_child(tank_rim)

## 污化腿：右腿外侧爬出三根紫色菌丝，膝盖处一颗小眼；和献祭长出的组织同色。
func _build_tainted_leg() -> void:
	for i in range(3):
		var tendril := Line2D.new()
		tendril.width = 1.8 - i * 0.3
		tendril.default_color = Color(0.40, 0.18, 0.50, 0.9)
		tendril.points = PackedVector2Array([
			Vector2(5, 2 + i * 2),
			Vector2(11 + i * 2, 7 + i * 2),
			Vector2(15 + i * 3, 14 + i * 2),
		])
		_faction_visual.add_child(tendril)
	var knee_eye := Polygon2D.new()
	knee_eye.color = Color(0.86, 0.58, 1.0, 0.95)
	knee_eye.position = Vector2(9, 8)
	knee_eye.polygon = PackedVector2Array([
		Vector2(-2, -1), Vector2(1, -2), Vector2(2, 1), Vector2(-1, 2),
	])
	_faction_visual.add_child(knee_eye)

func _on_sacrifice_done(_sacrifice_id: String, total_count: int) -> void:
	_show_corruption(total_count)

func _show_corruption(count: int) -> void:
	if _corruption == null:
		return
	_corruption_count = count
	_corruption.visible = true
	# 第二道馈赠让寄生组织再向外扩一圈，仍不改碰撞/数值
	_corruption.scale = Vector2(1.0 + minf(count - 1, 3) * 0.12, 1.0 + minf(count - 1, 3) * 0.08)
	var tw := create_tween()
	tw.tween_property(_corruption, "modulate", Color(1.0, 0.72, 1.0, 1.0), 0.18)
	tw.tween_property(_corruption, "modulate", Color(1, 1, 1, 1.0), 0.45)

## 打击火花：命中点炸一小簇冷白点，补足"打到了"的反馈（不加任何判定）
func _spawn_hit_spark(pos: Vector2, strength: float = 3.6, duration: float = 0.12) -> void:
	if _spark == null:
		return
	_spark.global_position = pos
	_spark.restart()
	_spark.emitting = true
	_spawn_impact_ring(pos)
	_shake_camera(strength, duration)

## 命中扩散环：和火花同时出现，给一个"刀砍进去了"的顿挫轮廓。
func _spawn_impact_ring(pos: Vector2) -> void:
	if _impact_ring == null:
		return
	if _impact_tween != null and _impact_tween.is_valid():
		_impact_tween.kill()
	_impact_ring.global_position = pos
	_impact_ring.visible = true
	_impact_ring.scale = Vector2(0.35, 0.35)
	_impact_ring.modulate = Color(1, 1, 1, 0.95)
	_impact_tween = create_tween().set_parallel()
	_impact_tween.tween_property(_impact_ring, "scale", Vector2(1.9, 1.9), 0.16)
	_impact_tween.tween_property(_impact_ring, "modulate:a", 0.0, 0.18)
	_impact_tween.tween_callback(_hide_impact_ring)

func _hide_impact_ring() -> void:
	if _impact_ring != null:
		_impact_ring.visible = false

func _shake_camera(strength: float = 3.6, duration: float = 0.12) -> void:
	var camera := get_tree().get_first_node_in_group("camera")
	if camera != null and camera.has_method("shake"):
		camera.call("shake", strength, duration)

## 落地扬尘：只有下落速度够快才扬，轻跳落地不出尘
func _update_landing_dust() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		# 轻落脚只给一点低频，重落地才扬尘 + 更响的石面撞击
		if _land_impact_vy > 180.0:
			GameManager.play_sfx("land", -4.0 if _land_impact_vy > 480.0 else -8.0,
				1.0 + minf(_land_impact_vy / 900.0, 0.12))
		if _land_impact_vy > 260.0 and _dust != null:
			_dust.global_position = global_position + Vector2(0, 13)
			_dust.restart()
			_dust.emitting = true
		_land_impact_vy = 0.0
	_was_on_floor = on_floor

## 石面脚步：只在地面、真正走动、没锁输入时响；跑得快间隔就短
func _update_footsteps(delta: float) -> void:
	if _input_locked or _is_dead or _revive_timer > 0.0 or not is_on_floor() or absf(velocity.x) < 18.0:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		GameManager.play_sfx("step", -13.0)
		_step_timer = 0.26 if absf(velocity.x) > 160.0 else 0.34

func _build_fx() -> void:
	var fx := Node2D.new()
	fx.name = "Fx"
	fx.z_index = 1
	add_child(fx)
	_dust = _make_burst(Color(0.36, 0.39, 0.39, 0.65), 10, 0.45, 34.0, 170.0, -30.0, 0.5, 1.6)
	_dust.name = "LandingDust"
	fx.add_child(_dust)
	_spark = _make_burst(Color(0.80, 0.95, 1.0, 0.95), 20, 0.30, 150.0, 190.0, 160.0, 0.35, 1.3)
	_spark.name = "HitSpark"
	var spark_mat := CanvasItemMaterial.new()
	spark_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_spark.material = spark_mat
	fx.add_child(_spark)

	# 命中环：一圈细白线从命中点扩散，不和火花抢同一块像素
	_impact_ring = Line2D.new()
	_impact_ring.name = "HitRing"
	_impact_ring.width = 2.0
	_impact_ring.default_color = Color(0.82, 0.96, 1.0, 0.9)
	_impact_ring.antialiased = true
	var ring_points := PackedVector2Array()
	for i in range(20):
		var angle := TAU * float(i) / 20.0
		ring_points.append(Vector2(cos(angle), sin(angle)) * 15.0)
	_impact_ring.points = ring_points
	_impact_ring.z_index = 2
	_impact_ring.visible = false
	var ring_mat := CanvasItemMaterial.new()
	ring_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_impact_ring.material = ring_mat
	fx.add_child(_impact_ring)

func _make_burst(color: Color, amount: int, lifetime: float, speed: float, spread: float, gravity: float, scale_min: float, scale_max: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.direction = Vector2(0, -1)
	p.spread = spread
	p.gravity = Vector2(0, gravity)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.color = color
	p.texture = _dot_texture()
	p.local_coords = false
	return p

func _dot_texture() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			var d := Vector2(x - 1.5, y - 1.5).length() / 2.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

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
	# 二段跳只在落地时补满；单段跳不能靠“按两下”跳更高
	if is_on_floor():
		_air_jumps_left = 1 if has_steam_boots else 0

func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		# 地面/土狼时间内的按键走原来的 buffer；空中按键只给二段跳，
		# 否则落地前按一下会变成“自动再跳”，手感会飘。
		if is_on_floor() or _coyote_timer > 0.0:
			_jump_buffer_timer = JUMP_BUFFER_TIME
		elif try_air_jump():
			_jump_buffer_timer = 0.0
			return
	# coyote 与 buffer 同时满足才起跳，两者都是给操作留的宽容窗口
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_air_jumps_left = 1 if has_steam_boots else 0
		GameManager.play_sfx("jump", -3.0)
	# 固定跳高：起跳速度与重力恒定，无论按多久，跳跃高度一致（见决策日志 D-008）

## 二段跳：有靴子且这次离地还没用过才生效；返回是否真的起跳，便于无头回归
func try_air_jump() -> bool:
	if not has_steam_boots or _air_jumps_left <= 0:
		return false
	_air_jumps_left -= 1
	velocity.y = AIR_JUMP_VELOCITY
	_spawn_air_jump_fx()
	GameManager.play_sfx("double_jump", -4.0)
	return true

## 二段跳的脚底蒸汽环：不新增贴图，复用落地尘粒并给它一点向上的速度感
func _spawn_air_jump_fx() -> void:
	if _dust == null:
		return
	_dust.global_position = global_position + Vector2(0, 12)
	_dust.restart()
	_dust.emitting = true

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
		# 地面上：按住下键(S) + 攻击 = 朝下劈；只按攻击 = 前方横砍
		if Input.is_action_pressed("move_down"):
			_start_down_slash()
		else:
			_start_side_slash()
	elif Input.is_action_pressed("move_down"):
		# 空中同样靠"按住下 + 攻击"进入下劈；不再自动把空中攻击变成下劈
		_start_pogo()
	else:
		# 空中普通攻击：只朝面前横砍
		_start_side_slash()

## 地面上的下劈：站在原地朝脚下挥一刀，能打到贴地的矮目标（不再靠下落触发）
func _start_down_slash() -> void:
	_attack_dir = _facing
	_attack_cooldown_timer = ATTACK_COOLDOWN
	_attack_active_timer = ATTACK_ACTIVE_TIME
	_attack_anim_timer = ATTACK_ANIM_TIME
	_attack_anim_kind = 1
	_attack_running = false
	_hit_this_swing.clear()
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = true
	_pogo_active = false
	GameManager.play_sfx("swing", -2.0, 0.82)

# 地面：普通横砍（0.12s 短暂判定，一次挥砍只命中一次）
func _start_side_slash() -> void:
	_attack_dir = _facing  # 锁定出手朝向
	_attack_cooldown_timer = ATTACK_COOLDOWN
	_attack_active_timer = ATTACK_ACTIVE_TIME
	_attack_anim_timer = ATTACK_ANIM_TIME
	_attack_anim_kind = 0
	# 跑着砍 / 站着砍：动作、冲量、是否钉住脚都不一样
	_attack_running = is_on_floor() and absf(velocity.x) > RUN_SLASH_SPEED
	if _attack_running:
		_attack_root_timer = 0.0
		# 保留原有冲量并补一口前冲，让“人还在跑”和“刀在挥”接得上
		# 补前冲但不超过跑速上限：否则连砍就能跑得比跑步还快
		velocity.x = float(_attack_dir) * minf(maxf(absf(velocity.x), RUN_SPEED * 0.6) + RUN_SLASH_LUNGE, RUN_SPEED)
	else:
		# 站定才把脚钉住；空中挥砍保留原有水平速度，不要"后坐力"把人刹住
		_attack_root_timer = RUN_SLASH_ROOT_TIME if is_on_floor() else 0.0
	_hit_this_swing.clear()
	_hitbox_side.monitoring = true
	_hitbox_down.monitoring = false
	_pogo_active = false
	_slash.rotation = RUN_SLASH_ARC_ROT if _attack_running else 0.0
	GameManager.play_sfx("swing", -2.0)

# 空中：下砍（pogo）—— 只朝脚下判定，不再强制加速下坠
func _start_pogo() -> void:
	_attack_dir = _facing  # 锁定出手朝向
	_pogo_active = true
	_attack_anim_timer = ATTACK_ANIM_TIME + 0.1
	_attack_anim_kind = 1
	_hit_this_swing.clear()
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = true
	_attack_cooldown_timer = POGO_RETRIGGER_COOLDOWN
	GameManager.play_sfx("swing", -2.0, 0.82)
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
	# 下劈不再强制下坠：保留玩家原本的垂直速度，只负责脚下的判定
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
	# 判定框只在逻辑层生效；挥砍反馈由 SlashArc / SlashDown 两条弧线承担，不再画调试矩形

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
	var was_pogo := _pogo_active
	if body.has_method("take_damage"):
		body.take_damage(ATTACK_DAMAGE)
	# 物理反馈：目标按重量被推开，玩家吃反作用力；大怪推得少、玩家退得多。
	var weight := _target_weight(body)
	var knock_dir := signf(body.global_position.x - global_position.x)
	if knock_dir == 0.0:
		knock_dir = float(_attack_dir)
	if body.has_method("apply_knockback"):
		body.call("apply_knockback", global_position, ENEMY_KNOCKBACK_SPEED / weight)
	var recoil_dir := -knock_dir
	var recoil := minf(PLAYER_RECOIL_BASE + PLAYER_RECOIL_PER_WEIGHT * weight, PLAYER_RECOIL_MAX)
	if was_pogo:
		# 下劈主要是垂直踩跳，水平只给一点后坐，避免把玩家从目标头上推歪
		recoil *= 0.45
	velocity.x = recoil_dir * recoil
	_recoil_timer = RECOIL_TIME
	_hitstop_timer = HITSTOP_POGO if was_pogo else HITSTOP_SIDE
	var shake_strength := 6.8 if was_pogo else 3.6
	var shake_time := 0.16 if was_pogo else 0.12
	_spawn_hit_spark(body.global_position, shake_strength, shake_time)
	# 命中声按被打的东西走：肉、木头、铁各有各的声音，别一刀一个通用闷响
	if was_pogo:
		GameManager.play_sfx("pogo")
	else:
		var material := "flesh"
		var raw_material: Variant = body.get("hit_material")
		if raw_material != null:
			material = str(raw_material)
		GameManager.play_sfx("hit_" + material)

func _target_weight(body: Node2D) -> float:
	var raw: Variant = body.get("knockback_weight")
	var weight := float(raw) if raw != null else 1.0
	return maxf(weight, 0.1)

# ---- 受击 / 死亡 ----

## 篝火休息：回满血。HUD 订阅 player_healed 刷新心数。
## 返回实际回复的心数（满血时 0），供篝火决定显示"已恢复"还是"不需要休息"。
func heal_full() -> int:
	if _is_dead:
		return 0
	var before := hp
	hp = MAX_HP
	var healed := hp - before
	if healed > 0:
		EventBus.player_healed.emit(healed)
	return healed

## 篝火休息：放剑 → 蹲坐 → 抓剑撑地起身。默认 3.2 秒足够看清三段动作。
func sit_rest(duration: float = 3.2) -> void:
	_rest_total = maxf(duration, 1.8)
	_rest_timer = _rest_total

## 身侧地上的剑：休息开始就摆到脚边，起身抓回手里后移除
func _ensure_ground_sword() -> void:
	if _rest_prop != null and is_instance_valid(_rest_prop):
		return
	var prop := Node2D.new()
	prop.name = "RestSword"
	prop.z_index = -1
	var blade := Polygon2D.new()
	blade.color = Color(0.76, 0.80, 0.83, 1.0)
	blade.polygon = PackedVector2Array([
		Vector2(-24, -1.6), Vector2(10, -1.6), Vector2(14, 0),
		Vector2(10, 1.6), Vector2(-24, 1.6),
	])
	prop.add_child(blade)
	var guard := Polygon2D.new()
	guard.color = Color(0.50, 0.38, 0.22, 1.0)
	guard.polygon = PackedVector2Array([
		Vector2(-27, -5), Vector2(-23, -5), Vector2(-23, 5), Vector2(-27, 5),
	])
	prop.add_child(guard)
	var grip := Polygon2D.new()
	grip.color = Color(0.26, 0.18, 0.12, 1.0)
	grip.polygon = PackedVector2Array([
		Vector2(-35, -1.6), Vector2(-27, -1.6), Vector2(-27, 1.6), Vector2(-35, 1.6),
	])
	prop.add_child(grip)
	get_parent().add_child(prop)
	prop.global_position = global_position + Vector2(-22.0 * float(_facing), 12.0)
	prop.rotation = 0.28
	_rest_prop = prop

func _free_ground_sword() -> void:
	if _rest_prop != null and is_instance_valid(_rest_prop):
		_rest_prop.queue_free()
	_rest_prop = null

## 中途起身：恢复持剑、收掉地上的剑
func _end_rest_pose() -> void:
	_rest_timer = 0.0
	_sword.visible = true
	_free_ground_sword()

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
	GameManager.play_sfx("heal", -3.0)
	_attack_cooldown_timer = 0.0
	_attack_active_timer = 0.0
	_attack_anim_timer = 0.0
	_pogo_active = false
	_pogo_end_lag_timer = 0.0
	_pogo_requested = false
	_input_locked = false
	_hurt_timer = 0.0
	_hitstop_timer = 0.0
	_recoil_timer = 0.0
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = false
	_hit_this_swing.clear()
	# 复活给满无敌时长 + 起身动作，避免卡在受击点原地连续掉血
	_invincible_timer = INVINCIBLE_TIME
	_revive_timer = REVIVE_ANIM_TIME
	# 复活时补回全局武器/蒸汽靴状态，防死亡动画期间被场景重载/清空
	if GameManager.has_weapon:
		has_weapon = true
	if GameManager.has_steam_boots:
		has_steam_boots = true
		_air_jumps_left = 0
	_sword.visible = has_weapon
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
