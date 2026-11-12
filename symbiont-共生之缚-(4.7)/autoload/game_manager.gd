extends Node
## 全局游戏状态机（GameManager，autoload 单例）
##
## 负责：全局状态流转（BOOT → MAIN_MENU → PLAYING → ENDING）、
## 献祭计数、当前楼层、阵营路线（faction）等元进度。
## 详细状态机与结局结算见 docs/design/GDD.md。

enum GameState { BOOT, MAIN_MENU, PLAYING, PAUSED, ENDING, GAME_OVER }

var state: GameState = GameState.BOOT
var sacrifice_count: int = 0          # 献祭次数（结局结算依据，见 GDD）
var monster_limb_count: int = 0       # 怪物肢体持有数（拾取记账、献祭消耗，见 M1-04）
var current_floor: String = "floor_1"
var faction: String = ""              # "" / "heretic" / "engineer"（第二层抉择）
var flags: Dictionary = {}            # 通用剧情旗标（flag_<名称> = true）

func _ready() -> void:
	state = GameState.MAIN_MENU
	# M1-04：肢体拾取物广播 item_picked 时统一记账；只认 monster_limb，避免误加其它物品
	EventBus.item_picked.connect(_on_item_picked)

## 拾取事件记账：只有怪物肢体才累加计数（其它物品由各自系统处理）
func _on_item_picked(item_id: String, count: int) -> void:
	if item_id == "monster_limb":
		add_monster_limb(count)

## 增加肢体持有数（n 为拾取数量，通常为 1）
func add_monster_limb(n: int) -> void:
	monster_limb_count += n

## 尝试消耗一个肢体（祭坛献祭用）：有肢体才 -1 并返回 true，没有返回 false
func try_consume_monster_limb() -> bool:
	if monster_limb_count <= 0:
		return false
	monster_limb_count -= 1
	return true

func start_new_game() -> void:
	sacrifice_count = 0
	monster_limb_count = 0
	current_floor = "floor_1"
	faction = ""
	flags.clear()
	_change_state(GameState.PLAYING)

func record_sacrifice(sacrifice_id: String = "generic") -> void:
	sacrifice_count += 1
	EventBus.sacrifice_done.emit(sacrifice_id, sacrifice_count)
	EventBus.log_event("sacrifice", {"id": sacrifice_id, "total": sacrifice_count})

func set_flag(flag_name: String) -> void:
	flags[flag_name] = true
	EventBus.log_event("flag_set", {"flag": flag_name})

func has_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false)

func _change_state(next: GameState) -> void:
	if state == next:
		return
	state = next
	EventBus.log_event("game_state", {"state": GameState.keys()[state]})

# ---- 序列化（SaveSystem 调用） ----
func to_dict() -> Dictionary:
	return {
		"sacrifice_count": sacrifice_count,
		"monster_limb_count": monster_limb_count,
		"current_floor": current_floor,
		"faction": faction,
		"flags": flags,
	}

func from_dict(data: Dictionary) -> void:
	sacrifice_count = int(data.get("sacrifice_count", 0))
	monster_limb_count = int(data.get("monster_limb_count", 0))
	current_floor = str(data.get("current_floor", "floor_1"))
	faction = str(data.get("faction", ""))
	flags = data.get("flags", {})
