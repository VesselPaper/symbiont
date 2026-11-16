extends Node
## 设置（Settings，autoload 单例）
##
## 音量 / 全屏 / 分辨率等，持久化到 user://settings.cfg（ConfigFile）。
## M4-11：主音量、BGM、SFX 分开存；改完立即生效，暂停菜单不再只是“能看不能调”。
## 0.0 要真的静音，所以这里对 linear_to_db(0) 做下限保护，避免 -inf 进 AudioServer。

signal audio_changed

const SETTINGS_PATH := "user://settings.cfg"
const MIN_DB := -80.0

var master_volume: float = 1.0
var bgm_volume: float = 1.0
var sfx_volume: float = 1.0
var fullscreen: bool = false
## 多存档开关（M5-06）：默认关 = 只用槽位 1，存档界面不给选，玩家不用挑；
## 想在同一个进度上开三条线（不同打法/不同楼层）才打开，打开后存档可以分别命名。
var multi_save := false

func _ready() -> void:
	load_settings()
	apply_master()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(cf.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	bgm_volume = clampf(float(cf.get_value("audio", "bgm_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(cf.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
	fullscreen = bool(cf.get_value("display", "fullscreen", false))
	multi_save = bool(cf.get_value("game", "multi_save", false))

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("audio", "bgm_volume", bgm_volume)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("game", "multi_save", multi_save)
	cf.save(SETTINGS_PATH)

## 切多存档：立刻落盘，下次打开暂停菜单/主菜单就按新的槽位数走
func set_multi_save(value: bool) -> void:
	multi_save = value
	save_settings()

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_master()
	audio_changed.emit()

func set_bgm_volume(value: float) -> void:
	bgm_volume = clampf(value, 0.0, 1.0)
	audio_changed.emit()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	audio_changed.emit()

## 主音量走 Master 总线；BGM/SFX 的单独音量由 AudioDirector 按各自基准叠加。
func apply_master() -> void:
	AudioServer.set_bus_volume_db(0, maxf(linear_to_db(master_volume), MIN_DB))
