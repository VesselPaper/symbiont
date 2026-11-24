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
##   - 提示形态（P0 反馈改版）：只把"当前这一环"的一句话交给 HUD，显示在屏幕底部；
##     进入下一环就换下一句，教程结束收起。不再把做过的句子留在背景里当地标。
##
## 挂载：作为场景子节点，export ui_path 指向目标文字 UI（scenes/ui/objective_hud.tscn）。
## UI 契约（duck typing；ui_path 留空则只走逻辑不显示，便于无头测试）：
##   show_objective(step, text, world_pos) / set_active_step(step)
##   show_bubble(text) / hide_bubble() / set_bubble_position(global_pos)   ← 临时提示

## 开场对话入口 id：它整条链（含 next_id）播完后教程才开始
const START_AFTER_DIALOGUE_ID := "intro_parasite_1"
## 拿到铁剑后"获得铁剑"气泡的停留时长（秒），到点进入攻击环。
## P0 反馈：操作后弹的提示统一播 2 秒再收，1.2 秒来不及读完
const WEAPON_FLASH_DURATION := 2.0
## 教程完成提示的停留时长（秒），到点隐藏气泡（同上，统一 2 秒）
const DONE_HINT_DURATION := 2.0

## 每环提示文字的默认锚点。旧版把这些字刻在世界坐标上，现在提示固定在屏幕底部，
## 锚点只剩"临时气泡挂在哪"这一个用途；保留这份表和 set_step_anchors，
## 是为了关卡的 STAGE 表仍能一次性推进来、以后要回到世界提示时不用改接口。
## 兜底锚点（M5-25）：这一环落脚面往上 3 个角色身高（28×3=84）。
const STEP_ANCHORS: Array[Vector2] = [
	Vector2(640, 575),   # MOVE：平地 659 - 84
	Vector2(1190, 575),  # JUMP：跳台前面 1 秒的平地 659 - 84
	Vector2(2140, 487),  # WEAPON：跳台顶 571 - 84（尸体+剑）
	Vector2(2890, 487),  # ATTACK：同上（木桩甲）
	Vector2(3650, 487),  # POGO：方台左边（写方块里会被埋），台面往上 84
	Vector2(4500, 575),  # COMBAT：地面 659 - 84
	Vector2(5250, 575),  # PICKUP：肢体掉落处 659 - 84（祭坛上方只留献祭那一行）
	Vector2(8750, 575),  # SACRIFICE：右岸地面 659 - 84（门旁边）
]

## 教学假人节点名（test_arena 内的实例名，见 test_arena.tscn）
const DUMMY_A_NODE := "DummyA"
const DUMMY_B_NODE := "DummyB"

## 位置判定用到的 STAGE 表键（场景侧接口的参数；表在 test_arena.gd）
const MOVE_MARK_KEY := "move_mark"
const JUMP_PLATFORM_KEY := "ledge"
const POGO_PLATFORM_KEY := "pogo"

## 每环目标文案。M4-23 组长定稿：提示要带上按键，新手才知道按什么；
## 但话说在前面，按键放在括号里当“旁注”，读起来仍是寄生体在耳边低语，不像说明书。
## P0 反馈：第一个要跳的地方恢复一句"空格跳跃"；它和其它目标提示一样走近才出现，
## 按下空格就算做出反应，随即收起（见 _process 的 JUMP 分支）。
const OBJECTIVE_TEXTS := [
	"按 A 或 D 往右走，走一段它自己就熟了。",  # MOVE
	"按空格进行跳跃。",                        # JUMP
	"把地上那把铁器捡起来，走近了按 K。",      # WEAPON
	"对着草人按 J，砍一下试试手感。",          # ATTACK
	"踩着草人借力，落地前按 J 往下劈，上那个方台。",  # POGO（成功标志是站上去，不是挥出下劈）
	"有东西过来了，它扑的时候别硬接。",        # COMBAT
	"走近它按 K，把掉下来的肢体带走。",        # PICKUP
	"把肢体放进祭坛，按 K。",                  # SACRIFICE
]
const WEAPON_FLASH_TEXT := "获得铁剑"
const DONE_BUBBLE_TEXT := "教程完成"

## 靠近提示（P0 反馈）：铁剑、木桩这类目标提示，只有走到离目标这么近才出现；
## 离开范围就收起，做失败（比如挥空）还站在附近的话继续挂着，直到动作成功。
## 240 ≈ 8.5 个角色身高（28px），比一屏（12 身高）小，玩家能感觉出是"走到跟前才提醒"。
const HINT_RADIUS := 240.0
## 哪些环吃"靠近才提示"，值为场景 tutorial_hint_targets() 的键；空串 = 进环就提示。
## 下标与 Step 枚举对齐：MOVE=0 … SACRIFICE=7
const HINT_TARGET_KEYS := ["", "JUMP", "WEAPON", "ATTACK", "POGO", "COMBAT", "PICKUP", "SACRIFICE"]

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
## MOVE 环的按下沿判定：上一帧是否按着 A/D（见 _process 里的 MOVE 分支）
var _move_held_last := false
## JUMP 环的按下沿判定：上一帧是否按着空格
var _jump_held_last := false
## 跳跃提示是否已被"按键反应"消费：按下空格后不再因为还站在范围内而重新弹出
var _jump_hint_consumed := false
## 当前环的提示是否正显示（靠近类提示用，见 _update_proximity_hint）
var _hint_shown := false

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
	# 目标类提示：每帧按"离目标多远"决定显示/收起（成功与否由下面的判定推进）
	_update_proximity_hint()
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
			# P0 反馈：玩家按下 A/D 就说明"会走了"，提示在同一帧收掉、门打开；
			# 不用再走到 STAGE 的 move_mark。保留过线兜底，传送/读档回来也能推进。
			# 用"上一帧是否按着"自己判按下沿：无头测试里 action_press 与 _process
			# 不在同一帧，is_action_just_pressed 会漏掉（踩过）。
			var moving := Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
			if moving and not _move_held_last:
				_advance()
			elif _player_reached(MOVE_MARK_KEY):
				_advance()
			_move_held_last = moving
		Step.JUMP:
			# 近距提示：按下空格就算"做出反应"，提示立刻收起；
			# 人还在范围内也不重弹（_jump_hint_consumed 卡住），直到真的站上平台推进
			var jumping := Input.is_action_pressed("jump")
			if jumping and not _jump_held_last:
				_jump_hint_consumed = true
				if _hint_shown:
					_hint_shown = false
					_hide_step_text()
			_jump_held_last = jumping
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
	# P0 改版：教程结束后不再把八句话留在背景里，直接收起目标提示；
	# 只让"教程完成"这句临时提示自己计时收掉。
	if _ui != null and _ui.has_method("set_active_step"):
		_ui.call("set_active_step", -1)
	_show_bubble(DONE_BUBBLE_TEXT)

