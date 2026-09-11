extends StaticBody2D
## 木桩假人（M1-01 / M1-10）
##
## 无行为，用于验证玩家攻击判定与「移动 → 攻击 → 命中 → 扣血 → 击倒」战斗闭环。
## 被命中闪红扣血，血尽消失。血量常量占位，M2 迁入数据文件。
## M1-10 软隔离：默认 active=false（教程还没轮到这一环时打了没反应），
## 教程进入对应环时调 activate() 才可受击。

const MAX_HP := 3
const FLASH_TIME := 0.12                # 受击闪红时长
const HIT_FLASH_COLOR := Color(1.0, 0.3, 0.3)

var active := false                     # M1-10：未激活时受击无效（软隔离）
var hp := MAX_HP
var _flash_timer := 0.0
var _base_color := Color.WHITE

@onready var _body: Polygon2D = $Body

func _ready() -> void:
	# 玩家攻击判定框通过该分组识别可受击目标（见 player.gd _apply_hit）
	add_to_group("damageable")
	_base_color = _body.color

func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_body.color = _base_color

## 激活教学假人（M1-10 软隔离核心）：教程到对应环才调用，之前打了没反应
func activate() -> void:
	active = true

## 被玩家攻击判定框命中时调用（见 player.gd _apply_hit）。
func take_damage(amount: int) -> void:
	# M1-10 软隔离：未激活时直接忽略（"提前做后一环无事可做"）
	if not active:
		return
	if hp <= 0:
		return
	hp -= amount
	# 埋点：玩家攻击命中木桩（M1-01 要求，事件名/数据见任务卡）
	EventBus.log_event("attack_hit", {"target": "dummy"})
	_body.color = HIT_FLASH_COLOR
	_flash_timer = FLASH_TIME
	if hp <= 0:
		EventBus.log_event("dummy_killed", {})
		queue_free()
