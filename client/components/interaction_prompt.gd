extends RefCounted
## 世界空间交互提示（M4-13）
##
## 钟绳、守钟人、调查点、阵营 NPC、货梯、宝箱原来各写一份 Label：
## 字体、描边、阴影、居中、z_index 全是复制粘贴，改一处漏五处。
## 这里只负责“长什么样”，不负责范围判定和按键；交互逻辑仍归各自组件。

const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"

## 统一入口：父节点、文字、相对位置、提示框大小、字号、颜色、描边、层级。
## 位置/大小仍由调用方给，因为每个物件的提示要避开自己的模型。
static func create(
	parent: Node,
	text: String,
	position: Vector2,
	box_size: Vector2,
	font_size := 14,
	color := Color(0.86, 0.90, 0.78, 0.96),
	outline_size := 2,
	z_index := 5,
	with_shadow := true
) -> Label:
	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = text
	prompt.position = position
	prompt.size = box_size
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.z_index = z_index
	prompt.add_theme_font_size_override("font_size", font_size)
	prompt.add_theme_color_override("font_color", color)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	if outline_size > 0:
		prompt.add_theme_constant_override("outline_size", outline_size)
	if with_shadow:
		prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		prompt.add_theme_constant_override("shadow_offset_x", 1)
		prompt.add_theme_constant_override("shadow_offset_y", 1)
	var font := load(FONT_PATH) as Font
	if font != null:
		prompt.add_theme_font_override("font", font)
	parent.add_child(prompt)
	return prompt
