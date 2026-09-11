extends CanvasLayer
## 新手教程提示条 UI（M1-08）
##
## 只负责显示，不包含任何流程逻辑（流程在 components/tutorial.gd，与 dialogue 组件
## 同风格：UI 只显示、组件只做流程）。
## 对 tutorial 组件暴露的接口（duck typing）：
##   show_hint(text: String) / hide_hint()
##
## 屏幕上方居中的半透明提示条；中文必须用 Noto Sans CJK 字体，否则渲染成方块
## （同 dialogue_box：在 _ready 里 load 字体并 override 到 Label 的 theme_override_fonts/font）。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"

@onready var _panel: PanelContainer = $HintPanel
@onready var _label: Label = $HintPanel/Label

func _ready() -> void:
	var font := load(FONT_PATH) as Font
	if font == null:
		# 字体缺失时 UI 仍可用（英文/数字），但中文会显示成方块，属必须修复的资产问题
		push_error("tutorial_hint: 加载中文字体失败 %s" % FONT_PATH)
	else:
		_label.add_theme_font_override("font", font)
	hide_hint()

func show_hint(text: String) -> void:
	_label.text = text
	_panel.visible = true

func hide_hint() -> void:
	_panel.visible = false
