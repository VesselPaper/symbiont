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
const HOP_PROBE_AHEAD := 64.0        # 起跳前探落点：前方这么远的下方得有地
const HOP_PROBE_DOWN := 64.0         # 落点探测的下探深度

# ---- 接触伤害 ----
const CONTACT_DAMAGE_COOLDOWN := 0.8 # 两次接触伤害的最小间隔（防连续扣血）
const VOICE_COOLDOWN := 7.5          # 追击时的软体低鸣间隔，避免每帧叫

# ---- 受击表现 ----
const FLASH_TIME := 0.1              # 受击闪红时长
const HIT_FLASH_COLOR := Color(1.0, 0.3, 0.3)
const HIT_STUN := 0.18               # 受击硬直：期间不巡逻/不追击，让击退真的推得动
const KNOCKBACK_FRICTION := 1200.0
const DEATH_ANIM_TIME := 0.28        # 死亡压扁淡出时长（尸体消失前）
const SQUASH_SPEED := 7.0            # 静止时的软体挤压频率

# ---- 跳跃移动（第一版是匀速平移，组长反馈“一直锁定玩家走、平移太僵硬”）----
# 现在改成一段一段地蹦：蹲下蓄力 → 腾空 → 落地停顿。空中不转向，
# 落点带一点瞄准误差，玩家看到的就不是“贴着你滑过来”。
const HOP_UP := 300.0                # 起跳竖直速度，决定弹起高度
const HOP_SPEED_FACTOR := 4.2        # 腾空水平速度 = speed * 该系数（平均速度仍接近 speed）
const HOP_WINDUP := 0.30             # 起跳前的下蹲时间
const HOP_REST_CHASE := 0.18         # 追击时两跳之间的停顿（短一点才有压迫感）
const HOP_REST_PATROL := 0.75        # 巡逻时停顿更长，显得悠哉
const HOP_AIR_MIN := 0.16            # 起飞后至少这么久才算落地，避免起跳同帧被判落地
const HOP_GROUND_FRICTION := 900.0   # 地面上水平速度衰减，击退才推得动
const AIM_ERROR := 30.0              # 落点横向误差：不要每一跳都精确咬住玩家
const CLOSE_RANGE := 56.0            # 离玩家这么近改小跳，别一头撞过去

const PHASE_REST := 0
const PHASE_WINDUP := 1
const PHASE_AIR := 2

const LIMB_PICKUP_SCENE := preload("res://scenes/items/limb_pickup.tscn")
const CORPSE_SCENE := preload("res://scenes/entities/slime_corpse.tscn")

var hp: int
var speed: float
var attack_damage: int
## 击退重量：小史莱姆轻，被打退得远；boss/重甲怪在各自脚本里给更大值。
var knockback_weight := 1.0
## 被打中时用什么材质声（player 按这个名字取 hit_<材质>）
var hit_material := "flesh"

var _facing := 1             # 1 朝右，-1 朝左
var _is_chasing := false
var _contact_cooldown := 0.0
var _stun_timer := 0.0
var _flash_timer := 0.0
var _base_color: Color
var _is_dying := false
var _death_timer := 0.0
var _anim_time := 0.0
var _blink_timer := 2.8      # 下次眨眼倒计时
var _blink_time := 0.0       # 当前眨眼剩余
var _voice_cd := 3.0         # 第一次低鸣不要和出生同帧
var _hop_phase := PHASE_WINDUP   # 出生先蹲一下再跳，别一落地就窜出去
var _hop_timer := HOP_WINDUP
var _hop_air_time := 0.0
var _land_squash := 0.0      # 落地压扁的剩余时间

@onready var _visual: Node2D = $Visual
@onready var _body: Polygon2D = $Visual/Body
@onready var _eye_left: Polygon2D = $Visual/EyeLeft
@onready var _eye_right: Polygon2D = $Visual/EyeRight
@onready var _contact_area: Area2D = $ContactArea
@onready var _edge_check: RayCast2D = $EdgeCheck

func _ready() -> void:
	# 玩家攻击判定通过 damageable 分组识别可受击目标（见 player.gd _apply_hit）
	add_to_group("damageable")
	# 对话组件按 enemy 分组冻结敌人，避免剧情播放时被巡逻怪贴脸扣血
	add_to_group("enemy")
	_load_stats()
	_base_color = _body.color
	_contact_area.body_entered.connect(_on_contact_area_body_entered)
	_aim_edge_ray()
	# 复用 EventBus 现成信号：敌人登场广播，M2 的生成特效 / 计数可直接订阅
	# 用 /root 查找而不是全局标识符：--script 测试加载场景时也能正常工作
	var bus := _event_bus()
	if bus != null:
		bus.enemy_spawned.emit(self)

func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus")

func _physics_process(delta: float) -> void:
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)
	_voice_cd = maxf(_voice_cd - delta, 0.0)
	_apply_gravity(delta)
	if _stun_timer > 0.0:
		# 受击硬直：不巡逻、不掉头，只让击退速度自然衰减
		_stun_timer = maxf(_stun_timer - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, KNOCKBACK_FRICTION * delta)
		move_and_slide()
		return
	_aim_edge_ray()
	_update_chase_state()
	_update_hop(delta)
	move_and_slide()
	_handle_patrol_turn()
	_maybe_voice()

