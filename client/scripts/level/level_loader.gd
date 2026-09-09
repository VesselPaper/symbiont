extends Node2D
## 关卡加载器：从 JSON 数据驱动构建房间（地形 / 平台 / 敌人 / 装饰 / 门 / 边界）。
## 对应《系统详细设计》FR-C-06 关卡与地图数据（JSON → 引擎渲染）。
## 房间坐标约定：y 向下；terrain.y / platform.y 为方块顶面。

signal door_entered(to: String, entry: Vector2)

@export var level_path := "res://data/levels/dungeon.json"

const PLAYER_LAYER := 2

var _level_data: Dictionary = {}
var _enemy_scene := preload("res://scenes/enemy.tscn")

# 调色（地牢极简方案：土 + 石墙）
const C_DIRT := Color(0.36, 0.27, 0.17)
const C_DIRT_TOP := Color(0.53, 0.42, 0.27)
const C_STONE := Color(0.30, 0.28, 0.25)
const C_STONE_TOP := Color(0.43, 0.40, 0.36)


func _ready() -> void:
	_level_data = JSON.parse_string(FileAccess.get_file_as_string(level_path))
	assert(_level_data != null and _level_data.has("rooms"), "关卡 JSON 解析失败: " + level_path)


func build_room(id: String, player: Node2D) -> void:
	# 清空旧房间（立即释放，避免节点名冲突）
	for child in get_children():
		child.free()

	var room: Dictionary = {}
	for r in _level_data["rooms"]:
		if r["id"] == id:
			room = r
			break
	assert(not room.is_empty(), "未找到房间: " + id)

	_build_bounds(room)
	_build_terrain(room)
	_build_decor(room)
	_build_enemies(room)
	_build_doors(room)

	var start: Array = room.get("player_start", [0.0, -11.0])
	player.position = Vector2(start[0], start[1])
	player.velocity = Vector2.ZERO


# ---------- 地形 / 平台 ----------

func _build_bounds(room: Dictionary) -> void:
	if not room.has("bounds"):
		return
	var b: Dictionary = room["bounds"]
	_make_wall(b.get("left", -600.0), b.get("right", 600.0))


func _build_terrain(room: Dictionary) -> void:
	for t in room.get("terrain", []):
		_make_block(Vector2(t.x, t.y), t.w, t.h, t.get("layer", "dirt"))
	for p in room.get("platforms", []):
		_make_block(Vector2(p.x, p.y), p.w, 14.0, "dirt")


func _make_wall(left: float, right: float) -> void:
	for x in [left, right]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, -200.0)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(32.0, 520.0)
		shape.shape = rect
		wall.add_child(shape)
		add_child(wall)


func _make_block(pos: Vector2, w: float, h: float, layer: String) -> void:
	var body := StaticBody2D.new()
	body.position = pos + Vector2(w / 2.0, h / 2.0)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	shape.shape = rect
	body.add_child(shape)

	var main_color := C_DIRT if layer == "dirt" else C_STONE
	var top_color := C_DIRT_TOP if layer == "dirt" else C_STONE_TOP

	var vis := ColorRect.new()
	vis.offset_left = -w / 2.0
	vis.offset_top = -h / 2.0
	vis.offset_right = w / 2.0
	vis.offset_bottom = h / 2.0
	vis.color = main_color
	body.add_child(vis)

	# 顶面亮条：让"可站立"的顶面一眼可读
	var top := ColorRect.new()
	top.offset_left = -w / 2.0
	top.offset_top = -h / 2.0
	top.offset_right = w / 2.0
	top.offset_bottom = -h / 2.0 + 4.0
	top.color = top_color
	body.add_child(top)

	add_child(body)


# ---------- 敌人 ----------

func _build_enemies(room: Dictionary) -> void:
	for e in room.get("enemies", []):
		var enemy := _enemy_scene.instantiate()
		enemy.position = Vector2(e.x, e.y)
		enemy.patrol_half_width = e.get("range", 80.0)
		add_child(enemy)


