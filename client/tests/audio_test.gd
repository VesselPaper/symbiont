extends SceneTree
## 音频回归（M4-05 / M4-10 / M4-14）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/audio_test.gd
##
## 验收：BGM 七首都在并循环；四层环境音都在；SFX 目录至少 30 个且覆盖战斗/移动/道具/UI/剧情；
## 播放器池够用；Boss 战进/出、死亡清战斗标记；对话/一次性音乐压低 BGM 后恢复；未知音效/曲目静默返回。

const BGM_KEYS := ["menu", "tutorial", "floor1", "floor2", "floor3", "combat", "ending"]
const MUSIC_KEYS := ["transition", "sacrifice", "death"]
const AMB_KEYS := ["menu", "tutorial", "floor1", "floor2", "floor3"]
const REQUIRED_SFX := [
	"hit", "swing", "pogo", "enemy_hit", "enemy_die",
	"boss_hit", "boss_roar", "boss_charge", "boss_slam", "shockwave", "boss_down",
	"jump", "double_jump", "land", "step", "hurt", "death", "heal", "checkpoint",
	"pickup", "weapon_pickup", "boots_pickup", "relic_pickup", "chest_open",
	"ui", "ui_hover", "pause", "dialogue", "whisper",
	"bell", "gate", "chain", "altar", "sacrifice", "transition", "ending", "true_he",
	"spore_charge", "spore_fire", "steam",
	"voice_murmur", "voice_whisper", "slime_voice", "spore_voice",
]

var _frames := 0
var _failed := false
var _audio: Node
var _checks_run := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# 窗口模式下 GameManager 也会自动挂一份；先让它停手，避免测试实例和自动实例各播一层
		var gm := root.get_node_or_null("/root/GameManager")
		var auto_audio := gm.get_node_or_null("AudioDirector") if gm != null else null
		if auto_audio != null:
			auto_audio.call("stop_all")
			auto_audio.set_process(false)
		var scene: PackedScene = load("res://scenes/audio/audio_director.tscn")
		_audio = scene.instantiate()
		_audio.set("force_audio", true)
		root.add_child(_audio)
		return false
	if _frames < 20:
		return false
	if not _checks_run:
		_run_checks()
		_checks_run = true
		# 先 stop_all 再释放，并多等一段时间让音频线程放掉 playback
		_audio.call("stop_all")
		_audio.free()
		_audio = null
		return false
	if _frames < 180:
		return false
	print("[audio] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[audio] " + msg)
		_failed = true

