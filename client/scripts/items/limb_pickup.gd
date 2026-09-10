extends Area2D
## 怪物肢体拾取物（M1-02）
##
## 史莱姆被击倒后掉落在脚下，玩家碰到即拾取：emit EventBus.item_picked("monster_limb", 1)
## 后销毁。极简单的上下浮动动画（正弦摆动）让它在地面上显眼。
## 视觉为绿色小方块占位，美术资源到位后替换 Body 节点即可。

const ITEM_ID := "monster_limb"
const FLOAT_AMPLITUDE := 3.0   # 上下浮动幅度 px
const FLOAT_SPEED := 3.5       # 浮动角速度 rad/s

var _base_y := 0.0
var _time := 0.0

func _ready() -> void:
	_base_y = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * FLOAT_SPEED) * FLOAT_AMPLITUDE

func _on_body_entered(body: Node2D) -> void:
	# mask=2 只探测玩家；has_method 兜底防御（只有玩家挂 take_damage）
	if not body.has_method("take_damage"):
		return
	EventBus.item_picked.emit(ITEM_ID, 1)
	queue_free()
