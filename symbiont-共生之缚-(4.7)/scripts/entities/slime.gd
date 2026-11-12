extends CharacterBody2D
## 巡逻史莱姆（M1-02）—— 第一个真实敌人
##
## 行为：地面左右巡逻（碰墙 / 前方无地面掉头）；玩家进入水平追击距离后
## 朝玩家走，超出范围恢复巡逻（带滞回防来回抖动）。
## 伤害：身体上的 ContactArea（mask=2 只探测玩家）在玩家进入时调用
## player.take_damage(attack_damage, self)，并带冷却防止连续扣血。
## 受击：take_damage(amount) 扣血 + 闪红约 0.1s；血归零 → emit enemy_killed
## → 脚下生成肢体拾取物 → queue_free()。
## 属性（hp/speed/attack_damage）来自 DataDB.get_enemy("patrol_slime")，
## 读不到时回退脚本内安全默认值；行为常数放脚本顶部便于调参。

const ENEMY_ID := "patrol_slime"

# ---- 数据缺失时的安全默认值（正常应来自 DataDB，见 _load_stats）----
const DEFAULT_HP := 8
const DEFAULT_SPEED := 40.0
const DEFAULT_ATTACK_DAMAGE := 1

# ---- 行为常数（可调，不属于数值表，故不写进数据文件）----
const GRAVITY := 1600.0
const MAX_FALL_SPEED := 900.0
const CHASE_DISTANCE := 200.0        # 玩家水平距离 <= 该值 → 开始追击
const LOST_DISTANCE := 280.0         # 追击中玩家超出该距离 → 恢复巡逻（滞回，防边缘来回抖动）
const SAME_FLOOR_TOLERANCE := 48.0   # 与玩家垂直差在范围内视为同一层（防隔层追击）
const EDGE_CHECK_FORWARD := 16.0     # 边缘检测射线水平前伸量（在脚前方探地）
const EDGE_CHECK_DOWN := 16.0        # 边缘检测射线垂直下探量（须越过脚底平面）

# ---- 接触伤害 ----
const CONTACT_DAMAGE_COOLDOWN := 0.8 # 两次接触伤害的最小间隔（防连续扣血）

# ---- 受击表现 ----
const FLASH_TIME := 0.1              # 受击闪红时长
const HIT_FLASH_COLOR := Color(1.0, 0.3, 0.3)

const LIMB_PICKUP_SCENE := preload("res://scenes/items/limb_pickup.tscn")

var hp: int
var speed: float
var attack_damage: int

var _facing := 1             # 1 朝右，-1 朝左
var _is_chasing := false
var _contact_cooldown := 0.0
var _flash_timer := 0.0
var _base_color: Color
var _is_dying := false

@onready var _body: Polygon2D = $Body
@onready var _contact_area: Area2D = $ContactArea
@onready var _edge_check: RayCast2D = $EdgeCheck

func _ready() -> void:
	# 玩家攻击判定通过 damageable 分组识别可受击目标（见 player.gd _apply_hit）
	add_to_group("damageable")
	_load_stats()
	_base_color = _body.color
	_contact_area.body_entered.connect(_on_contact_area_body_entered)
	_aim_edge_ray()
	# 复用 EventBus 现成信号：敌人登场广播，M2 的生成特效 / 计数可直接订阅
	EventBus.enemy_spawned.emit(self)

func _physics_process(delta: float) -> void:
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)
	_apply_gravity(delta)
	_aim_edge_ray()
	_decide_horizontal()
	move_and_slide()
	_handle_patrol_turn()

func _process(delta: float) -> void:
	_update_flash(delta)

# ---- 数据驱动属性 ----

func _load_stats() -> void:
	var data := DataDB.get_enemy(ENEMY_ID)
	if data.is_empty():
		push_warning("Slime: DataDB 缺少敌人数据 %s，使用安全默认值 hp=%d speed=%f attack=%d" % [ENEMY_ID, DEFAULT_HP, DEFAULT_SPEED, DEFAULT_ATTACK_DAMAGE])
		hp = DEFAULT_HP
		speed = DEFAULT_SPEED
		attack_damage = DEFAULT_ATTACK_DAMAGE
		return
	hp = int(data.get("hp", DEFAULT_HP))
	speed = float(data.get("speed", DEFAULT_SPEED))
	attack_damage = int(data.get("attack_damage", DEFAULT_ATTACK_DAMAGE))

