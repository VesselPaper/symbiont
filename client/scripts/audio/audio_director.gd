extends Node
## 音频总监（M4-05 / M4-10 / M4-14）
##
## 不作为 autoload 新增，避免打乱现有六个单例；由 GameManager 在 _ready 里实例化。
## BGM 按“游戏状态 + 当前场景”轮询切换，SFX 用播放器池轮换，环境音单独一层。
## M4-14 起：BGM 七首分层循环；转场/献祭/死亡走 Music 一次性层；
## Boss 激活切战斗曲；NPC/怪物声音由事件和 AI 脚本触发。
## M4-15 起音乐和地方环境音改用真实录音渲染（tools/generate_music.py），
## 八条音效由 tools/import_sfx.py 生成：六条从录音库剪，史莱姆叫声和拾取音是现场拼的；
## 素材许可见 assets/audio/README.md。

const BGM_DIR := "res://assets/audio/"
const BGM_TRACKS := {
	"menu": "bgm_menu.wav",
	"tutorial": "bgm_tutorial.wav",
	"floor1": "bgm_floor1.wav",
	"floor2": "bgm_floor2.wav",
	"floor3": "bgm_floor3.wav",
	"combat": "bgm_combat.wav",
	"ending": "bgm_ending.wav",
}
## 一次性音乐层：不循环，叠在 BGM 上，播完把 BGM 抬回来。
const MUSIC_TRACKS := {
	"transition": "music_transition.wav",
	"sacrifice": "music_sacrifice.wav",
	"death": "music_death.wav",
}
const AMB_TRACKS := {
	"menu": "amb_menu.wav",
	"tutorial": "amb_floor1.wav",
	"floor1": "amb_floor1.wav",
	"floor2": "amb_floor2.wav",
	"floor3": "amb_floor3.wav",
}
## 与 tools/generate_audio.py 的 SFX_TABLE 一一对应；加音效时两边一起改。
const SFX_NAMES := [
	"hit", "hit_flesh", "hit_wood", "hit_metal", "swing", "pogo", "enemy_hit", "enemy_die",
	"boss_hit", "boss_roar", "boss_charge", "boss_slam", "shockwave", "boss_down",
	"jump", "double_jump", "land", "step", "hurt", "death", "heal", "checkpoint",
	"pickup", "limb_pickup", "weapon_pickup", "boots_pickup", "relic_pickup", "chest_open",
	"ui", "ui_hover", "pause", "dialogue", "whisper",
	"bell", "gate", "chain", "altar", "sacrifice", "transition", "ending", "true_he",
	"spore_charge", "spore_fire", "steam",
	"voice_murmur", "voice_whisper", "slime_voice", "spore_voice",
]
## 同一音效连续触发时给一点随机音高，避免“电子音复读机”。
const PITCH_RANGE := {
	"hit": 0.08, "swing": 0.06, "step": 0.10, "enemy_hit": 0.10,
	"enemy_die": 0.08, "hurt": 0.06, "ui_hover": 0.04,
	"voice_murmur": 0.03, "slime_voice": 0.08, "spore_voice": 0.10, "limb_pickup": 0.06,
}
const SFX_PLAYERS := 14
# 压低档只比正常档低 5dB。之前压 8dB，加上环境声抬到 −12，压低时的音乐和环境声一样响，
# 玩家听到的就是“音乐没了”。
const BGM_VOLUME_DB := -14.0
# 组长第三次反馈“BGM 突然就没了 / 突然变小”。对话、音乐层、转场都会压 BGM，
# 教学关的提示气泡又频繁开关对话，听感就是音量一会儿大一会儿小。
# 现在音乐音量恒定：压低档取和正常档一样的值，代码路径留着，但不再真的改音量。
const BGM_DUCK_DB := BGM_VOLUME_DB
const AMB_VOLUME_DB := -12.0
const MUSIC_VOLUME_DB := -7.0
const SFX_VOLUME_DB := -5.0
const POLL_INTERVAL := 0.2
## 对话早结束了还在压低、音乐层早停了还当它在播，超过这个时间就判定为卡住
const STUCK_DUCK_SECONDS := 3.0
const STUCK_MUSIC_SECONDS := 1.5

@export var force_audio := false
# 审计日志：组长连续三次说“BGM 放一会儿就没了”，光靠无头测试查不出来，
# 把每次换曲/停播/改音量都写进 user://audio_log.txt，出问题直接看这个文件。
var _audit_file: FileAccess
var _audit_heartbeat := 0.0

