## 验收：每个能被打的实体都声明了 hit_material，且对应音效文件都在。
##
## 为什么单独一条：命中音是按 body.get("hit_material") 现查的，
## 漏一个属性不会报错，只会安静地退回通用命中声——那种错只能靠遍历实体抓。

extends SceneTree

var _fail := 0
var _frames := 0

const ENTITIES := {
	"res://scenes/entities/slime.tscn": "flesh",
	"res://scenes/entities/spore_shooter.tscn": "flesh",
	"res://scenes/entities/dummy_target.tscn": "wood",
	"res://scenes/entities/gatekeeper_boss.tscn": "metal",
}

const MATERIALS := ["flesh", "wood", "metal"]


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok  ", msg)
	else:
		_fail += 1
		printerr("  FAIL ", msg)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	print("[hit_material] 开始")

	for path in ENTITIES:
		var scene := load(path) as PackedScene
		_check(scene != null, "场景能加载：%s" % path)
		if scene == null:
			continue
		var node := scene.instantiate()
		var material := ""
		var raw: Variant = node.get("hit_material")
		if raw != null:
			material = str(raw)
		_check(material != "", "%s 声明了 hit_material" % path.get_file())
		_check(material == ENTITIES[path],
			"%s 的材质是 %s（实际 %s）" % [path.get_file(), ENTITIES[path], material])
		node.free()

	var names := []
	var audio_scene: PackedScene = load("res://scenes/audio/audio_director.tscn")
	if audio_scene != null:
		var audio := audio_scene.instantiate()
		names = audio.get("SFX_NAMES")
		audio.free()
	_check(not names.is_empty(), "能读到 SFX 目录")

	for material: String in MATERIALS:
		var key := "hit_" + material
		_check(key in names, "%s 在 SFX 目录里" % key)
		_check(FileAccess.file_exists("res://assets/audio/sfx_%s.wav" % key),
			"%s 的文件存在" % key)

	if _fail == 0:
		print("[hit_material] PASS")
		quit(0)
	else:
		printerr("[hit_material] FAIL %d 项" % _fail)
		quit(1)
	return true
