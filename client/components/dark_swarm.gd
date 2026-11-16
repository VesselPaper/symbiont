extends Node2D
## 黑影"化雾入体"（M4-54 重写，原版 140 颗硬边圆点）。
##
## 原版为什么看着幼稚：
##   ① 每颗是 draw_circle 画的正圆，边缘是硬的，没有"烟"的厚度；
##   ② 尺寸只有 1.2~3.0，全部一样大，没有前后景；
##   ③ 每颗按自己的随机数抖动，邻近的两颗各走各的 —— 真实的气流里邻居是抱团走的；
##   ④ 不拉伸，速度再快也是个点，看不出"被抽走"。
##
## 这一版的做法（仍然是手写的，不用 GPUParticles：无头回归里要能断言数量与进度）：
##   · 用一张径向渐变贴图当每颗烟丝，边缘自己就化开；
##   · 尺寸按"距离"分层（近的小而实、远的大而淡），有前后景纵深；
##   · 加速度 = 向心 + 切向旋涡 + 相干噪声流场。噪声流场在空间上连续，
##     所以相邻的烟丝会一起拐弯，看起来是同一股气流，而不是一堆跳蚤；
##   · 按速度沿运动方向拉长成条，越快越像被抽走的一缕；
##   · 出生淡入、被吸收前淡出，不会凭空出现/消失。

## 烟丝数量。320 颗时每颗都小，远看像一群黑点（"飞虫感"），
## 240 颗 + 更大的尺寸 + 更长的拉伸，才读成一缕缕被抽走的烟。
const COUNT := 240
## 出生环半径：比原来 180 大一圈，让"整片虚空都在往这里塌"的感觉更足
const SPAWN_RADIUS := 215.0
## 进到这个半径以内就算被身体吸收，不再画
const INNER_RADIUS := 26.0
## 向心加速度：越近越大，所以最后一段是"被拽进去"的快，不是匀速漂
const PULL_NEAR := 1500.0
const PULL_FAR := 260.0
## 切向速度占比：给一团旋涡，而不是所有粒子直冲圆心
const SWIRL_RATIO := 0.62
## 相干噪声流场的强度（px/s²）。太大就散了，太小就看不出气流
const FLOW_STRENGTH := 240.0
## 速度上限：别让烟丝一瞬间穿过去，看不见过程
const MAX_SPEED := 980.0

var _motes: Array[Dictionary] = []
var _trails_tex: GradientTexture2D
var _target := Vector2.ZERO
var _running := false
var _absorber := 0
var _elapsed := 0.0

func _ready() -> void:
	_trails_tex = _make_soft_dot()

func play(origin: Vector2, target: Vector2, duration: float = 10.0) -> void:
	position = origin
	_target = target - origin
	_running = true
	_absorber = 0
	_elapsed = 0.0
	_motes.clear()
	# 分批出生：一开始只有几缕，后面越来越密（后面那半段烟最浓）
	for i in range(COUNT):
		var stagger := float(i) / float(COUNT)
		var delay := stagger * stagger * duration * 0.55
		_motes.append(_make_mote(delay))
	var tw := create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(_finish)

func _make_mote(delay: float) -> Dictionary:
	var a := randf() * TAU
	# 出生点不铺满整个圆：靠近外侧的稀、内侧的密，读起来像从远处慢慢涌来
	var r := SPAWN_RADIUS * sqrt(randf_range(0.10, 1.0))
	var pos := Vector2(cos(a), sin(a) * 0.82) * r
	return {
		"pos": pos,
		"vel": Vector2.ZERO,
		"size": randf_range(3.0, 11.0) * (1.0 + r / SPAWN_RADIUS * 0.8),
		"delay": delay,
		"life": randf_range(1.4, 3.4),
		"age": 0.0,
		"seed": randf() * 100.0,
		"curl": randf_range(0.7, 1.5),
	}

