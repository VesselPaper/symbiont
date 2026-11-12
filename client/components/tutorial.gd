extends Node
## 新手教程组件（M1-10 改版 / M1-12 流程重排 / M4-21 去光点 / M4-22 提示常驻）
##
## 纯流程逻辑，与 UI 解耦（风格同 components/dialogue.gd）：
##   - 等待 EventBus.dialogue_finished("intro_parasite_1")（开场低语整条链播完）后开始
##   - 环环相扣的分区教学：MOVE → JUMP → WEAPON → ATTACK → POGO → COMBAT
##     → PICKUP → SACRIFICE → DONE，一个目标达成才推进下一环
##   - 软隔离（组长定稿）：假人默认不激活、史莱姆到战斗环才生成、祭坛要肢体才能献祭，
##     不设门/墙 —— 提前跑去后一环无事可做
##   - M4-21 组长定稿「不用指引光」：原来那颗会飞的引导光点连同 marker_path 一起删了。
##     现在 MOVE/JUMP/POGO 三环都是**位置判定**（人真的走到了/真的站上了才算过），
##     判定数字只在 test_arena 的 STAGE 表里，本组件通过 player_reached / player_on_platform
##     两个duck-typing接口去问场景，自己不抄坐标：
##       MOVE = 横向走过移动点；JUMP = 双脚站上跳台；POGO = 双脚站上下劈方台（不是“做出下劈动作”）
##   - 其余环仍走事件：铁剑拾取(WEAPON)、假人受击(ATTACK)、击杀(COMBAT)、
##     肢体拾取(PICKUP)、献祭(SACRIFICE)
##   - 对话台词走 DataDB 是对话组件的职责；本组件的目标文案属 UI 提示，
##     允许写在代码常量里（见 OBJECTIVE_TEXTS）
##   - M4-22 组长定稿：每环提示做完**不消失**，留在地图上当路标（走过的句子变暗、当前那句亮），
##     临时话只有「获得铁剑」「教程完成」两句，各自计时收掉
##
## 挂载：作为场景子节点，export ui_path 指向目标文字 UI（scenes/ui/objective_hud.tscn）。
## UI 契约（duck typing；ui_path 留空则只走逻辑不显示，便于无头测试）：
##   show_objective(step, text, world_pos) / set_active_step(step)
##   show_bubble(text) / hide_bubble() / set_bubble_position(global_pos)   ← 临时提示

## 开场对话入口 id：它整条链（含 next_id）播完后教程才开始
const START_AFTER_DIALOGUE_ID := "intro_parasite_1"
## 拿到铁剑后"获得铁剑"气泡的停留时长（秒），到点进入攻击环
const WEAPON_FLASH_DURATION := 1.2
## 教程完成提示的停留时长（秒），到点隐藏气泡
const DONE_HINT_DURATION := 1.0

## 每环提示文字的默认锚点（文字刻在锚点上方，钉在世界坐标，不跟玩家走）。
## M4-19/M4-21 起实际站位由 test_arena 的 STAGE 表在 _ready 里推进来，
## 这份常量只作“单独挂 Tutorial、没有场景注入”时的兜底，数值和 STAGE 表一致。
## 高度统一抬到地面/平台顶面之上 60px 以上（组长反馈：A/D 那句贴着石墙读不清）。
## M4-22：MOVE 那句整句左移一个文字宽度（560 → 406），让开 600 处那道 200px 高的教学骨栅门；
## 走路的判定点还是 STAGE 表的 move_mark(560)，这里只挪“话写在哪”。
const STEP_ANCHORS: Array[Vector2] = [
	Vector2(406, 585),   # MOVE：地面（地面顶 659），避开 600 的骨栅门
	Vector2(900, 500),   # JUMP：跳台顶 571
	Vector2(1310, 500),  # WEAPON：尸体+剑
	Vector2(1650, 480),  # ATTACK：木桩甲
	Vector2(2155, 372),  # POGO：下劈方台（顶 440）
	Vector2(2660, 590),  # COMBAT：浅坑底（坑底 659）
	Vector2(3130, 498),  # PICKUP：祭坛石碗上方（台顶 572）
	Vector2(3130, 498),  # SACRIFICE：同一点
]

## 教学假人节点名（test_arena 内的实例名，见 test_arena.tscn）
const DUMMY_A_NODE := "DummyA"
const DUMMY_B_NODE := "DummyB"

## 位置判定用到的 STAGE 表键（场景侧接口的参数；表在 test_arena.gd）
const MOVE_MARK_KEY := "move_mark"
const JUMP_PLATFORM_KEY := "ledge"
const POGO_PLATFORM_KEY := "pogo"

## 每环目标文案（UI 提示而非对话台词，允许硬编码；数组下标即 Step 枚举值）
## 口吻说明（组长定稿）：寄生体在耳边低语式引导 —— 命令短句 + 括号标按键。
const OBJECTIVE_TEXTS := [
	"走到前面（A/D）",            # MOVE
	"跳上平台（空格）",            # JUMP
	"拿上那把剑",                  # WEAPON
	"用 J 攻击木桩",               # ATTACK
	"从木桩上踩一下，跳上方台",    # POGO（成功标志是站上去，不是挥出下劈）
	"击杀它（J）",                 # COMBAT
	"捡起肢体，献给我",            # PICKUP
	"带到祭坛，按 K 献祭",         # SACRIFICE
]
const WEAPON_FLASH_TEXT := "获得铁剑"
const DONE_BUBBLE_TEXT := "教程完成"

