extends Node
## 网络层（Network，autoload 单例）
##
## 离线优先：所有上报先进内存队列，可联网时批量 POST。
## 服务器不可用 / 无网络时游戏完全可玩（演示兜底）。
## REST API 定义见 docs/02-系统接口设计文档.md。

const DEFAULT_BASE_URL := "http://127.0.0.1:8000/api/v1"
const BATCH_SIZE := 20

var base_url: String = DEFAULT_BASE_URL
var auth_token: String = ""
var _pending_events: Array = []
var _save_cache: Dictionary = {}

func configure(base: String, token: String = "") -> void:
	base_url = base
	auth_token = token

## 上报游戏事件（统计埋点）。失败自动留在队列，下次联网补发。
func report_event(event_name: String, data: Dictionary = {}) -> void:
	_pending_events.append({
		"event": event_name,
		"data": data,
		"ts": Time.get_unix_time_from_system(),
	})
	if _pending_events.size() >= BATCH_SIZE:
		flush_events()

func flush_events() -> void:
	if _pending_events.is_empty():
		return
	var batch := _pending_events.duplicate()
	_pending_events.clear()
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_flush_completed.bind(http, batch))
	http.request("%s/events" % base_url, _headers(), HTTPClient.METHOD_POST, JSON.stringify({"events": batch}))

func _on_flush_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, batch: Array) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# 网络不可用：放回队列尾部（去重策略后续优化）
		_pending_events.append_array(batch)

## 远程存档同步（M2 实现）。离线时本地优先。
func push_save(slot: int, data: Dictionary) -> void:
	_save_cache[slot] = data
	# TODO(M2): POST /api/v1/saves/{slot}，带 token；失败留在队列

func pull_save(slot: int) -> void:
	# TODO(M2): GET /api/v1/saves/{slot} → 回填 SaveSystem
	pass

func _headers() -> PackedStringArray:
	var h := PackedStringArray(["Content-Type: application/json"])
	if auth_token != "":
		h.append("Authorization: Bearer %s" % auth_token)
	return h
