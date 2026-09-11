extends CanvasLayer
## 对话 UI（M1-03 · 寄生体低语）
##
## 只负责显示，不包含任何流程逻辑（流程在 components/dialogue.gd）。
## 对 dialogue 组件暴露的接口（duck typing）：
##   show_box() / hide_box()
##   set_speaker(speaker: String)
##   set_text(text: String)
##
## 中文必须用 Noto Sans CJK 字体，否则渲染成方块：在 _ready 里 load 字体
## 并 override 到 Label 的 theme_override_fonts/font（SIL OFL，随工程分发）。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"

@onready var _panel: PanelContainer = $Panel
@onready var _speaker_label: Label = $Panel/Margin/VBox/SpeakerLabel
@onready var _text_label: Label = $Panel/Margin/VBox/TextLabel

func _ready() -> void:
	var font := load(FONT_PATH) as Font
	if font == null:
		# 字体缺失时 UI 仍可用（英文/数字），但中文会显示成方块，属必须修复的资产问题
		push_error("dialogue_box: 加载中文字体失败 %s" % FONT_PATH)
	else:
		_speaker_label.add_theme_font_override("font", font)
		_text_label.add_theme_font_override("font", font)
	hide_box()

func show_box() -> void:
	_panel.visible = true

func hide_box() -> void:
	_panel.visible = false

func set_speaker(speaker: String) -> void:
	_speaker_label.text = speaker

func set_text(text: String) -> void:
	_text_label.text = text
