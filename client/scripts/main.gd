extends Node2D
## 主场景：管理房间切换与玩家重生
## 对应《系统详细设计》关卡系统 / 存档点语义（掉出即回出生点）

@onready var loader: Node2D = $LevelLoader
@onready var player: CharacterBody2D = $Player

var _current_room := "entrance"
var _switching := false


func _ready() -> void:
	loader.door_entered.connect(_on_door_entered)
	_enter_room(_current_room)


func _process(_delta: float) -> void:
	# 掉出地图（落入深渊）→ 回到当前房间出生点
	if player.global_position.y > 320.0:
		_enter_room(_current_room)


func _enter_room(id: String) -> void:
	_current_room = id
	loader.build_room(id, player)


func _on_door_entered(to: String, entry: Vector2) -> void:
	if _switching:
		return
	_switching = true
	_enter_room(to)
	player.global_position = entry
	_switching = false