func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	var t := _elapsed
	var alive: Array[Dictionary] = []
	for m in _motes:
		var delay: float = float(m["delay"])
		if delay > 0.0:
			m["delay"] = delay - delta
			alive.append(m)
			continue
		m["age"] = float(m["age"]) + delta
		if float(m["age"]) >= float(m["life"]):
			continue
		var pos: Vector2 = m["pos"]
		var vel: Vector2 = m["vel"]
		var to_target := _target - pos
		var dist := maxf(to_target.length(), 0.001)
		var near := 1.0 - clampf(dist / SPAWN_RADIUS, 0.0, 1.0)
		var pull := lerpf(PULL_FAR, PULL_NEAR, near * near)
		# 向心 + 切向旋涡：所有烟丝朝同一个方向转，才是同一团气
		var inward := to_target / dist
		var tangent := Vector2(-inward.y, inward.x)
		var flow := _flow(pos, t, float(m["seed"]))
		var accel := inward * pull + tangent * pull * SWIRL_RATIO * float(m["curl"]) + flow * FLOW_STRENGTH
		vel += accel * delta
		# 阻尼：没有它烟丝会越转越快，变成弹球
		vel *= 1.0 - minf(1.8 * delta, 0.6)
		if vel.length() > MAX_SPEED:
			vel = vel.normalized() * MAX_SPEED
		m["vel"] = vel
		pos += vel * delta
		m["pos"] = pos
		if pos.distance_to(_target) < INNER_RADIUS:
			_absorber += 1
			continue
		alive.append(m)
	# 补新人：保持"一直有烟在往身体里进"，直到总时长走完
	if alive.size() < COUNT and _elapsed < 8.0:
		var fresh := _make_mote(0.0)
		# 补进来的从外圈起步，不然会从角色身上凭空冒出来
		var back := (fresh["pos"] as Vector2).normalized()
		if back.length() < 0.01:
			back = Vector2.RIGHT
		fresh["pos"] = back * SPAWN_RADIUS * randf_range(0.75, 1.0)
		alive.append(fresh)
	_motes = alive
	queue_redraw()

## 空间上连续的流场：邻居位置相近 → 采样结果相近 → 一起拐弯。
## 用两组正弦交叉，比真噪声便宜得多，但足够读出"有一股气在卷"。
func _flow(pos: Vector2, t: float, seed: float) -> Vector2:
	var x := sin(pos.y * 0.011 + t * 0.55 + seed * 0.07)
	var y := cos(pos.x * 0.013 - t * 0.47 + seed * 0.05)
	return Vector2(x, y).normalized()

func _draw() -> void:
	if _trails_tex == null:
		return
	for m in _motes:
		if float(m["delay"]) > 0.0:
			continue
		var age := float(m["age"])
		var life := float(m["life"])
		var k := clampf(age / life, 0.0, 1.0)
		# 出生淡入 20%，快被吸收时淡出 35%
		var alpha := clampf(k / 0.2, 0.0, 1.0) * clampf((1.0 - k) / 0.35, 0.0, 1.0)
		if alpha <= 0.01:
			continue
		var pos: Vector2 = m["pos"]
		var vel: Vector2 = m["vel"]
		var speed := vel.length()
		# 沿运动方向拉长：越快越像一缕被抽走的烟
		var stretch := 1.0 + clampf(speed / 420.0, 0.0, 2.6)
		var angle := vel.angle() if speed > 8.0 else 0.0
		var s := float(m["size"])
		draw_set_transform(pos, angle, Vector2(stretch, 1.0))
		draw_texture_rect(_trails_tex, Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), false,
			Color(0.020, 0.023, 0.032, 0.92 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 一颗烟的贴图：径向渐变，中间实、边缘完全化开（硬边圆点就是"幼稚"的来源）
func _make_soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.32, 0.62, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.72), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

func _finish() -> void:
	_running = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)

# ---- 给无头回归用的读数 ----

func alive_count() -> int:
	var n := 0
	for m in _motes:
		if float(m["delay"]) <= 0.0:
			n += 1
	return n

func absorbed_count() -> int:
	return _absorber

func is_running() -> bool:
	return _running

## 还在飞的那些烟丝离目标的平均距离：用它判断"是在往里收"还是"在原地乱蹦"
func mean_distance_to_target() -> float:
	var sum := 0.0
	var n := 0
	for m in _motes:
		if float(m["delay"]) > 0.0:
			continue
		sum += (_motes_dist(m))
		n += 1
	if n == 0:
		return 0.0
	return sum / float(n)

func _motes_dist(m: Dictionary) -> float:
	return ((m["pos"] as Vector2) - _target).length()

## 最远那颗离目标多远：用来反向验证没有烟丝被甩到画面外
func max_distance_to_target() -> float:
	var d := 0.0
	for m in _motes:
		d = maxf(d, _motes_dist(m))
	return d
