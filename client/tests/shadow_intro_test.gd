extends SceneTree
## 黑影重构回归（M4-54）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/shadow_intro_test.gd
##
## 组长原话："黑影太幼稚了，改得真实一点、质量高一点"。
## 幼稚的根源是可测的：形状由十几个顶点的折线决定，镜头一推近每条边都是直线；
## 入体的黑雾是 140 颗 draw_circle 的硬边圆点，尺寸全一样、各走各的。
##
## 这里钉四件事：
##   ① 黑影不再是折线剪影（没有 Polygon2D/Line2D 外框），换成着色器算密度的烟体；
##   ② 烟体的三个参数（reveal / dissolve / light）真的到得了着色器，且越界会被夹住；
##   ③ 烟丝：数量够、真的在往里收（平均距离递减）、不会被甩到画面外；
##   ④ 融合开始 5 秒内，黑影本体必须已经压到灵魂身上 ——
##      上一版用满 10 秒挪过去，结果整段时间它都在光圈外，玩家只看见几粒黑点。

const SCENE := "res://scenes/world/prologue.tscn"
const SWARM := "res://components/dark_swarm.gd"

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var level: Node2D = load(SCENE).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	_check_body(level)
	await _check_swarm()
	await _check_fuse_reaches(level)
	_finish()

# ---- ① ② 烟体 ----

func _check_body(level: Node2D) -> void:
	var heart := level.get_node_or_null("Heart") as Node2D
	_check(heart != null, "缺少 Heart 节点")
	if heart == null:
		return
	# 反向：旧版的折线剪影/火舌/外框都不该再存在
	var old_shapes: Array[String] = []
	for name in ["Flame", "Hood", "Outline"]:
		if heart.get_node_or_null(name) != null:
			old_shapes.append(name)
	_check(old_shapes.is_empty(), "旧的折线剪影还在：%s" % ", ".join(old_shapes))
	for child in heart.get_children():
		_check(not (child is Line2D), "Heart 下还有 Line2D（%s）：那又是一根画出来的外框线" % child.name)
		_check(not (child is Polygon2D), "Heart 下还有 Polygon2D（%s）：折线剪影会出直线边" % child.name)

	var body := heart.get_node_or_null("Body") as Node2D
	_check(body != null, "缺少烟体节点 Heart/Body")
	if body == null:
		return
	var quad := body.get_node_or_null("Quad") as Sprite2D
	_check(quad != null, "烟体没有画布子节点 Quad")
	if quad == null:
		return
	var mat := quad.material as ShaderMaterial
	_check(mat != null, "烟体没有用 ShaderMaterial —— 密度必须逐像素算")
	if mat == null:
		return
	var shader := mat.shader
	_check(shader != null and shader.code.findn("fbm") >= 0, "着色器里没有噪声场，边缘会是圆的")
	_check(shader != null and shader.code.findn("dissolve") >= 0, "着色器没有化雾参数")
	for key in ["reveal", "dissolve", "light_local", "quad"]:
		_check(mat.get_shader_parameter(key) != null, "着色器参数 %s 没设上" % key)

	# ② 接口：越界要夹住，不能把 0.4 的 reveal 传成 4
	body.call("set_reveal", 1.8)
	_check(is_equal_approx(body.call("get_reveal"), 1.0), "reveal 超过 1 没被夹住")
	body.call("set_reveal", -0.5)
	_check(is_equal_approx(body.call("get_reveal"), 0.0), "reveal 小于 0 没被夹住")
	body.call("set_dissolve", 2.0)
	_check(is_equal_approx(body.call("get_dissolve"), 1.0), "dissolve 超过 1 没被夹住")
	body.call("set_dissolve", 0.0)
	body.call("set_reveal", 1.0)
	_check(float(mat.get_shader_parameter("dissolve")) == 0.0, "dissolve 没写进着色器")
	print("[shadow] 烟体 = 着色器密度场，参数 reveal/dissolve/light 就位")

# ---- ③ 烟丝 ----

