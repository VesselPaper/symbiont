extends Node
## 新手教程组件（M1-10 改版）
##
## 纯流程逻辑，与 UI 解耦（风格同 components/dialogue.gd）：
##   - 等待 EventBus.dialogue_finished("intro_parasite_1")（开场低语整条链播完）后开始
##   - 环环相扣的分区教学：WEAPON → MOVE → JUMP → ATTACK → POGO → COMBAT
##     → PICKUP → SACRIFICE → DONE，一个目标达成才推进下一环
##   - 软隔离（组长定稿）：假人默认不激活、史莱姆到战斗环才生成、祭坛要肢体才能献祭，
##     不设门/墙 —— 提前跑去后一环无事可做
##   - 事件驱动为主：铁剑拾取(WEAPON)、击杀(COMBAT)、肢体拾取(PICKUP)、献祭(SACRIFICE)
##     走 EventBus；区域进入(MOVE/JUMP)与假人受击(ATTACK/POGO)走每帧检查
##   - 每环条件满足后立即推进，天然防抖（同一提示不会重复触发）
##   - 对话台词走 DataDB 是对话组件的职责；本组件的气泡文案属 UI 提示，
##     允许写在代码常量里（见 BUBBLE_TEXTS）
##
## 挂载：作为场景子节点，export ui_path 指向头顶气泡 UI（scenes/ui/tutorial_bubble.tscn）。
## UI 契约（duck typing；ui_path 留空则只走逻辑不显示，便于无头测试）：
##   show_bubble(text) / hide_bubble() / set_bubble_position(global_pos)
##
## 玩家节点通过 get_tree().get_first_node_in_group("player") 获取（player 在 "player" 分组）。

## 开场对话入口 id：它整条链（含 next_id）播完后教程才开始
const START_AFTER_DIALOGUE_ID := "intro_parasite_1"
## 拿到铁剑后"获得铁剑"气泡的停留时长（秒），到点进入行走环
const WEAPON_FLASH_DURATION := 1.2
## 教程完成提示的停留时长（秒），到点隐藏气泡
const DONE_HINT_DURATION := 1.0

## 标记区坐标矩形（与 test_arena.tscn 的发光块视觉对齐；区域判定用玩家节点坐标）：
## 行走标记在地面(x≈475，玩家站地 y≈647)；跳跃标记在 JumpPlatform 高台顶(x≈660，玩家站台 y≈557)
const MOVE_MARK_ZONE := Rect2(450, 600, 60, 80)   # x:450~510 —— 覆盖 x≈475 的行走标记
const JUMP_MARK_ZONE := Rect2(630, 530, 60, 60)   # x:630~690 —— 覆盖 x≈660 的跳跃标记（高台上）

## 教学假人节点名（test_arena 内的实例名，见 test_arena.tscn）
const DUMMY_A_NODE := "DummyA"
const DUMMY_B_NODE := "DummyB"

## 每环气泡文案（UI 提示而非对话台词，允许硬编码；数组下标即 Step 枚举值）
## 口吻说明（组长定稿）：寄生体在耳边低语式引导 —— 命令短句 + 括号标按键。
const BUBBLE_TEXTS := [
	"拿上那把剑",            # WEAPON
	"走到前面的光点（A/D）", # MOVE
	"跳过障碍（空格）",      # JUMP
	"用 J 攻击它",           # ATTACK
	"从高处跳下，按 J 下砍", # POGO
	"击杀它（J）",           # COMBAT
	"捡起肢体，献给我",      # PICKUP
	"带到祭坛，按 K 献祭",   # SACRIFICE
]
const WEAPON_FLASH_TEXT := "获得铁剑"
const DONE_BUBBLE_TEXT := "教程完成"

