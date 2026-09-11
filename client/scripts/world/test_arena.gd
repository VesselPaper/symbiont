extends Node2D
## 测试竞技场（M1-01）
##
## 平地 + 左右边界墙 + 两个高度递进的小平台；玩家出生在左侧、木桩在右侧，
## 用于验证移动 / 跳跃 / 攻击的完整可玩闭环。真正的楼层场景在 M2 制作。
## M1-03：挂载对话 UI（DialogueBox，CanvasLayer 子节点保证 UI 在顶层）和对话
## 组件（Dialogue），场景稳定后自动弹出开场寄生体低语（intro_parasite_1 链）。

## 开场对话延迟（秒）：等场景 / 玩家 / 相机稳定后再弹出
const INTRO_DIALOGUE_DELAY := 0.5
## 开场对话 id（台词内容一律从 DataDB 读，这里只指定入口 id）
const INTRO_DIALOGUE_ID := "intro_parasite_1"

func _ready() -> void:
	# 相机挂到玩家身上跟随；limit 是场景绝对坐标，不随父节点变化
	var camera := $Camera2D as Camera2D
	camera.reparent($Player)
	camera.position = Vector2.ZERO
	camera.make_current()

	# M1-03：延时播放开场寄生体低语，让场景先稳定（玩家出生 → 低语弹出）
	var intro_timer := get_tree().create_timer(INTRO_DIALOGUE_DELAY)
	intro_timer.timeout.connect(_play_intro_dialogue)

func _play_intro_dialogue() -> void:
	# Dialogue 是挂 dialogue.gd 组件的普通 Node，用 call() 动态调用，
	# 避免静态类型检查把 play() 当作 Node 上不存在的方法报错
	var dialogue := get_node_or_null("Dialogue")
	if dialogue != null and dialogue.has_method("play"):
		dialogue.call("play", INTRO_DIALOGUE_ID)
