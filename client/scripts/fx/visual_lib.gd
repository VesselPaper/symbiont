class_name VisualLib
extends RefCounted
## 程序化视觉工具库：光晕 / 粒子 / Kenney 素材包贴图加载
## 素材：assets/vendor/kenney_tiny-dungeon（CC0）+ fantasy-ui-borders（CC0）
## 对应《美术风格与建模规划》素材来源章节

static var _pack_cache: Dictionary = {}


## 加载 Kenney Tiny Dungeon 的 16×16 tile（缓存）
static func pack(tile: String) -> Texture2D:
	if not _pack_cache.has(tile):
		_pack_cache[tile] = load("res://assets/vendor/kenney_tiny-dungeon/Tiles/" + tile + ".png")
	return _pack_cache[tile]


# ---- 地形贴图 ----
static func get_dirt_texture() -> Texture2D:
	return pack("tile_0000")
static func get_dirt_top_texture() -> Texture2D:
	return pack("tile_0002")
static func get_stone_texture() -> Texture2D:
	return pack("tile_0007")
static func get_stone_top_texture() -> Texture2D:
	return pack("tile_0009")


# ---- 角色 / 敌人 / 门 ----
static func get_hero_texture() -> Texture2D:
	return pack("tile_0104")
static func get_enemy_patrol_texture() -> Texture2D:
	return pack("tile_0103")
static func get_enemy_spitter_texture() -> Texture2D:
	return pack("tile_0108")
static func get_enemy_diver_texture() -> Texture2D:
	return pack("tile_0116")
static func get_door_texture() -> Texture2D:
	return pack("tile_0117")


## 径向发光光晕（叠加混合）
static func make_glow(radius: float, color: Color, alpha := 0.35) -> Sprite2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(color.r, color.g, color.b, alpha),
		Color(color.r, color.g, color.b, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2.ONE * (radius * 2.0 / 128.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = mat
	return spr


## 一次性粒子（尘土 / 死亡爆散）
static func make_dust_puff() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 8
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 85.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 55.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Color(0.62, 0.58, 0.5, 0.55)
	return p
