extends Node2D
## 高草丛（M5-37）：沿地面长一片很高的草，玩家走过去会被拨动。
##
## 为什么做成"一整片一个脚本"而不是每根草一个节点：教学关地面有 22000px 长，
## 一根草一个 _process 就是几百个脚本在每帧跑，白白吃掉帧。这里一片草共用一个计时器，
## 每 0.1 秒只检查玩家附近（160px 内）的那几丛，其余直接跳过。
##
## 用法：new() 之后设置 from_x / to_x / ground_y / tuft_step，再加进场景。

@export var from_x := 0.0
@export var to_x := 0.0
@export var ground_y := 659.0
## 两丛草之间的间距（px）
@export var tuft_step := 34.0
## 草的高度范围
@export var min_height := 22.0
@export var max_height := 46.0
## 玩家在这个距离内经过，草会被拨动
@export var brush_radius := 90.0
@export var seed_value := 20261117

## 每丛草：{node, base_rot, sway, phase, bent}
var _tufts: Array = []
var _time := 0.0
var _check_timer := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = seed_value
	z_index = -1          # 压在角色后面（草是地面上的装饰）
	_build()

func _build() -> void:
	var x := from_x
	while x < to_x:
		var tuft := Node2D.new()
		tuft.position = Vector2(x, ground_y)
		add_child(tuft)
		var blades := int(_rng.randf_range(4.0, 9.0))
		for i in range(blades):
			var blade := Line2D.new()
			blade.width = _rng.randf_range(1.6, 2.6)
			var tone := _rng.randf_range(0.10, 0.17)
			blade.default_color = Color(tone * 0.85, tone * 1.35, tone * 1.05, _rng.randf_range(0.55, 0.8))
			var lx := _rng.randf_range(-9.0, 9.0)
			var h := _rng.randf_range(min_height, max_height)
			var lean := _rng.randf_range(-9.0, 11.0)
			blade.points = PackedVector2Array([
				Vector2(lx, 1.0),
				Vector2(lx + lean * 0.35, -h * 0.55),
				Vector2(lx + lean, -h),
			])
			tuft.add_child(blade)
		# 根部一小块暗色，让草不是凭空长在亮面上
		var root := Polygon2D.new()
		root.color = Color(0.045, 0.060, 0.052, 0.55)
		root.polygon = PackedVector2Array([
			Vector2(-11, 2), Vector2(11, 2), Vector2(7, -2), Vector2(-7, -2),
		])
		tuft.add_child(root)
		_tufts.append({
			"node": tuft,
			"base_x": x,
			"phase": _rng.randf_range(0.0, TAU),
			"sway": _rng.randf_range(0.6, 1.8),
		})
		x += tuft_step * _rng.randf_range(0.7, 1.4)

func _process(delta: float) -> void:
	_time += delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var px := player.global_position.x if player != null else -100000.0
	var py := player.global_position.y if player != null else 0.0
	_check_timer += delta
	var do_check := _check_timer >= 0.1
	if do_check:
		_check_timer = 0.0
	# 只处理玩家附近的一小段：草是按 x 顺序排的，二分找起点再往后扫
	var start := 0
	var lo := 0
	var hi := _tufts.size() - 1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(_tufts[mid]["base_x"]) < px - 260.0:
			lo = mid + 1
		else:
			hi = mid - 1
	start = maxi(lo - 2, 0)
	for i in range(start, mini(start + 16, _tufts.size())):
		var tuft: Dictionary = _tufts[i]
		var node := tuft["node"] as Node2D
		if node == null:
			continue
		var dx := float(tuft["base_x"]) - px
		var bend := 0.0
		if do_check and absf(dx) < brush_radius and absf(py - ground_y) < 90.0:
			bend = -signf(dx) * (1.0 - absf(dx) / brush_radius) * 0.55
		# 风：慢慢摆；被拨动时额外往一侧歪，然后弹回来
		var wind := sin(_time * 1.6 + float(tuft["phase"])) * 0.06 * float(tuft["sway"])
		node.rotation = lerpf(node.rotation, bend + wind, clampf(delta * 8.0, 0.0, 1.0))
