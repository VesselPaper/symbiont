extends Node2D
## 新手教程头顶气泡 UI（M1-10）
##
## 世界空间 Node2D 根（不是 CanvasLayer）：由 tutorial 组件每帧把它定位到玩家头顶
## 并切换文字，做出"提示跟着人走"的效果（M1-08 的屏幕上方提示条已删除）。
## 只负责显示，不包含任何流程逻辑（流程在 components/tutorial.gd）。
## 对 tutorial 组件暴露的接口（duck typing）：
##   show_bubble(text: String) / hide_bubble() / set_bubble_position(global_pos)
##
## 中文必须用 Noto Sans CJK 字体，否则渲染成方块（同 dialogue_box：在 _ready 里
## load 字体并 override 到 Label 的 theme_override_fonts/font）。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Label

func _ready() -> void:
	var font := load(FONT_PATH) as Font
	if font == null:
		# 字体缺失时 UI 仍可用（英文/数字），但中文会显示成方块，属必须修复的资产问题
		push_error("tutorial_bubble: 加载中文字体失败 %s" % FONT_PATH)
	else:
		_label.add_theme_font_override("font", font)
	hide_bubble()

func _process(_delta: float) -> void:
	# 面板宽度随文字内容变化，每帧以根节点为锚点水平居中、面板整体悬在定位点上方
	# （根节点 = 玩家头顶定位点，见 tutorial.gd _position_bubble_on_player）
	_panel.position = Vector2(-_panel.size.x * 0.5, -_panel.size.y)

func show_bubble(text: String) -> void:
	_label.text = text
	_panel.visible = true
	_panel.position = Vector2(-_panel.size.x * 0.5, -_panel.size.y)

func hide_bubble() -> void:
	_panel.visible = false

## 定位点 = 世界坐标（tutorial 组件每帧传入玩家头顶位置）
func set_bubble_position(global_pos: Vector2) -> void:
	global_position = global_pos
