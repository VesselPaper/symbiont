extends Node2D
## 主场景：房间切换 / 死亡重生 / 掉坑判定
## 对应 GDD：轻惩罚死亡（保留进度，死亡数+1）

@onready var loader: Node2D = $LevelLoader
@onready var player: CharacterBody2D = $Player

var _current_room := "entrance"
var _switching := false
var deaths := 0


func _ready() -> void:
	loader.door_entered.connect(_on_door_entered)
	GameEvents.player_died.connect(_on_player_died)
	_enter_room(_current_room)


func _process(_delta: float) -> void:
	# 掉出地图（落入深渊）→ 视为死亡重生
	if player.global_position.y > 320.0 and not _switching:
		_on_player_died()


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


func _on_player_died() -> void:
	if _switching:
		return
	_switching = true
	deaths += 1
	await get_tree().create_timer(0.8).timeout
	_enter_room(_current_room)
	player.reset_after_death()
	_switching = false