## 步骤状态机：WAIT_FOR_DIALOGUE 等待开场对话；MOVE..SACRIFICE 对应分区环；DONE 结束
enum Step { WAIT_FOR_DIALOGUE = -1, MOVE, JUMP, WEAPON, ATTACK, POGO, COMBAT, PICKUP, SACRIFICE, DONE }

## 气泡 UI 节点（objective_hud）；留空则只走逻辑不显示
@export var ui_path: NodePath

var _ui: Node
var _step := Step.WAIT_FOR_DIALOGUE
var _player: Node                 # 分组 "player" 的玩家节点（缓存，失效自动重取）
var _dummies: Dictionary = {}     # 教学假人缓存：节点名 → 节点
var _dummy_a_initial_hp := 0      # 进入 ATTACK 时假人甲的初始 hp，受击小于它就推进
var _dummy_b_initial_hp := 0      # 进入 ATTACK 时假人乙的初始 hp
var _anchors: Array[Vector2] = STEP_ANCHORS.duplicate()  # 实际锚点，场景可在 _ready 里覆盖
var _weapon_flash_timer := 0.0    # "获得铁剑"气泡倒计时，到点进 ATTACK
var _done_hint_timer := 0.0

## 由所在场景推进来的锚点表（test_arena 的 STAGE 表）。参数不对就保持默认，不崩。
func set_step_anchors(list: Array) -> void:
	if list.size() != STEP_ANCHORS.size():
		push_warning("tutorial: 锚点表应为 %d 项，收到 %d 项，继续用默认锚点" % [STEP_ANCHORS.size(), list.size()])
		return
	var typed: Array[Vector2] = []
	for item in list:
		typed.append(item as Vector2)
	_anchors = typed

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
	if _step == Step.DONE:
		if _done_hint_timer > 0.0:
			_done_hint_timer -= delta
			if _done_hint_timer <= 0.0:
				_hide_bubble()
		return
	if _step == Step.WAIT_FOR_DIALOGUE:
		return
	# WEAPON：拿到铁剑后短暂显示"获得铁剑"，到点进 ATTACK。
	# 剑拾取物没有软隔离，玩家在 JUMP 环跳上台时可能顺路先捡走，
	# 所以进环时直接判"已持剑"也能开始闪烁提示，避免教学卡死
	if _step == Step.WEAPON:
		if not _player_has_weapon():
			return
		if _weapon_flash_timer <= 0.0:
			_weapon_flash_timer = WEAPON_FLASH_DURATION
			_show_bubble(WEAPON_FLASH_TEXT)
		_weapon_flash_timer -= delta
		if _weapon_flash_timer <= 0.0:
			_advance()
		return
	match _step:
		Step.MOVE:
			# 组长定稿：走到位就算学会，不用光点碰
			if _player_reached(MOVE_MARK_KEY):
				_advance()
		Step.JUMP:
			# 必须真的站上跳台（在台上按着跳跃键乱蹦也会过，因为判定是“落地站在台上”）
			if _player_on_platform(JUMP_PLATFORM_KEY):
				_advance()
		Step.ATTACK:
			# 假人甲受击一次（hp 小于进入本环时的初始值）→ 进 POGO
			if _dummy_hit(DUMMY_A_NODE, _dummy_a_initial_hp):
				_advance()
		Step.POGO:
			# 组长定稿：下劈成功的标志是**站上那块方台**，不是挥出下劈动作
			if _player_on_platform(POGO_PLATFORM_KEY):
				_advance()
		Step.PICKUP:
			# 肢体拾取物没有软隔离：战斗环击杀后可能顺手捡起，
			# 进环时已持有肢体直接推进，避免教学卡死
			if _has_monster_limb():
				_advance()
		Step.COMBAT, Step.SACRIFICE:
			# 由事件推进（击杀/献祭），不需每帧轮询
			pass

# ---- 事件 / 推进 ----

func _on_dialogue_finished(dialogue_id: String) -> void:
	if _step != Step.WAIT_FOR_DIALOGUE:
		return
	if dialogue_id != START_AFTER_DIALOGUE_ID:
		return
	# WAIT_FOR_DIALOGUE → MOVE：提示往前走
	_advance()

## 拾取：WEAPON 环收到铁剑 → 短暂"获得铁剑"；PICKUP 环收到肢体 → 去献祭
func _on_item_picked(item_id: String, _count: int) -> void:
	match _step:
		Step.WEAPON:
			# 碰到插地剑：显示"获得铁剑"，时长走完由 _process 推进到 ATTACK
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
	# 组长（M4-22）：每环提示做完要留在地图上当地标，所以这里只把全部刻字调暗，
	# 不藏 HUD；"教程完成"才是临时一句，1 秒后自己收。
	if _ui != null and _ui.has_method("set_active_step"):
		_ui.call("set_active_step", -1)
	_show_bubble(DONE_BUBBLE_TEXT)

