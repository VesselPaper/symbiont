extends Node2D
## 黑雾改粒子：一大群黑色小点从四周被吸进目标身体（M4-49）。
##
## 不用雾锥也不用 GPUParticles：这里要的是"大量黑粒子持续涌入"的密度感，
## 手写还能在无头回归里断言粒子数与被吸收进度。

const COUNT := 140
const SPAWN_RADIUS := 180.0
const INNER_RADIUS := 26.0

var _particles: Array = []
var _target := Vector2.ZERO
var _running := false

func play(origin: Vector2, target: Vector2, duration: float = 10.0) -> void:
	position = origin
	_target = target - origin
	_running = true
	_particles.clear()
	for i in range(COUNT):
		_spawn_one(float(i) / float(COUNT) * duration)
	var tw := create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(_finish)

## 每颗粒子从外圈随机方向出现，带一点切向速度，往里卷
func _spawn_one(delay: float = 0.0) -> void:
	var a := randf() * TAU
	var r := SPAWN_RADIUS * randf_range(0.5, 1.0)
	var pos := Vector2(cos(a), sin(a) * 0.8) * r
	var tangent := Vector2(-sin(a), cos(a)) * randf_range(-30.0, 30.0)
	_particles.append({
		"pos": pos,
		"vel": tangent,
		"size": randf_range(1.2, 3.0),
		"delay": delay,
		"life": randf_range(1.2, 2.6),
		"age": 0.0,
	})

func _process(delta: float) -> void:
	if not _running:
		return
	var alive: Array = []
	for p in _particles:
		var d: float = float(p["delay"])
		if d > 0.0:
			p["delay"] = d - delta
			alive.append(p)
			continue
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["life"]):
			continue
		var pos := Vector2(p["pos"])
		# 向目标加速（越近越快），再加一点随机抖动，看起来是"被吸进去"
		var to_target := _target - pos
		var pull := to_target.normalized() * (220.0 + 520.0 * (1.0 - clampf(to_target.length() / SPAWN_RADIUS, 0.0, 1.0)))
		var vel := (Vector2(p["vel"]) + pull * 3.0 + Vector2(randf_range(-40, 40), randf_range(-40, 40))) * 0.92
		p["vel"] = vel
		p["pos"] = pos + vel * delta
		if p["pos"].distance_to(_target) < INNER_RADIUS:
			continue
		alive.append(p)
	# 持续补充，保持"一直有粒子在往身体里进"
	if alive.size() < COUNT:
		_spawn_one()
	_particles = alive
	queue_redraw()

func _draw() -> void:
	for p in _particles:
		if float(p["delay"]) > 0.0:
			continue
		var k: float = clampf(1.0 - float(p["age"]) / float(p["life"]), 0.0, 1.0)
		draw_circle(Vector2(p["pos"]), float(p["size"]), Color(0.02, 0.02, 0.03, 0.95 * k))

func _finish() -> void:
	_running = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)

func alive_count() -> int:
	return _particles.size()

func is_running() -> bool:
	return _running
