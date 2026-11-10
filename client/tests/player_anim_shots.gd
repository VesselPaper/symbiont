extends SceneTree
## 玩家动作特写（开发用，手动跑）：
##   Godot_v4.7.2-stable_win64_console.exe --path client --script res://tests/player_anim_shots.gd
## 单独实例化玩家、关掉物理，按时间摆出 待机/挥砍/下劈/受击/倒地/复活 六个姿势各拍一张。

const PLAYER := "res://scenes/player/player.tscn"
const OUT_DIR := "res://shots"

var _elapsed := 0.0
var _started := false
var _player: Node2D
var _shots: Array = [
	{"t": 0.18, "name": "player_empty_hand", "action": ""},
	{"t": 0.22, "name": "", "action": "equip"},
	{"t": 0.30, "name": "player_idle", "action": ""},
	{"t": 0.34, "name": "", "action": "slash"},
	{"t": 0.42, "name": "player_slash_windup", "action": ""},
	{"t": 0.50, "name": "player_slash", "action": ""},
	{"t": 0.72, "name": "", "action": "pogo"},
	{"t": 0.82, "name": "player_pogo", "action": ""},
	{"t": 1.00, "name": "", "action": "end_pogo"},
	{"t": 1.05, "name": "", "action": "hurt"},
	{"t": 1.14, "name": "player_hurt", "action": ""},
	{"t": 1.30, "name": "", "action": "die"},
	{"t": 1.48, "name": "player_death", "action": ""},
	{"t": 2.48, "name": "player_revive", "action": ""},
]
var _index := 0

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var bg := ColorRect.new()
		bg.color = Color(0.075, 0.095, 0.110, 1.0)
		bg.size = Vector2(1280, 720)
		root.add_child(bg)
		var ground := Polygon2D.new()
		ground.color = Color(0.16, 0.18, 0.19, 1.0)
		ground.polygon = PackedVector2Array([Vector2(380, 414), Vector2(900, 414), Vector2(900, 520), Vector2(380, 520)])
		root.add_child(ground)
		_player = load(PLAYER).instantiate() as Node2D
		_player.position = Vector2(640, 400)
		root.add_child(_player)
		_player.set_physics_process(false)
		var cam := Camera2D.new()
		cam.zoom = Vector2(5.5, 5.5)
		cam.position = Vector2(640, 372)
		root.add_child(cam)
		cam.make_current()
		return false
	_elapsed += delta
	if _index >= _shots.size():
		quit(0)
		return true
	var item: Dictionary = _shots[_index]
	if _elapsed >= item["t"]:
		var action: String = item["action"]
		if action != "":
			_do_action(action)
		else:
			_save(str(item["name"]) + ".png")
		_index += 1
	return false

func _do_action(action: String) -> void:
	match action:
		"equip":
			_player.set("has_weapon", true)
			_player.set("_weapon_flash_timer", 0.35)
		"slash":
			_player.call("_start_side_slash")
		"pogo":
			_player.set("_pogo_active", true)
			_player.set("_attack_anim_timer", 0.38)
			_player.set("_attack_anim_kind", 1)
		"end_pogo":
			_player.set("_pogo_active", false)
		"hurt":
			_player.call("take_damage", 1)
		"die":
			_player.call("_die")

func _save(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name])
	img.save_png(path)
	print("[anim] t=%.2fs %s" % [_elapsed, path])