## 教程是否已跑完（献祭完成）。场景用它决定下一层的门开不开。
func is_completed() -> bool:
	return _step == Step.DONE

## 进入下一步：先推进再显示对应环提示；到 DONE 由献祭流程接管
func _advance() -> void:
	_step += 1
	match _step:
		Step.JUMP:
			# MOVE 做完，移门打开；玩家才能真正靠近第一平台
			_open_gate("move")
		Step.WEAPON:
			# JUMP 做完，跳台门打开；剑在门后
			_open_gate("jump")
		Step.ATTACK:
			# 到攻击环才激活假人甲（软隔离：提前打它没反应），记下初始 hp 作受击判定基准
			_activate_dummy(DUMMY_A_NODE)
			_dummy_a_initial_hp = _read_hp(_get_dummy(DUMMY_A_NODE))
		Step.POGO:
			# 木桩甲被打到，攻击门打开；去假人乙
			_open_gate("attack")
			_activate_dummy(DUMMY_B_NODE)
			_dummy_b_initial_hp = _read_hp(_get_dummy(DUMMY_B_NODE))
		Step.COMBAT:
			# 站上方台（下劈跳上去）后才开下劈门；再去坑区战斗
			_open_gate("pogo")
			# 战斗环开始前，让所在场景生成史莱姆（对话/教程前期无敌人，见 test_arena.spawn_enemies）
			_spawn_enemies_for_combat()
	if _step < Step.DONE:
		_show_step_text(_step)

## 调用所在场景的 spawn_enemies()（duck typing；场景不提供则跳过）
func _spawn_enemies_for_combat() -> void:
	var arena := get_parent()
	if arena != null and arena.has_method("spawn_enemies"):
		arena.call("spawn_enemies")

## 打开场景里的教学门（test_arena 提供 open_tutorial_gate；无场景时静默跳过）
func _open_gate(gate_id: String) -> void:
	var arena := get_parent()
	if arena != null and arena.has_method("open_tutorial_gate"):
		arena.call("open_tutorial_gate", gate_id)

## 激活教学假人（activate 由 dummy_target.gd 提供，软隔离核心）
func _activate_dummy(node_name: String) -> void:
	var dummy := _get_dummy(node_name)
	if dummy != null and dummy.has_method("activate"):
		dummy.activate()

# ---- 位置判定（真正的“做到了”由场景答，坐标只存在 STAGE 表）----

## 玩家是否已横向走到某个站位（MOVE 环）
func _player_reached(mark_key: String) -> bool:
	var arena := get_parent()
	if arena == null or not arena.has_method("player_reached"):
		return false
	var player := _get_player()
	return bool(arena.call("player_reached", mark_key, player))

## 玩家是否双脚站上某块平台（JUMP/POGO 环）
func _player_on_platform(rect_key: String) -> bool:
	var arena := get_parent()
	if arena == null or not arena.has_method("player_on_platform"):
		return false
	var player := _get_player()
	return bool(arena.call("player_on_platform", rect_key, player))

# ---- 检测 ----

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

## 玩家是否已持有铁剑（WEAPON 环提前拾剑兼容：剑拾取物没有软隔离）
func _player_has_weapon() -> bool:
	var player := _get_player()
	return player != null and bool(player.get("has_weapon"))

## 是否已持有怪物肢体（PICKUP 环提前拾肢体兼容：肢体拾取物没有软隔离）
func _has_monster_limb() -> bool:
	return GameManager.monster_limb_count > 0

# ---- 世界里的目标文字 ----

## 进入某环：这一环亮起来，句子刻到地图上。做过的那些句子由 HUD 自己留着变暗。
## 先 set_active_step 再 show_objective：这样新刻的那句直接按“当前环”上色。
func _show_step_text(step: int) -> void:
	if step < 0 or step >= OBJECTIVE_TEXTS.size() or _ui == null:
		return
	var anchor_index := clampi(step, 0, _anchors.size() - 1)
	if _ui.has_method("set_active_step"):
		_ui.call("set_active_step", step)
	if not _ui.has_method("show_objective"):
		# UI 没实现新契约（老气泡/纯逻辑测试）：退回临时气泡，至少话还在
		_show_bubble(OBJECTIVE_TEXTS[step])
		return
	_ui.call("show_objective", step, OBJECTIVE_TEXTS[step], _anchors[anchor_index])

## 临时提示（获得铁剑 / 教程完成）：挂在当前环锚点上方，显示时长由本组件计时
func _show_bubble(text: String) -> void:
	if _ui == null:
		return
	# 文字是地图背景的一部分：每步钉在自己那环的锚点上方，不跟着玩家走。
	if _ui.has_method("set_bubble_position"):
		var target_index := clampi(_step, 0, _anchors.size() - 1)
		_ui.call("set_bubble_position", _anchors[target_index])
	_ui.show_bubble(text)

func _hide_bubble() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.hide_bubble()

func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player
