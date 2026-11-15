extends Node
## 网络层（Network，autoload 单例）
##
## 离线优先：所有上报先进内存队列，可联网时批量 POST。
## 服务器不可用 / 无网络时游戏完全可玩（演示兜底）。
## REST API 定义见 docs/02-系统接口设计文档.md。
##
## 地址与证书：
##   默认打到 Web 入口网关 https://localhost/api/v1（走 TLS、限流与转发）。
##   本地开发想让游戏直连 uvicorn，把环境变量设成
##     SYMBIONT_API_BASE=http://127.0.0.1:8000/api/v1   （scripts/run_server.ps1）
##   网关用本地 CA 签的证书，客户端需要知道去哪找根证书：
##     SYMBIONT_CA_FILE=<repo>/deploy/certs/ca.crt
##   临时排障可以设 SYMBIONT_TLS_INSECURE=1 跳过校验（只用于本机调试）。

const DEFAULT_BASE_URL := "https://localhost/api/v1"
const BATCH_SIZE := 20
const FLUSH_INTERVAL := 30.0

var base_url: String = DEFAULT_BASE_URL
var auth_token: String = ""
## 无头回归与离线演示用：置 1 时所有 HTTP 都不发出去
var offline: bool = OS.get_environment("SYMBIONT_NETWORK_OFF") == "1"
var _pending_events: Array = []
var _save_cache: Dictionary = {}
var _timer := 0.0


func _ready() -> void:
	var configured := OS.get_environment("SYMBIONT_API_BASE")
	if configured != "":
		base_url = configured


func _process(delta: float) -> void:
	# 攒不满 20 条也要定期发一次，否则玩得慢的会话会一直积压
	if _pending_events.is_empty():
		_timer = 0.0
		return
	_timer += delta
	if _timer >= FLUSH_INTERVAL:
		_timer = 0.0
		flush_events()


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
	if offline:
		return
	if _pending_events.is_empty():
		return
	var batch := _pending_events.duplicate()
	_pending_events.clear()
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_flush_completed.bind(http, batch))
	# 4.x 的 request() 只有四个参数，TLS 选项要用 set_tls_options 单独设
	_apply_tls(http)
	http.request("%s/events" % base_url, _headers(), HTTPClient.METHOD_POST, JSON.stringify({"events": batch}))


func _on_flush_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, batch: Array) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# 网络不可用或服务端拒收：放回队列尾部（去重策略后续优化）
		_pending_events.append_array(batch)


## 远程存档同步。本地永远优先，远端只是备份与换机恢复。
##
## 单机游戏没有登录，存档按设备归属：首次运行时生成一个设备 id 存在 user://，
## 之后每次请求带 X-Device-Id，服务端据此隔离各台机器的存档。
signal save_pulled(slot: int, data: Dictionary)
signal save_pull_failed(slot: int, reason: String)
signal save_pushed(slot: int)

const DEVICE_FILE := "user://device.id"

var device_id: String = ""


func _ensure_device_id() -> String:
	if device_id != "":
		return device_id
	if FileAccess.file_exists(DEVICE_FILE):
		device_id = FileAccess.get_file_as_string(DEVICE_FILE).strip_edges()
	if device_id.length() < 8:
		var rng := Crypto.new()
		device_id = rng.generate_random_bytes(16).hex_encode()
		var f := FileAccess.open(DEVICE_FILE, FileAccess.WRITE)
		if f != null:
			f.store_string(device_id)
	return device_id


func push_save(slot: int, data: Dictionary) -> void:
	_save_cache[slot] = data
	if offline:
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_push_completed.bind(http, slot))
	_apply_tls(http)
	http.request(
		"%s/saves/%d" % [base_url, slot],
		_headers(),
		HTTPClient.METHOD_PUT,
		JSON.stringify({"save_data": data, "version": data.get("version", 1)})
	)


func _on_push_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, slot: int) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("[Network] 云端存档写入失败 slot=%d code=%d" % [slot, code])
		return
	save_pushed.emit(slot)


func pull_save(slot: int) -> void:
	if offline:
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_pull_completed.bind(http, slot))
	_apply_tls(http)
	http.request("%s/saves/%d" % [base_url, slot], _headers(), HTTPClient.METHOD_GET, "")


func _on_pull_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, slot: int) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		save_pull_failed.emit(slot, "network")
		return
	if code == 404:
		save_pull_failed.emit(slot, "not_found")
		return
	if code != 200:
		save_pull_failed.emit(slot, "http_%d" % code)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("save_data"):
		save_pull_failed.emit(slot, "bad_body")
		return
	save_pulled.emit(slot, parsed["save_data"])


func _apply_tls(http: HTTPRequest) -> void:
	var tls := _tls_options()
	if tls != null:
		http.set_tls_options(tls)


func _headers() -> PackedStringArray:
	var h := PackedStringArray([
		"Content-Type: application/json",
		"X-Device-Id: %s" % _ensure_device_id(),
	])
	if auth_token != "":
		h.append("Authorization: Bearer %s" % auth_token)
	return h


## 只有 https 才需要额外配置；脚本里传 null 给 HTTPRequest 表示用默认行为。
func _tls_options() -> TLSOptions:
	if not base_url.begins_with("https"):
		return null

	if OS.get_environment("SYMBIONT_TLS_INSECURE") == "1":
		push_warning("[Network] 跳过证书校验（只用于本机调试）")
		return TLSOptions.client_unsafe()

	var ca_path := OS.get_environment("SYMBIONT_CA_FILE")
	if ca_path != "":
		var cert := X509Certificate.new()
		if cert.load(ca_path) == OK:
			return TLSOptions.client(cert)
		push_warning("[Network] 读不到根证书：%s，回退到系统信任链" % ca_path)

	# 没显式给 CA 就走系统信任链：装了根证书的机器（trust_ca.ps1）可以直接过
	return TLSOptions.client()
