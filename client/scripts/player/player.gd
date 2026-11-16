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
const RUN_SPEED := 250.0        # 最大跑速 px/s
const ACCELERATION := 1800.0    # 有方向输入时的加速（地面/空中一致，手感更跟手）
const FRICTION := 1600.0        # 地面无输入时的减速
const AIR_FRICTION := 300.0     # 空中无输入时只轻微减速，保留跳跃飘动感

# ---- 垂直移动 ----
const GRAVITY := 2550
const MAX_FALL_SPEED := 900.0
const CHARACTER_HEIGHT := 28.0    # 角色视觉身高（knight_body.tscn 里贴图整体就是 28 单位高）
## 头的基准位置：和 knight_body.tscn 里 Head 节点的 position 一致（M4-61 换成第二版渲染图后重接）
const HEAD_BASE := Vector2(0, 0)
## 斗篷的基准位置（也和 knight_body.tscn 对齐）：_update_cloth 会在这里加减摆动量。
## M4-62：斗篷切成"上段 + 下摆"两片 —— 一片整布只能整块摇，切成两片下摆才能自己甩起来。
## 身后那片深色披风本身是黑的，已经并进身体层，CAPE 只留占位。
const CAPE_BASE := Vector2(2, 0.5)
const TAIL_BASE := Vector2(-3, 0.5)
const HEM_BASE := Vector2(-1, 3.76)
const JUMP_VELOCITY := -727.0     # 跳跃初速：√(2×2550×3.7×28)≈727 → 跳高≈3.7 倍身高（D-009）
const AIR_JUMP_VELOCITY := -640.0 # 二段跳略低于一段，避免拿靴后跳跃高度失控
const COYOTE_TIME := 0.1        # 离开平台边缘后仍可起跳的宽容时间
const JUMP_BUFFER_TIME := 0.15  # 落地前提前按跳的输入缓冲

# ---- 攻击 ----
const ATTACK_DAMAGE := 1
const ATTACK_COOLDOWN := 0.25
const ATTACK_ACTIVE_TIME := 0.12   # 判定框单次启用时长（一次挥砍只命中一次）
const SIDE_HITBOX_OFFSET := Vector2(32, -14)  # 横砍判定框：64宽×56高（4×角色宽16 × 2×角色高28），从头顶上方到身前（面朝右时 x:0→64, y:-42→+14）
const SIDE_HITBOX_SIZE_DEFAULT := Vector2(64, 56)  # 第一段横劈的判定框尺寸；二三段会换
const POGO_HITBOX_OFFSET := Vector2(32, 14)   # 下砍判定框：64宽×28高（前方4×宽16 × 下方1×高28），面朝右时 x:0→64, y:0→28
const POGO_FALL_SPEED := 700.0       # 下砍时强制下落速度（加速下落）
const POGO_BOUNCE_VELOCITY := -650.0 # 命中实体后的向上反弹初速（≈83px 高，可调）
const POGO_RETRIGGER_COOLDOWN := 0.1 # 反弹后可再次下砍的最小间隔（支持多段踩跳）
const POGO_END_LAG := 0.2        # 下砍结束后的后摇：期间按 J 不触发攻击（防落地瞬间秒横砍）
const POGO_MIN_FALL_DISTANCE := 20.0  # 下砍需已下落的距离阈值（刚起跳/刚出边缘/贴地时不触发）
## 空中攻击后的硬后摇（M5-07）：这一整段内按 J 不出刀，落地立刻解除。
## 0.34 秒 ≈ 一次下劈动作的长度，玩家读得出"这一刀挥完了才能接下一刀"。
const AIR_ATTACK_RECOVERY := 0.34

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
## 死亡表现（M4-60，组长定）：身体化成一团黑雾，只把空头盔留在原地、掉到地上躺住。
const DEATH_ANIM_TIME := 1.15   # 化雾 → 头盔落地躺住 → 才复活。留够时间让"盔掉下来"看得清
const DEATH_DISSOLVE_TIME := 0.26  # 身体化雾用的时间，剩下都留给头盔落地
const DEATH_HELMET_GRAVITY := 1450.0
## 掉在地上的空头盔贴图：和头上一层同一张，只是眼窝里的蓝眼换成近黑（摘空了就该是空的）
const HELMET_EMPTY_TEX := preload("res://assets/art/player/helmet_empty.png")
const REVIVE_ANIM_TIME := 0.4   # 复活起身时长
## 开场从虚空砸下来之后的"落地站起"时长（落地压扁 → 弹起过头 → 站定）
const INTRO_LAND_TIME := 0.62
const WEAPON_FLASH_TIME := 0.35 # 刚捡到剑时的亮一下
## 横砍白色弧线的半径：判定框是 64px 宽，弧线视觉要接近边缘，不能只到 26px。
const SLASH_ARC_RADIUS := 48.0
const SLASH_DOWN_RADIUS := 34.0

# ---- 三连击（组长反馈“攻击动作太二，只是直接旋转刀”）----
# 三段各有自己的弧线、前冲、判定框与收招节奏；最短间隔仍按 ATTACK_COOLDOWN 卡，
# 所以只改手感、不改每秒输出（数值由组长定，这里不动伤害）。
const COMBO_MAX := 3
const COMBO_WINDOW := 0.5          # 本段动作结束后这么久内再按 J，接下一段
const COMBO_STAGE_TIME := [0.42, 0.40, 0.55]      # 本段动作总时长
const COMBO_STAGE_LUNGE := [90.0, 56.0, 150.0]    # 本段起手补的前冲
const COMBO_STAGE_ARC := [
	{"radius": 48.0, "from": -1.65, "to": 1.00, "rot": 0.00},   # 横劈：左上 → 右下
	{"radius": 44.0, "from": 1.45, "to": -0.70, "rot": 0.00},    # 反手上撩：下 → 上
	{"radius": 58.0, "from": -0.55, "to": 0.40, "rot": -0.10},   # 前刺：窄而远的一道
]
const COMBO_STAGE_HITBOX := [
	{"offset": Vector2(32, -14), "size": Vector2(64, 56)},       # 横劈：身前一片
	{"offset": Vector2(30, -20), "size": Vector2(58, 64)},       # 上撩：偏上一点
	{"offset": Vector2(42, -12), "size": Vector2(84, 40)},       # 前刺：更远更窄
]
const COMBO_STAGE_PITCH := [1.00, 1.14, 0.82]    # 挥砍音高，第三段更沉


# ---- 跑砍 / 站砍分家（组长反馈“走路时点攻击就直接播攻击动画，很僵硬”）----
# 处理办法：跑着砍保留冲量、换一套更贴地的动作；站着砍把脚钉住再抬手。
# 中间的“慢慢走”按停砍处理，不然会一边滑半步一边挥刀。
const RUN_SLASH_SPEED := 70.0        # 超过这个水平速度算“跑着砍”
const RUN_SLASH_LUNGE := 90.0        # 跑砍起手补一点前冲，位移和动作连起来
const RUN_SLASH_ROOT_TIME := 0.18    # 站砍时把脚钉住的时长
const RUN_SLASH_ROOT_FRICTION := 2200.0
const RUN_SLASH_ARC_ROT := -0.42     # 跑砍的刀弧压低向前扫，和站砍的横向弧分开

