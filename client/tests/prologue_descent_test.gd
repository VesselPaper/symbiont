extends SceneTree
## 序章下落演出回归（M4-39）：一镜到底里的四件事必须成立——
## 镜头始终锁玩家、鼓点间隔在收紧、身体在生长、旁白降到字幕位；
## 落地后停在暗拍，再从玩家向外亮。
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
	await create_timer(6.0).timeout

	# 镜头锁玩家
	_check(cam.global_position.distance_to(soul.global_position) < 6.0,
			"镜头没锁住玩家（差 %.0fpx）" % cam.global_position.distance_to(soul.global_position))
	# 镜头在拉远
	_check(cam.zoom.x < 0.995, "镜头没有拉远（zoom=%.3f）" % cam.zoom.x)
	# 鼓点在收紧
	var beat1 := float(_p.get("_beat_interval"))
	_check(beat1 < beat0, "鼓点间隔没有收紧（%.2f → %.2f）" % [beat0, beat1])
	# 越接近落地越急促：把时间拨到 95%%，间隔应接近 1 秒`n	_p.set("_desc_t", 33.2)`n	await create_timer(0.1).timeout`n	var beat_end := float(_p.get("_beat_interval"))`n	_check(beat_end < 1.4, "临落地时鼓点没有到 1 秒（%.2f）" % beat_end)`n	# 身体在生长
	_check(knight.scale.x > 0.63, "骑士没有生长（scale=%.2f）" % knight.scale.x)

	# 落地：停在暗拍 → 一秒后从玩家亮起
	_p.call("_desc_hold_dark")
	await create_timer(0.15).timeout
	_check(int(_p.get("_desc_phase")) == 2, "没有停在暗拍")
	_check(float(_p.get("_pulse_rect").get("color").a) > 0.5, "落地时不是暗的（全屏遮罩没压下来）")

	await create_timer(1.2).timeout
	_check(int(_p.get("_desc_phase")) == 3, "一秒后没有开始亮起")
	var radius := float(_p.get("_dark_mat").get_shader_parameter("radius"))
	_check(radius > 120.0, "亮起时黑幕没扩大（radius=%.0f）" % radius)

	print("[descent] %s（鼓点 %.1fs→%.1fs）" % ["PASS" if not _failed else "FAIL", beat0, beat1])
	quit(0 if not _failed else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[descent] " + msg)
		_failed = true
