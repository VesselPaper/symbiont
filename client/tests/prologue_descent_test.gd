extends SceneTree
## 序章下落演出回归（M4-39 / M4-64）：一镜到底里的几件事必须成立——
## 镜头始终锁玩家、鼓点间隔在收紧、灵魂保持原样、在拍点上一瞬间变成主角（两倍大）、
## 掉满 30 秒后的**下一拍**砸成全黑，全黑 3 秒（鼓不停），然后才切教学关。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/prologue_descent_test.gd

const SCENE := "res://scenes/world/prologue.tscn"

var _p: Node2D
var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	_p = load(SCENE).instantiate() as Node2D
	root.add_child(_p)
	await create_timer(0.4).timeout

	var soul: Node2D = _p.get("_soul")
	var cam: Camera2D = _p.get("_camera")
	var knight: Node2D = _p.get("_knight")
	var label: Control = _p.get("_soul_label")
	_check(soul != null and cam != null and knight != null, "序章节点没取全")

	_p.set("_fused", true)
	_p.call("_begin_descent")
	await create_timer(0.2).timeout
	_check(int(_p.get("_desc_phase")) == 1, "没有进入下落阶段")

	# 字幕位：附身一开始旁白就该降到画面底部
	_check(label.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM, "旁白没降到字幕位")
	_check(absf(label.offset_bottom + 84.0) < 0.5, "字幕位偏移不对（%.0f）" % label.offset_bottom)

	var beat0 := float(_p.get("_beat_interval"))
	var soul_scale0 := soul.scale.x
	await create_timer(6.0).timeout

	# 镜头锁玩家
	_check(cam.global_position.distance_to(soul.global_position) < 6.0,
			"镜头没锁住玩家（差 %.0fpx）" % cam.global_position.distance_to(soul.global_position))
	# M4-64：镜头回到原来的 1.42→0.80，灵魂因此保持原样（组长要"灵魂大小不变，人变两倍"）
	_check(cam.zoom.x < 1.42 and cam.zoom.x > 0.75,
			"镜头没有按原样拉远（zoom=%.3f，期望 0.75~1.42）" % cam.zoom.x)
	_check(is_equal_approx(soul.scale.x, soul_scale0), "灵魂自己也被放大了（%.2f → %.2f）" % [soul_scale0, soul.scale.x])
	# 这时还没到变身点：灵魂就该还是灵魂
	_check(not bool(_p.get("_transformed")), "还没到拍点就变身了")
	# 鼓点在收紧
	var beat1 := float(_p.get("_beat_interval"))
	_check(beat1 < beat0, "鼓点间隔没有收紧（%.2f → %.2f）" % [beat0, beat1])

	# 把时间拨到尾巴：间隔应该已经到 1 秒一拍
	_p.set("_form_t", 28.9)
	await create_timer(0.1).timeout
	var beat_end := float(_p.get("_beat_interval"))
	_check(beat_end < 1.05 and beat_end > 0.95, "临落底时鼓点没停在 1 秒（%.2f）" % beat_end)

	# 等那一次"暗→亮"的拍点：变身之后必须是完整角色，而且是两倍大
	var transformed := false
	for _i in range(240):
		await physics_frame
		if bool(_p.get("_transformed")):
			transformed = true
			break
	_check(transformed, "拍点上没有变身")
	# M4-65：变身那一拍必须是**全屏直接黑**，然后在下一拍"亮"的时候才撤黑、露出骑士
	var pulse_rect := _p.get("_pulse_rect") as ColorRect
	_check(pulse_rect != null, "缺少全屏遮罩")
	var black_ok := false
	for _i in range(200):
		await physics_frame
		if bool(_p.get("_transform_black")):
			black_ok = true
			break
	_check(black_ok and pulse_rect.color.a >= 0.95,
		"变身那一拍没有全屏压黑（遮罩 %.2f）" % pulse_rect.color.a)
	var lifted := false
	for _i in range(400):
		await physics_frame
		if not bool(_p.get("_transform_black")):
			lifted = true
			break
	_check(lifted, "黑屏一直没撤，骑士没露出来")
	_check(pulse_rect.color.a <= 0.05, "撤黑不是干净的（遮罩 %.2f）" % pulse_rect.color.a)
	# M4-66：虚空下坠时斗篷要被风掀起来（幅度/角度都比教学关大）。
	# 下摆现在是上段的子节点，它自己的 rotation 只是"额外甩动"，所以这里量的是
	# 上段（CloakTail）的总角度 —— 那才是肉眼看到的"布被吹平"。
	var tail_node := knight.get_node_or_null("CloakTail") as Node2D
	_check(tail_node != null, "主角缺少斗篷上段层")
	var max_rot := 0.0
	var max_skew := 0.0
	for _i in range(24):
		await physics_frame
		max_rot = maxf(max_rot, absf(tail_node.rotation))
		max_skew = maxf(max_skew, absf(tail_node.skew))
	print("[descent] 斗篷上段最大角度 %.2f rad、斜切 %.2f" % [max_rot, max_skew])
	_check(max_rot > 0.8, "斗篷没被风掀起来（最大 %.2f rad）" % max_rot)
	_check(max_skew > 0.05, "斗篷没有横向斜切（最大 %.2f）" % max_skew)
	_check(knight.modulate.a >= 0.9, "变身后主角没显形（alpha=%.2f）" % knight.modulate.a)
	_check(is_equal_approx(knight.scale.x, 2.0), "虚空里的主角不是两倍大小（%.2f）" % knight.scale.x)
	var grown_cloak := knight.get_node_or_null("CloakTail") as CanvasItem
	_check(grown_cloak != null and grown_cloak.modulate.a >= 0.9,
		"斗篷没有一起显出来（%.2f）" % (grown_cloak.modulate.a if grown_cloak != null else -1.0))
	var head_node := knight.get_node_or_null("Head") as CanvasItem
	_check(head_node != null and head_node.modulate.a >= 0.9, "头没有显出来")
	var skull := knight.get_node_or_null("Head/Skull") as Sprite2D
	_check(skull != null and skull.texture != null, "头盔那一层贴图没出来")
	_check(soul.global_position.y > 700.0, "灵魂没有在往下掉（y=%.0f）" % soul.global_position.y)

	# 结尾：掉满之后的第一拍砸成全黑，不是渐变
	var blacked := false
	for _i in range(600):
		await physics_frame
		if int(_p.get("_desc_phase")) == 2:
			blacked = true
			break
	_check(blacked, "掉满之后没有砸成全黑")
	var pulse: ColorRect = _p.get("_pulse_rect")
	_check(pulse != null and pulse.color.a > 0.95, "砸黑不是一瞬间到位（遮罩 %.2f）" % (pulse.color.a if pulse != null else -1.0))
	# 全黑这 3 秒鼓不能停：期间还得有鼓点把明暗继续切
	var beats_during_black := 0
	var dark_before := bool(_p.get("_beat_dark"))
	for _i in range(300):
		await physics_frame
		var now_dark := bool(_p.get("_beat_dark"))
		if now_dark != dark_before:
			beats_during_black += 1
			dark_before = now_dark
		if bool(_p.get("_leaving")):
			break
	print("[descent] 全黑期间鼓点切换 %d 次" % beats_during_black)
	_check(beats_during_black >= 2, "全黑那 3 秒鼓停了（只切了 %d 次）" % beats_during_black)
	# 3 秒之后才切场景
	_check(bool(_p.get("_leaving")), "全黑 3 秒后没有切到教学关")

	print("[descent] %s（鼓点 %.1fs→%.1fs）" % ["PASS" if not _failed else "FAIL", beat0, beat1])
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[descent] " + msg)
		_failed = true