var hp := MAX_HP
var display_only := false
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
## "这一次按住攻击键已经出过刀"（M5-07）：松开才解锁，防长按 echo 触发连发
var _attack_press_latch := false
## 空中攻击后摇剩余（落地清零）
var _air_attack_recovery := 0.0
var _hit_this_swing: Array[Node2D] = []     # 本次挥砍已命中的目标，防止同一判定框重复扣血
var _invincible_timer := 0.0
var _hitstop_timer := 0.0       # 命中顿帧：期间玩家不移动，给打击反馈留出阅读时间
var _recoil_timer := 0.0        # 攻击反作用力期间不响应移动输入，避免一帧就被拉回
var _input_locked := false      # 对话期间锁输入：不能移动/跳跃/攻击/下砍（见 _on_dialogue_*）
var _spawn_point := Vector2.ZERO
var _anim_time := 0.0           # 视觉动画时钟（待机起伏 / 走步颤步），与物理无关
## M4-56 布料与反冲：披风和下摆的角度、攻击反冲、攻击时甩出来的额外摆幅。
## 这三个都只在 _update_visual_anim / _update_cloth 里写，别在别处碰
var _cape_rot := 0.0
var _tail_rot := 0.0
## 斗篷下摆自己的角度（M4-62 切成两片后才有）：比上段慢半拍、甩得更开
var _hem_rot := 0.0
## 开场砸地后"压扁 → 弹起 → 站定"的计时（M4-62）：结算在 _update_visual_anim 里
var _intro_land_timer := 0.0
## 启动/停止的视觉量（M4-69）：上一帧水平速度、起步前倾、停步顿挫
var _prev_vx := 0.0
var _start_lean := 0.0
var _stop_lean := 0.0
var _start_dip := 0.0
var _stop_dip := 0.0
## 斜切（布被风推着走的横向错位）：上段小、下摆大
var _tail_skew := 0.0
var _hem_skew := 0.0
var _recoil := 0.0
var _cloak_flare := 0.0
var _attack_anim_timer := 0.0   # 挥砍动作剩余时间（表现，不影响 0.12s 判定）
var _attack_anim_total := ATTACK_ANIM_TIME  # 本次动作的总时长，用来算动画进度（三段各不同）
var _attack_anim_kind := 0      # 0 = 横砍，1 = 下劈
var _attack_running := false    # 本次横砍是不是跑着砍（决定动作和是否保留冲量）
var _attack_root_timer := 0.0   # 站砍时把脚钉住的剩余时间
var _pogo_kick_timer := 0.0     # 下劈命中后的"腿弹开"余韵
var _combo_step := 0            # 当前是第几段（0 起）；窗口过期就回到 0
var _combo_window := 0.0        # 连招窗口剩余时间
var _side_hitbox_size := SIDE_HITBOX_SIZE_DEFAULT
var _side_hitbox_offset := SIDE_HITBOX_OFFSET
var _rest_timer := 0.0          # 篝火休息：坐姿剩余时间（期间压扁身体、停止动画覆盖）
var _rest_total := 0.0          # 本次休息的总时长，用来分段：放剑 / 坐 / 起身
var _rest_prop: Node2D          # 休息时放在身侧的剑
var _hurt_timer := 0.0          # 受击缩身剩余时间
var _death_timer := 0.0         # 化雾/等复活剩余时间，走完才复活
var _revive_timer := 0.0        # 复活起身剩余时间
## 死亡后掉在地上的空头盔（挂在关卡里而不是玩家身上：玩家复活要传送走，盔得留在原地）
var _dropped_helmet: Node2D
var _helmet_vy := 0.0
var _helmet_vx := 0.0
var _helmet_spin := 0.0
var _helmet_ground := 0.0
var _helmet_bounces := 1
var _helmet_rest := true
var _helmet_rest_rot := 0.0
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
var _sparks: Node2D
var _slash_core: Line2D         # 横砍内层白芯
var _slash_down_glow: Line2D    # 下劈外层柔光
var _slash_down_core: Line2D    # 下劈内层白芯

