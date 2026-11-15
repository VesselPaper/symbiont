extends Node2D
## 刀光碎屑：命中/挥砍瞬间沿刀弧溅出一小把短亮线，0.18s 内飞散淡出。
##
## 不用 GPUParticles：一是无头回归里粒子不渲染、断言不到；二是这里要的只是几条
## 短线段，手写反而更可控（方向顺着刀弧、长度随机、颜色跟刀光一致）。

const LIFE := 0.18
const COUNT := 7
const SPEED_MIN := 60.0
const SPEED_MAX := 150.0

var _sparks: Array = []   # 每条：{pos, vel, len, life, max_life}

func burst(arc_points: PackedVector2Array, dir: int = 1) -> void:
	if arc_points.size() < 2:
		return
	for i in range(COUNT):
		var t := float(i) / float(maxi(COUNT - 1, 1))
		var idx := clampi(int(t * (arc_points.size() - 1)), 0, arc_points.size() - 1)
		var at := arc_points[idx]
		var out := at.normalized()
		if out.length() < 0.01:
			out = Vector2(float(dir), 0.0)
		var speed := randf_range(SPEED_MIN, SPEED_MAX)
		_sparks.append({
			"pos": at,
			"vel": out * speed + Vector2(float(dir) * 40.0, randf_range(-30.0, 10.0)),
			"len": randf_range(3.0, 8.0),
			"life": LIFE * randf_range(0.7, 1.0),
			"max_life": LIFE,
		})
	queue_redraw()

func _process(delta: float) -> void:
	if _sparks.is_empty():
		return
	var alive: Array = []
	for s in _sparks:
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			continue
		s["pos"] = Vector2(s["pos"]) + Vector2(s["vel"]) * delta
		s["vel"] = Vector2(s["vel"]) * 0.88
		alive.append(s)
	_sparks = alive
	queue_redraw()

func _draw() -> void:
	for s in _sparks:
		var k: float = clampf(float(s["life"]) / float(s["max_life"]), 0.0, 1.0)
		var pos := Vector2(s["pos"])
		var tail := pos - Vector2(s["vel"]).normalized() * float(s["len"]) * k
		draw_line(tail, pos, Color(0.92, 0.98, 1.0, 0.85 * k), 1.6, true)

## 给回归用：当前还活着的碎屑数量
func alive_count() -> int:
	return _sparks.size()