func _maybe_voice() -> void:
	if _is_dying or _voice_cd > 0.0 or not _is_chasing:
		return
	var player := _get_player()
	if player == null or not _player_in_range(player, CHASE_DISTANCE):
		return
	_voice_cd = VOICE_COOLDOWN + randf_range(-1.0, 1.5)
	GameManager.play_sfx("slime_voice", -11.0, randf_range(0.88, 1.08))

func _process(delta: float) -> void:
	_update_flash(delta)
	_update_visual(delta)

## 软体表现：移动时挤压 / 拉伸，偶尔眨眼；死亡时压扁淡出再掉肢体
func _update_visual(delta: float) -> void:
	_anim_time += delta
	if _is_dying:
		if _death_timer > 0.0:
			_death_timer -= delta
			var p := 1.0 - maxf(_death_timer, 0.0) / DEATH_ANIM_TIME
			_visual.scale = Vector2(float(_facing) * (1.0 + 0.45 * p), 1.0 - 0.85 * p)
			_visual.modulate = Color(1, 1, 1, 1.0 - p)
			if _death_timer <= 0.0:
				_finish_death()
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_time = 0.09
		_blink_timer = 2.6 + float(int(_anim_time * 13.0) % 9) * 0.18
	if _blink_time > 0.0:
		_blink_time -= delta
	var eyes_open := _blink_time <= 0.0
	_eye_left.visible = eyes_open
	_eye_right.visible = eyes_open
	# 挤压跟着跳跃阶段走：下蹲压扁 → 腾空拉长 → 落地再压一下 → 静止慢呼吸
	var sx := 1.0
	var sy := 1.0
	if _hop_phase == PHASE_WINDUP:
		var charge := 1.0 - clampf(_hop_timer / HOP_WINDUP, 0.0, 1.0)
		sx = 1.0 + 0.26 * charge
		sy = 1.0 - 0.30 * charge
	elif _hop_phase == PHASE_AIR:
		sx = 0.88
		sy = 1.16
	elif _land_squash > 0.0:
		_land_squash = maxf(_land_squash - delta, 0.0)
		var land := _land_squash / 0.16
		sx = 1.0 + 0.42 * land
		sy = 1.0 - 0.46 * land
	else:
		var squash := sin(_anim_time * SQUASH_SPEED) * 0.045
		sx = 1.0 + squash
		sy = 1.0 - squash
	_visual.scale = Vector2(float(_facing) * sx, sy)

# ---- 数据驱动属性 ----

func _load_stats() -> void:
	# 同样用 /root 查找，避免 --script 测试加载场景时把 DataDB 当成未声明标识符
	var data_db := get_node_or_null("/root/DataDB")
	var data: Dictionary = data_db.get_enemy(ENEMY_ID) if data_db != null else {}
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

## 只负责“要不要追”，不直接写 velocity：真正移动交给 _update_hop。
## 带滞回：进圈用 CHASE_DISTANCE，出圈用 LOST_DISTANCE，防止在边界来回抽搐。
func _update_chase_state() -> void:
	var player := _get_player()
	if player == null:
		_is_chasing = false
		return
	if _is_chasing:
		if not _player_in_range(player, LOST_DISTANCE):
			_is_chasing = false
	elif _player_in_range(player, CHASE_DISTANCE):
		_is_chasing = true


## 蹦跳状态机：地上停 → 下蹲 → 腾空 → 落地（带压扁）。
## 空中完全不控制方向，落地后才重新瞄一次，所以看起来是“跳过去”而不是“粘着走”。
func _update_hop(delta: float) -> void:
	if _hop_phase == PHASE_AIR:
		_hop_air_time += delta
		if _hop_air_time >= HOP_AIR_MIN and is_on_floor():
			_hop_phase = PHASE_REST
			# 落地立刻停住：靠摩擦滑一段的话，玩家看到的就是“平移”
			if _stun_timer <= 0.0:
				velocity.x = 0.0
			_hop_timer = HOP_REST_CHASE if _is_chasing else HOP_REST_PATROL
			_land_squash = 0.16
		return
	# 地面阶段：把残余速度（击退、被推）自然吃掉，不做硬归零，不然打上去像打在墙上
	velocity.x = move_toward(velocity.x, 0.0, HOP_GROUND_FRICTION * delta)
	_hop_timer -= delta
	if _hop_timer > 0.0:
		return
	if _hop_phase == PHASE_REST:
		_hop_phase = PHASE_WINDUP
		_hop_timer = HOP_WINDUP
		return
	_launch()