@onready var _body: Node2D = $Body
## M4-56：不再给角色手里画剑。斗篷把身体盖住，只露两只脚；
## 攻击靠身前一道白剑痕 + 粒子 + 反冲来表达（组长定稿：拿剑摆着突兀，动作也不好做）。
## 斗篷分前后两层：Cape 在身后跟着风摆；CloakTail 盖在身体上、右侧只留一条缝给内袍。
## M4-59：美术改成组长新画的高质量图，拆成 4 张透明 PNG（盔/身/斗篷左/斗篷右），
## 节点名和以前一样，动画逻辑不用重写；Head 现在能单独点头。
@onready var _cape: Node2D = $Body/Cape
@onready var _cloak_tail: Node2D = $Body/CloakTail
## 斗篷下摆（下段）：单独一层才能"随风飘"，见 _update_cloth
@onready var _cloak_hem: Node2D = $Body/CloakTail/CloakHem
@onready var _head: Node2D = $Body/Head
## 眼睛单独一层（M4-71）：虚空坠落时不亮、死亡时也不亮，只有活着/进关时亮
@onready var _eyes: CanvasItem = $Body/Head/Eyes
@onready var _foot_l: Node2D = $Body/FootL
@onready var _foot_r: Node2D = $Body/FootR
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
	# 三连击每段换判定框尺寸：把 shape 复制一份，免得改到场景里的共享资源
	var side_shape := _hitbox_side.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if side_shape != null and side_shape.shape != null:
		side_shape.shape = side_shape.shape.duplicate()
		_side_hitbox_size = (side_shape.shape as RectangleShape2D).size
	# M1-13：下劈命中查询用的 shape 引用（HitboxDown 的 CollisionShape2D）
	var hb_shape_node := $HitboxDown/CollisionShape2D as CollisionShape2D
	if hb_shape_node != null:
		_hitbox_down_shape = hb_shape_node.shape as RectangleShape2D
	# 挥砍残影的弧线点一次算好，后面只改透明度和显隐（每帧重算没必要）
	# 弧线中心略向前，半径 48，视觉末端接近 64px 横砍判定框边缘；线宽加粗成白色刀光
	_slash.position = Vector2(8, -6)
	_slash.width = 8.0
	_slash.default_color = Color(0.94, 1.0, 1.0, 0.95)
	_slash.points = _make_arc(Vector2.ZERO, SLASH_ARC_RADIUS, 12.0, -1.65, 1.0, 12)
	_slash_down.position = Vector2(5, 8)
	_slash_down.width = 4.0
	_slash_down.default_color = Color(0.94, 1.0, 1.0, 0.9)
	_slash_down.points = _make_arc(Vector2.ZERO, SLASH_DOWN_RADIUS, 9.0, 0.15, 2.95, 10)
	_build_slash_layers()
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
	# 序章只是把玩家模型借过去当"最终形态"展示：跑动画，但不参与物理
	if display_only:
		_update_visual_anim(delta)
		return
	_recoil_timer = maxf(_recoil_timer - delta, 0.0)
	# 空头盔自己往下掉：它挂在关卡里，玩家复活传送走之后还要继续落地
	if not _helmet_rest:
		_update_helmet_prop(delta)
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
		# 手里不再挂剑（M4-56）：只亮一下表示"能砍了"，剑本身留给敌人/场景里的道具
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
	_pogo_kick_timer = maxf(_pogo_kick_timer - delta, 0.0)
	_hurt_timer = maxf(_hurt_timer - delta, 0.0)
	_weapon_flash_timer = maxf(_weapon_flash_timer - delta, 0.0)
	_revive_timer = maxf(_revive_timer - delta, 0.0)
	# 空中后摇一旦落地就立刻解除：地上一帧都不该多等
	if _air_attack_recovery > 0.0:
		_air_attack_recovery = 0.0 if is_on_floor() else maxf(_air_attack_recovery - delta, 0.0)
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
	_slash.width_curve = _make_width_curve(0.02, 1.0, 0.02)
	_slash_down.gradient = gradient
	_slash_down.width_curve = _make_width_curve(0.12, 0.9, 0.10)

	_slash_glow = Line2D.new()
	_slash_glow.name = "SlashGlow"
	_slash_glow.width = 20.0
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
	_slash_core.width = 2.2
	_slash_core.default_color = Color(1.0, 1.0, 1.0, 1.0)
	_slash_core.antialiased = true
	_slash_core.points = _slash.points
	_slash_core.position = _slash.position
	_slash_core.z_index = 1
	_slash_core.visible = false
	_body.add_child(_slash_core)

	_sparks = preload("res://components/slash_sparks.gd").new()
	_sparks.name = "SlashSparks"
	_sparks.z_index = 2
	_body.add_child(_sparks)

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
		# 篝火休息：蹲坐 → 撑地起身；按方向键可随时中断。
		# M4-56 起角色手里不挂剑，所以不再有"把剑放到地上再抓回来"那一段。
		if absf(Input.get_axis("move_left", "move_right")) > 0.1:
			_end_rest_pose()
			return
		_rest_timer = maxf(_rest_timer - delta, 0.0)
		var total := maxf(_rest_total, 1.6)
		var t := total - _rest_timer
		var stand_at := maxf(total - 0.95, 0.6)
		if t < 0.45:
			var p := t / 0.45
			_body.scale = Vector2(float(_facing), lerpf(1.0, 0.86, p))
			_body.position = Vector2(0, lerpf(0.0, 3.0, p))
			_body.rotation = 0.03 * float(_facing) * p
		elif t < stand_at:
			_body.scale = Vector2(float(_facing) * 1.04, 0.60)
			_body.position = Vector2(0, 10)
			_body.rotation = 0.12 * float(_facing)
		else:
			var q := clampf((t - stand_at) / maxf(total - stand_at, 0.01), 0.0, 1.0)
			var rise := clampf((q - 0.35) / 0.65, 0.0, 1.0)
			_body.scale = Vector2(float(_facing), lerpf(0.60, 1.0, rise))
			_body.position = Vector2(0, lerpf(10.0, 0.0, rise) - 4.0 * sin(rise * PI))
			_body.rotation = 0.12 * float(_facing) * (1.0 - rise)
		_update_cloth(delta, 0.0, 0.0)
		return
	_anim_time += delta
	# 开场砸地那一下的计时（M4-62）：放在这里统一递减，_update_visual_anim 只负责摆姿势
	_intro_land_timer = maxf(_intro_land_timer - delta, 0.0)
	_update_start_stop(delta)
	if _body == null:
		return
	var body_x := 0.0
	var body_y := 0.0
	var body_rot := 0.0
	var body_scale := Vector2(1.0, 1.0)
	var tint := Color(1, 1, 1, 1)
	var foot_l := Vector2.ZERO
	var foot_r := Vector2.ZERO
	# 攻击时身前那道白痕的朝向：0 = 横劈弧，负 = 上撩，正 = 下压
	var slash_rot := 0.0
	_hide_slash_layers()

	if _death_timer > 0.0:
		# 死亡（M4-60）：身体不是侧倒，是往下塌、化成一团黑雾散掉，只剩一只空头盔掉在地上。
		# 前 30% 化完，后面身体就当不存在了 —— 盔已经由 _drop_helmet 摘下来自己掉。
		var p := 1.0 - _death_timer / DEATH_ANIM_TIME
		var dissolve := clampf(p / (DEATH_DISSOLVE_TIME / DEATH_ANIM_TIME), 0.0, 1.0)
		body_scale = Vector2(1.0 + 0.22 * dissolve, 1.0 - 0.14 * dissolve)
		body_y = -2.0 * dissolve
		tint = Color(1, 1, 1, 1.0 - dissolve)
	elif _intro_land_timer > 0.0:
		# 开场砸地（M4-62）：砸下去那一下压到最扁，再弹起过头，最后站定。
		# 这三段是"落地的重量"全部来源 —— 少了压扁，落地就只是一次停住。
		var p := 1.0 - _intro_land_timer / INTRO_LAND_TIME
		var squash := 0.0
		if p < 0.30:
			squash = lerpf(0.0, 1.0, p / 0.30)
		elif p < 0.60:
			squash = lerpf(1.0, -0.32, (p - 0.30) / 0.30)
		else:
			squash = lerpf(-0.32, 0.0, (p - 0.60) / 0.40)
		body_scale = Vector2(1.0 + 0.26 * squash, 1.0 - 0.34 * squash)
		body_y = 6.0 * maxf(squash, 0.0)
		_cloak_flare = maxf(_cloak_flare, 0.5 * maxf(squash, 0.0))
	elif _revive_timer > 0.0:
		var p := 1.0 - _revive_timer / REVIVE_ANIM_TIME
		var up := p * p
		body_rot = 1.5 * (1.0 - up)
		body_y = 5.0 * (1.0 - up) - 6.0 * sin(p * PI)
		body_scale = Vector2(0.9 + 0.1 * up, 0.85 + 0.15 * up)
		tint = Color(1, 1, 1, up)
	else:
		if _pogo_active:
			# 下劈：没有剑可挥，改成整个人往下砸 —— 先缩、再拉长，脚下那道白痕朝下
			var wind := 1.0 - clampf((_attack_anim_total - _attack_anim_timer) / 0.09, 0.0, 1.0)
			body_scale = Vector2(1.0 + 0.12 * wind, 1.0 - 0.16 * wind)
			body_y = 2.0 * wind
			slash_rot = 0.0
			_set_down_slash(_attack_anim_timer > 0.0, 0.75 * minf(1.0, _attack_anim_timer / 0.2))
		elif _attack_anim_timer > 0.0:
			var p := 1.0 - _attack_anim_timer / maxf(0.01, _attack_anim_total)
			if _attack_anim_kind == 1:
				# 下劈动作（判定已结束也把动作收完）
				body_scale = Vector2(1.06, 0.94)
				_set_down_slash(p < 0.7, maxf(0.0, 0.75 - p))
			elif _attack_running:
				# 跑砍：身体整体前压，脚下的步子不停；白痕在身前亮一条横的
				# M5-26：跑砍也走"只往下沉"这一套，别把人抬离地面
				var step_run := sin(_anim_time * 12.0)
				body_y = absf(step_run) * 1.2
				body_rot = 0.14
				body_scale = Vector2(1.05, 0.95)
				foot_l = Vector2(step_run * 1.6, absf(step_run) * 1.2)
				foot_r = Vector2(-step_run * 1.6, absf(step_run) * 1.2)
				slash_rot = 0.0
				if p < 0.18:
					body_x = -0.8
				elif p < 0.74:
					var q1 := (p - 0.18) / 0.56
					body_x = 1.2 * q1 * q1
					_set_side_slash(true, sin(minf(q1, 0.9) * PI) * 0.95)
				else:
					var q2 := (p - 0.74) / 0.26
					body_x = 1.2 * (1.0 - q2)
					_set_side_slash(true, (1.0 - q2) * 0.5)
			elif _combo_step == 1:
				# 第二段·上撩：身体先沉下去，再整体往上一弹，白痕自下往上扫
				slash_rot = -0.85
				if p < 0.20:
					var q2 := p / 0.20
					body_y = 2.2 * q2
					body_scale = Vector2(1.0 + 0.06 * q2, 1.0 - 0.10 * q2)
				elif p < 0.72:
					var q3 := (p - 0.20) / 0.52
					var swing_up := q3 * q3
					body_y = lerpf(2.2, -2.0, swing_up)
					body_scale = Vector2(0.98, 1.06)
					_set_side_slash(true, sin(minf(q3, 0.9) * PI) * 0.92)
				else:
					var q4 := (p - 0.72) / 0.28
					body_y = lerpf(-2.0, 0.0, q4)
					_set_side_slash(true, (1.0 - q4) * 0.5)
			elif _combo_step == 2:
				# 第三段·前刺：整个人往前扎出去，斗篷被甩在身后
				var thrust := 0.0
				if p < 0.30:
					var q5 := p / 0.30
					body_x = -1.6 * q5
					body_scale = Vector2(0.96, 1.02)
				elif p < 0.60:
					var q6 := (p - 0.30) / 0.30
					var push := 1.0 - pow(1.0 - q6, 3.0)
					thrust = push
					body_x = lerpf(-1.6, 3.2, push)
					body_rot = -0.12 * push
					_set_side_slash(true, sin(minf(q6, 0.9) * PI) * 0.95)
				else:
					var q7 := (p - 0.60) / 0.40
					body_x = lerpf(3.2, 0.0, q7)
					body_rot = -0.12 * (1.0 - q7)
					_set_side_slash(true, (1.0 - q7) * 0.6)
				slash_rot = -0.25
				_cloak_flare = maxf(_cloak_flare, thrust) * 0.8
			elif p < 0.26:
				# 第一段·横劈 蓄力：重心后坐，斗篷先被拉开
				var q := p / 0.26
				body_x = -1.8 * q
				body_rot = -0.16 * q
				body_scale = Vector2(0.98, 1.02)
				_cloak_flare = maxf(_cloak_flare, q * 0.7)
			elif p < 0.78:
				# 挥出：人往前压回去，白痕在身前扫过；斗篷被这一下甩起来
				var q := (p - 0.26) / 0.52
				var swing := q * q
				body_x = lerpf(-1.8, 1.6, swing)
				body_rot = lerpf(-0.16, 0.10, swing)
				_set_side_slash(true, sin(minf(q, 0.9) * PI) * 0.95)
				_cloak_flare = maxf(_cloak_flare, sin(minf(q, 0.9) * PI) * 0.9)
			else:
				# 收招：回到站姿
				var q := (p - 0.78) / 0.22
				body_x = lerpf(1.6, 0.0, q)
				body_rot = lerpf(0.10, 0.0, q)
				_set_side_slash(true, (1.0 - q) * 0.55)
		elif not is_on_floor():
			# 空中（M4-62 重做）：不做伸缩（组长说那是"橡皮人"），只留一点前后倾，
			# 上升绷直一点、下落重心往前，剩下的交给斗篷去飘。
			if velocity.y < 0.0:
				body_rot = -0.06 * float(_facing)
			else:
				body_rot = 0.10 * float(_facing)
		elif absf(velocity.x) > 30.0:
			# 走路（M4-62 重做）：不做伸缩。走路只做两件事 ——
			# 身体一上一下地颠（落脚的重量），头跟着摆（_update_head 里做），斗篷跟着风飘。
			# M5-26（组长反馈"有时候看着悬空在地面上"）：这一颠原来写成 -1.6（往上抬），
			# 而整幅画（含脚）都挂在 Body 上，人每走一步就被抬起来 1.6px —— 看着就是离地。
			# 改成**只往下沉**（abs 取正），像落脚时把重心压下去，脚永远踩在地上。
			var step := sin(_anim_time * 12.0)
			body_y = absf(step) * 0.5
			foot_l = Vector2(step * 2.4, absf(step) * 0.5)
			foot_r = Vector2(-step * 2.4, absf(step) * 0.5)
			# M4-69 启动/停止：起步时身子先往前压一点（像被自己拽出去），
			# 停步时反过来往后坐一下再回正。这个量只看"有没有在加速/减速"，
			# 稳态跑动时它是 0，所以不会让跑动变成一直斜着。
			body_rot += _start_lean
			body_y += _start_dip
			body_scale = Vector2(1.0 + 0.03 * _start_dip, 1.0 - 0.05 * _start_dip)
		else:
			# 待机：呼吸起伏，斗篷轻轻起伏
			# M5-26：呼吸也只许**往下**（见走路那段的注释 —— 整幅画都在 Body 上，往上抬就是离地）
			var breath := sin(_anim_time * 2.0)
			body_y = absf(breath) * 0.3
			# 刚停下来那几帧：身子往前一顿再收回来（M4-69 的"停止"）
			body_rot += _stop_lean
			body_y += _stop_dip
			foot_l = Vector2(0.0, absf(breath) * 0.2)
			foot_r = Vector2(0.0, absf(breath) * 0.2)
		# 受击：短暂缩身 + 泛红，叠加在其它状态上
		if _hurt_timer > 0.0:
			var k := _hurt_timer / HURT_ANIM_TIME
			body_rot += sin(_hurt_timer * 45.0) * 0.18 * k
			tint = tint.lerp(Color(1.0, 0.62, 0.62, 1.0), 0.5 * k)

	# 攻击反冲：打完这一下人会往回收一点。它不是"位移"，只是身体在局部坐标里退半步，
	# 物理位置不动 —— 否则会把手感搅乱（位移归 _physics_process 管）
	_recoil = maxf(_recoil - delta * 7.0, 0.0)
	body_x += -2.6 * _recoil
	_cloak_flare = maxf(_cloak_flare - delta * 2.2, 0.0)

	# 命中顿帧时压扁一点，让"停住"不是单纯的卡帧，而是有受力形变
	if _pogo_kick_timer > 0.0:
		var kk := _pogo_kick_timer / 0.18
		body_scale = Vector2(body_scale.x * (1.0 + 0.12 * kk), body_scale.y * (1.0 - 0.10 * kk))
		body_y -= 2.0 * kk
	if _hitstop_timer > 0.0:
		body_scale = Vector2(body_scale.x * 1.10, body_scale.y * 0.88)

	_body.position = Vector2(body_x, body_y)
	_body.rotation = body_rot
	_body.scale = Vector2(float(_facing) * body_scale.x, body_scale.y)
	_body.modulate = tint
	_foot_l.position = Vector2(-2.6, 10.6) + foot_l
	_foot_r.position = Vector2(2.6, 10.6) + foot_r
	_update_head(delta, body_y, body_rot)
	_slash.rotation = slash_rot
	_update_cloth(delta, body_x, _cloak_flare)
	# 刚捡到铁剑时整身亮一下，代替过去"手里那把剑发光"
	if _weapon_flash_timer > 0.0:
		tint = tint.lerp(Color(1.5, 1.6, 1.4, 1.0), 0.35)
		_body.modulate = tint

