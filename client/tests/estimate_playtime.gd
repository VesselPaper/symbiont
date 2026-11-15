extends SceneTree
## 通关时长估算：按"一直往前走 + 跳过所有剧情 + 已经知道解谜答案"的最短路线算。
##
## 口径（组长给的）：
##   1) 角色一直往前走的纯移动时间
##   2) 必经的跳跃/攀爬滞空时间（不是可选探索）
##   3) 玩家已经知道解谜办法后仍需要的走动时间
## 剧情文字不计（全部按跳过算）。
##
## 跑法：Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tests/estimate_playtime.gd

const SCENES := [
	["教学关", "res://scenes/world/test_arena.tscn"],
	["第一层", "res://scenes/world/floor1.tscn"],
	["第二层", "res://scenes/world/floor2.tscn"],
	["第三层", "res://scenes/world/floor3.tscn"],
]

# 与 player.gd 保持一致；改了那边要同步这里
const RUN_SPEED := 300.0
const JUMP_VELOCITY := -727.0
const GRAVITY := 2550.0

func _initialize() -> void:
	print("[estimate] 最短通关估算（跳过全部剧情、已知解谜答案）")
	print("[estimate] 跑速 %.0f px/s，单跳滞空 %.2fs" % [RUN_SPEED, _air_time()])
	var total := 0.0
	for entry in SCENES:
		var name: String = entry[0]
		var scene = load(entry[1])
		if scene == null:
			print("[estimate] %s 场景加载失败" % name)
			continue
		var stage := _stage_of(scene)
		if stage.is_empty():
			print("[estimate] %s 没有 STAGE 表，跳过" % name)
			continue
		var width: float = float(stage.get("world_width", 0.0))
		var walk := width / RUN_SPEED
		# 必经跳跃：光点/台阶这些位置每 400px 左右至少一次，按跳跃滞空算
		var hops := maxi(1, int(width / 400.0))
		var air := hops * _air_time() * 0.5   # 跳跃时仍在前进，取一半算额外耗时
		var sec := walk + air
		total += sec
		print("[estimate] %-6s 宽 %5.0fpx  走 %.0fs + 跳跃 %d 次 %.0fs = %4.0fs（%.1f 分）"
				% [name, width, walk, hops, air, sec, sec / 60.0])
	print("[estimate] 合计 %.0f 秒（%.1f 分钟）" % [total, total / 60.0])
	quit(0)

## 场景脚本里的 STAGE 常量
func _stage_of(scene: PackedScene) -> Dictionary:
	var inst := scene.instantiate()
	var scr = inst.get_script()
	var map: Dictionary = scr.get_script_constant_map() if scr != null else {}
	var stage: Dictionary = map.get("STAGE", {})
	inst.free()
	return stage

## 一次满跳的滞空时间：上去 + 下来
func _air_time() -> float:
	return 2.0 * absf(JUMP_VELOCITY) / GRAVITY