var _bgm: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _music: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index := 0
var _current_track := ""
var _current_amb := ""
var _poll_timer := 0.0
var _ducked := false
var _music_ducked := false
var _combat := false
var _shut_down := false
# 压低状态挂了多久：事件成对时用不上，漏掉 finished 时靠它兜底
var _ducked_for := 0.0
var _music_ducked_for := 0.0
var _vol_tween: Tween
var _cache: Dictionary = {}
var _bgm_db := BGM_VOLUME_DB
var _duck_db := BGM_DUCK_DB
var _amb_db := AMB_VOLUME_DB
var _music_db := MUSIC_VOLUME_DB
var _sfx_db := SFX_VOLUME_DB

func _ready() -> void:
	# 无头回归不启动音频：AudioServer 是 dummy，硬播只会在退出时留下
	# “resources still in use”噪声。audio_test 用 force_audio 单独实例化一份。
	if DisplayServer.get_name() == "headless" and not force_audio:
		set_process(false)
		return
	_open_audit()
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	_bgm.volume_db = _bgm_db
	add_child(_bgm)
	_amb = AudioStreamPlayer.new()
	_amb.name = "Ambience"
	_amb.volume_db = _amb_db
	add_child(_amb)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.volume_db = _music_db
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	for i in range(SFX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.volume_db = _sfx_db
		add_child(p)
		_sfx_players.append(p)
	# 预加载，避免第一次命中才读盘卡一下
	for name in SFX_NAMES:
		_get_stream("sfx_" + name + ".wav")
	_apply_mix()
	# GameManager 比 Settings 先 ready，不能在这里假设 Settings 已经入树；
	# 延后一帧再接音量信号，窗口模式和 --script 测试都能拿到同一个单例。
	call_deferred("_connect_settings")
	# 战斗/剧情/场景事件统一在这里发声，业务脚本不用各自加载音频
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.player_hurt.connect(_on_player_hurt)
	EventBus.player_died.connect(_on_player_died)
	EventBus.sacrifice_done.connect(_on_sacrifice)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.player_moved_between_floors.connect(_on_floor_changed)
	EventBus.ending_reached.connect(_on_ending_reached)
	EventBus.boss_encounter_started.connect(_on_boss_encounter_started)

func _connect_settings() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null or not settings.has_signal("audio_changed"):
		return
	if not settings.audio_changed.is_connected(_apply_mix):
		settings.audio_changed.connect(_apply_mix)
	_apply_mix()

## 把 Settings 的 0~1 音量档换算成 dB，叠加到各自基准上。
## 主音量由 Master 总线负责，这里只分别管 BGM/环境音和 SFX，避免两层重复衰减。
func _apply_mix() -> void:
	_audit("apply_mix 音量档重算")
	var bgm_mul := 1.0
	var sfx_mul := 1.0
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		bgm_mul = clampf(float(settings.get("bgm_volume")), 0.0, 1.0)
		sfx_mul = clampf(float(settings.get("sfx_volume")), 0.0, 1.0)
	_bgm_db = BGM_VOLUME_DB + _volume_db(bgm_mul)
	_duck_db = _bgm_db - (BGM_VOLUME_DB - BGM_DUCK_DB)
	_amb_db = AMB_VOLUME_DB + _volume_db(bgm_mul)
	_music_db = MUSIC_VOLUME_DB + _volume_db(bgm_mul)
	_sfx_db = SFX_VOLUME_DB + _volume_db(sfx_mul)
	if _vol_tween != null and _vol_tween.is_valid():
		_vol_tween.kill()
	if _bgm != null:
		_bgm.volume_db = _duck_db if (_ducked or _music_ducked) else _bgm_db
	if _amb != null:
		_amb.volume_db = _amb_db
	if _music != null:
		_music.volume_db = _music_db
	for p in _sfx_players:
		p.volume_db = _sfx_db

func _volume_db(multiplier: float) -> float:
	# 0 档用 -60dB 当作“听不见”，避免 linear_to_db(0) = -inf 被音频总线拒掉
	return maxf(linear_to_db(maxf(multiplier, 0.001)), -60.0)


## 测试/退出时统一松手：先停播放再把 stream 置空，最后清缓存。
## 只停节点不置空的话，AudioServer 仍可能持有 playback，退出时报资源未释放。
func stop_all() -> void:
	_audit("stop_all 被调用（谁调的都记一下）")
	# 先让 _process 停手，否则退出等待的几帧里还会重新加载 BGM/环境音
	_shut_down = true
	if _vol_tween != null and _vol_tween.is_valid():
		_vol_tween.kill()
	if _bgm != null:
		_bgm.stop()
		_bgm.stream = null
	if _amb != null:
		_amb.stop()
		_amb.stream = null
	if _music != null:
		_music.stop()
		_music.stream = null
	for p in _sfx_players:
		p.stop()
		p.stream = null
	_cache.clear()

func _exit_tree() -> void:
	stop_all()

func _process(delta: float) -> void:
	_clock += delta
	if _shut_down:
		return
	_audit_heartbeat += delta
	if _audit_heartbeat >= 5.0:
		_audit_heartbeat = 0.0
		_audit_beat()
	_poll_timer += delta
	if _poll_timer < POLL_INTERVAL:
		return
	_poll_timer = 0.0
	var track := _track_for_context()
	if track != _current_track:
		_play_bgm(track)
	var amb := _amb_for_context()
	if amb != _current_amb:
		_play_amb(amb)
	_guard_stuck_state(POLL_INTERVAL)

## 状态自愈。
##
## 压低本来是成对事件：dialogue_started 压、dialogue_finished 抬；play_music 压、
## music.finished 抬。但切场景、连按 K、一段音乐层被下一段打断，都可能让后半句没来，
## 结果就是 BGM 一直挂在压低档上——玩家听到的是“音乐走着走着就没了”。
## 这里只处理明显卡住的情况，正常的短时压低（对话、转场）不受影响。
func _guard_stuck_state(step: float) -> void:
	if _bgm == null:
		return
	if _ducked:
		_ducked_for += step
		if _ducked_for > STUCK_DUCK_SECONDS and not _dialogue_active():
			_ducked = false
			_fade_bgm(_duck_db if _music_ducked else _bgm_db, 0.4)
	else:
		_ducked_for = 0.0
	if _music_ducked:
		_music_ducked_for += step
		if _music_ducked_for > STUCK_MUSIC_SECONDS and (_music == null or not _music.playing):
			_music_ducked = false
			if not _ducked:
				_fade_bgm(_bgm_db, 0.4)
	else:
		_music_ducked_for = 0.0
	# 长曲子开了循环不会自己停，停了就是被打断了
	if _current_track != "" and _bgm.stream == null:
		# 流被清掉了（资源重载/切换失败）：整条重来，不然就是“音乐突然没了”
		_audit("!! stream 被清空，重放整条")
		_play_bgm(_current_track)
	elif _current_track != "" and not _bgm.playing:
		_audit("!! BGM 停住了，重新 play")
		_bgm.play()
	# 循环保险：只要在播 BGM，就保证流自己是循环的。
	# 有几次“音乐放完就没了/不能循环”的反馈查下来都是流被重新赋值后 loop 丢了，
	# 这里每 0.2 秒补一次，代价可以忽略。
	if _current_track != "":
		_ensure_loop(_bgm)
		# 音量保险：没有补间在跑的时候，BGM 必须停在目标音量。
		# 补间被打断/被别处改过音量时，会停在半路，听感就是“突然变小”。
		if _vol_tween == null or not _vol_tween.is_valid():
			if absf(_bgm.volume_db - _bgm_db) > 0.5:
				_audit("!! 音量被改到 %.1f，拉回 %.1f" % [_bgm.volume_db, _bgm_db])
				_bgm.volume_db = _bgm_db


## 审计：每次调用都刷盘，崩溃/被杀进程也能留下记录
func _audit(msg: String) -> void:
	if _audit_file == null:
		return
	_audit_file.store_line("[%7.2fs] %s" % [_clock, msg])
	_audit_file.flush()

## 心跳：每秒记一次播放器实况，能直接看出“第几秒断的、断的时候是什么状态”
func _audit_beat() -> void:
	if _audit_file == null or _bgm == null:
		return
	_audit("beat track=%s pos=%.1f len=%.1f vol=%.1f playing=%s stream=%s tree_paused=%s ducked=%s music=%s" % [
		_current_track, _bgm.get_playback_position(),
		(_bgm.stream.get_length() if _bgm.stream != null else 0.0),
		_bgm.volume_db, str(_bgm.playing), str(_bgm.stream != null),
		str(get_tree().paused if get_tree() != null else false), str(_ducked),
		str(_music != null and _music.playing)])

func _open_audit() -> void:
	_audit_file = FileAccess.open("user://audio_log.txt", FileAccess.WRITE)
	_audit("=== run start, headless=%s ===" % str(DisplayServer.get_name() == "headless"))

var _clock := 0.0

## 把某个播放器上的 WAV 流强制成从头到尾循环
func _ensure_loop(player: AudioStreamPlayer) -> void:
	if player == null or player.stream == null:
		return
	var wav := player.stream as AudioStreamWAV
	if wav == null:
		return
	var frames := int(wav.get_length() * wav.mix_rate)
	if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD or wav.loop_end <= 0 or wav.loop_end > frames + 1:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = maxi(frames, 1)


func _dialogue_active() -> bool:
	var node := get_tree().get_first_node_in_group("dialogue")
	if node == null or not node.has_method("is_playing"):
		return false
	return bool(node.call("is_playing"))


func _track_for_context() -> String:
	var state := int(GameManager.state)
	if state == GameManager.GameState.ENDING or state == GameManager.GameState.GAME_OVER:
		return "ending"
	if state == GameManager.GameState.MAIN_MENU or state == GameManager.GameState.BOOT:
		return "menu"
	if _combat:
		return "combat"
	var scene_path := ""
	var scene := get_tree().current_scene
	if scene != null:
		scene_path = scene.scene_file_path
	if scene_path.contains("test_arena"):
		return "tutorial"
	if scene_path.contains("floor2"):
		return "floor2"
	if scene_path.contains("floor3"):
		return "floor3"
	if scene_path.contains("floor1"):
		return "floor1"
	# --script 无头测试里 current_scene 可能为空，退回当前楼层
	if GameManager.current_floor == "floor_3":
		return "floor3"
	if GameManager.current_floor == "floor_2":
		return "floor2"
	return "floor1"

func _amb_for_context() -> String:
	var track := _track_for_context()
	if track == "ending" or track == "combat":
		return ""
	return track

func _play_bgm(track: String) -> void:
	if _shut_down:
		return
	var file: String = BGM_TRACKS.get(track, "")
	if file == "":
		return
	var stream := _get_stream(file)
	if stream == null:
		return
	_audit("play_bgm %s file=%s len=%.1f" % [track, file, stream.get_length()])
	_current_track = track
	if _bgm.stream == stream:
		# 同一个流可能在别处被停过，这里补一次播放，不然切回同曲会静音
		if not _bgm.playing:
			_bgm.play()
		return
	_bgm.stop()
	_bgm.stream = stream
	_ensure_loop(_bgm)
	# 切场景时从低一点浮上来，避免硬切
	_bgm.volume_db = _duck_db
	_fade_bgm(_duck_db if _ducked else _bgm_db, 0.55)
	_bgm.play()

func _play_amb(track: String) -> void:
	if _shut_down:
		return
	_current_amb = track
	if _amb == null:
		return
	var file: String = AMB_TRACKS.get(track, "")
	if file == "":
		_amb.stop()
		_amb.stream = null
		return
	var stream := _get_stream(file)
	if stream == null:
		_amb.stop()
		_amb.stream = null
		return
	if _amb.stream == stream:
		if not _amb.playing:
			_amb.play()
		return
	_amb.stop()
	_amb.stream = stream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	# 环境声不再从低处浮上来：换场景那一下“先小声再大声”也被反馈成音量突变
	_amb.volume_db = _amb_db
	_amb.play()

func _fade_bgm(to_db: float, time: float) -> void:
	if _bgm == null:
		return
	if _vol_tween != null and _vol_tween.is_valid():
		_vol_tween.kill()
	_vol_tween = create_tween()
	_vol_tween.tween_property(_bgm, "volume_db", to_db, time)

## 一次性音乐层：转场/献祭/死亡。不循环，播完由 finished 信号把 BGM 抬回来。
func play_music(name: String, volume_db: float = 0.0) -> void:
	if _shut_down:
		return
	var file: String = MUSIC_TRACKS.get(name, "")
	if file == "" or _music == null:
		return
	var stream := _get_stream(file)
	if stream == null:
		return
	_audit("play_music %s file=%s len=%.1f" % [name, file, stream.get_length()])
	_music.stop()
	_music.stream = stream
	_music.volume_db = _music_db + volume_db
	_music.play()
	_music_ducked = true
	_music_ducked_for = 0.0
	_fade_bgm(_duck_db, 0.25)

func _on_music_finished() -> void:
	_audit("music_finished %s" % str(_music.stream != null))
	_music_ducked = false
	_music_ducked_for = 0.0
	if not _ducked:
		_fade_bgm(_bgm_db, 0.6)

func _get_stream(file: String) -> AudioStream:
	var path := BGM_DIR + file
	if _cache.has(path):
		return _cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream != null:
		_cache[path] = stream
	return stream

## 一次性音效。volume_db 是相对 SFX 基准的增减；pitch 1.0 为原速。
func play_sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _shut_down:
		return
	var stream := _get_stream("sfx_" + name + ".wav")
	if stream == null or _sfx_players.is_empty():
		return
	var player := _sfx_players[_sfx_index % _sfx_players.size()]
	_sfx_index += 1
	player.stop()
	player.stream = stream
	player.volume_db = _sfx_db + volume_db
	var spread := float(PITCH_RANGE.get(name, 0.0))
	player.pitch_scale = maxf(0.55, pitch + randf_range(-spread, spread))
	player.play()

func _on_item_picked(item_id: String, _count: int) -> void:
	match item_id:
		"iron_sword":
			play_sfx("weapon_pickup", 1.0)
		"steam_boots":
			play_sfx("boots_pickup", 1.0)
		"origin_relic":
			play_sfx("relic_pickup", 1.0)
		"monster_limb":
			# 残肢是湿的，和金属、布料的拾取分开放，不然捡什么都一样响
			play_sfx("limb_pickup", 0.0)
		_:
			play_sfx("pickup", 0.0)

func _on_player_hurt(_amount: int, _source: Node) -> void:
	play_sfx("hurt")

func _on_player_died() -> void:
	# 死亡会回存档点，Boss 也要重新开场；先清战斗标记，别让复活后直接铺战斗曲
	_combat = false
	play_sfx("death", 1.0)
	play_music("death", -2.0)

func _on_sacrifice(_id: String, _total: int) -> void:
	play_sfx("sacrifice", 0.0)
	play_music("sacrifice", -2.0)

func _on_enemy_killed(enemy: Node, _position: Vector2) -> void:
	# Boss 自己还有 boss_down 长音，不用再叠一个普通小怪的死亡声
	if enemy != null and is_instance_valid(enemy) and enemy.is_in_group("boss"):
		return
	play_sfx("enemy_die")

func _on_boss_encounter_started(_boss_id: String) -> void:
	_combat = true
	_play_bgm("combat")

func _on_boss_defeated(_boss_id: String) -> void:
	_combat = false
	play_sfx("boss_down", 2.0)
	# 下一轮 _process 会切回第三层环境曲；这里不硬切，让死亡长音先落地
	_play_bgm("floor3")

func _on_dialogue_started(id: String) -> void:
	_audit("dialogue_started")
	_ducked = true
	_ducked_for = 0.0
	_fade_bgm(_duck_db, 0.25)
	# 献祭后/真 HE 归还的低语，给“墙后有东西”一层底；普通对话不铺
	if id.contains("sacrifice") or id.contains("true_he"):
		play_sfx("whisper", -9.0, 0.92)

func _on_dialogue_finished(_id: String) -> void:
	_ducked = false
	_ducked_for = 0.0
	# 音乐层还在播时继续压着 BGM，等 finished 再抬回来
	if not _music_ducked:
		_fade_bgm(_bgm_db, 0.35)

func _on_floor_changed(floor_id: String) -> void:
	# 离开第三层还没打死 Boss 时，战斗曲必须收掉；否则下一层会一直放战斗音乐
	if _combat and floor_id != "floor3":
		_combat = false
	play_sfx("transition", 0.0)
	# 这里原来还叠了一条 7 秒的 music_transition。进第一层/第二层时它比底噪高
	# 10dB 左右，听着就是“这一层的开场音乐”，7 秒放完就没了，之后只剩很轻的
	# 底乐——组长连着几次说“放一会儿就没了”说的就是这条。开场的过场声只留
	# 那声 by-SFX，曲子的切换交给 _process 的换曲逻辑，底乐从头到尾不断。
	_audit("floor_changed %s（不铺一次性过场音乐）" % floor_id)

func _on_ending_reached(ending_id: String) -> void:
	play_sfx("true_he" if ending_id == "true_he" else "ending", 2.0)
