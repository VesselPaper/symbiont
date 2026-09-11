extends Node2D
## 通用任务光点组件（M1-11）
##
## 把教学关里"地上的小方块标记"升级成悬浮 + 粒子的通用任务光点：
##   - 悬浮在空中的菱形光点（上下正弦浮动）+ 半透明光晕
##   - 常驻青白粒子（CPUParticles2D）围绕飘散 + 触发时一次性爆发
##   - 玩家接触且已 activate() 才触发：闪光弹跳 + 粒子爆发，然后
##     fly_away_on_touch=true 匀速飘向远方（离开视口后释放），否则淡出消失
##   - 触发时广播 EventBus.marker_triggered(marker_id)，剧情 / 任务监听方自取
## 软隔离：active 默认 false（TriggerArea monitoring 也关），教程到对应环才
## activate()，之前玩家碰了没反应（同 M1-10 假人软隔离思路）。
## 参考代码风格：limb_pickup.gd 的悬浮写法、slime.gd 的常量组织。

# ---- 触发表现 ----
const FLASH_SCALE := 1.4               # 触发闪光：本体 scale 峰值
const FLASH_SCALE_UP_TIME := 0.1       # 弹起时长（秒）
const FLASH_SCALE_DOWN_TIME := 0.1     # 回弹时长（秒）
const FADE_OUT_TIME := 0.35            # 非飞走模式淡出时长（秒）
const OFFSCREEN_MARGIN := 200.0        # 飞走判离屏缓冲（px），超过视口边沿这么远才释放

## 光点标识：触发广播携带，教程 / 任务用它与当前环匹配
@export var marker_id := "marker"
@export var fly_away_on_touch := false          # true = 接触后飘向远方
@export var fly_away_velocity := Vector2(300, -120)  # 飘走速度（向右上方飘）
@export var float_amplitude := 6.0              # 悬浮上下浮动幅度 px
@export var float_speed := 2.5                  # 悬浮角速度 rad/s

var active := false          # 软隔离：activate() 前接触无效（对外只读，教程调用 activate()）
var _triggered := false      # 防重复：触发过一次后不再触发
var _fly_away := false       # 当前是否处于飞走状态（飞走模式下 _process 接管位置）
var _base_y := 0.0
var _base_captured := false
var _time := 0.0

@onready var _body: Polygon2D = $Body
@onready var _burst_particles: CPUParticles2D = $BurstParticles
@onready var _trigger_area: Area2D = $TriggerArea

func _ready() -> void:
	_trigger_area.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# 悬浮：基准高度在"节点被放到最终位置之后"再记（同 limb_pickup.gd 防
	# 父节点后设 global_position 把浮动拽回屏幕顶的教训）
	if not _base_captured:
		_base_y = position.y
		_base_captured = true
	if _fly_away:
		# 飞走模式：匀速飘向远方，离开视口后释放（不再悬浮）
		position += fly_away_velocity * delta
		if _is_offscreen():
			queue_free()
		return
	_time += delta
	position.y = _base_y + sin(_time * float_speed) * float_amplitude

## 激活光点（软隔离核心）：教程到对应环才调，之前接触无效
func activate() -> void:
	active = true
	_trigger_area.monitoring = true

func _on_body_entered(body: Node2D) -> void:
	# 反向测试：只有"player 分组"的节点接触才算（mask=2 只探测玩家是兜底，
	# 再按分组确认一次，防止其它误入 layer 2 的物体触发），且必须已激活、未触发过
	if not active or _triggered:
		return
	if not body.is_in_group("player"):
		return
	_trigger()

func _trigger() -> void:
	if _triggered:
		return
	_triggered = true
	# 触发后关触碰：在 body_entered 回调里直接改 monitoring 会被 Godot 拦截
	# （"Function blocked during in/out signal"），必须 set_deferred 延后（规范第 7 条）
	_trigger_area.set_deferred("monitoring", false)
	_flash()
	_burst_particles.emitting = true
	EventBus.marker_triggered.emit(marker_id)
	if fly_away_on_touch:
		_fly_away = true
	else:
		_fade_out()

## 触发闪光：本体 scale 快速弹跳一下（1 → 1.4 → 1）
func _flash() -> void:
	var tween := create_tween()
	tween.tween_property(_body, "scale", Vector2(FLASH_SCALE, FLASH_SCALE), FLASH_SCALE_UP_TIME)
	tween.tween_property(_body, "scale", Vector2.ONE, FLASH_SCALE_DOWN_TIME)

## 淡出消失（非飞走模式）：整组 modulate.a 渐隐后释放
func _fade_out() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_TIME)
	tween.tween_callback(queue_free)

## 是否已飞出当前视口（fly_away 模式释放条件）
func _is_offscreen() -> bool:
	var vp := get_viewport_rect()
	return (global_position.x < vp.position.x - OFFSCREEN_MARGIN
		or global_position.x > vp.end.x + OFFSCREEN_MARGIN
		or global_position.y < vp.position.y - OFFSCREEN_MARGIN
		or global_position.y > vp.end.y + OFFSCREEN_MARGIN)