## 步骤状态机：WAIT_FOR_DIALOGUE 等待开场对话；WEAPON..SACRIFICE 对应分区环；DONE 结束
enum Step { WAIT_FOR_DIALOGUE = -1, WEAPON, MOVE, JUMP, ATTACK, POGO, COMBAT, PICKUP, SACRIFICE, DONE }

## 头顶气泡 UI 节点（tutorial_bubble）；留空则只走逻辑不显示
@export var ui_path: NodePath

var _ui: Node
var _step := Step.WAIT_FOR_DIALOGUE
var _player: Node                 # 分组 "player" 的玩家节点（缓存，失效自动重取）
var _dummies: Dictionary = {}     # 教学假人缓存：节点名 → 节点
var _dummy_a_initial_hp := 0      # 进入 ATTACK 时假人甲的初始 hp，受击小于它就推进
var _dummy_b_initial_hp := 0      # 进入 POGO 时假人乙的初始 hp
var _weapon_flash_timer := 0.0    # "获得铁剑"气泡倒计时，到点进 MOVE
var _done_hint_timer := 0.0

func _ready() -> void:
	if ui_path != NodePath(""):
		_ui = get_node_or_null(ui_path)
		if _ui == null:
			push_warning("tutorial: 找不到 ui_path=%s，本组件只走逻辑不显示" % ui_path)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.sacrifice_done.connect(_on_sacrifice_done)

func _process(delta: float) -> void:
	# 气泡每帧跟随玩家头顶（UI 存在才定位；无 UI 时纯逻辑仍正常推进）
	_position_bubble_on_player()
	if _step == Step.DONE:
		if _done_hint_timer > 0.0:
			_done_hint_timer -= delta
			if _done_hint_timer <= 0.0:
				_hide_bubble()
		return
	if _step == Step.WAIT_FOR_DIALOGUE:
		return
	# WEAPON：拿到铁剑后短暂显示"获得铁剑"，到点进 MOVE（行走环）
	if _step == Step.WEAPON:
		if _weapon_flash_timer > 0.0:
			_weapon_flash_timer -= delta
			if _weapon_flash_timer <= 0.0:
				_advance()
		return
	match _step:
		Step.MOVE:
			# 走到行走标记区（x≈475 发光块）→ 进 JUMP；提前踩进去不推进，轮到即可立即推进
			if _player_in_rect(MOVE_MARK_ZONE):
				_advance()
		Step.JUMP:
			# 跳过矮墙后进入跳跃标记区（x≈710 发光块）→ 进 ATTACK
			if _player_in_rect(JUMP_MARK_ZONE):
				_advance()
		Step.ATTACK:
			# 假人甲受击一次（hp 小于进入本环时的初始值）→ 进 POGO
			if _dummy_hit(DUMMY_A_NODE, _dummy_a_initial_hp):
				_advance()
		Step.POGO:
			# 假人乙受击一次 → 进 COMBAT
			if _dummy_hit(DUMMY_B_NODE, _dummy_b_initial_hp):
				_advance()
		Step.COMBAT, Step.PICKUP, Step.SACRIFICE:
			pass  # 由事件推进（击杀/拾取/献祭），不需每帧轮询

# ---- 事件 / 推进 ----

func _on_dialogue_finished(dialogue_id: String) -> void:
	if _step != Step.WAIT_FOR_DIALOGUE:
		return
	if dialogue_id != START_AFTER_DIALOGUE_ID:
		return
	# WAIT_FOR_DIALOGUE → WEAPON：提示去拿地上的剑
	_advance()

## 拾取：WEAPON 环收到铁剑 → 短暂"获得铁剑"；PICKUP 环收到肢体 → 去献祭
func _on_item_picked(item_id: String, _count: int) -> void:
	match _step:
		Step.WEAPON:
			# 碰到插地剑：显示"获得铁剑"，时长走完由 _process 推进到 MOVE
			if item_id == "iron_sword":
				_weapon_flash_timer = WEAPON_FLASH_DURATION
				_show_bubble(WEAPON_FLASH_TEXT)
		Step.PICKUP:
			if item_id == "monster_limb":
				_advance()  # PICKUP → SACRIFICE

