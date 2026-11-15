extends SceneTree
## 端到端联调：让游戏进程真的经网关把事件写进数据库。
##
## 与回归测试的区别：这里需要真实的后端与网关在跑，所以文件名不带 _test，
## 不会被 test_all.ps1 收进无头回归（否则没起 docker 的机器会误报失败）。
##
## 跑法：scripts/integration_events.ps1
##      它会先起栈，再带着 SYMBIONT_API_BASE / SYMBIONT_CA_FILE 调用本脚本。

const WAIT_LIMIT := 8.0
const SETTLE := 2.0

var _net: Node
var _elapsed := 0.0
var _sent := false


func _process(delta: float) -> bool:
	if not _sent:
		_net = root.get_node_or_null("/root/Network")
		if _net == null:
			print("[integration] FAIL 找不到 Network autoload")
			quit(1)
			return true

		print("[integration] base_url=%s" % str(_net.get("base_url")))
		_net.report_event("integration_probe", {"source": "godot-headless", "n": 1})
		_net.report_event("integration_probe", {"source": "godot-headless", "n": 2})
		_net.flush_events()
		_sent = true
		return false

	_elapsed += delta
	if _elapsed < SETTLE:
		return false

	var pending: Array = _net.get("_pending_events")
	if pending.is_empty():
		print("[integration] PASS 两条事件已提交")
		quit(0)
		return true

	if _elapsed >= WAIT_LIMIT:
		print("[integration] FAIL 上报失败，队列里还压着 %d 条" % pending.size())
		quit(1)
		return true

	return false
