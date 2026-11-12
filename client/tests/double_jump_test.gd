extends SceneTree
## 蒸汽靴宝箱 + 二段跳回归（M4-06）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/double_jump_test.gd
##
## 验收：宝箱在祭坛右侧、不重叠；靠近按 K 才开；只开一次；开箱后 GameManager/Player 都有靴子；
## 二段跳只在有靴子且本次离地未用过时生效；存档字段可往返。
## 反向：K 抬起/长按 echo/其它键不触发；没靴子/已用完第二段不触发。

const SCENE := "res://scenes/world/test_arena.tscn"

var _frames := 0
var _failed := false
var _level: Node
var _player: Node
var _chest: Node
var _gm: Node
var _opened_once := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_gm = root.get_node("/root/GameManager")
		_gm.set("has_steam_boots", false)
		_gm.set("flags", {})
		_level = load(SCENE).instantiate()
		root.add_child(_level)
		_player = _level.get_node("Player")
		_chest = _level.get_node_or_null("SteamBootsChest")
		return false
	if _frames < 25:
		return false
	_run_checks()
	print("[boots] %s" % ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[boots] " + msg)
		_failed = true

func _make_key(code: int, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func _run_checks() -> void:
	_check(_chest != null, "教学关没有 SteamBootsChest")
	if _chest == null:
		return
	# 位置必须在祭坛右侧、和祭坛保持距离，不能挡住祭坛 K 判定
	var altar := _level.get_node_or_null("Altar")
	_check(altar != null, "缺少祭坛")
	if altar != null:
		_check(float(_chest.global_position.x) > float(altar.global_position.x) + 250.0,
			"宝箱离祭坛太近，可能挡 K")

	# 没靴子时第二段跳必须无效
	_player.set("_air_jumps_left", 1)
	_check(not bool(_player.call("try_air_jump")), "没蒸汽靴也能二段跳")

	# 反向输入：靠近但只按抬起/echo/其它键不开
	_chest.call("_on_body_entered", _player)
	_check(bool(_chest.get_node("Prompt").visible), "靠近后没有 K 提示")
	_chest.call("_unhandled_input", _make_key(KEY_K, false))
	_chest.call("_unhandled_input", _make_key(KEY_K, true, true))
	_chest.call("_unhandled_input", _make_key(KEY_J))
	_check(not bool(_gm.get("has_steam_boots")), "反向输入不应开箱")
	_check(not bool(_chest.get("_opened")), "反向输入不应标记已开箱")

	# 正向：K 开箱，GameManager 和 Player 同时获得靴子
	_chest.call("_unhandled_input", _make_key(KEY_K))
	_opened_once = bool(_chest.get("_opened"))
	_check(_opened_once, "按 K 没有开箱")
	_check(bool(_gm.get("has_steam_boots")), "开箱后 GameManager.has_steam_boots 仍为 false")
	_check(bool(_player.get("has_steam_boots")), "开箱后 Player.has_steam_boots 仍为 false")
	_check(not bool(_chest.get_node("Prompt").visible), "开箱后 K 提示仍然显示")
	# M4-20：靴子只给能力，不改角色外观——开箱后身上不许冒出靴子/护甲之类的新东西
	var body := _player.get_node("Body")
	_check(body.get_node_or_null("SteamBootsVisual") == null, "开箱后角色身上多了蒸汽靴外观（组长要求不改外貌）")
	# 换阵营也不能因此长出宝箱靴子；这里只允许工程师阵营自己那套装束
	_player.call("apply_faction", "heretic")
	_check(body.get_node_or_null("SteamBootsVisual") == null, "选祭司后身上冒出了蒸汽靴外观")
	_check(body.get_node_or_null("FactionVisual") != null, "选祭司后阵营外观没生成")

	# 二段跳：有靴子时第一段空中跳成功，第二段必须失败
	_player.set("_air_jumps_left", 1)
	_check(bool(_player.call("try_air_jump")), "有靴子但二段跳失败")
	_check(is_equal_approx(float(_player.velocity.y), -640.0), "二段跳初速不是 -640")
	_check(not bool(_player.call("try_air_jump")), "一次离地只能用一次二段跳")

	# 再次按 K 不能重复开箱/重复发物品
	_chest.call("_unhandled_input", _make_key(KEY_K))
	_check(bool(_chest.get("_opened")), "开箱状态被重置")

	# 存档字段往返；并验证 SaveSystem 落盘时能把靴子同步回 Player
	_gm.call("from_dict", {"has_steam_boots": true, "flags": {}})
	_check(bool((_gm.call("to_dict") as Dictionary).get("has_steam_boots", false)),
		"has_steam_boots 没进存档字典")
	_gm.set("has_steam_boots", false)
	_player.set("has_steam_boots", false)
	var save := root.get_node("/root/SaveSystem")
	save.set("pending_player", {"has_steam_boots": true})
	save.call("apply_pending_player", _player)
	_check(bool(_player.get("has_steam_boots")), "读档后 Player 没恢复蒸汽靴")
	_check(bool(_gm.get("has_steam_boots")), "读档后 GameManager 没同步蒸汽靴")
	# 读档把靴子补回来也不许长外观：存档里只有能力，没有外观
	_check(body.get_node_or_null("SteamBootsVisual") == null, "读档恢复靴子后身上冒出了蒸汽靴外观")
	# 还原，别污染后续测试
	_gm.set("has_steam_boots", false)
	_gm.set("flags", {})
	save.set("pending_player", {})