func _check_swarm() -> void:
	var swarm: Node2D = load(SWARM).new()
	root.add_child(swarm)
	await process_frame
	var origin := Vector2.ZERO
	var target := Vector2(0, -260)
	swarm.call("play", origin, target, 4.0)
	await create_timer(1.0).timeout
	var early_count := int(swarm.call("alive_count"))
	var early_absorbed := int(swarm.call("absorbed_count"))
	var max_d := float(swarm.call("max_distance_to_target"))
	await create_timer(1.5).timeout
	var late_absorbed := int(swarm.call("absorbed_count"))
	# 数量：密度要够，140 颗的时代结束了
	_check(early_count >= 120, "同时在飞的烟丝太少（%d）" % early_count)
	# 方向：吸收数在涨，说明真的是一颗一颗进到身体里，不是在原地乱飘。
	# （这里不能比"平均距离"：烟是持续补的，均值一直由刚出生的外圈烟丝撑着，
	#   上一版就是这么写出一个假断言的）
	_check(late_absorbed > early_absorbed,
		"没有烟丝被吸进去（吸收数 %d → %d）" % [early_absorbed, late_absorbed])
	# 反向：不该有烟丝被甩到出生圈之外（出生圈 215 + 目标距原点 260）
	_check(max_d <= 215.0 + 260.0 + 40.0, "有烟丝飞到出生圈外（最远 %.0f）" % max_d)
	print("[shadow] 烟丝 %d 颗，累计吸收 %d → %d，最远 %.0f" % [
		early_count, early_absorbed, late_absorbed, max_d])
	# 收尾：时长走完后节点自己释放，不留一堆空转的
	await create_timer(3.2).timeout
	_check(not is_instance_valid(swarm), "时长走完了烟丝节点还没释放")

# ---- ④ 黑影必须真的压到身上 ----

func _check_fuse_reaches(level: Node2D) -> void:
	var soul := level.get_node_or_null("Soul") as Node2D
	var heart := level.get_node_or_null("Heart") as Node2D
	if soul == null or heart == null:
		return
	soul.position = Vector2(900, 560)
	await process_frame
	level.call("_fuse")
	await create_timer(5.0).timeout
	if not is_instance_valid(heart):
		_check(false, "融合 5 秒后 Heart 已经没了，黑影没来得及压上来")
		return
	var dist := heart.global_position.distance_to(soul.global_position)
	print("[shadow] 融合 5 秒时黑影距灵魂 %.0fpx" % dist)
	_check(dist <= 60.0, "融合 5 秒时黑影还在 %.0fpx 外，玩家根本看不见它" % dist)
	var body := heart.get_node_or_null("Body") as Node2D
	if body != null:
		var reveal := float(body.call("get_reveal"))
		var dissolve := float(body.call("get_dissolve"))
		print("[shadow] 融合 5 秒时 reveal=%.2f dissolve=%.2f" % [reveal, dissolve])
		_check(reveal >= 0.8, "都贴到跟前了还不显形（reveal=%.2f）" % reveal)
		_check(dissolve < 1.0, "还没贴上来就已经化光了（dissolve=%.2f）" % dissolve)

	# 胸口那点紫的尺寸：它是 Sprite2D（贴图 256px），scale 的语义是"半径/128"。
	# 换节点类型时最容易翻车的地方 —— 原来的 scale=1.9 在 Polygon2D 上是 1.9 倍半径，
	# 到 Sprite2D 上就是 1.9×256px 的一坨大白，整屏都糊了。
	var core := heart.get_node_or_null("Core") as Sprite2D
	_check(core != null, "缺少胸口核心 Heart/Core")
	if core != null:
		var radius_px := 128.0 * core.scale.x
		var zoom := 1.0
		var cam := level.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			zoom = cam.zoom.x
		print("[shadow] 胸口核心半径 %.1fpx（屏幕 %.1fpx）" % [radius_px, radius_px * zoom])
		_check(radius_px <= 24.0, "胸口核心半径 %.1fpx 太大，说明 scale 又被当成倍率用了" % radius_px)
		# 脉冲乘数必须被夹在合理区间：它是唯一的 scale 写者
		var pulse := float(level.get("_core_pulse"))
		_check(pulse >= 0.5 and pulse <= 1.6, "心跳脉冲乘数跑飞了（_core_pulse=%.2f）" % pulse)

func _finish() -> void:
	print("[shadow] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[shadow] " + msg)
		_failed = true
