extends Node2D
## 黑影的"体"（M4-54）：一片会缓慢翻滚的黑烟，用片元着色器逐像素算密度。
##
## 为什么换掉原来的 Polygon2D 剪影：
##   折线剪影只有十几个顶点，镜头推到 1.4~1.7 倍时每条边都有几十像素长，
##   一眼就是"贴上去的色块"；再往外画几个三角形当火舌，更像纸片。
##   真实的烟/影没有边 —— 密度从里到外连续掉到 0，边界还被气流推着缓慢变形。
##   这两件事都是逐像素的活，只能写进着色器。
##
## 为什么用梯度噪声 + 域扭曲，而不是一坨随机数：
##   值噪声的等高线是一圈方块台阶（第一版就是这么翻车的），看着像 JPEG 坏块；
##   梯度噪声是连续的，再让坐标自己按噪声弯一下（域扭曲），边界才会"卷"起来 ——
##   烟的所有看头都在这个卷边上。
##
## 对外接口（prologue.gd 只碰这几样，别直接写节点树）：
##   set_time(t)            推进内部翻滚
##   set_reveal(0~1)        远处只剩很淡的一层，走近才压实
##   set_dissolve(0~1)      化雾时从外缘往里被抽走
##   set_light_local(pos)   灵魂在体局部的像素坐标，用来决定背光那一侧的高光
##
## 无头回归里可以拿到 shader 参数直接断言（见 tests/shadow_intro_test.gd）。

## 体的大小（像素）。比原来的剪影大一圈：多出来的部分全是散开的边，
## 真正"实"的核心还在原来剪影那个尺度上。
var quad_size := Vector2(520.0, 660.0)
## 实心部分的颜色：接近纯黑，但和虚空留一点差，不然完全看不出有东西
var body_color := Color(0.004, 0.005, 0.009, 1.0)
## 薄处的颜色：偏冷的灰，像烟透光
var edge_color := Color(0.075, 0.085, 0.112, 1.0)
## 背光轮廓光（冷蓝），只在朝灵魂那一侧、且光真的照得到的地方出现
var rim_color := Color(0.30, 0.34, 0.46, 1.0)

var _body: Sprite2D
var _mat: ShaderMaterial
var _time := 0.0
var _reveal := 1.0
var _dissolve := 0.0

const SHADOW_SHADER := """
shader_type canvas_item;

uniform float time = 0.0;
uniform float reveal = 1.0;
uniform float dissolve = 0.0;
uniform vec2 quad = vec2(520.0, 660.0);
uniform vec4 body_col : source_color = vec4(0.004, 0.005, 0.009, 1.0);
uniform vec4 edge_col : source_color = vec4(0.075, 0.085, 0.112, 1.0);
uniform vec4 rim_col : source_color = vec4(0.30, 0.34, 0.46, 1.0);
uniform float rim_amount = 0.55;
uniform vec2 light_local = vec2(0.0, 0.0);
uniform float seed = 0.0;

// 梯度噪声：格点上给随机方向，格内做点积插值 —— 结果是连续的，
// 不会出现值噪声那种一圈方块台阶
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p + seed) * 43758.5453123);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// 五次插值：一阶导也连续，边缘不会有折角
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash22(i), f);
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 每层转一点角度，避免各层格子对齐后出现方格纹理
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 4; i++) {
		v += amp * gnoise(p);
		p = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)) * p * 2.07 + vec2(11.3, 7.1);
		amp *= 0.5;
	}
	return v * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = UV;
	// 画布边缘强制淡到 0。形状本身不该长到画布边上，这一层是保险：
	// 少了它，密度在边界上还剩一点，屏幕上就会出现一条笔直的矩形边（踩过这个坑）。
	float edge_fade = smoothstep(0.0, 0.16, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));

	// u 在 [-1,1]，原点在体中心
	vec2 u = (uv - 0.5) * 2.0;

	// 形状：上窄下宽的烟柱。t = 0 是顶，1 是底。
	float t = clamp(u.y * 0.5 + 0.5, 0.0, 1.0);
	float widen = mix(0.60, 1.0, smoothstep(0.02, 0.72, t));

	// 形体边界落在 |u| ≈ 0.65，四周留出散开的余量
	// （系数越大形体越小；这里第一版写成 0.68，形体直接撑满画布，出来是个方块）
	vec2 q = vec2(u.x / widen, u.y + 0.10) * 1.35;

	// 域扭曲：先让坐标自己按噪声弯一下，边界才会有"卷"，而不是一圈圆起伏
	vec2 w = vec2(fbm(q * 0.85 + vec2(0.0, -time * 0.05)),
				  fbm(q * 0.85 + vec2(4.7, -time * 0.05)));
	vec2 qw = q + (w - 0.5) * 0.85;

	// 半径：低频撕边 + 中频起伏 + 高频颗粒
	float r = length(qw);
	r += (fbm(qw * 1.6 - vec2(0.0, time * 0.09)) - 0.5) * 0.40;
	r += (fbm(qw * 3.7 + vec2(7.3, 0.0)) - 0.5) * 0.18;
	r += (fbm(qw * 7.5 - vec2(0.0, time * 0.30)) - 0.5) * 0.07;

	// 密度：宽的 softstep 收尾 —— 边缘不是一条线，是一段透明到实的过渡
	float body = 1.0 - smoothstep(0.50, 1.04, r);

	// 内部密度斑块：真实烟的明暗是成片变化的，均匀一团灰会显得像塑料
	float veins = fbm(qw * 2.4 + vec2(0.0, -time * 0.16));
	body *= 0.42 + 0.58 * smoothstep(0.30, 0.72, veins);
	// 再叠一层细的"缕"：远看是烟里的丝，近看让边缘不是一块均匀的糊
	float ribbons = fbm(qw * 5.6 + vec2(time * 0.02, -time * 0.40));
	body *= 0.82 + 0.18 * smoothstep(0.18, 0.82, ribbons);

	// 顶部撕成丝：越往上越容易被噪声打散，读起来是烟往上散，而不是剪影收了顶
	float top = smoothstep(0.60, 0.0, t);
	float strand = smoothstep(0.30, 0.66, fbm(qw * 2.9 + vec2(3.0, -time * 0.38)));
	body *= mix(1.0, strand, top * 0.85);

	// 颜色：真实烟是"薄处散射发灰、厚处吸收发黑"。
	// 这一点在这里很关键 —— 虚空本身是纯黑，通体纯黑的烟等于隐形，
	// 只能靠一圈画出来的线读形状（旧版就是这么变成"贴纸"的）。
	// 现在薄边留一点冷灰（对黑底可见），核心压到近黑（挡住后面的光）。
	float dens = 1.0 - smoothstep(0.0, 0.62, r);
	vec3 col = mix(edge_col.rgb, body_col.rgb, pow(clamp(dens, 0.0, 1.0), 1.4));

	// 背光轮廓：整团在纯黑的虚空里本来是一点看不到的 —— 旧版靠一圈折线外框读形状，
	// 那也是"贴纸感"的来源。这里改成贴着烟自己边界的冷色散射：远处留一点（0.30），
	// 光越近越亮。既没有一根画出来的线，又能把形状从黑底上托出来。
	// light_local 是像素坐标，先换算到和 u 同一套 [-1,1]。
	vec2 light_u = light_local / quad * 2.0;
	vec2 to_light = normalize(light_u - u + vec2(0.0001, 0.0001));
	float lit = clamp(dot(normalize(qw + vec2(0.0001, 0.0001)), to_light) * 0.5 + 0.5, 0.0, 1.0);
	float prox = 1.0 - smoothstep(0.30, 1.10, length(u - light_u));
	float rim_band = smoothstep(0.45, 0.78, r) * (1.0 - smoothstep(0.86, 1.06, r));
	col += rim_col.rgb * rim_band * rim_amount * mix(1.0, pow(lit, 1.7), prox) * (0.45 + 0.55 * prox);

	// 化雾：从外缘往里被抽走。用 1.02 - r 当"保留下来的程度"，
	// dissolve 越大门槛越高，dissolve=1 时连中心也留不住；
	// 边界已被噪声打碎，不会出现整齐的切口。
	// 注意：alpha 必须在化雾之后算。上一版先把 `a_final` 算好、再来乘 keep，
	// 结果 keep 只改了 body 却没进 COLOR，化雾整段是空转（靠逐档量覆盖率才发现的）。
	float th = dissolve * 1.05;
	float keep = th <= 0.001 ? 1.0 : smoothstep(th - 0.28, th + 0.06, 1.02 - r);
	body *= keep * edge_fade;

	float a = clamp(body * 1.18, 0.0, 1.0) * clamp(reveal, 0.0, 1.0);
	if (a <= 0.002) {
		discard;
	}
	COLOR = vec4(col, a);
}
"""

