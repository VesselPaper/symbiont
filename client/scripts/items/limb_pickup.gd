extends Area2D
## 地面拾取物通用脚本（M1-02 肢体 / M1-10 武器拾取物复用）
##
## 玩家碰到即拾取：emit EventBus.item_picked(item_id, 1) 后销毁。
## 极简单的上下浮动动画（正弦摆动）让它在地面上显眼。
## 视觉为占位方块，美术资源到位后替换 Body 节点即可。
## M1-10：ITEM_ID 常量泛化为 @export item_id，默认仍是 "monster_limb"（M1-02 行为不变），
## 武器拾取物场景里配成 "iron_sword"。

@export var item_id := "monster_limb"
## 上下浮动幅度 px。默认 0 = 静止（武器拾取物插在尸体上要静止）；
## 需要浮动的拾取物（如肢体）在各自场景里显式设 >0（见 limb_pickup.tscn float_amplitude=3.0）
@export var float_amplitude := 0.0
const FLOAT_SPEED := 3.5       # 浮动角速度 rad/s

var _base_y := 0.0
var _base_captured := false
var _time := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# 基准高度要在"节点被放到最终位置之后"再记：父节点先 add_child 再设 global_position，
	# _ready 里记的初始值(0)是错的，会导致浮动动画把掉落物拽回屏幕顶部（M1-02 教训）。
	if not _base_captured:
		_base_y = position.y
		_base_captured = true
	_time += delta
	position.y = _base_y + sin(_time * FLOAT_SPEED) * float_amplitude

func _on_body_entered(body: Node2D) -> void:
	# mask=2 只探测玩家；has_method 兜底防御（只有玩家挂 take_damage）
	if not body.has_method("take_damage"):
		return
	EventBus.item_picked.emit(item_id, 1)
	queue_free()
