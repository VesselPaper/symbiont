extends Node
## 设置（Settings，autoload 单例）
##
## 音量 / 全屏 / 分辨率等，持久化到 user://settings.cfg（ConfigFile）。

const SETTINGS_PATH := "user://settings.cfg"

var master_volume: float = 1.0
var fullscreen: bool = false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	master_volume = cf.get_value("audio", "master_volume", 1.0)
	fullscreen = cf.get_value("display", "fullscreen", false)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.save(SETTINGS_PATH)
