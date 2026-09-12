extends Node2D
## 通用任务光点组件（M1-11 改版 / M1-12 单个引导光点）
##
## 把教学关里"地上的小方块标记"升级成悬浮 + 粒子的通用任务光点（M1-11）后，
## M1-12 按组长定稿改成**单个白色引导光点**：
##   - 取消大量粒子效果（AmbientParticles / BurstParticles 已删干净）
##   - 纯白半透明菱形小点（Body Color(1,1,1,0.6)，约 8x8）+ 更淡的白色光晕（Halo 0.2）
##   - 保留小幅上下悬浮（正弦浮动）
##   - 玩家接触且已 activate() 才触发：闪光 + 广播 EventBus.marker_triggered(marker_id)，
##     触发后**不再消失 / 飞远**，停在原地等 tutorial 调 move_to() 指定下一目标
##   - move_to(target_pos)：Tween 约 0.5s 平滑飞到目标点，到达后重置触发标记、
##     重新开放触碰 —— 保证"触碰 → 飞到下一目标 → 再触碰"循环
## 软隔离：active 默认 false（TriggerArea monitoring 也关），教程到对应环才
## activate()，之前玩家碰了没反应（同 M1-10 假人软隔离思路）。
## 参考代码风格：limb_pickup.gd 的悬浮写法、slime.gd 的常量组织。

# ---- 触发表现 ----
const FLASH_SCALE := 1.4               # 触发闪光：本体 scale 峰值
const FLASH_SCALE_UP_TIME := 0.1       # 弹起时长（秒）
const FLASH_SCALE_DOWN_TIME := 0.1     # 回弹时长（秒）
const MOVE_DURATION := 0.5             # move_to 飞到下一个目标点的时长（秒）

## 光点标识：触发广播携带。M1-12 起教学只有单个光点，不再用它区分环节，
## 但字段保留（EventBus 信号契约兼容，其它监听方可能按 id 取用）
@export var marker_id := "marker"
@export var float_amplitude := 6.0              # 悬浮上下浮动幅度 px
@export var float_speed := 2.5                  # 悬浮角速度 rad/s

var active := false          # 软隔离：activate() 前接触无效（对外只读，教程调用 activate()）
var _triggered := false      # 防重复：触发过一次后不再触发（move_to 到达后重置）
var _base_y := 0.0
var _base_captured := false
var _time := 0.0
var _tween: Tween

@onready var _body: Polygon2D = $Body
@onready var _trigger_area: Area2D = $TriggerArea

func _ready() -> void:
	_trigger_area.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# 飞行中不悬浮（位置由 Tween 接管）；到达后按新基准点继续上下浮动
	if _tween != null and _tween.is_valid() and _tween.is_running():
		return
	# 基准高度在"节点被放到最终位置之后"再记（同 limb_pickup.gd 防
	# 父节点后设 global_position 把浮动拽回屏幕顶的教训）
	if not _base_captured:
		_base_y = position.y
		_base_captured = true
	_time += delta
	position.y = _base_y + sin(_time * float_speed) * float_amplitude

## 激活光点（软隔离核心）：教程到对应环才调，之前接触无效
func activate() -> void:
	active = true
	_trigger_area.monitoring = true

## 飞到下一个引导点：Tween 平滑移动（约 MOVE_DURATION 秒），到达后重置触发标记、
## 重新开放触碰，实现"触碰 → 飞到下一目标 → 再触碰"循环。
## 已在目标点附近（如 PICKUP→SACRIFICE 同点）则直接回到可触发状态，不飞。
func move_to(target_pos: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if position.distance_to(target_pos) < 1.0:
		_on_arrived()
		return
	_base_captured = false
	# 飞行中关闭触碰：光点从玩家头顶掠过时不能误触发，到达后再开。
	# 用 set_deferred：move_to 可能在 body_entered 信号链里被调用（规范第 7 条）
	_trigger_area.set_deferred("monitoring", false)
	_tween = create_tween()
	_tween.tween_property(self, "position", target_pos, MOVE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_on_arrived)

## 到达目标点：清触发标记 + 重开触碰（仍受 active 软隔离约束）。
## 同样用 set_deferred，避免在物理 in/out 信号链里改 monitoring 被拦截
func _on_arrived() -> void:
	_triggered = false
	_base_y = position.y
	_base_captured = true
	if active:
		_trigger_area.set_deferred("monitoring", true)

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
	# （"Function blocked during in/out signal"），必须 set_deferred 延后（规范第 7 条）。
	# M1-12：不再消失 / 飞走，等 tutorial 收到信号后调 move_to 指定下一目标
	_trigger_area.set_deferred("monitoring", false)
	_flash()
	EventBus.marker_triggered.emit(marker_id)

## 触发闪光：本体 scale 快速弹跳一下（1 → 1.4 → 1）
func _flash() -> void:
	var tween := create_tween()
	tween.tween_property(_body, "scale", Vector2(FLASH_SCALE, FLASH_SCALE), FLASH_SCALE_UP_TIME)
	tween.tween_property(_body, "scale", Vector2.ONE, FLASH_SCALE_DOWN_TIME)
