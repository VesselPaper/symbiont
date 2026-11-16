extends SceneTree
## 序章重构回归（M4-24）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/prologue_test.gd
##
## 组长反馈“虚空质感差、直接弹文字、节奏太快”，这里按可测的部分钉住：
##   ① 环境不再是“纯黑 + 一条硬地面线”：有分层雾、两层尘埃、柔边视野圈；
##   ② 耳语贴着角色出现（是 Soul / Heart 的子节点），不是屏幕中央通告；
##   ③ 移动是带惯性的漂浮（松手还在滑一段、不会瞬移），不是直接改坐标；
##   ④ 开场不抢话：头一秒不弹任何字；走近身影才融合。

const SCENE := "res://scenes/world/prologue.tscn"
const MAX_STEP_PER_FRAME := 6.0   # 150px/s ÷ 60fps ≈ 2.5；超过 6 就是瞬移

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.25).timeout
	var level: Node2D = load(SCENE).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var soul := level.get_node_or_null("Soul") as Node2D
	var heart := level.get_node_or_null("Heart") as Node2D
	_check(soul != null, "缺少 Soul 节点")
	_check(heart != null, "缺少 Heart 节点")
	if soul == null or heart == null:
		_finish()
		return

	# ① 环境：旧的硬地面线必须已经删掉，换成雾/尘/柔边视野圈
	_check(level.get_node_or_null("Ground") == null, "旧的灰白地面线还在，虚空会显得很假")
	var fog := 0
	var motes := 0
	for child in level.get_children():
		if child is Polygon2D and str(child.name).begins_with("@"):
			fog += 1
		if child is CPUParticles2D:
			motes += 1
	_check(motes >= 2, "尘埃层不足（%d）" % motes)
	# M4-29：只有角色周围一小圈有光 —— 黑幕必须存在，且洞心跟着灵魂
	var dark_mask := level.get_node_or_null("UI/Darkness") as ColorRect
	_check(dark_mask != null, "缺少黑幕（其余区域应该是看不见的）")
	if dark_mask != null and dark_mask.material is ShaderMaterial:
		var mat := dark_mask.material as ShaderMaterial
		var hole: Vector2 = mat.get_shader_parameter("hole")
		var radius: float = float(mat.get_shader_parameter("radius"))
		_check(radius <= 140.0, "光斑太大（radius=%.0f），整片都看得见了" % radius)
		_check(hole.distance_to(Vector2(250, 560)) <= 40.0, "洞心没跟着灵魂（%s）" % str(hole))
	var vignette := level.get_node_or_null("UI/Vignette") as TextureRect
	_check(vignette != null, "缺少柔边视野圈")
	if vignette != null:
		_check(vignette.modulate.a < 0.9, "视野圈太重，边角会像黑幕（a=%.2f）" % vignette.modulate.a)
		_check(vignette.texture is GradientTexture2D, "视野圈不是渐变贴图，边缘会是硬的")

	# ② 旁白摆在屏幕正中央（M4-26 组长定稿：虚无阶段的字就该在正中，不再跟着角色飘）
	var soul_note := level.get_node_or_null("UI/Narration") as Label
	_check(soul_note != null, "旁白不在 UI 层（应铺满屏幕、固定居中）")
	if soul_note != null:
		var center := soul_note.get_global_rect().get_center()
		_check(absf(center.x - 640.0) <= 2.0 and absf(center.y - 360.0) <= 2.0,
			"旁白不在屏幕正中（%s）" % str(center))
		_check(soul_note.get_theme_font_size("font_size") >= 20, "旁白字号偏小")
		print("[prologue] 旁白中心 %s" % str(center))

	# ③ 开场不抢话：第一秒内不该出现任何台词
	await create_timer(0.8).timeout
	var early := ""
	if soul_note != null:
		early = soul_note.text
	_check(early.strip_edges() == "", "开场 0.8 秒就弹字了（%s）" % early)

	# ④ 漂浮：按方向键一小段时间，位移要明显小于“瞬移”，松手还要滑一段
	level.set("_can_move", true)
	var x0 := soul.position.x
	Input.action_press("move_right")
	var max_step := 0.0
	var last := soul.position.x
	for _i in range(30):
		await process_frame
		max_step = maxf(max_step, absf(soul.position.x - last))
		last = soul.position.x
	Input.action_release("move_right")
	var x1 := soul.position.x
	var drift_after_release := float(level.get("_drift"))
	for _i in range(12):
		await process_frame
	var x2 := soul.position.x
	print("[prologue] 按住 0.5s 走 %.1fpx，单帧最大 %.2fpx，松手后还滑 %.1fpx" % [
		x1 - x0, max_step, x2 - x1])
	_check(x1 > x0, "按方向键没有向前飘")
	_check(max_step <= MAX_STEP_PER_FRAME, "单帧位移 %.2fpx 太大，像瞬移" % max_step)
	_check(drift_after_release > 1.0, "松手立刻停住，没有惯性（drift=%.2f）" % drift_after_release)
	_check(x2 - x1 > 1.0, "松手后没有再滑一段（%.1fpx）" % (x2 - x1))

	# ⑤ 走近才融合：先测“还远的时候不融合”，再挪到跟前
	soul.position = Vector2(400, soul.position.y)
	for _i in range(20):
		await process_frame
	_check(not bool(level.get("_fused")), "离得还远就融合了")
	soul.position = Vector2(heart.position.x - 40.0, heart.position.y)
	for _i in range(20):
		await process_frame
	_check(bool(level.get("_fused")), "贴到身影跟前没有触发融合")

	# ⑥ 坠落：M4-64 改成"灵魂一直原样往下掉 → 某个暗→亮的拍点上**直接**变成主角"，
	# 不再按进度慢慢长。所以这里验的是"变身前是灵魂、变身后是完整角色"这条界线。
	level.call("_begin_descent")
	var knight := soul.get_node_or_null("Knight") as Node2D
	_check(knight != null, "缺少玩家身体 Knight")
	if knight == null:
		_finish()
		return
	# 必须就是教学关里那个角色的身体美术，不能是序章另画一份
	_check(knight.scene_file_path == "res://scenes/player/knight_body.tscn",
		"Knight 不是主角身体资源（%s）" % knight.scene_file_path)
	# M4-61：美术换成第二版渲染图分层（盔 / 身 / 斗篷）。颜色没法再按"三通道接近"断言了，
	# 改验"层和贴图都在"：谁把层改名或删掉，序章的变身就会漏一块，这里先炸。
	var skull := knight.get_node_or_null("Head/Skull") as Sprite2D
	_check(skull != null and skull.texture != null, "缺少头盔那一层贴图")
	# M4-71：眼睛是单独一层，虚空里必须是灭的（组长：坠落时没有眼睛）
	var eyes := knight.get_node_or_null("Head/Eyes") as CanvasItem
	_check(eyes != null, "缺少眼睛那一层")
	_check(eyes.modulate.a <= 0.01, "虚空里眼睛还亮着（alpha=%.2f）" % eyes.modulate.a)
	var base := knight.get_node_or_null("Silhouette") as Sprite2D
	_check(base != null and base.texture != null, "缺少身体那一层贴图")
	var cloak_panel := knight.get_node_or_null("CloakTail/Panel") as Sprite2D
	_check(cloak_panel != null and cloak_panel.texture != null, "缺少斗篷那一层贴图")

	# 刚开掉的时候还是灵魂：主角不该显形（_grow 必须是 0，不是"慢慢涨上来"）
	await process_frame
	await process_frame
	var grow0 := float(level.get("_grow"))
	var cloak_a0: float = (knight.get_node("CloakTail") as CanvasItem).modulate.a
	print("[prologue] 刚开掉：_grow=%.2f 斗篷=%.2f 变身=%s" % [
		grow0, cloak_a0, str(level.get("_transformed"))])
	_check(grow0 <= 0.01, "还没到拍点主角就已经长出来了（_grow=%.2f）" % grow0)
	# 注意读的是部件（斗篷）的 alpha，不是 Knight 容器：容器一直是 1.0，
	# 显不显形是由 _apply_growth 一个一个写在部件上的。
	_check(cloak_a0 <= 0.05, "还没变身主角就显形了（斗篷 alpha=%.2f）" % cloak_a0)

	# 等变身：不按绝对秒数断，轮询到 _transformed（资源加载会让时间漂）
	var transformed := await _wait_transformed(level, 25.0)
	_check(transformed, "25 秒内都没有在拍点上变身")
	var full: float = float(level.get("_grow"))
	var cloak_a: float = (knight.get_node("CloakTail") as CanvasItem).modulate.a
	var eye_energy: float = (knight.get_node("EyeGlow") as PointLight2D).energy
	print("[prologue] 变身：_grow=%.2f 斗篷=%.2f 眼灯=%.2f 缩放=%.2f 魂光 core=%.2f" % [
		full, cloak_a, eye_energy, knight.scale.x, (level.get("_soul_core") as Node2D).modulate.a])
	_check(full >= 0.99, "变身不是一次到位（_grow=%.2f）" % full)
	_check(cloak_a > 0.95, "变身后斗篷没完全显出来（%.2f）" % cloak_a)
	_check(eye_energy > 0.4, "眼睛没亮起来（眼灯 %.2f）" % eye_energy)
	_check(float(level.get("_soul_fade")) <= 0.05, "魂体没褪干净（%.2f）" % float(level.get("_soul_fade")))
	# M4-64：虚空里的主角是教学关的两倍大（这是组长点名要的；教学关里那份仍是 1.0）
	_check(is_equal_approx(knight.scale.x, 2.0), "虚空里的主角不是两倍大小（%.2f）" % knight.scale.x)

	_finish()

## 轮询等变身；返回是否等到了。
## 用 create_timer 而不是数 process_frame：无头模式下帧率不受限，
## "1500 帧"可能只过了 2 秒游戏时间，固定帧数会随机翻车（之前就踩过）。
func _wait_transformed(level: Node, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		await create_timer(0.25).timeout
		waited += 0.25
		if bool(level.get("_transformed")):
			return true
	return false

func _finish() -> void:
	print("[prologue] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[prologue] " + msg)
		_failed = true
