extends SceneTree
## M4-11 音量设置验收（无头）
##
## 只验证三件事：Settings 的量程钳制与信号；AudioDirector 的 BGM/SFX 基准确实跟着档位走；
## 暂停面板上的滑条能改值、标签跟着变，并且不改默认混音基准。
## 不写 user://settings.cfg，避免把试玩机上的音量设置覆盖掉。

var _audio: Node
var _pause: CanvasLayer
var _settings: Node
var _checks := 0
var _failures := 0
var _orig_bgm := 1.0
var _orig_sfx := 1.0
var _elapsed := 0.0

func _initialize() -> void:
	print("[audio_settings] START")

func _process(delta: float) -> bool:
	if _elapsed < 0.1:
		_elapsed += delta
		return false
	_run()
	quit(0 if _failures == 0 else 1)
	return true

func _run() -> void:
	_settings = root.get_node_or_null("Settings")
	if _settings == null:
		_fail("缺少 Settings autoload")
		return
	_orig_bgm = float(_settings.get("bgm_volume"))
	_orig_sfx = float(_settings.get("sfx_volume"))

	# 量程：负数/大于 1 都要被钳制；改值要发 audio_changed
	var signal_box := [0]
	_settings.audio_changed.connect(func() -> void: signal_box[0] += 1)
	_settings.call("set_bgm_volume", -0.2)
	_check(is_equal_approx(float(_settings.get("bgm_volume")), 0.0), "BGM 负值没有钳到 0")
	_settings.call("set_sfx_volume", 1.4)
	_check(is_equal_approx(float(_settings.get("sfx_volume")), 1.0), "SFX 大于 1 没有钳到 1")
	_check(signal_box[0] >= 2, "音量变化没有广播 audio_changed")

	# AudioDirector：0.5 的 BGM 档位应让基准下降约 6dB，SFX 0.25 约 12dB
	var audio_scene := load("res://scenes/audio/audio_director.tscn") as PackedScene
	_audio = audio_scene.instantiate()
	_audio.set("force_audio", true)
	root.add_child(_audio)
	var constants: Dictionary = _audio.get_script().get_script_constant_map()
	_settings.call("set_bgm_volume", 0.5)
	_audio.call("_apply_mix")
	var base_bgm := float(constants.get("BGM_VOLUME_DB", -14.0))
	var got_bgm := float(_audio.get("_bgm_db"))
	_check(absf((got_bgm - base_bgm) - linear_to_db(0.5)) < 0.1, "BGM 档位没有换成 dB：%.2f" % got_bgm)
	_settings.call("set_sfx_volume", 0.25)
	_audio.call("_apply_mix")
	var base_sfx := float(constants.get("SFX_VOLUME_DB", -5.0))
	var got_sfx := float(_audio.get("_sfx_db"))
	_check(absf((got_sfx - base_sfx) - linear_to_db(0.25)) < 0.1, "SFX 档位没有换成 dB：%.2f" % got_sfx)

	# 暂停面板：滑条存在、能改 Settings、标签同步；默认基准不变
	_pause = load("res://scenes/ui/pause_menu.tscn").instantiate() as CanvasLayer
	root.add_child(_pause)
	var slider := _pause.get_node_or_null("Panel/BgmSlider") as HSlider
	var sfx_slider := _pause.get_node_or_null("Panel/SfxSlider") as HSlider
	_check(slider != null and sfx_slider != null, "暂停面板缺少音量滑条")
	if slider != null:
		slider.value = 0.4
		_check(is_equal_approx(float(_settings.get("bgm_volume")), 0.4), "滑条没有写回 Settings")
		var label := _pause.get_node_or_null("Panel/BgmValue") as Label
		_check(label != null and label.text.contains("40%"), "BGM 标签没有跟着滑条更新")
		# 键盘方向键不会发 drag_ended，靠 SaveTimer 兜底
		_check(bool(_pause.get("_volume_touched")), "音量改动没有标脏，键盘调整不会存盘")
	if sfx_slider != null:
		sfx_slider.value = 0.7
		_check(is_equal_approx(float(_settings.get("sfx_volume")), 0.7), "SFX 滑条没有写回 Settings")
		_audio.call("_apply_mix")
		_check(float(_audio.get("_sfx_db")) < base_sfx, "SFX 滑条没有影响播放基准")

	_finish()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[audio_settings] FAIL " + message)

func _fail(message: String) -> void:
	_failures += 1
	push_error("[audio_settings] FAIL " + message)

func _finish() -> void:
	if _settings != null:
		_settings.set("bgm_volume", _orig_bgm)
		_settings.set("sfx_volume", _orig_sfx)
		_settings.call("apply_master")
	if _audio != null and is_instance_valid(_audio):
		_audio.queue_free()
	if _pause != null and is_instance_valid(_pause):
		# 测试只验证信号/标签，不把临时 40%/70% 写进试玩机的 settings.cfg
		var timer := _pause.get_node_or_null("SaveTimer") as Timer
		if timer != null:
			timer.stop()
		_pause.set("_volume_touched", false)
		_pause.queue_free()
	if _failures == 0:
		print("[audio_settings] PASS checks=%d" % _checks)
	else:
		print("[audio_settings] FAIL checks=%d failures=%d" % [_checks, _failures])
