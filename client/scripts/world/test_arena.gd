extends Node2D
## 测试竞技场（M1-01）
##
## 平地 + 左右边界墙 + 两个高度递进的小平台；玩家出生在左侧、木桩在右侧，
## 用于验证移动 / 跳跃 / 攻击的完整可玩闭环。真正的楼层场景在 M2 制作。

func _ready() -> void:
	# 相机挂到玩家身上跟随；limit 是场景绝对坐标，不随父节点变化
	var camera := $Camera2D as Camera2D
	camera.reparent($Player)
	camera.position = Vector2.ZERO
	camera.make_current()