func _run_checks() -> void:
	# 无头下 GameManager 刻意不挂 AudioDirector（避免资源占用报告）；测试自己实例化
	_check(_audio != null, "测试用 AudioDirector 未实例化")
	if _audio == null:
		return
	_check(_audio.get_node_or_null("Bgm") != null, "缺少 Bgm 播放器")
	_check(_audio.get_node_or_null("Ambience") != null, "缺少 Ambience 播放器")
	_check(_audio.get_node_or_null("Music") != null, "缺少 Music 一次性音乐层播放器")
	var pool := 0
	for child in _audio.get_children():
		if str(child.name).begins_with("Sfx"):
			pool += 1
	_check(pool >= 14, "SFX 播放器池少于 14 个，实际 %d" % pool)

	var tracks: Dictionary = _audio.get("BGM_TRACKS")
	_check(tracks.size() == BGM_KEYS.size(), "BGM 曲目数量不对")
	for key in BGM_KEYS:
		_check(tracks.has(key), "缺少 BGM 键 %s" % key)
		var file := str(tracks.get(key, ""))
		_check(file.ends_with(".wav"), "BGM %s 不是 wav" % key)
		_check(FileAccess.file_exists("res://assets/audio/" + file), "BGM 文件缺失：%s" % file)

	var stings: Dictionary = _audio.get("MUSIC_TRACKS")
	_check(stings.size() == MUSIC_KEYS.size(), "一次性音乐层数量不对")
	for key in MUSIC_KEYS:
		_check(stings.has(key), "缺少音乐层键 %s" % key)
		_check(FileAccess.file_exists("res://assets/audio/" + str(stings.get(key, ""))), "音乐层文件缺失：%s" % key)
	var amb: Dictionary = _audio.get("AMB_TRACKS")
	_check(amb.size() >= 4, "环境音轨少于 4 个")
	for key in AMB_KEYS:
		if amb.has(key):
			_check(FileAccess.file_exists("res://assets/audio/" + str(amb[key])), "环境音缺失：%s" % key)

	# 直接切到第一层曲，检查循环设置和播放器状态
	_audio.call("_play_bgm", "floor1")
	_check(str(_audio.get("_current_track")) == "floor1", "切歌后 current_track 不是 floor1")
	var bgm := _audio.get_node("Bgm") as AudioStreamPlayer
	_check(bgm.stream != null, "Bgm 没有 stream")
	if bgm.stream is AudioStreamWAV:
		_check((bgm.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGM 没有设循环")
		_check((bgm.stream as AudioStreamWAV).get_length() >= 18.0, "BGM 太短，不到 18s")
		# 组长两次反馈“音乐一小段就没了/不能循环”。循环长度写进断言：
		# 每层曲子至少 60 秒，并且 loop_end 必须覆盖整首（不能停在中间）
		var bgm_wav := bgm.stream as AudioStreamWAV
		var frames := int(bgm_wav.get_length() * bgm_wav.mix_rate)
		_check(bgm_wav.get_length() >= 60.0, "BGM 不到 60 秒（%.1f），会被听成一小段" % bgm_wav.get_length())
		_check(bgm_wav.loop_end >= frames - 2, "BGM 的 loop_end 没覆盖整首（%d / %d）" % [bgm_wav.loop_end, frames])
		# 有损 QOA/IMA 导入会把短音效和低电平 BGM 的量化误差放大成“沙沙”底噪
		# 16-bit PCM = 1；QOA/IMA 会造成短音效和低电平 BGM 的量化底噪
		_check((bgm.stream as AudioStreamWAV).get("format") == 1,
			"BGM 不是 16-bit PCM，应该把 .import 的 compress/mode 设为 0")

	# 战斗曲：Boss 一激活就切，死亡后回第三层，不靠场景路径猜
	_audio.call("_on_boss_encounter_started", "gatekeeper_boss")
	_check(str(_audio.get("_current_track")) == "combat", "Boss 激活没有切战斗曲")
	_check(bool(_audio.get("_combat")), "Boss 激活没有置战斗标记")
	_audio.call("_on_boss_defeated", "gatekeeper_boss")
	_check(not bool(_audio.get("_combat")), "Boss 死亡没有清战斗标记")
	# 死亡回存档点时也要清；否则复活后 Boss 还没开场就先铺战斗曲
	_audio.set("_combat", true)
	_audio.call("_on_player_died")
	_check(not bool(_audio.get("_combat")), "玩家死亡没有清战斗标记")

	# 一次性音乐层：转场/献祭/死亡都要能挂到 Music 播放器
	_audio.call("play_music", "death", -4.0)
	var music := _audio.get_node("Music") as AudioStreamPlayer
	_check(music.stream != null, "死亡音乐没有挂到 Music")
	_check(music.playing, "死亡音乐没有开始播放")
	_check(bool(_audio.get("_music_ducked")), "一次性音乐层没有压低 BGM")
	_audio.call("_on_music_finished")
	_check(not bool(_audio.get("_music_ducked")), "音乐层结束没有恢复 BGM")

	# 组长反馈“第一层、第二层的开头音乐放一会儿就没了”。查下来是进层时
	# 叠了一条 7 秒的 music_transition：它比底乐响 10dB，听着就是这层的开场曲，
	# 7 秒放完只剩底乐，像音乐断了。现在进层只留 transition 音效，不许起一次性音乐层。
	# 先把上一步的死亡音乐清干净，否则“还在播”是那一条，看不出进层有没有新起
	var music_after_floor := _audio.get_node("Music") as AudioStreamPlayer
	music_after_floor.stop()
	music_after_floor.stream = null
	_audio.set("_music_ducked", false)
	_audio.call("_on_floor_changed", "floor1")
	_check(not music_after_floor.playing, "进层时又起了 7 秒过场音乐（就是组长说的“放一会儿就没了”）")
	_check(not bool(_audio.get("_music_ducked")), "进层不该压低 BGM")

	# 环境音：切到第二层，确认加载 + 循环
	_audio.call("_play_amb", "floor2")
	var ambient := _audio.get_node("Ambience") as AudioStreamPlayer
	_check(ambient.stream != null, "Ambience 没有 stream")
	if ambient.stream is AudioStreamWAV:
		_check((ambient.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "环境音没有设循环")

	# SFX 全目录：文件存在；再抽战斗/移动/剧情/UI 各一个实际加载并播放
	var sfx_names: Array = _audio.get("SFX_NAMES")
	_check(sfx_names.size() >= 30, "SFX 目录少于 30 个，实际 %d" % sfx_names.size())
	for name in REQUIRED_SFX:
		_check(name in sfx_names, "SFX 目录缺少 %s" % name)
		_check(FileAccess.file_exists("res://assets/audio/sfx_%s.wav" % name), "SFX 文件缺失：%s" % name)
	for name in ["swing", "enemy_hit", "double_jump", "step", "boss_roar", "chest_open", "whisper"]:
		_audio.call("play_sfx", name)
	var probes := 0
	for p in _audio.get("_sfx_players"):
		if (p as AudioStreamPlayer).stream != null:
			probes += 1
	_check(probes >= 1, "播放后没有任何 SFX 播放器拿到 stream")

	# 事件到音效的映射：铁剑/靴子/骨片不能都响同一个“通用拾取”
	_audio.call("_on_item_picked", "iron_sword", 1)
	_check(_last_sfx_path().ends_with("sfx_weapon_pickup.wav"), "铁剑拾取没有走 weapon_pickup")
	_audio.call("_on_item_picked", "steam_boots", 1)
	_check(_last_sfx_path().ends_with("sfx_boots_pickup.wav"), "蒸汽靴拾取没有走 boots_pickup")
	_audio.call("_on_item_picked", "origin_relic", 1)
	_check(_last_sfx_path().ends_with("sfx_relic_pickup.wav"), "骨片拾取没有走 relic_pickup")
	_audio.call("_on_item_picked", "monster_limb", 1)
	_check(_last_sfx_path().ends_with("sfx_limb_pickup.wav"), "残肢拾取没有走 limb_pickup")

	# 对话时 BGM 压低，献祭/真 HE 对话额外铺低语；结束后恢复
	_audio.call("_on_dialogue_started", "sacrifice_after_1")
	_check(bool(_audio.get("_ducked")), "对话开始没有压低 BGM")
	_check(_last_sfx_path().ends_with("sfx_whisper.wav"), "献祭后对话没有铺低语")
	_audio.call("_on_dialogue_finished", "sacrifice_after_1")
	_check(not bool(_audio.get("_ducked")), "对话结束没有恢复 BGM")

	# 反向：未知音效/未知曲目/未知环境音必须静默返回，不能把当前曲目清空
	var before := str(_audio.get("_current_track"))
	_audio.call("play_sfx", "does_not_exist")
	_audio.call("_play_bgm", "does_not_exist")
	_check(str(_audio.get("_current_track")) == before, "未知曲目不应改变当前 BGM")
	_audio.call("_play_amb", "does_not_exist")
	_check(str(_audio.get("_current_amb")) == "does_not_exist", "未知环境音不应崩溃")

func _last_sfx_path() -> String:
	var idx := int(_audio.get("_sfx_index")) - 1
	var pool: Array = _audio.get("_sfx_players")
	if idx < 0 or pool.is_empty():
		return ""
	var player := pool[idx % pool.size()] as AudioStreamPlayer
	if player == null or player.stream == null:
		return ""
	return player.stream.resource_path