## 启动 / 停止（M4-69）：从"速度变化量"里读出来，专门给视觉用，不碰物理。
## 起步那一下身子往前压、停步那一下往前一顿再收回，靠这两个量在走路/待机里叠加。
## 为什么用加速度而不是"按了键"：按住方向键跑起来以后加速度是 0，
## 这时必须归零，否则人会一直斜着跑（看起来像瘸了）。
func _update_start_stop(delta: float) -> void:
	var acc := 0.0
	if delta > 0.0001:
		acc = (velocity.x - _prev_vx) / delta
	_prev_vx = velocity.x
	var k_in := 1.0 - exp(-14.0 * delta)     # 起步要快，才有"被拽出去"的感觉
	var k_out := 1.0 - exp(-7.0 * delta)     # 收回来慢一点，读得出余味
	var toward := signf(velocity.x) if absf(velocity.x) > 1.0 else float(_facing)
	var pushing := acc * toward            # >0 = 往当前方向加速
	var target_start := 0.0
	var target_stop := 0.0
	if is_on_floor():
		if pushing > 250.0:
			target_start = 0.11 * float(_facing) * clampf(pushing / 1600.0, 0.0, 1.0)
		if absf(velocity.x) < RUN_SPEED * 0.9 and pushing < -300.0:
			target_stop = 0.09 * float(_facing) * clampf(-pushing / 1600.0, 0.0, 1.0)
	_start_lean = lerpf(_start_lean, target_start, k_in if target_start != 0.0 else k_out)
	_stop_lean = lerpf(_stop_lean, target_stop, k_in if target_stop != 0.0 else k_out)
	# 顿挫：起步时身体往下坐一点（脚在蹬），停止时也坐一下（重量压回去）
	_start_dip = lerpf(_start_dip, absf(target_start) / 0.11 * 0.9, k_in if target_start != 0.0 else k_out)
	_stop_dip = lerpf(_stop_dip, absf(target_stop) / 0.09 * 0.8, k_in if target_stop != 0.0 else k_out)