func _on_enemy_killed(_enemy: Node, _position: Vector2) -> void:
	if _step != Step.COMBAT:
		return
	_advance()  # COMBAT → PICKUP：提示去捡掉落的肢体

func _on_sacrifice_done(_sacrifice_id: String, _total_count: int) -> void:
	if _step != Step.SACRIFICE:
		return
	# SACRIFICE → DONE（终态，不走 _advance，避免再显示环提示）
	_step = Step.DONE
	_done_hint_timer = DONE_HINT_DURATION
	_show_bubble(DONE_BUBBLE_TEXT)

## 进入下一步：先推进再显示对应环提示；到 DONE 由献祭流程接管
func _advance() -> void:
	_step += 1
	match _step:
		Step.ATTACK:
			# 到攻击环才激活假人甲（软隔离：提前打它没反应），记下初始 hp 作受击判定基准
			_activate_dummy(DUMMY_A_NODE)
			_dummy_a_initial_hp = _read_hp(_get_dummy(DUMMY_A_NODE))
		Step.POGO:
			_activate_dummy(DUMMY_B_NODE)
			_dummy_b_initial_hp = _read_hp(_get_dummy(DUMMY_B_NODE))
		Step.COMBAT:
			# 战斗环开始前，让所在场景生成史莱姆（对话/教程前期无敌人，见 test_arena.spawn_enemies）
			_spawn_enemies_for_combat()
	if _step < Step.DONE:
		_show_step_bubble(_step)

## 调用所在场景的 spawn_enemies()（duck typing；场景不提供则跳过）
func _spawn_enemies_for_combat() -> void:
	var arena := get_parent()
	if arena != null and arena.has_method("spawn_enemies"):
		arena.call("spawn_enemies")

## 激活教学假人（activate 由 dummy_target.gd 提供，软隔离核心）
func _activate_dummy(node_name: String) -> void:
	var dummy := _get_dummy(node_name)
	if dummy != null and dummy.has_method("activate"):
		dummy.activate()

# ---- 检测 ----

## 玩家节点是否进入区域矩形（MOVE/JUMP 用；玩家中心点坐标）
func _player_in_rect(rect: Rect2) -> bool:
	var player := _get_player()
	if player == null:
		return false
	return rect.has_point(player.global_position)

## 假人是否已被打到（hp 小于进入本环时的初始值即算受击一次，不用打死）
func _dummy_hit(node_name: String, initial_hp: int) -> bool:
	var dummy := _get_dummy(node_name)
	if dummy == null or not is_instance_valid(dummy):
		return false
	return _read_hp(dummy) < initial_hp

func _read_hp(dummy: Node) -> int:
	if dummy == null or not is_instance_valid(dummy):
		return 0
	return int(dummy.get("hp"))

## 按节点名取教学假人（挂在 tutorial 的兄弟场景节点下，缓存失效自动重取）
func _get_dummy(node_name: String) -> Node:
	var dummy: Node = _dummies.get(node_name)
	if dummy == null or not is_instance_valid(dummy):
		dummy = get_parent().get_node_or_null(node_name)
		_dummies[node_name] = dummy
	return dummy

# ---- 气泡 ----

func _position_bubble_on_player() -> void:
	if _ui == null or not is_instance_valid(_ui):
		return
	var player := _get_player()
	if player == null:
		return
	_ui.set_bubble_position(player.global_position + Vector2(0, -44))

func _show_step_bubble(step: int) -> void:
	if step < 0 or step >= BUBBLE_TEXTS.size():
		return
	_show_bubble(BUBBLE_TEXTS[step])

func _show_bubble(text: String) -> void:
	if _ui != null:
		_ui.show_bubble(text)

func _hide_bubble() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.hide_bubble()

func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player
