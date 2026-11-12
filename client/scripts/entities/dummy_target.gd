extends StaticBody2D
## 木桩假人（M1-01 / M1-10 / M1-12）
##
## 无行为，用于验证玩家攻击判定与「移动 → 攻击 → 命中 → 扣血」战斗闭环。
## 实体（StaticBody2D，玩家穿不过），但**打不死**：血尽自动重置回满、不消失，
## 玩家可一直练习（教程推进依赖"受击一次 hp 下降"，见 tutorial.gd _dummy_hit）。
## M1-10 软隔离：默认 active=false（教程还没轮到这一环时打了没反应），
## 教程进入对应环时调 activate() 才可受击。
## M2：换成木架 + 稻草人造型，受击时整体晃一下（不再是占位方块）。

const MAX_HP := 3
const FLASH_TIME := 0.12                # 受击闪红时长
const HIT_FLASH_COLOR := Color(1.0, 0.45, 0.35)

var active := false                     # M1-10：未激活时受击无效（软隔离）
var hp := MAX_HP
## 木桩固定在地上不位移，但重量仍影响玩家攻击反作用力（打桩也会被顶退）。
var knockback_weight := 2.0
## 被打中时用什么材质声（player 按这个名字取 hit_<材质>）
var hit_material := "wood"
var _flash_timer := 0.0
var _swing_tween: Tween

@onready var _visual: Node2D = $Visual

func _ready() -> void:
	# 玩家攻击判定框通过该分组识别可受击目标（见 player.gd _apply_hit）
	add_to_group("damageable")

func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_visual.modulate = Color(1, 1, 1, 1)

## 激活教学假人（M1-10 软隔离核心）：教程到对应环才调用，之前打了没反应
func activate() -> void:
	active = true

## 被玩家攻击判定框命中时调用（见 player.gd _apply_hit）。
## M1-12：教学木桩打不死 —— 血尽重置回满（不 queue_free），玩家可一直练习；
## 实体属性和受击闪红照常
func take_damage(amount: int) -> void:
	# M1-10 软隔离：未激活时直接忽略（"提前做后一环无事可做"）
	if not active:
		return
	hp -= amount
	# 埋点：玩家攻击命中木桩（M1-01 要求，事件名/数据见任务卡）
	EventBus.log_event("attack_hit", {"target": "dummy"})
	_visual.modulate = HIT_FLASH_COLOR
	_flash_timer = FLASH_TIME
	_wobble()
	if hp <= 0:
		# 血尽不消失：重置回满，继续当靶子
		EventBus.log_event("dummy_killed", {})
		hp = MAX_HP

## 受击晃动：绕脚底左右摆两下再回正（草人的"被打得晃"）
func _wobble() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(_visual, "rotation", 0.16, 0.07)
	_swing_tween.tween_property(_visual, "rotation", -0.11, 0.10)
	_swing_tween.tween_property(_visual, "rotation", 0.05, 0.08)
	_swing_tween.tween_property(_visual, "rotation", 0.0, 0.09)