## 头比身体慢半拍（M4-59）：身体一冲，头先留在原地再跟上来，这一下的延迟就是"重量"。
## M4-62：走路时头要跟着步频摆（组长要的"正常的摆动"）—— 左右点一点、上下慢半拍，
## 不能再只靠身体上下颠，那样看起来像整块木头在跳。
func _update_head(delta: float, body_y: float, body_rot: float) -> void:
	if _head == null:
		return
	var target := -body_rot * 0.45
	if not is_on_floor():
		# 上升时头往后仰一点、下落时往前点一点，跟随跳跃方向
		target += clampf(velocity.y / 1400.0, -1.0, 1.0) * float(_facing) * -0.30
	elif absf(velocity.x) > 30.0:
		# 走路：每一步点一下头，幅度小、频率跟脚步一致
		target += sin(_anim_time * 12.0) * 0.075 * float(_facing)
	_head.rotation = lerpf(_head.rotation, target, 1.0 - exp(-9.0 * delta))
	# 竖直方向也反过来跟一点：身体往下坐，头还在上面
	var lag := -body_y * 0.35
	if absf(velocity.x) > 30.0:
		# 走路时头自己也有个小起伏，和身体的颠错开半个拍子，看着才不是连体的
		lag += sin(_anim_time * 12.0 - 0.7) * 0.35
	_head.position = HEAD_BASE + Vector2(0.0, lag)