func _ready() -> void:
	_body = Sprite2D.new()
	# 名字别叫 Body：烟体节点自己已经叫 Body，同名会让 get_node("Body") 拿到外层
	_body.name = "Quad"
	# 1×1 白图当画布：UV 照样是 0..1，整块矩形都交给着色器算
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	_body.texture = ImageTexture.create_from_image(img)
	_body.scale = quad_size
	_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADOW_SHADER
	_mat.shader = shader
	_mat.set_shader_parameter("quad", quad_size)
	# 三个对外参数先给初值：不然 get_shader_parameter 拿回来是 null，
	# 外面（包括测试）读不到"现在是多少"，只能读到"没设过"
	_mat.set_shader_parameter("time", 0.0)
	_mat.set_shader_parameter("reveal", _reveal)
	_mat.set_shader_parameter("dissolve", _dissolve)
	_mat.set_shader_parameter("light_local", Vector2.ZERO)
	_mat.set_shader_parameter("body_col", body_color)
	_mat.set_shader_parameter("edge_col", edge_color)
	_mat.set_shader_parameter("rim_col", rim_color)
	_mat.set_shader_parameter("rim_amount", 0.55)
	# 每团烟的噪声相位不同，不然同时出现两团会一模一样
	_mat.set_shader_parameter("seed", randf() * 40.0)
	_body.material = _mat
	add_child(_body)

func _process(delta: float) -> void:
	# 自己推进时间，调用方不用每帧喂；外部 set_time 仍可覆盖
	_time += delta
	if _mat != null:
		_mat.set_shader_parameter("time", _time)

func set_time(t: float) -> void:
	_time = t
	if _mat != null:
		_mat.set_shader_parameter("time", _time)

func set_reveal(v: float) -> void:
	_reveal = clampf(v, 0.0, 1.0)
	if _mat != null:
		_mat.set_shader_parameter("reveal", _reveal)

func set_dissolve(v: float) -> void:
	_dissolve = clampf(v, 0.0, 1.0)
	if _mat != null:
		_mat.set_shader_parameter("dissolve", _dissolve)

func set_light_local(pos: Vector2) -> void:
	if _mat != null:
		_mat.set_shader_parameter("light_local", pos)

func get_reveal() -> float:
	return _reveal

func get_dissolve() -> float:
	return _dissolve

func shader_material() -> ShaderMaterial:
	return _mat

func body_node() -> Sprite2D:
	return _body
