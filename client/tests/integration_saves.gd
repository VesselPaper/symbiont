extends SceneTree
## 端到端联调：远程存档走一遍完整往返。
##
## 流程：本地存档 → 推云端 → 删掉本地（模拟换机器）→ 从云端拉回 → 比对内容。
## 需要真栈在跑，所以不带 _test 后缀，不进无头回归。
##
## 跑法：scripts/integration_saves.ps1

const SLOT := 2
const PUSH_WAIT := 2.0
const PULL_WAIT := 10.0

var _save: Node
var _phase := 0
var _t := 0.0
var _saved_at := ""


func _process(delta: float) -> bool:
	_t += delta

	if _phase == 0:
		_save = root.get_node_or_null("/root/SaveSystem")
		if _save == null:
			print("[saves] FAIL 找不到 SaveSystem")
			quit(1)
			return true

		_save.save(SLOT)
		var path: String = _save.call("_save_path", SLOT)
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		_saved_at = str(parsed.get("saved_at", "")) if parsed != null else ""
		print("[saves] 本地已写入 slot=%d saved_at=%s" % [SLOT, _saved_at])
		_phase = 1
		_t = 0.0
		return false

	if _phase == 1:
		if _t < PUSH_WAIT:
			return false
		_save.delete_slot(SLOT)
		print("[saves] 删掉本地存档（模拟换机器），exists=%s" % str(_save.has_save(SLOT)))
		_save.pull_remote(SLOT, false)
		_phase = 2
		_t = 0.0
		return false

	if _phase == 2:
		if _save.has_save(SLOT):
			var restored = JSON.parse_string(FileAccess.get_file_as_string(_save.call("_save_path", SLOT)))
			var at := str(restored.get("saved_at", "")) if restored != null else ""
			if at == _saved_at and _saved_at != "":
				print("[saves] PASS 已从云端恢复，saved_at=%s" % at)
				# 联调不能在本地留垃圾：槽位会抢占主菜单的"最新存档"
				_save.delete_slot(SLOT)
				quit(0)
			else:
				print("[saves] FAIL 内容不一致：本地 %s / 云端 %s" % [_saved_at, at])
				quit(1)
			return true
		if _t > PULL_WAIT:
			print("[saves] FAIL 等待云端存档超时")
			quit(1)
			return true
		return false

	return true