## 布料（M4-62 重做）：斗篷分上段和下摆两片，两片一直有风。
## 组长原话是"帐篷（斗篷）需要随风飘，这样才有反馈" —— 风不是"跑起来才有的奖励"，
## 站着待机也在飘。摆动不只靠旋转：
##   旋转 = 上沿钉在肩上、整片往下甩，像合页；
##   斜切(skew) = 上沿不动、下沿横向错开 —— 这才是布"被风推着走"的样子。
## 两者叠起来才是飘；只用旋转会像一块硬板在摇。下摆比上段甩得狠、频率也慢半拍。
func _update_cloth(delta: float, body_x: float, flare: float) -> void:
	if _cloak_tail == null:
		return
	# 正向旋转 = 下摆往身后甩（局部 +x 是面朝方向）
	var fx := float(_facing) * clampf(velocity.x / 300.0, -1.0, 1.0)
	# 风：两个正弦叠起来，周期不同才不会像节拍器
	var wind := sin(_anim_time * 1.9) * 0.075 + sin(_anim_time * 3.1 + 1.2) * 0.035
	var gust := sin(_anim_time * 1.9 - 0.9) * 0.085 + sin(_anim_time * 2.6 + 0.4) * 0.035
	if absf(velocity.x) > 30.0:
		# 走一步被带起来一下，和步频同步
		wind += sin(_anim_time * 12.0) * 0.055
		gust += sin(_anim_time * 12.0 - 0.6) * 0.075
	var target_top := fx * 0.09 + wind
	var target_hem := fx * 0.14 + wind * 1.9
	var target_skew_top := fx * 0.05 + gust * 0.6
	var target_skew_hem := fx * 0.10 + gust
	if not is_on_floor():
		# 空中：下摆被风往上掀，速度越快掀得越平、越往后错。
		# 注意不能整体上移 —— 一吊起来下摆就离开脚，身体那根黑柱子会裸露一大截。
		var vy := clampf(velocity.y / 900.0, -1.0, 1.0)
		target_top += 0.10 * vy
		target_hem += 0.30 * vy + 0.08
		target_skew_hem += 0.16 * vy
	# 攻击甩出来的额外摆幅，叠加在速度摆幅上
	target_top += flare * 0.16
	target_hem += flare * 0.30
	target_skew_hem += flare * 0.18
	_tail_rot = lerpf(_tail_rot, target_top, 1.0 - exp(-6.0 * delta))
	_hem_rot = lerpf(_hem_rot, target_hem, 1.0 - exp(-4.5 * delta))
	_tail_skew = lerpf(_tail_skew, target_skew_top, 1.0 - exp(-6.0 * delta))
	_hem_skew = lerpf(_hem_skew, target_skew_hem, 1.0 - exp(-4.5 * delta))
	# 身后那片斗篷（Cape）跟着一起摆，幅度小一点：它挡在身体后面，
	# 甩太开会把黑影露出一条缝。身体现在是从"没斗篷"那张图拿的完整黑影，
	# 所以就算真露出来一点，看到的也是完整躯干（M4-70）。
	_cape_rot = lerpf(_cape_rot, target_top * 0.7, 1.0 - exp(-5.0 * delta))
	if _cape != null:
		_cape.rotation = _cape_rot
		_cape.skew = _tail_skew * 0.7
	_cloak_tail.rotation = _tail_rot
	_cloak_tail.skew = _tail_skew
	if _cloak_hem != null:
		_cloak_hem.rotation = _hem_rot
		_cloak_hem.skew = _hem_skew
		# 下摆再带一点"张开/收拢"：布被风灌进去会胀，收风会贴回身上。
		# 幅度很小（±6%），但三条信号叠起来（转、斜、胀）才真的像布在飘。
		_cloak_hem.scale = Vector2(1.0 + 0.06 * _hem_skew * 4.0, 1.0)

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
	# M5-07（组长反馈「空中一直按攻击会无限攻击」）：
	# 以前这里只靠 Input.is_action_just_pressed 判断，但键盘长按的重复事件（echo）
	# 每一帧都会让 just_pressed 再变 true 一次 —— 按住 J 就等于每帧都在"重新按下"，
	# 空中的下劈又只有 0.1 秒冷却，于是变成了连发。
	# 现在认两种"按下"：真正的按下沿（just_pressed），或者"这一轮还没出过刀"的按下状态；
	# 只要这一轮已经出过刀，按住不放就不会再出刀，松开才解锁。
	var pressed := Input.is_action_pressed("attack")
	var just := Input.is_action_just_pressed("attack")
	if not pressed and not just:
		_attack_press_latch = false
		return
	if pressed and _attack_press_latch:
		return
	# 最短间隔统一由冷却卡：狂按不会跳段，也不会把连招打成每帧一次
	if _attack_cooldown_timer > 0.0:
		return
	# 下砍后摇期间不触发任何攻击（防落地瞬间秒横砍）
	if _pogo_end_lag_timer > 0.0:
		return
	# 空中攻击后的硬后摇：落地前不许再出下一刀，避免"按住 J = 空中连劈"
	if _air_attack_recovery > 0.0:
		return
	_attack_press_latch = true
	if is_on_floor():
		# 地面上：按住下键(S) + 攻击 = 朝下劈；只按攻击 = 前方横砍（或接下一段连招）
		if Input.is_action_pressed("move_down"):
			_start_down_slash()
		else:
			_start_side_slash(_combo_advance())
	else:
		# 空中：按攻击一律是下劈（踩敌反弹）。
		# M4-23 组长反馈：原来空中要求“按住 S + J”才下劈，玩家在稻草人头上按 J 只挥了
		# 一记横砍，人接着往下掉，看起来就是“砍到了却不反弹”。空中不需要再按方向键。
		_start_pogo()
		_air_attack_recovery = AIR_ATTACK_RECOVERY

## 地面上的下劈：站在原地朝脚下挥一刀，能打到贴地的矮目标（不再靠下落触发）
func _start_down_slash() -> void:
	_attack_dir = _facing
	_attack_cooldown_timer = ATTACK_COOLDOWN
	_attack_active_timer = ATTACK_ACTIVE_TIME
	_attack_anim_timer = ATTACK_ANIM_TIME
	_attack_anim_total = ATTACK_ANIM_TIME
	_attack_anim_kind = 1
	_attack_running = false
	_hit_this_swing.clear()
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = true
	_pogo_active = false
	GameManager.play_sfx("swing", -2.0, 0.82)
	# 反冲：没有剑可挥，这一下的"力气"全靠身体退半步 + 斗篷被甩起来表达
	_recoil = 1.0
	_cloak_flare = maxf(_cloak_flare, 0.9)
	# 下劈同样要有粒子：沿脚下方那条白痕飞散几缕
	if _sparks != null:
		_sparks.call("burst", _slash_down.points, _attack_dir)

# 地面横砍。stage 是三连击的第几段（0 横劈 / 1 反手上撩 / 2 前刺）。
# 每段的弧线、前冲、判定框、动作时长都不同；伤害与最短间隔不变，只改手感。
func _start_side_slash(stage: int = 0) -> void:
	_attack_dir = _facing  # 锁定出手朝向
	_combo_step = clampi(stage, 0, COMBO_MAX - 1)
	_attack_cooldown_timer = ATTACK_COOLDOWN
	_attack_active_timer = ATTACK_ACTIVE_TIME
	_attack_anim_timer = COMBO_STAGE_TIME[_combo_step]
	_attack_anim_total = COMBO_STAGE_TIME[_combo_step]
	_combo_window = COMBO_STAGE_TIME[_combo_step] + COMBO_WINDOW
	_attack_anim_kind = 0

	# 每段换判定框：上撩偏上、前刺更远更窄
	var box: Dictionary = COMBO_STAGE_HITBOX[_combo_step]
	_side_hitbox_offset = box["offset"]
	_side_hitbox_size = box["size"]
	var side_shape := _hitbox_side.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if side_shape != null and side_shape.shape is RectangleShape2D:
		(side_shape.shape as RectangleShape2D).size = _side_hitbox_size

	# 跑着砍 / 站着砍：动作、冲量、是否钉住脚都不一样
	_attack_running = _combo_step == 0 and is_on_floor() and absf(velocity.x) > RUN_SLASH_SPEED
	if _attack_running:
		_attack_root_timer = 0.0
		# 补前冲但不超过跑速上限：否则连砍就能跑得比跑步还快
		velocity.x = float(_attack_dir) * minf(maxf(absf(velocity.x), RUN_SPEED * 0.6) + RUN_SLASH_LUNGE, RUN_SPEED)
	elif _combo_step == 2 and is_on_floor():
		# 前刺要往前踏一步：不钉脚，给一口较长的前冲
		_attack_root_timer = 0.0
		velocity.x = float(_attack_dir) * minf(absf(velocity.x) + COMBO_STAGE_LUNGE[_combo_step], RUN_SPEED)
	else:
		# 站定把脚钉住；空中挥砍保留原有水平速度，不要"后坐力"把人刹住
		_attack_root_timer = RUN_SLASH_ROOT_TIME if is_on_floor() else 0.0

	_hit_this_swing.clear()
	_hitbox_side.monitoring = true
	_hitbox_down.monitoring = false
	_pogo_active = false
	_apply_side_slash_shape()
	GameManager.play_sfx("swing", -2.0, COMBO_STAGE_PITCH[_combo_step])
	# 反冲 + 斗篷被这一下甩起来：没有手臂和剑，全靠这两件读出"打了"的力气
	_recoil = 1.0 * (1.0 + 0.25 * float(_combo_step))
	_cloak_flare = maxf(_cloak_flare, 0.9)
	if _sparks != null:
		_sparks.call("burst", _slash.points, _attack_dir)

