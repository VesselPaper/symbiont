extends Node
## 新手教程组件（M1-08）
##
## 纯流程逻辑，与 UI 解耦（风格同 components/dialogue.gd）：
##   - 等待 EventBus.dialogue_finished("intro_parasite_1")（开场低语整条链播完）后开始
##   - 动作触发式逐步推进：移动 → 跳跃 → 攻击 → 下砍(pogo) → 战斗（击杀任意敌人）
##     → 捡肢体（item_picked）→ 献祭（sacrifice_done）→ 完成
##   - 每步条件满足后立即进入下一步，天然防抖（同一提示不会重复触发）
##   - 对话台词走 DataDB 是对话组件的职责；本组件的提示文案属 UI 提示，
##     允许写在代码常量里（见 STEP_HINTS）
##
## 挂载：作为场景子节点，export ui_path 指向提示条 UI（scenes/ui/tutorial_hint.tscn）。
## UI 契约（duck typing；ui_path 留空则只走逻辑不显示，便于无头测试）：
##   show_hint(text) / hide_hint()
##
## 玩家节点通过 get_tree().get_first_node_in_group("player") 获取（player 在 "player" 分组）。

## 开场对话入口 id：它整条链（含 next_id）播完后教程才开始
const START_AFTER_DIALOGUE_ID := "intro_parasite_1"
## 教程完成提示的停留时长（秒），到点隐藏提示条
const DONE_HINT_DURATION := 1.0

## 每步提示文案（UI 提示而非对话台词，允许硬编码；数组顺序即状态机推进顺序）
const STEP_HINTS := [
	"按 A/D 左右移动",
	"按 空格 跳跃",
	"按 J 攻击",
	"空中下落时按 J 下砍",
	"有敌人靠近！按 J 攻击它",
	"捡起地上的怪物肢体",
	"到祭坛按 K 献上肢体",
]
const DONE_HINT_TEXT := "教程完成"

## 步骤状态机：WAIT_FOR_DIALOGUE 等待开场对话；MOVE..SACRIFICE 对应提示步骤；DONE 结束
enum Step { WAIT_FOR_DIALOGUE = -1, MOVE, JUMP, ATTACK, POGO, COMBAT, PICKUP, SACRIFICE, DONE }

## 提示条 UI 节点（tutorial_hint）；留空则只走逻辑不显示
@export var ui_path: NodePath

var _ui: Node
var _step := Step.WAIT_FOR_DIALOGUE
var _player: Node            # 分组 "player" 的玩家节点（缓存，失效自动重取）
var _player_pogo_active := false  # 玩家 _pogo_active 上一帧快照，用于边沿检测（防抖）
var _done_hint_timer := 0.0

func _ready() -> void:
	if ui_path != NodePath(""):
		_ui = get_node_or_null(ui_path)
		if _ui == null:
			push_warning("tutorial: 找不到 ui_path=%s，本组件只走逻辑不显示" % ui_path)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	# M1-04：捡肢体 / 献祭是事件驱动的推进（同击杀，不每帧轮询）
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.sacrifice_done.connect(_on_sacrifice_done)

func _process(delta: float) -> void:
	# 完成后的"教程完成"短提示计时：到点隐藏提示条
	if _step == Step.DONE:
		if _done_hint_timer > 0.0:
			_done_hint_timer -= delta
			if _done_hint_timer <= 0.0:
				_hide_hint()
		return
	if _step < Step.MOVE:
		return
	match _step:
		Step.MOVE:
			# 移动是按住持续的状态，用 get_axis 判断（不用 just_pressed，防只读到一帧）
			if Input.get_axis("move_left", "move_right") != 0.0:
				_advance()
		Step.JUMP:
			if Input.is_action_just_pressed("jump"):
				_advance()
		Step.ATTACK:
			if Input.is_action_just_pressed("attack"):
				_advance()
		Step.POGO:
			# 下砍：检测玩家 _pogo_active 从 false 变 true（边沿，防每帧重复触发）
			if _pogo_edge_activated():
				_advance()
		Step.COMBAT:
			pass  # 由 _on_enemy_killed 推进（击杀事件驱动，不需每帧轮询）

# ---- 事件 / 推进 ----

func _on_dialogue_finished(dialogue_id: String) -> void:
	if _step != Step.WAIT_FOR_DIALOGUE:
		return
	if dialogue_id != START_AFTER_DIALOGUE_ID:
		return
	_step = Step.MOVE
	_show_step_hint(Step.MOVE)

func _on_enemy_killed(_enemy: Node, _position: Vector2) -> void:
	if _step != Step.COMBAT:
		return
	# COMBAT → PICKUP：提示去捡掉落的肢体（M1-04）
	_advance()

## 捡起肢体：PICKUP 步收到 item_picked("monster_limb") → 推进到 SACRIFICE（提示去献祭）
func _on_item_picked(item_id: String, _count: int) -> void:
	if _step != Step.PICKUP:
		return
	if item_id != "monster_limb":
		return
	_advance()

## 献祭完成：SACRIFICE 步收到 sacrifice_done → 教程走完（沿用原有"教程完成"短提示逻辑）
func _on_sacrifice_done(_sacrifice_id: String, _total_count: int) -> void:
	if _step != Step.SACRIFICE:
		return
	_step = Step.DONE
	_done_hint_timer = DONE_HINT_DURATION
	_show_hint(DONE_HINT_TEXT)

## 进入下一步：先推进再显示对应提示；到 DONE 则交给击杀/完成流程
func _advance() -> void:
	_step += 1
	# 战斗步骤开始前，让所在场景生成敌人（对话/教程前期无敌人，见 test_arena.spawn_enemies）
	if _step == Step.COMBAT:
		_spawn_enemies_for_combat()
	if _step < Step.DONE:
		_show_step_hint(_step)

## 调用所在场景的 spawn_enemies()（duck typing；场景不提供则跳过）
func _spawn_enemies_for_combat() -> void:
	var arena := get_parent()
	if arena != null and arena.has_method("spawn_enemies"):
		arena.call("spawn_enemies")

func _show_step_hint(step: int) -> void:
	if step < 0 or step >= STEP_HINTS.size():
		return
	_show_hint(STEP_HINTS[step])

func _show_hint(text: String) -> void:
	if _ui != null:
		_ui.show_hint(text)

func _hide_hint() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.hide_hint()

# ---- 检测 ----

## 玩家 _pogo_active 边沿检测：仅在 false→true 的那一帧返回 true
func _pogo_edge_activated() -> bool:
	var player := _get_player()
	if player == null:
		return false
	var pogo_now := bool(player.get("_pogo_active"))
	var activated := pogo_now and not _player_pogo_active
	_player_pogo_active = pogo_now
	return activated

func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player
