extends Node2D
## 攀升竖井（M1-15）—— 固定镜头垂直攀升模块
##
## 规则：相机固定一屏；地形（平台）整体向下滚动，玩家被平台带着下沉，必须不停
## 向上跳；平台移出屏幕下沿后回收到顶部，按"必然可达"的规则重新摆放；玩家碰到
## 屏幕底部判定区 → 本模块重开；坚持满 SURVIVE_TIME 秒 → 通关。
##
## 下落速度从"FALL_TIME_START 秒穿过全屏"线性加快到"FALL_TIME_END 秒穿过全屏"。
##
## 可达性依据 player.gd：重力 2550、跳跃初速 727 → 最大跳高 ≈ 103.6px，
## 故垂直间距上限 SAFE_JUMP_HEIGHT=80（留余量），水平偏移上限 PLATFORM_H_SPAN。
##
## 说明：本脚本**不引用 EventBus 全局**（便于无头 --script 测试），只用本地信号。
## 数值全部为脚本顶部常量，M2 再迁入 database/game_data。

signal module_completed(elapsed: float)   # 坚持满 SURVIVE_TIME 秒
signal module_restarted                    # 玩家触底、模块重开

# ---- 相机 / 可视区域（与 test_arena 同口径）----
const VIEW_HEIGHT_IN_CHARACTERS := 15.0
const PLAYER_CHARACTER_HEIGHT := 28.0
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)
const VISIBLE_HEIGHT := 720.0 / CAMERA_ZOOM     # ≈ 420
const VISIBLE_WIDTH := 1280.0 / CAMERA_ZOOM     # ≈ 747

# ---- 下落速度曲线：全屏耗时 10s → 5s ----
const FALL_TIME_START := 10.0
const FALL_TIME_END := 5.0
const RAMP_DURATION := 30.0                     # 速度爬升时长（与生存目标一致）

# ---- 生存目标 ----
const SURVIVE_TIME := 30.0

# ---- 平台生成（可达性约束）----
const SAFE_JUMP_HEIGHT := 80.0                  # 垂直间距上限（< 最大跳高 103.6）
const PLATFORM_GAP_MIN := 48.0
const PLATFORM_GAP_MAX := 80.0
const PLATFORM_H_SPAN := 128.0                  # 相邻平台最大水平偏移
const PLATFORM_WIDTH := 96.0
const PLATFORM_HEIGHT := 16.0
const PLATFORM_COLOR := Color(0.15686275, 0.15686275, 0.15686275, 1)

# ---- 回收 / 起始 ----
const RECYCLE_MARGIN := 48.0                    # 完全越过屏幕下沿多少像素后回收
const START_PLATFORM_Y := 170.0                 # 起始宽平台中心 y
const PLAYER_SPAWN := Vector2(0.0, 140.0)       # 玩家起点（站在起始平台上方）

var _elapsed := 0.0
var _progress := 0.0
var _completed := false
var _rng := RandomNumberGenerator.new()
var _platforms: Array[Node2D] = []
var _top_x := 0.0                                # 当前最高平台的中心 x
var _top_y := 0.0                                # 当前最高平台的中心 y

@onready var _terrain: Node2D = $Terrain
@onready var _player: Node2D = get_node_or_null("Player")
@onready var _bottom_zone: Area2D = $BottomZone

func _ready() -> void:
	_rng.randomize()
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
		camera.make_current()
	if _bottom_zone != null:
		_bottom_zone.body_entered.connect(_on_bottom_zone_body_entered)
	_reset_module()

func _physics_process(delta: float) -> void:
	if _completed:
		return
	_elapsed += delta
	_progress = clampf(_elapsed / RAMP_DURATION, 0.0, 1.0)

	# 1) 地形整体下落（同步移动，AnimatableBody2D 会把站上面的玩家一起带下去）
	var dy := fall_speed_for_progress(_progress) * delta
	for platform in _platforms:
		platform.position.y += dy

	# 2) 越过下沿的平台回收到顶部
	_recycle_platforms()

	# 3) 生存达标
	if _elapsed >= SURVIVE_TIME:
		_complete()

# ---- 速度曲线（纯函数，便于测试）----