## 按当前段重建刀弧（三层 Line2D 用同一组点，一起转）
func _apply_side_slash_shape() -> void:
	var spec: Dictionary = COMBO_STAGE_ARC[_combo_step]
	var radius: float = spec["radius"]
	var rot: float = spec["rot"]
	if _attack_running:
		rot += RUN_SLASH_ARC_ROT
	var pts := _make_arc(Vector2.ZERO, radius, 12.0, spec["from"], spec["to"], 12)
	_slash.points = pts
	_slash.rotation = rot
	if _slash_glow != null:
		_slash_glow.points = pts
		_slash_glow.rotation = rot
	if _slash_core != null:
		_slash_core.points = pts
		_slash_core.rotation = rot


# 空中：下砍（pogo）—— 只朝脚下判定，不再强制加速下坠
func _start_pogo() -> void:
	_attack_dir = _facing  # 锁定出手朝向
	_pogo_active = true
	_attack_anim_timer = ATTACK_ANIM_TIME + 0.1
	_attack_anim_total = ATTACK_ANIM_TIME + 0.1
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
	# M5-07：下劈砍到东西的那一下补一层"剑魂"——白蓝的刀光 + 光斑 + 往上飘的魂丝。
	# 以前只有一个腿部弹开的动作，看不出"这一刀劈进了什么东西"。
	_spawn_pogo_soul(global_position + Vector2(float(_attack_dir) * 24.0, 16.0))
	velocity.y = POGO_BOUNCE_VELOCITY
	_end_pogo()
	_pogo_kick_timer = 0.18
	_camera_dip()
	_attack_cooldown_timer = POGO_RETRIGGER_COOLDOWN
	EventBus.log_event("pogo_bounce", {"target": target.name})

## 下劈命中的"剑魂"：一个 0.26 秒的小爆发，纯代码画，不读贴图（除了现成的径向光斑）。
## 挂在关卡里而不是挂在玩家身上：人物下劈后马上被弹开，挂在身上特效会跟着人飞走。
func _spawn_pogo_soul(point: Vector2) -> void:
	var level := get_parent()
	if level == null:
		return
	var root := Node2D.new()
	root.name = "PogoSoul"
	root.position = point
	root.z_index = 3
	var glow := Sprite2D.new()
	glow.texture = _puff_texture()
	glow.modulate = Color(0.70, 0.90, 1.0, 0.80)
	glow.scale = Vector2(3.4, 2.6)
	root.add_child(glow)
	# 两道斜着交叉的刀光：读作"一刀劈开"，比一个圆圈有方向
	for ang in [-0.62, 0.62]:
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color(0.86, 0.96, 1.0, 0.95)
		line.points = PackedVector2Array([Vector2(-20, -7), Vector2(0, 0), Vector2(20, -7)])
		line.rotation = float(ang)
		root.add_child(line)
	# 往上飘的魂丝
	for i in range(3):
		var streak := Line2D.new()
		streak.width = 1.4
		streak.default_color = Color(0.62, 0.84, 1.0, 0.65)
		var x := -6.0 + 6.0 * float(i)
		streak.points = PackedVector2Array([Vector2(x, 0), Vector2(x + 2.0, -17.0)])
		root.add_child(streak)
	level.add_child(root)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "scale", Vector2(1.75, 1.75), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 0.0, 0.26)
	tw.chain().tween_callback(root.queue_free)

## 相机下压：找不到相机就静默跳过（无头测试场景可能没有）
func _camera_dip() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.has_method("dip"):
		cam.call("dip", 6.0, 0.16)

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
	# 连招：动作结束后还留一段窗口可以接下一段
	if _combo_window > 0.0:
		_combo_window = maxf(_combo_window - delta, 0.0)
		if _combo_window <= 0.0:
			_combo_step = 0
	if _attack_active_timer <= 0.0:
		return
	_attack_active_timer -= delta
	if _attack_active_timer <= 0.0:
		_end_attack()


## 决定这次按 J 接第几段：窗口内、过了最短间隔、且没到第三段才往后接，否则重新起手
func _combo_advance() -> int:
	if _combo_window > 0.0 and _combo_step + 1 < COMBO_MAX:
		return _combo_step + 1
	return 0

func _end_attack() -> void:
	_attack_active_timer = 0.0
	_hitbox_side.monitoring = false
	_hitbox_down.monitoring = false
	_hit_this_swing.clear()

func _update_hitbox_pose() -> void:
	# 横砍/下砍判定框按"攻击锁定朝向"定位：攻击中按反方向键只改移动，不改变已出手的攻击方向
	_hitbox_side.position = Vector2(_side_hitbox_offset.x * _attack_dir, _side_hitbox_offset.y)
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

## 篝火休息（M5-02 组长新规则）：一次只回 1 颗心，人站在原地不动（不再蹲坐/放剑/起身）。
## 拆成按颗回的函数，以后药剂、泉水之类也能用，不必一律回满。
func heal(amount: int = 1) -> int:
	if _is_dead:
		return 0
	var before := hp
	hp = clampi(hp + amount, 0, MAX_HP)
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

## 中途起身：把先前收起来的休息道具清掉
func _end_rest_pose() -> void:
	_rest_timer = 0.0
	_free_ground_sword()

