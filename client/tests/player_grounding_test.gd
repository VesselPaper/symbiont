extends SceneTree
## 主角踩地校准回归（M5-26）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/player_grounding_test.gd
##
## 组长反馈：「主角有些时候看着像悬空在地面上。」两个原因，各钉一条：
##   ① 画的底边和碰撞盒底边没对齐 —— 贴图本身下沿有空行，画出来比碰撞盒高 0.66 单位；
##   ② 待机/走路的起伏写成了"往上抬"，而整幅画（含脚）挂在 Body 上，一抬就离地。
## 这条测试直接量：站在地上、跑动画的时候，**画的底边不许比碰撞盒底边高**。

const SCENE := "res://scenes/player/player.tscn"
## 角色碰撞盒 14×26，原点在中心 → 脚底线在 +13
const HALF_HEIGHT := 13.0
## 允许的误差：画的底边可以比脚底线低（踩进地里）到 1.5，但**不能高**过 0.2
const MAX_ABOVE := 0.2
const MAX_BELOW := 1.5

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var level := Node2D.new()
	level.name = "Level"
	root.add_child(level)
	var ground := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000, 60)
	col.shape = shape
	col.name = "CollisionShape2D"
	ground.add_child(col)
	ground.position = Vector2(0, 40)
	level.add_child(ground)

	var player: CharacterBody2D = load(SCENE).instantiate()
	player.position = Vector2(0, 0)
	level.add_child(player)
	for _i in range(30):
		await physics_frame
	_check(player.is_on_floor(), "人没落地，测试场景不成立")

	# 量"画的底边"：Body 下所有 Sprite2D 的贴图不透明区域最低那行换算成局部坐标
	var art_bottom := _art_bottom(player)
	print("[grounding] 画的底边 %.2f（脚底线 %.2f）" % [art_bottom, HALF_HEIGHT])
	_check(art_bottom >= HALF_HEIGHT - MAX_ABOVE,
		"画的底边比脚底线高 %.2f（会看着悬空）" % (HALF_HEIGHT - art_bottom))

	# 待机 1.5 秒：Body 只许往下沉，不许往上抬
	var worst_idle: float = await _sample_body_y(player, 90, 0.0)
	_check(worst_idle >= -0.05, "待机时身体被抬起了 %.2f（离地）" % worst_idle)

	# 走路 1.5 秒：同样只许往下
	Input.action_press("move_right")
	var worst_walk: float = await _sample_body_y(player, 90, 0.0)
	Input.action_release("move_right")
	_check(worst_walk >= -0.05, "走路时身体被抬起了 %.2f（离地）" % worst_walk)

	# 走路过程中再量一次画的底边：Body 下沉只会让它更低，不会更高
	var walk_bottom := _art_bottom(player)
	_check(walk_bottom >= HALF_HEIGHT - MAX_ABOVE,
		"走路时画的底边高于脚底线 %.2f" % (HALF_HEIGHT - walk_bottom))
	_check(walk_bottom <= HALF_HEIGHT + MAX_BELOW,
		"走路时画沉进地里 %.2f，太夸张" % (walk_bottom - HALF_HEIGHT))

	level.queue_free()
	await process_frame
	print("[grounding] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

## 脚那一片的底边：只看 Silhouette（黑影+衣摆），斗篷下摆本来就该拖到地上，不能算进来。
## 换算到 Player 局部坐标：sprite 左上角（含父节点变换）+ 不透明区最下一行 × 缩放。
func _art_bottom(player: Node2D) -> float:
	var body := player.get_node_or_null("Body") as Node2D
	if body == null:
		return -999.0
	var sp := body.get_node_or_null("Silhouette") as Sprite2D
	if sp == null or sp.texture == null:
		return -999.0
	var img := sp.texture.get_image()
	var used := img.get_used_rect()
	var bottom_row := float(used.position.y + used.size.y)
	var local := sp.get_transform().origin.y + bottom_row * sp.scale.y
	return body.position.y + local * body.scale.y

## 采样 Body 的竖直偏移（取最小值，也就是"被抬得最高"的那一帧）
func _sample_body_y(player: Node, frames: int, _unused: float) -> float:
	var worst := 0.0
	for _i in range(frames):
		await physics_frame
		var body := player.get_node_or_null("Body") as Node2D
		if body != null:
			worst = minf(worst, body.position.y)
	return worst

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[grounding] " + msg)
		_failed = true
