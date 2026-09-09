class_name VisualLib
extends RefCounted
## 程序化视觉工具库：发光光晕 / 程序纹理 / 尘土粒子（纯代码生成，无外部素材）
## 对应《美术风格与建模规划》——代码生成色块保底路线的精修版

static var _tex_cache: Dictionary = {}


## 径向发光光晕（叠加混合），radius 为光晕半径（px）
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


## 落地尘土（一次性粒子，调用 restart() 触发）
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


## 土壤 tile（16×16 无缝：斑点 + 微地层）
static func get_dirt_texture() -> ImageTexture:
	if not _tex_cache.has("dirt"):
		var size := 16
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color8(0x5a, 0x46, 0x32))
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260301
		for i in 26:
			var x := rng.randi_range(0, size - 1)
			var y := rng.randi_range(0, size - 1)
			var c := Color8(0x4a, 0x3a, 0x28) if rng.randf() < 0.5 else Color8(0x6b, 0x54, 0x3a)
			img.set_pixel(x, y, c)
			if rng.randf() < 0.5:
				img.set_pixel((x + 1) % size, y, c)
		for x in size:
			img.set_pixel(x, 5, Color8(0x50, 0x3e, 0x2b))
			img.set_pixel(x, 11, Color8(0x50, 0x3e, 0x2b))
		_tex_cache["dirt"] = ImageTexture.create_from_image(img)
	return _tex_cache["dirt"]


## 土壤顶面 tile（16×8：亮顶边 + 草叶）
static func get_dirt_top_texture() -> ImageTexture:
	if not _tex_cache.has("dirt_top"):
		var w := 16
		var h := 8
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		for y in h:
			for x in w:
				var c := Color8(0x6b, 0x54, 0x3a)
				if y == 0:
					c = Color8(0x8a, 0x6f, 0x4a)
				elif y == 1:
					c = Color8(0x7d, 0x63, 0x43)
				img.set_pixel(x, y, c)
		for i in 5:
			var x := rng.randi_range(0, w - 1)
			img.set_pixel(x, 0, Color8(0x5a, 0x7a, 0x3a))
			if rng.randf() < 0.6:
				img.set_pixel(x, 1, Color8(0x4a, 0x6b, 0x3a))
		_tex_cache["dirt_top"] = ImageTexture.create_from_image(img)
	return _tex_cache["dirt_top"]


## 石墙 tile（16×16 无缝：错缝砖 + 砖间色差 + 高光棱）
static func get_stone_texture() -> ImageTexture:
	if not _tex_cache.has("stone"):
		var size := 16
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			var row := 0 if y < 8 else 1
			var off := 4 if row % 2 == 1 else 0
			for x in size:
				var mx := (x + off) % 8
				if y % 8 == 0 or mx == 0:
					img.set_pixel(x, y, Color8(0x35, 0x32, 0x2e))
				else:
					var xx := (x + off) % 16
					var col := 0 if xx < 8 else 1
					var v := ((row * 7 + col) % 5) * 2
					var c := Color8(0x4a + v, 0x47 + v, 0x42 + v)
					if y % 8 == 1 or mx == 1:
						c = Color8(0x56 + v, 0x53 + v, 0x4d + v)
					img.set_pixel(x, y, c)
		_tex_cache["stone"] = ImageTexture.create_from_image(img)
	return _tex_cache["stone"]


## 石墙顶面 tile（16×5：亮顶边）
static func get_stone_top_texture() -> ImageTexture:
	if not _tex_cache.has("stone_top"):
		var w := 16
		var h := 5
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var c := Color8(0x55, 0x52, 0x4d)
				if y == 0:
					c = Color8(0x6a, 0x66, 0x60)
				elif y == 1:
					c = Color8(0x60, 0x5c, 0x56)
				img.set_pixel(x, y, c)
		_tex_cache["stone_top"] = ImageTexture.create_from_image(img)
	return _tex_cache["stone_top"]
