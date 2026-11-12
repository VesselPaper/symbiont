extends RefCounted
## 对话组件定位与状态查询（M4-13）
##
## 为什么单独抽出来：AudioStreamPlayer 也有 play()/is_playing()。
## 之前钟绳、守钟人、调查点、阵营 NPC 各自全局扫“有 play 的节点”，
## 在真实窗口里会先抓到 GameManager/AudioDirector/Bgm，把 BGM 当成旁白；
## 无头测试音频不播放，所以一直测不出来。
##
## 统一规则：
##   1. 先认显式路径
##   2. 再认控制器场景里的 Dialogue
##   3. 再认场景根节点的 Dialogue / dialogue 分组
##   4. 最后才全局扫描，但必须同时有 is_line_done（dialogue.gd 独有接口）
## 因此 AudioStreamPlayer、音效节点永远不会被当成对话。

const DIALOGUE_GROUP := "dialogue"
const DIALOGUE_NODE_NAME := "Dialogue"

static func resolve(owner: Node, controller: Node = null, explicit_path: NodePath = NodePath("")) -> Node:
	if owner == null:
		return null
	if explicit_path != NodePath(""):
		var explicit := owner.get_node_or_null(explicit_path)
		if is_dialogue(explicit):
			return explicit
	if controller != null:
		var controlled := controller.get_node_or_null(DIALOGUE_NODE_NAME)
		if is_dialogue(controlled):
			return controlled
	var scene_root := owner.owner
	if scene_root == null and owner.is_inside_tree():
		scene_root = owner.get_tree().current_scene
	if scene_root != null:
		var scene_dialogue := scene_root.get_node_or_null(DIALOGUE_NODE_NAME)
		if is_dialogue(scene_dialogue):
			return scene_dialogue
	if not owner.is_inside_tree():
		return null
	for node in owner.get_tree().get_nodes_in_group(DIALOGUE_GROUP):
		if is_dialogue(node):
			return node
	for node in owner.get_tree().get_root().find_children("*", "Node", true, false):
		if is_dialogue(node):
			return node
	return null

static func is_dialogue(node) -> bool:
	return node != null \
		and is_instance_valid(node) \
		and node.has_method("play") \
		and node.has_method("is_playing") \
		and node.has_method("is_line_done")

static func is_playing(node) -> bool:
	if not is_dialogue(node):
		return false
	return bool(node.call("is_playing"))

static func is_active(node) -> bool:
	if not is_dialogue(node):
		return false
	var raw = node.get("_active")
	if raw is bool:
		return bool(raw)
	return bool(node.call("is_playing"))

static func is_line_done(node) -> bool:
	if not is_dialogue(node):
		return false
	if node.has_method("is_line_done"):
		return bool(node.call("is_line_done"))
	var raw = node.get("_line_done")
	return bool(raw) if raw is bool else false
