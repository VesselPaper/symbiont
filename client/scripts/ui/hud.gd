extends CanvasLayer
## 战斗 HUD：生命（红心）+ 能量（青白格），由 GameEvents 驱动
## 对应 GDD 战斗系统数值（HP 上限 6 格 / 能量 3 格）

const MAX_HEARTS := 6
const MAX_PIPS := 3

var _hearts: Array[ColorRect] = []
var _pips: Array[ColorRect] = []


func _ready() -> void:
	_build()
	GameEvents.player_hp_changed.connect(_on_hp)
	GameEvents.player_energy_changed.connect(_on_energy)
	GameEvents.player_hp_changed.emit(4, 4)
	GameEvents.player_energy_changed.emit(0.0, MAX_PIPS)


func _build() -> void:
	# 生命红心（左上）
	for i in MAX_HEARTS:
		var h := ColorRect.new()
		h.position = Vector2(12 + i * 18, 12)
		h.size = Vector2(14, 14)
		h.color = Color(0.35, 0.20, 0.20, 0.5)
		add_child(h)
		_hearts.append(h)
	# 能量格（红心下方）
	for i in MAX_PIPS:
		var p := ColorRect.new()
		p.position = Vector2(12 + i * 14, 30)
		p.size = Vector2(10, 6)
		p.color = Color(0.3, 0.35, 0.4, 0.5)
		add_child(p)
		_pips.append(p)


func _on_hp(hp: int, max_hp: int) -> void:
	for i in MAX_HEARTS:
		_hearts[i].visible = i < max_hp
		_hearts[i].color = Color(0.92, 0.30, 0.28) if i < hp else Color(0.35, 0.20, 0.20, 0.5)


func _on_energy(energy: float, max_energy: int) -> void:
	for i in _pips.size():
		_pips[i].color = Color(0.6, 0.95, 0.9) if energy >= float(i + 1) else Color(0.3, 0.35, 0.4, 0.5)