func _launch() -> void:
	var player := _get_player()
	var up := HOP_UP
	var aim := float(_facing)
	if _is_chasing and player != null:
		var dx := player.global_position.x - global_position.x
		# 落点带误差，偶尔会跳偏一点，玩家就不会觉得被吸住
		aim = dx + randf_range(-AIM_ERROR, AIM_ERROR)
		if absf(dx) <= CLOSE_RANGE:
			# 贴脸时改成小跳短扑，别整段大跳直接砸过去
			up = HOP_UP * 0.55
			aim = dx * 0.5
	elif not _is_chasing:
		# 巡逻方向前方没地面、或者跳过去会落空，先掉头再跳，别跳进坑里
		if is_on_wall() or not _edge_check.is_colliding() or not _can_hop_toward(_facing):
			_facing = -_facing
			_aim_edge_ray()
		if not _can_hop_toward(_facing):
			# 两边都是悬空的窄台：原地弹一下，不往前送
			velocity = Vector2(0.0, -up)
			_hop_phase = PHASE_AIR
			_hop_air_time = 0.0
			return
		aim = float(_facing)
	if absf(aim) < 4.0:
		aim = float(_facing) * 4.0
	_update_facing_toward(global_position.x + aim)
	velocity = Vector2(float(_facing) * speed * HOP_SPEED_FACTOR, -up)
	_hop_phase = PHASE_AIR
	_hop_air_time = 0.0


func _update_facing_toward(target_x: float) -> void:
	var dir := signf(target_x - global_position.x)
	if dir != 0.0:
		_facing = int(dir)


## 起跳前探一下：跳到这个方向，前方 HOP_PROBE_AHEAD 处的下方还有没有地。
## 没有的话说明这一跳会落进坑里，得掉头或者原地蹦。
func _can_hop_toward(dir: int) -> bool:
	var from := global_position + Vector2(float(dir) * HOP_PROBE_AHEAD, -12.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, HOP_PROBE_DOWN), 1)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()

func _player_in_range(player: Node2D, distance: float) -> bool:
	var horizontal_dist := absf(player.global_position.x - global_position.x)
	var vertical_dist := absf(player.global_position.y - global_position.y)
	return horizontal_dist <= distance and vertical_dist <= SAME_FLOOR_TOLERANCE

func _get_player() -> Node2D:
	# 玩家节点归入 "player" 分组（M1-02 在 player.tscn 上补的分组，仅用于查找，未改行为）
	return get_tree().get_first_node_in_group("player")

## 巡逻状态下碰墙或前方无地面 → 掉头；追击状态下不主动掉头（保持朝玩家）。
## 只在落地且没在空中时判断，免得腾空中被墙判定打断整段跳跃。
func _handle_patrol_turn() -> void:
	if _is_chasing or _hop_phase == PHASE_AIR or not is_on_floor():
		return
	if _hop_phase == PHASE_REST and not _edge_check.is_colliding():
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
## 被推开：由玩家攻击命中时调用；strength 已按目标重量除过。
func apply_knockback(source_pos: Vector2, strength: float) -> void:
	if hp <= 0 or _is_dying:
		return
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = float(-_facing)
	velocity.x = dir * strength
	velocity.y = -55.0
	_stun_timer = HIT_STUN
	_is_chasing = false
	# 被打飞时别接着原计划起跳，落地后重新蓄力
	_hop_phase = PHASE_REST
	_hop_timer = HOP_REST_CHASE

func take_damage(amount: int) -> void:
	if hp <= 0 or _is_dying:
		return
	hp = maxi(hp - amount, 0)
	_body.color = HIT_FLASH_COLOR
	_flash_timer = FLASH_TIME
	GameManager.play_sfx("enemy_hit", -2.0)
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
	_death_timer = DEATH_ANIM_TIME
	var bus := _event_bus()
	if bus != null:
		bus.enemy_killed.emit(self, global_position)
		# 埋点：史莱姆被击倒（M1-02 要求；玩家被碰扣血由 player_hurt 触发，不在此重复埋）
		bus.log_event("slime_killed", {"pos": global_position})
	# 肢体与销毁等到压扁动画放完再做（见 _finish_death），别在受击回调里改物理状态
	_contact_area.set_deferred("monitoring", false)
	_spawn_death_burst()

## 死亡时炸一簇绿色孢子；粒子挂在父节点上，史莱姆本体压扁消失后还能飘完
func _spawn_death_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.amount = 16
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 70)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 105.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.color = Color(0.55, 0.90, 0.58, 0.85)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			var d := Vector2(x - 1.5, y - 1.5).length() / 2.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	p.texture = ImageTexture.create_from_image(img)
	p.global_position = global_position
	parent.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.7).timeout.connect(p.queue_free)

func _finish_death() -> void:
	if not is_inside_tree():
		return
	_death_timer = 0.0
	_spawn_corpse()
	_spawn_limb_pickup()
	queue_free()

## 尸体先落在地上，再把肢体放在旁边；两个模型错开，玩家一眼能分清"尸体"和"可拾取肢体"
func _spawn_corpse() -> void:
	var corpse := CORPSE_SCENE.instantiate()
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(corpse)
	corpse.global_position = global_position + Vector2(0, 6)

func _spawn_limb_pickup() -> void:
	var pickup := LIMB_PICKUP_SCENE.instantiate()
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector2(12, 8)