## 开场从虚空砸到地上之后调用（M4-62）：播"压扁 → 弹起 → 站定"，
## 由关卡在落地那一帧调，播完玩家自然回到常规待机。
## 落地声不在这里放：真正的落地冲击已经由 _update_landing_dust 按速度放过了，再加一下会叠成一坨。
func play_intro_land() -> void:
	_intro_land_timer = INTRO_LAND_TIME

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
	# 死亡时眼睛要灭（组长要求），空盔里不该还亮着两粒
	if _eyes != null:
		_eyes.visible = false
	velocity = Vector2(0, -140.0)
	_pogo_active = false
	_pogo_requested = false
	_hitbox_side.set_deferred("monitoring", false)
	_hitbox_down.set_deferred("monitoring", false)
	_hit_this_swing.clear()
	# 表现：先把头盔摘下来扔出去，再让身体化雾。顺序反过来的话，
	# 盔会跟着正在消失的身体一起淡掉，看不见"掉在地上"。
	_drop_helmet()
	_spawn_death_mist()
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
	_attack_press_latch = false
	_air_attack_recovery = 0.0
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
	_body.visible = true
	# 复活时眼睛重新亮起来（死亡时灭了，见 _die）
	if _eyes != null:
		_eyes.visible = true

## 把头盔从头上摘下来扔到地上（M4-60，组长定的死亡表现）。
## 拿头部贴图另起一个 Node2D 挂在关卡里：给一点向上的初速和自旋，落到"死的时候脚下那条线"
## 弹一下再歪着躺住。挂在关卡里而不是玩家身上，是因为复活要传送回出生点 ——
## 盔得留在死的地方，不然就成了"尸体跟着人一起飞走"。
func _drop_helmet() -> void:
	var skull := _head.get_node_or_null("Skull") as Sprite2D
	if skull == null or skull.texture == null:
		return
	if _dropped_helmet != null and is_instance_valid(_dropped_helmet):
		_dropped_helmet.queue_free()
	_dropped_helmet = null
	var level := get_parent()
	if level == null:
		return
	# 贴图里"头盔"这一块的中心：贴图 200px 高 = 28 单位，1px = 0.14
	var px_center := Vector2(53.5, 51.4)
	var sc := Vector2(0.14 * float(_facing), 0.14)
	var holder := Node2D.new()
	holder.name = "DroppedHelmet"
	var sp := Sprite2D.new()
	sp.texture = HELMET_EMPTY_TEX
	sp.centered = false
	sp.scale = sc
	sp.position = -px_center * sc
	holder.add_child(sp)
	level.add_child(holder)
	# 刚摘下来那一帧必须和头上那只重合：直接取"贴图里那个点现在的世界坐标"
	holder.global_position = skull.get_global_transform() * px_center
	# 插到玩家前面一位：躺在地上要压在玩家脚下，别盖住活着的角色
	level.move_child(holder, get_index())
	_dropped_helmet = holder
	_helmet_vx = -float(_facing) * 26.0
	_helmet_vy = -155.0
	_helmet_spin = float(_facing) * 2.2
	# 躺住的高度不再用"死的时候脚下"直接算（M5-05 组长反馈：从悬崖掉下去死的那一次，
	# 盔停在半空不掉，看着像挂在墙上）。改成从盔的位置往下打一条射线，
	# 打到地面就落在地面上；打不到（脚下是深渊）就一直往下掉，掉出画面再收掉。
	_helmet_ground = _find_helmet_ground(holder.global_position)
	_helmet_bounces = 1
	_helmet_rest = false
	_helmet_rest_rot = float(_facing) * 1.35

## 身体化雾：从身上爆一团深灰的烟，往上飘着散掉。
## 挂在关卡而不是身体上 —— 身体正在淡出，挂在身上会被 modulate 一起乘成透明。
func _spawn_death_mist() -> void:
	var level := get_parent()
	if level == null:
		return
	var mist := GPUParticles2D.new()
	mist.name = "DeathMist"
	mist.one_shot = true
	mist.amount = 20
	mist.lifetime = 0.65
	mist.explosiveness = 0.85
	mist.local_coords = false
	mist.texture = _puff_texture()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 70.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 115.0
	mat.gravity = Vector3(0, -70.0, 0)
	mat.scale_min = 0.20
	mat.scale_max = 0.65
	# 深灰带一点冷色：纯黑在深色背景上根本看不见，亮一点才读得出"烟"
	mat.color = Color(0.16, 0.18, 0.22, 0.45)
	mist.process_material = mat
	level.add_child(mist)
	mist.global_position = _body.global_position + Vector2(0, -4)
	mist.emitting = true
	# 粒子放完自己删掉，不然每死一次就攒一堆节点
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(mist):
		mist.queue_free()

## 一粒烟的形状：中间实、边缘透明的小圆（不用画图，GradientTexture2D 径向填色就够）
func _puff_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.95))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.4, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

## 空盔的落点：从盔的位置往下打 900px（比一屏还高）找地面，也是"为什么用射线"——
## 直接拿死亡坐标 +9 的话，掉进坑里死的那次脚下根本没有地面，盔就会停在半空。
## 打不到返回 INF，交给 _update_helmet_prop 一直掉下去。
func _find_helmet_ground(from: Vector2) -> float:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 900.0), 1)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return float((hit["position"] as Vector2).y) - 1.0

## 地上的空头盔：受重力往下掉，撞地弹一次，再歪着躺住
func _update_helmet_prop(delta: float) -> void:
	if _dropped_helmet == null or not is_instance_valid(_dropped_helmet):
		_helmet_rest = true
		return
	_helmet_vy += DEATH_HELMET_GRAVITY * delta
	_helmet_vx = move_toward(_helmet_vx, 0.0, 300.0 * delta)
	var pos := _dropped_helmet.global_position + Vector2(_helmet_vx, _helmet_vy) * delta
	# 脚下一片空：跟着身体一起往下掉，掉出视野就淡掉收走（别让它在关卡外面永远存在）
	if is_inf(_helmet_ground):
		if pos.y > global_position.y + 900.0:
			var fade := maxf(_dropped_helmet.modulate.a - delta * 2.0, 0.0)
			_dropped_helmet.modulate.a = fade
			if fade <= 0.0:
				_dropped_helmet.queue_free()
				_dropped_helmet = null
				_helmet_rest = true
				return
		_dropped_helmet.global_position = pos
		_dropped_helmet.rotation += _helmet_spin * delta
		return
	if pos.y >= _helmet_ground:
		pos.y = _helmet_ground
		if _helmet_bounces > 0:
			_helmet_bounces -= 1
			_helmet_vy = -absf(_helmet_vy) * 0.34
			_helmet_vx *= 0.55
			_helmet_spin *= -0.55
		else:
			_helmet_vy = 0.0
			_helmet_vx = 0.0
			_helmet_rest = true
	_dropped_helmet.global_position = pos
	_dropped_helmet.rotation += _helmet_spin * delta
	if _helmet_rest:
		# 停住时把角度收一收：歪着躺像空壳掉在地上，正着立着像还没死
		_dropped_helmet.rotation = lerpf(_dropped_helmet.rotation, _helmet_rest_rot, 0.35)

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