# ---- 移动 ----

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

func _decide_horizontal() -> void:
	# 追击（带滞回）：已在追击中按 LOST_DISTANCE 判断脱离，否则按 CHASE_DISTANCE 判断进入
	var player := _get_player()
	if _is_chasing:
		if player == null or not _player_in_range(player, LOST_DISTANCE):
			_is_chasing = false
		else:
			_update_facing_toward(player.global_position.x)
			velocity.x = float(_facing) * speed
			return
	elif player != null and _player_in_range(player, CHASE_DISTANCE):
		_is_chasing = true
		_update_facing_toward(player.global_position.x)
		velocity.x = float(_facing) * speed
		return
	# 巡逻：按当前朝向匀速前进
	velocity.x = float(_facing) * speed

func _update_facing_toward(target_x: float) -> void:
	var dir := signf(target_x - global_position.x)
	if dir != 0.0:
		_facing = int(dir)

func _player_in_range(player: Node2D, distance: float) -> bool:
	var horizontal_dist := absf(player.global_position.x - global_position.x)
	var vertical_dist := absf(player.global_position.y - global_position.y)
	return horizontal_dist <= distance and vertical_dist <= SAME_FLOOR_TOLERANCE

func _get_player() -> Node2D:
	# 玩家节点归入 "player" 分组（M1-02 在 player.tscn 上补的分组，仅用于查找，未改行为）
	return get_tree().get_first_node_in_group("player")

## 巡逻状态下碰墙或前方无地面 → 掉头；追击状态下不主动掉头（保持朝玩家）。
func _handle_patrol_turn() -> void:
	if _is_chasing:
		return
	if is_on_wall() or not _edge_check.is_colliding():
		_facing = -_facing
		_aim_edge_ray()

func _aim_edge_ray() -> void:
	# 射线从史莱姆中心出发，朝面朝方向前下探地：前方仍有地面则继续走，否则掉头
	_edge_check.target_position = Vector2(EDGE_CHECK_FORWARD * _facing, EDGE_CHECK_DOWN)

# ---- 接触伤害 ----

func _on_contact_area_body_entered(body: Node2D) -> void:
	if _contact_cooldown > 0.0 or _is_dying:
		return
	if not body.has_method("take_damage"):
		return
	# 玩家扣血与 player_hurt 埋点由 player.take_damage 内部完成，这里只负责触发
	body.take_damage(attack_damage, self)
	_contact_cooldown = CONTACT_DAMAGE_COOLDOWN

# ---- 受击 / 死亡 ----

## 被玩家攻击判定框命中时调用（见 player.gd _apply_hit）。
func take_damage(amount: int) -> void:
	if hp <= 0 or _is_dying:
		return
	hp = maxi(hp - amount, 0)
	_body.color = HIT_FLASH_COLOR
	_flash_timer = FLASH_TIME
	if hp <= 0:
		_die()

func _update_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_body.color = _base_color

func _die() -> void:
	if _is_dying:
		return
	_is_dying = true
	EventBus.enemy_killed.emit(self, global_position)
	# 埋点：史莱姆被击倒（M1-02 要求；玩家被碰扣血由 player_hurt 触发，不在此重复埋）
	EventBus.log_event("slime_killed", {"pos": global_position})
	# 死亡发生在玩家攻击命中的物理回调中；此时实例化带碰撞的 Area2D(肢体拾取物)
	# 会触发 "Can't change state while flushing queries" 错误，必须用 call_deferred 延后
	_spawn_limb_pickup.call_deferred()
	queue_free.call_deferred()

func _spawn_limb_pickup() -> void:
	var pickup := LIMB_PICKUP_SCENE.instantiate()
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector2(0, 8)
