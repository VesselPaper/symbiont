extends Node
## 数据访问层（DataDB，autoload 单例）
##
## 运行时只读数据统一入口。数据源：client/data/*.json，
## 由 tools/db_export.py 从 database/game_data（SQLite）生成。
## 禁止手改 client/data 下的 JSON —— 一律改 database 再导出。

const DATA_DIR := "res://data"
const TABLES := ["items", "enemies", "npc", "dialogues", "endings", "sacrifices"]

var _cache: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all() -> void:
	for table in TABLES:
		_load_table(table)

func _load_table(table: String) -> void:
	var path := "%s/%s" % [DATA_DIR, table]
	if not DirAccess.dir_exists_absolute(path):
		push_warning("DataDB: 缺少数据目录 %s（先运行 tools/db_export.py）" % path)
		_cache[table] = {}
		return
	_cache[table] = {}
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json") or file_name.ends_with("_index.json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [path, file_name]))
		if parsed == null:
			push_error("DataDB: JSON 解析失败 %s/%s" % [path, file_name])
			continue
		_cache[table][file_name.trim_suffix(".json")] = parsed

## 例：DataDB.get_item("iron_sword")
func get_item(item_id: String) -> Dictionary:
	return _cache.get("items", {}).get(item_id, {})

func get_enemy(enemy_id: String) -> Dictionary:
	return _cache.get("enemies", {}).get(enemy_id, {})

func get_npc(npc_id: String) -> Dictionary:
	return _cache.get("npc", {}).get(npc_id, {})

func get_dialogue(dialogue_id: String) -> Dictionary:
	return _cache.get("dialogues", {}).get(dialogue_id, {})

func get_ending(ending_id: String) -> Dictionary:
	return _cache.get("endings", {}).get(ending_id, {})

func get_sacrifice(sacrifice_id: String) -> Dictionary:
	return _cache.get("sacrifices", {}).get(sacrifice_id, {})

## 整表原始访问（返回 id -> 行数据）
func table(table_name: String) -> Dictionary:
	return _cache.get(table_name, {})
