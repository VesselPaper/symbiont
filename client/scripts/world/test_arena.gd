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

## 史莱姆场景与出生点：对话/教程前期场景无敌人（避免教学时被攻击的矛盾），
## 教程进入"战斗"步骤时由 spawn_enemies() 生成（M1-08 修正）
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const SLIME_SPAWN_POINTS := [Vector2(350, 648), Vector2(900, 648)]

# ---- 摄像机（M1-09）----
## 垂直视野 = 角色身高的 N 倍（改这里即可调远近）；角色视觉身高 28px（见 player.gd CHARACTER_HEIGHT）
const VIEW_HEIGHT_IN_CHARACTERS := 12.0
const PLAYER_CHARACTER_HEIGHT := 28.0
## zoom = 视口高(720) ÷ (N×28)。N=12 → 336px 垂直视野 → zoom ≈ 2.14
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

func _ready() -> void:
	# 相机挂到玩家身上跟随；limit 是场景绝对坐标，不随父节点变化
	var camera := $Camera2D as Camera2D
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.reparent($Player)
	camera.position = Vector2.ZERO
	camera.make_current()

	# M1-03：延时播放开场寄生体低语，让场景先稳定（玩家出生 → 低语弹出）
	var intro_timer := get_tree().create_timer(INTRO_DIALOGUE_DELAY)
	intro_timer.timeout.connect(_play_intro_dialogue)

## 生成史莱姆（教程战斗步骤调用；可重复调用会叠加，调用方保证只调一次）
func spawn_enemies() -> void:
	for i in range(SLIME_SPAWN_POINTS.size()):
		var slime := SLIME_SCENE.instantiate()
		slime.position = SLIME_SPAWN_POINTS[i]
		slime.name = "Slime%d" % (i + 1)
		add_child(slime)

func _play_intro_dialogue() -> void:
	# Dialogue 是挂 dialogue.gd 组件的普通 Node，用 call() 动态调用，
	# 避免静态类型检查把 play() 当作 Node 上不存在的方法报错
	var dialogue := get_node_or_null("Dialogue")
	if dialogue != null and dialogue.has_method("play"):
		dialogue.call("play", INTRO_DIALOGUE_ID)
