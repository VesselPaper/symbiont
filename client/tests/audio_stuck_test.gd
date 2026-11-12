## 音频状态自愈（M4-14 第十次修正）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/audio_stuck_test.gd
##
## 组长反馈"背景音乐走一段就没了"。探针查下来，循环本身是好的（位置会绕回去、finished 不响），
## 问题出在压低：对话开始压 8dB，如果 finished 因为切场景或连按 K 漏掉，压低就一直挂着，
## 加上环境声抬上来之后，压低的音乐听上去就是"没了"。
## 这里验三件事：压低卡住会自己恢复、音乐层卡住会自己恢复、BGM 被停掉会自己重开。

extends SceneTree

var _audio: Node
var _frames := 0
var _stage := 0
var _fail := 0
var _t := 0.0

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok  ", msg)
	else:
		_fail += 1
		printerr("  FAIL ", msg)

func _initialize() -> void:
	print("[audio_stuck] 开始")

func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var gm := root.get_node_or_null("/root/GameManager")
		if gm != null:
			var auto_audio := gm.get_node_or_null("AudioDirector")
			if auto_audio != null:
				auto_audio.call("stop_all")
				auto_audio.set_process(false)
		var scene: PackedScene = load("res://scenes/audio/audio_director.tscn")
		_audio = scene.instantiate()
		_audio.set("force_audio", true)
		root.add_child(_audio)
		_t = 0.0
		return false

	_t += delta
	if _audio == null:
		# 释放之后只剩等音频线程收尾
		if _t > 9.5:
			if _fail == 0:
				print("[audio_stuck] PASS")
				quit(0)
			else:
				printerr("[audio_stuck] FAIL %d 项" % _fail)
				quit(1)
		return false
	var bgm_db: float = _audio.get("_bgm_db")
	var duck_db: float = _audio.get("_duck_db")

	if _stage == 0 and _t > 1.0:
		# 关卡里没有对话节点，但压低标记被人为挂上：应当被判定为卡住并恢复
		_audio.call("_on_dialogue_started", "stuck_probe")
		_audio.set("_ducked", true)
		var bgm: AudioStreamPlayer = _audio.get("_bgm")
		bgm.volume_db = duck_db
		print("  压低挂上：vol=%.1f" % bgm.volume_db)
		_stage = 1
	elif _stage == 1 and _t > 5.0:
		var bgm: AudioStreamPlayer = _audio.get("_bgm")
		_check(not bool(_audio.get("_ducked")), "卡住的压低被清掉")
		_check(absf(bgm.volume_db - bgm_db) < 0.6, "音量回到正常档（%.1f → %.1f）" % [bgm.volume_db, bgm_db])
		_stage = 2
	elif _stage == 2 and _t > 6.0:
		# 手动停掉 BGM，守卫应当把它重新开起来
		var bgm: AudioStreamPlayer = _audio.get("_bgm")
		bgm.stop()
		_audio.call("_play_bgm", "floor1")
		_stage = 3
	elif _stage == 3 and _t > 8.0:
		var bgm: AudioStreamPlayer = _audio.get("_bgm")
		_check(bgm.playing, "BGM 被停掉后自己重开")
		_check(bgm.get_playback_position() > 0.1, "重新开始播的位置在推进")
		_audio.call("stop_all")
		_audio.free()
		_audio = null
		_t = 8.0
		# 先释放再等一段，让音频线程放掉 playback，退出时不报资源占用
		_stage = 4
	elif _stage == 4 and _t > 9.5:
		if _fail == 0:
			print("[audio_stuck] PASS")
			quit(0)
		else:
			printerr("[audio_stuck] FAIL %d 项" % _fail)
			quit(1)
		return true
	return false