# ---------- 装饰 ----------

func _build_decor(room: Dictionary) -> void:
	for d in room.get("decor", []):
		var pos := Vector2(d.x, d.y)
		match d.get("type", ""):
			"torch":
				_make_torch(pos)
			"stalactite":
				_make_stalactite(pos)
			"moss":
				_make_moss(pos)
			"seal":
				_make_seal(pos)


func _make_torch(pos: Vector2) -> void:
	var n := Node2D.new()
	n.position = pos

	var holder := ColorRect.new()
	holder.offset_left = -3.0
	holder.offset_top = -6.0
	holder.offset_right = 3.0
	holder.offset_bottom = 6.0
	holder.color = Color(0.42, 0.28, 0.14)
	n.add_child(holder)

	var flame := ColorRect.new()
	flame.offset_left = -2.0
	flame.offset_top = -16.0
	flame.offset_right = 2.0
	flame.offset_bottom = -6.0
	flame.color = Color(1.0, 0.65, 0.2)
	n.add_child(flame)

	var embers := CPUParticles2D.new()
	embers.position = Vector2(0, -16)
	embers.emitting = true
	embers.amount = 14
	embers.lifetime = 0.9
	embers.direction = Vector2(0, -1)
	embers.spread = 30.0
	embers.gravity = Vector2(0, -90)
	embers.initial_velocity_min = 25.0
	embers.initial_velocity_max = 55.0
	embers.scale_amount_min = 2.0
	embers.scale_amount_max = 4.0
	embers.color = Color(1.0, 0.55, 0.18, 0.9)
	n.add_child(embers)

	add_child(n)


func _make_stalactite(pos: Vector2) -> void:
	var p := Polygon2D.new()
	p.position = pos
	p.polygon = PackedVector2Array([Vector2(0, 0), Vector2(9, 36), Vector2(-9, 36)])
	p.color = Color(0.20, 0.18, 0.16)
	add_child(p)


func _make_moss(pos: Vector2) -> void:
	var r := ColorRect.new()
	r.offset_left = -9.0
	r.offset_top = 0.0
	r.offset_right = 9.0
	r.offset_bottom = 4.0
	r.color = Color(0.30, 0.42, 0.26, 0.7)
	add_child(r)


func _make_seal(pos: Vector2) -> void:
	## 深渊寄生物（发光小精灵系）—— 关卡目标视觉占位
	var n := Node2D.new()
	n.position = pos

	var glow := ColorRect.new()
	glow.offset_left = -14.0
	glow.offset_top = -14.0
	glow.offset_right = 14.0
	glow.offset_bottom = 14.0
	glow.color = Color(0.6, 0.85, 0.8, 0.25)
	n.add_child(glow)

	var orb := Polygon2D.new()
	orb.polygon = PackedVector2Array([Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0)])
	orb.color = Color(0.85, 0.98, 0.9)
	n.add_child(orb)

	add_child(n)


# ---------- 房间门 ----------

func _build_doors(room: Dictionary) -> void:
	for d in room.get("doors", []):
		var area := Area2D.new()
		area.position = Vector2(d.x, d.y)
		area.collision_layer = 0
		area.collision_mask = PLAYER_LAYER
		area.set_meta("to", d.to)
		area.set_meta("entry", Vector2(d.entry[0], d.entry[1]))

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(30.0, 110.0)
		shape.shape = rect
		area.add_child(shape)

		var vis := ColorRect.new()
		vis.offset_left = -15.0
		vis.offset_top = -55.0
		vis.offset_right = 15.0
		vis.offset_bottom = 55.0
		vis.color = Color(1.0, 0.45, 0.2, 0.9)
		area.add_child(vis)

		area.body_entered.connect(_on_door_body.bind(area))
		add_child(area)


func _on_door_body(body: Node2D, area: Area2D) -> void:
	if body is CharacterBody2D:
		door_entered.emit(area.get_meta("to"), area.get_meta("entry"))