## 教程是否已跑完（献祭完成）。场景用它决定下一层的门开不开。
func is_completed() -> bool:
	return _step == Step.DONE

## 进入下一步：先推进再显示对应环提示；到 DONE 由献祭流程接管
func _advance() -> void:
	_step += 1
	_hint_shown = false
	_jump_hint_consumed = false
	# 进环那一刻如果空格还按着（比如跳上平台的过程中），不算"新按了一次"，
	# 不然跳跃提示会被立刻消费掉、玩家根本没看见
	_jump_held_last = Input.is_action_pressed("jump")
	# 换环先把上一条收掉：靠近类提示如果"进来时不在范围内"，不会再有隐藏动作，
	# 不先收就会把上一环的要求留在屏幕上（踩过）
	_hide_step_text()
	# P0 反馈「获得铁剑一直播放」：气泡是上一环的临时提示，换环必须一起收。
	# 之前 WEAPON 的计时器到点只调 _advance()，没人隐藏气泡，它就永久挂在屏幕上了。
	_hide_bubble()
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

## 进入某环：把当前这一句交给 HUD。旧的那句由 HUD 在换字时一并收掉，
## 所以玩家做完动作后，屏幕上不会再留着刚才那条要求。
func _show_step_text(step: int) -> void:
	if step < 0 or step >= OBJECTIVE_TEXTS.size() or _ui == null:
		return
	# 目标类提示不在这里直接弹：等玩家走进 HINT_RADIUS 再显示（见 _update_proximity_hint）
	if _hint_target_key(step) != "":
		_update_proximity_hint()
		return
	_push_step_text(step)

## 真正把某环的文案交给 HUD（空文案 = 收起上一条）
func _push_step_text(step: int) -> void:
	if step < 0 or step >= OBJECTIVE_TEXTS.size() or _ui == null:
		return
	var text: String = str(OBJECTIVE_TEXTS[step])
	# 这一环按需求不提示（JUMP）：只把上一条收掉，屏幕上不留字
	if text.strip_edges() == "":
		_hide_step_text()
		return
	var anchor_index := clampi(step, 0, _anchors.size() - 1)
	if _ui.has_method("set_active_step"):
		_ui.call("set_active_step", step)
	if not _ui.has_method("show_objective"):
		# UI 没实现新契约（老气泡/纯逻辑测试）：退回临时气泡，至少话还在
		_show_bubble(text)
		return
	_ui.call("show_objective", step, text, _anchors[anchor_index])

## 收起当前目标提示（不动临时气泡）
func _hide_step_text() -> void:
	if _ui != null and _ui.has_method("set_active_step"):
		_ui.call("set_active_step", -1)

## 某环是否"靠近才提示"；返回场景目标表里的键，空串表示进环就提示
func _hint_target_key(step: int) -> String:
	if step < 0 or step >= HINT_TARGET_KEYS.size():
		return ""
	return str(HINT_TARGET_KEYS[step])

## 每帧按距离决定提示显隐：进了范围才弹，走出范围就收；
## 没做成之前一直有效 —— 挥空、捡错位置都不会让提示提前消失。
func _update_proximity_hint() -> void:
	var key := _hint_target_key(_step)
	if key == "":
		return
	# JUMP：按下空格后这次提示已经"消费"掉了，人还在附近也不再弹
	if _step == Step.JUMP and _jump_hint_consumed:
		return
	var arena := get_parent()
	var targets := {}
	if arena != null and arena.has_method("tutorial_hint_targets"):
		targets = arena.call("tutorial_hint_targets")
	# 场景没给目标点（组件单独挂测试）：退回"进环即提示"，别把提示弄丢
	if not targets.has(key):
		if not _hint_shown:
			_hint_shown = true
			_push_step_text(_step)
		return
	var player := _get_player() as Node2D
	if player == null or not is_instance_valid(player):
		return
	var target: Vector2 = targets[key]
	var near := player.global_position.distance_to(target) <= HINT_RADIUS
	if near == _hint_shown:
		return
	_hint_shown = near
	if near:
		_push_step_text(_step)
	else:
		_hide_step_text()

## 临时提示（获得铁剑 / 教程完成）：固定在屏幕提示条上方，显示时长由本组件计时
func _show_bubble(text: String) -> void:
	if _ui == null:
		return
	# 旧契约还要一个世界坐标；新版 HUD 固定在屏幕上，这个位置已经不影响排版
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