## progress ∈ [0,1] → 每秒下落的像素数；全屏耗时从 FALL_TIME_START 线性到 FALL_TIME_END
static func fall_speed_for_progress(progress: float) -> float:
	var duration := lerpf(FALL_TIME_START, FALL_TIME_END, clampf(progress, 0.0, 1.0))
	return VISIBLE_HEIGHT / duration

# ---- 生成规则（纯函数，便于测试）----

## 相邻平台的垂直间距（[PLATFORM_GAP_MIN, PLATFORM_GAP_MAX]，必然 ≤ 安全跳高）
static func random_gap(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(PLATFORM_GAP_MIN, PLATFORM_GAP_MAX)

## 下一个平台的中心 x：相对上一个平台左右随机，并夹在竖井内
static func random_next_x(prev_x: float, rng: RandomNumberGenerator) -> float:
	var half := VISIBLE_WIDTH * 0.5 - PLATFORM_WIDTH * 0.5 - 8.0
	return clampf(prev_x + rng.randf_range(-PLATFORM_H_SPAN, PLATFORM_H_SPAN), -half, half)

# ---- 模块生命周期 ----

func _reset_module() -> void:
	_elapsed = 0.0
	_progress = 0.0
	_completed = false
	_clear_platforms()
	_build_initial_platforms()
	_reset_player()

func _clear_platforms() -> void:
	for platform in _platforms:
		platform.queue_free()
	_platforms.clear()

## 从屏幕底往上铺满，保证开局有落脚点，且链式满足可达性
func _build_initial_platforms() -> void:
	_spawn_platform(Vector2(0.0, START_PLATFORM_Y), VISIBLE_WIDTH - 80.0)
	_top_x = 0.0
	_top_y = START_PLATFORM_Y
	while _top_y > -VISIBLE_HEIGHT * 0.5 - PLATFORM_HEIGHT:
		var next_x := random_next_x(_top_x, _rng)
		var next_y := _top_y - random_gap(_rng)
		_spawn_platform(Vector2(next_x, next_y), PLATFORM_WIDTH)
		_top_x = next_x
		_top_y = next_y

func _spawn_platform(pos: Vector2, width: float) -> void:
	# AnimatableBody2D + sync_to_physics：手动移动时会带动站在上面的 CharacterBody2D
	var body := AnimatableBody2D.new()
	body.sync_to_physics = true
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, PLATFORM_HEIGHT)
	shape.shape = rect
	body.add_child(shape)

	var visual := Polygon2D.new()
	visual.color = PLATFORM_COLOR
	var hw := width * 0.5
	var hh := PLATFORM_HEIGHT * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh),
	])
	body.add_child(visual)

	_terrain.add_child(body)
	_platforms.append(body)

## 回收越过屏幕下沿的平台：按 y 从小到大（越高越先）依次叠到当前顶部之上
func _recycle_platforms() -> void:
	var bottom := VISIBLE_HEIGHT * 0.5
	var crossed: Array[Node2D] = []
	for platform in _platforms:
		if platform.position.y - PLATFORM_HEIGHT * 0.5 > bottom + RECYCLE_MARGIN:
			crossed.append(platform)
	if crossed.is_empty():
		return
	crossed.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y < b.position.y)
	for platform in crossed:
		var next_x := random_next_x(_top_x, _rng)
		var next_y := _top_y - random_gap(_rng)
		platform.position = Vector2(next_x, next_y)
		_top_x = next_x
		_top_y = next_y

func _reset_player() -> void:
	if _player == null:
		return
	_player.global_position = PLAYER_SPAWN
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO

func _on_bottom_zone_body_entered(body: Node2D) -> void:
	if _completed:
		return
	if not body.is_in_group("player"):
		return
	# 物理回调内重建带碰撞的平台必须延后（规范第 7 条：Can't change state while flushing queries）
	_do_restart.call_deferred()

func _do_restart() -> void:
	_reset_module()
	module_restarted.emit()

func _complete() -> void:
	_completed = true
	print("[climb_shaft] 通关：坚持 %.1fs" % _elapsed)
	module_completed.emit(_elapsed)

# ---- 供测试 / 外部读取 ----

func get_platform_count() -> int:
	return _platforms.size()

func get_platform_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for platform in _platforms:
		out.append(platform.position)
	return out

func get_elapsed() -> float:
	return _elapsed

func is_completed() -> bool:
	return _completed

func force_restart() -> void:
	_reset_module()
