extends Node2D
## 测试竞技场（M1-01 / M1-12 布局重排）
##
## 教学关：平地 + 左右边界墙，从左到右是
##   出生 → 走一段（MOVE）→ 跳台（顶 571：JUMP、拿剑、打木桩、木桩乙在下劈台前）
##   → 下劈方台（顶 440，POGO 要站上去）→ 浅坑（两级石阶 + 战斗）
##   → 祭坛台（顶 572，献祭）→ 长廊台阶（可选）→ 下一层的门
## 布局数字全部在 STAGE 表里（M4-19 拉开距离 / M4-21 去掉引导光点），改布局只改表。
## M1-03：挂载对话 UI（DialogueBox，CanvasLayer 子节点保证 UI 在顶层）和对话
## 组件（Dialogue），场景稳定后自动弹出开场寄生体低语（intro_parasite_1 链）。

## 开场对话延迟（秒）：等场景 / 玩家 / 相机稳定后再弹出
const INTRO_DIALOGUE_DELAY := 0.5
## 开场对话 id（台词内容一律从 DataDB 读，这里只指定入口 id）
const INTRO_DIALOGUE_ID := "intro_parasite_1"

## 教程结束后开放的下一层门（同一地图右侧，地图边界墙前面）
const FLOOR1_SCENE := "res://scenes/world/floor1.tscn"

## 教学关站位表（M4-19）。
##
## 组长反馈：教学关和钟厅一样“每个项目都挤在一起”。这一版把各环之间的横向距离
## 统一拉到 340~510px（一屏约 747px），地图从 4000 加到 5000：
##
##   出生 80 → 移动光点 560 → 跳台 820..2400（拿剑 1310、木桩甲 1650、下劈台 2075..2235）
##   → 浅坑 2460..2800（史莱姆 2660，只有一只）→ 祭坛台 2860..3400（祭坛 3130）
##   → 长廊台阶 4060..4770 → 层门 4900 → 右墙 5000
##
## 场景文件 test_arena.tscn 里的坐标只是给编辑器看的初值，运行时全部按这张表摆。
## 改布局只改表（外加 world_width 那一项会同步地面/右墙/镜头/背景），别再去 .tscn 挪节点。
##
## M4-21 起表里的 *_mark 只当「这一环的提示写在哪」的锚点（原先是光点站位，光点已删）。
const PLAYER_HALF_HEIGHT := 13.0   # 玩家碰撞盒 14×26，中心到脚底 13
## 组长反馈"地图太紧凑"：整张教学关横向统一放大 1.25 倍（x 与宽度一起缩放，
## 拓扑不变、间距与跑动距离同步变长，约多出 1.2 km 的横向路程）。
const SPREAD := 1.25
const STAGE := {
	"world_width": 22300.0,
	"spawn": Vector2(140, 647),
	# 移动环：走到 1500 才算学会走路，字写在 1420
	"move_mark": Vector2(1500, 585),
	"move_hint": Vector2(1420, 585),
	"move_gate": Vector2(1660, 559),
	# 跳台：顶 571，从 3800 铺到 8400 —— 拿剑、打桩、下劈都在这一条长台上
	"ledge": Rect2(3800, 571, 8000, 90),
	"jump_mark": Vector2(4000, 500),
	"jump_gate": Vector2(4200, 471),
	"corpse": Vector2(6300, 567),
	"sword": Vector2(6500, 568),
	"weapon_mark": Vector2(6500, 500),
	"dummy_a": Vector2(9200, 558),
	"attack_mark": Vector2(9200, 480),
	"attack_gate": Vector2(9440, 471),
	# 下劈：小方台（顶 440），悬在台前的木桩乙是踏板
	"pogo": Rect2(11400, 440, 200, 131),
	"dummy_b": Vector2(11380, 496),   # 悬在方台前的踏板（落到地面就够不着台顶）
	"pogo_mark": Vector2(11500, 372),
	"pogo_gate": Vector2(11840, 449),
	# 战斗场景：史莱姆一直在这儿等着，走到能看见它的时候触发剧情
	# M5-37（组长："别每次都刷两只史莱姆"）：这里留空 —— 火焰剧情那只 CaveBeast 就是这一战的怪
	"slimes": [],
	"combat_mark": Vector2(14000, 590),
	"combat_gate": Vector2(14340, 309),
	# 浅坑两侧的台阶已撤（M5-30），这个键留着是因为 _build_hollow_steps 还在读
	"pit_steps": [],
	# 火堆：打完史莱姆再走 10 秒
	# 悬崖：左岸到 19000，右岸从 20400 起
	# 过河石台（M5-39）：各块之间留 90px，跳跃水平行程约 130px，够得着
	"gallery": [
		Rect2(19083, 607, 150, 26), Rect2(19316, 552, 150, 26),
		Rect2(19549, 505, 150, 26), Rect2(19782, 565, 150, 26),
		Rect2(20015, 530, 150, 26), Rect2(20248, 575, 150, 26),
	],
	"chasm_left": 19000.0,
	"chasm_right": 20400.0,
	# 右岸台地：过河之后的落脚台（顶 572），台后面就是祭坛和门
	"altar_hall": Rect2(20400, 572, 675, 90),
	"altar": Vector2(21500, 659),
	"pickup_mark": Vector2(14800, 646),
	"sacrifice_mark": Vector2(21500, 659),
	"door": Vector2(22150, 659),
}

## 物理门：每环一个，只有做完前面那一环才开。高度按玩家跳跃高度留死角：
## move/jump/attack 200，pogo 420，combat 700。位置由 STAGE 决定，这里只管高度。
const TUTORIAL_GATE_HEIGHTS := {
	"move": 200.0, "jump": 200.0, "attack": 200.0, "pogo": 420.0, "combat": 700.0,
}
## 演示快捷键：跳过教程直接进第一层（老师/组长试玩来不及打完整套教学时用）
const DEBUG_SKIP_KEY := KEY_F2

## 史莱姆场景：对话/教程前期场景无敌人（避免教学时被攻击的矛盾），
## 教程进入"战斗"步骤时由 spawn_enemies() 生成（M1-08 修正），位置见 STAGE["slimes"]。
const SLIME_SCENE := preload("res://scenes/entities/slime.tscn")
const CAMPFIRE_SCENE := preload("res://scenes/world/campfire.tscn")
const TALL_GRASS_SCRIPT := preload("res://components/tall_grass.gd")
const TUTORIAL_GATE_SCENE := preload("res://scenes/world/tutorial_gate.tscn")
const ORIGIN_RELIC_SCENE := preload("res://scenes/items/origin_relic.tscn")
const ENDING_SCENE := preload("res://scenes/ui/ending_screen.tscn")
const GAME_HUD_SCENE := preload("res://scenes/ui/game_hud.tscn")
const TRUE_HE_RETURN_DIALOGUE := "true_he_return"
const TRUE_HE_RELIC_POS := Vector2(430, 628)

# ---- 摄像机（M1-09）----
## 垂直视野 = 角色身高的 N 倍（改这里即可调远近）；角色视觉身高 28px（见 player.gd CHARACTER_HEIGHT）
## M4-62：N 从 15 收到 10（人物放大 1.5 倍）；M4-63 再放到 12（"正常的时候再拉远一点"）
const VIEW_HEIGHT_IN_CHARACTERS := 12.0
const PLAYER_CHARACTER_HEIGHT := 28.0
## zoom = 视口高(720) ÷ (N×28)。N=12 → 336px 垂直视野 → zoom ≈ 2.14
const CAMERA_ZOOM := 720.0 / (VIEW_HEIGHT_IN_CHARACTERS * PLAYER_CHARACTER_HEIGHT)

@onready var _tutorial: Node = $Tutorial
@onready var _altar: Node = $Altar
@onready var _dialogue: Node = $Dialogue

var _door_root: Node2D
var _door_seam: Line2D
var _door_glow: Sprite2D
var _door_open := false
var _entering := false
## 人是否站在门口（按 K 才进门，见 _unhandled_input）
var _door_near := false
var _door_prompt: Label
var _gates: Dictionary = {}
var _combat_started := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _fade_label: Label
var _true_he_mode := false
var _true_he_shown := false
var _relic: Node
var _ending_screen: CanvasLayer
var _refusing := false
## M4-25：这一局是从序章虚空掉下来的（落地要扬尘、开场要慢慢亮）
var _drop_in := false
## M4-63 开场黑幕：整屏压黑、只在角色周围留一个亮圈（和序章虚空里一个感觉）。
## 站起来之后把亮圈撑开，周围才慢慢显形。
var _intro_blackout: ColorRect
var _intro_shader: ShaderMaterial
## 开场打在人身上的那盏灯（Sprite2D，画在角色身后）
var _intro_spot: Sprite2D
var _camera: Camera2D
var _player: Node2D

func _ready() -> void:
	GameManager.mark_floor_start("tutorial")
	_build_campfire()
	_build_beast_encounter_deferred.call_deferred()
	# 相机 zoom 由这里设置（垂直视野 = N 倍角色身高）；水平跟随/垂直死区由 camera_follow.gd 处理
	var camera := $Camera2D as Camera2D
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera = camera
	_player = $Player as Node2D

	# M4-19：先按 STAGE 表把地形和道具摆好，后面所有构建都读同一张表
	_apply_stage()
	# 下一层的门：先立着，教程完成后才亮、才能进（软隔离，和教学关一个思路）
	_build_hollow_steps()
	_build_corridor_gallery()
	_build_next_floor_door()
	_build_tall_grass()
	_build_story_beats()
	_build_foreground_occluders()
	# 门前圣所装饰（供台、烛台、断柱、瓦砾、门楣旧布）
	_build_door_shrine()
	_build_tutorial_gates()
	# M5-28：屏幕前景先撤掉。组长说前景不该一直跟着镜头，真正的视差前景要单独做，
	# 这轮先不做（原来的固定版在提交 2ee07b9 里，想要可以捡回来）。
	_build_fade_overlay()
	# 从虚空进来：开场演出（_void_arrival）自己负责把画面亮起来；其余入口立刻淡入。
	# 注意判断用 _drop_in 而不是旗标：旗标在上面 _apply_stage 里已经被消费掉了，
	# 用旗标判断会在这里又叠一层 1.65 秒的黑幕，开局就会先黑两秒（踩过）。
	if not _drop_in:
		_build_fade_in()
	# 演出要等遮罩建好才能演（_void_arrival 会去动 _fade_rect），所以挪到这里再启动
	if _drop_in:
		_void_arrival(STAGE["spawn"])
	_build_hud()
	# 教程 8 个提示气泡锚点也在这张表里，推给 Tutorial；它自己的常量只作无场景时的兜底
	if _tutorial != null and _tutorial.has_method("set_step_anchors"):
		_tutorial.call("set_step_anchors", station_anchors())
	# 真 HE 二周目：从第三层货梯回来时跳过整套教学，只留“还骨片”这一件事
	if GameManager.has_flag("true_he_return") and GameManager.has_flag("boss_defeated"):
		_setup_true_he_return()
	if _altar != null and _altar.has_signal("refuse_requested"):
		_altar.connect("refuse_requested", Callable(self, "_on_refuse_requested"))
		_altar.call("set_refuse_allowed", not _true_he_mode)
		# M5-22：教学关里祭坛上方只留教程那一行，祭坛自己的"献上肢体（K）"关掉
		_altar.call("set_hint_enabled", false)
	var loaded_player := get_node_or_null("Player") as Node2D
	if loaded_player != null:
		SaveSystem.apply_pending_player(loaded_player)
	# 道具落地校准（M5-31）：地形加了岩体轮廓和折痕后，手填的 y 会差几像素，这里统一对齐一次
	_snap_props_deferred()

	# M1-03：延时播放开场寄生体低语，让场景先稳定（玩家出生 → 低语弹出）
	# M4-62：从虚空掉进来那一局要等"落地 → 站起 → 亮起来"演完再开口，
	# 否则低语会在人还在半空/还黑着的时候蹦出来。
	# M5-01：等多久别看写死的 7.6，直接从开场的两段时长算，改节奏不用两边一起改
	var intro_delay := INTRO_DIALOGUE_DELAY + (LAND_BUFFER + REVEAL_TIME + 1.0 if _drop_in else 0.0)
	var intro_timer := get_tree().create_timer(intro_delay)
	intro_timer.timeout.connect(_play_intro_dialogue)

# ---------- 站位表落地（M4-19） ----------

## 把 STAGE 表铺到场景上：地面/边界墙/背景/镜头限幅跟着 world_width 走，
## 三块平台按 rect 摆，道具和玩家按表定坐标。场景文件里那些数字只是编辑器里看的初值，
## 运行到这里就全被覆盖，所以改布局只需要改表。
func _apply_stage() -> void:
	var stage_w: float = STAGE["world_width"]

	# 地面：M5-11（组长要求"多平台下方地面多余，可设悬崖跳平台通过"）——
	# 长廊台阶那一段下面的地面被挖掉了，整条地面拆成"左岸 + 右岸"两块，
	# 中间是一道掉下去会死的深渊，只能踩着长廊的四块石台过去。
	var chasm_left: float = STAGE["chasm_left"]
	var chasm_right: float = STAGE["chasm_right"]
	var ground := $GroundLeft as StaticBody2D
	ground.position = Vector2(chasm_left * 0.5, 689)
	(ground.get_node("CollisionShape2D") as CollisionShape2D).shape.size = Vector2(chasm_left, 60)
	(ground.get_node("Visual") as Polygon2D).polygon = _box_polygon(Vector2(chasm_left, 60))
	_build_right_bank(chasm_right, stage_w)
	_build_chasm_kill_zone(chasm_left, chasm_right)
	($WallRight as Node2D).position = Vector2(stage_w, 75)

	# 背景板、视差背景、镜头右限幅：三者必须和地面同宽，不然走到头会看见空白
	($Backdrop as Node2D).position = Vector2(stage_w * 0.5, 360)
	($Backdrop as Polygon2D).polygon = _box_polygon(Vector2(stage_w, 720))
	($BackdropArt as Node).set("world_width", stage_w)
	# 告诉美术层悬崖的范围：它靠这两项决定"哪些石头/断柱不能浮在空气里"
	($BackdropArt as Node).set("gap_from", chasm_left)
	($BackdropArt as Node).set("gap_to", chasm_right)
	($Camera2D as Camera2D).limit_right = int(stage_w)

	# 三块平台：跳台、下劈小方台、祭坛台
	_place_platform($JumpPlatform as StaticBody2D, STAGE["ledge"], Vector2(300, 90))
	_place_platform($PogoPlatform as StaticBody2D, STAGE["pogo"], Vector2(250, 90))
	_place_platform($AltarPlatform as StaticBody2D, STAGE["altar_hall"], Vector2(300, 90))

	# 道具与玩家
	# M4-25：从序章的虚空掉下来时，人不是“站在地上”。
	# M4-62（组长定的新开场）：不再是"先躺在地上、等灵魂入体再慢慢爬起来"，
	# 改成主角自己从高处砸下来 → 落地（扬尘 + 压扁）→ 直接站起。
	# 位置抬到高空，下坠交给物理和重力去跑，落地的速度/扬尘/音效才是真的。
	var spawn_pos: Vector2 = STAGE["spawn"]
	if GameManager.has_flag("enter_from_void"):
		GameManager.flags.erase("enter_from_void")
		_drop_in = true
		($Player as Node2D).position = spawn_pos + Vector2(0, -DROP_HEIGHT)
		($Player as CharacterBody2D).velocity = Vector2(0, 120.0)
		($Player as Node2D).rotation = 0.0
		($Player as Node2D).scale = Vector2.ONE
		($Player as Node2D).set("_input_locked", true)
	else:
		($Player as Node2D).position = spawn_pos
	($Corpse as Node2D).position = STAGE["corpse"]
	($WeaponPickup as Node2D).position = STAGE["sword"]
	($DummyA as Node2D).position = STAGE["dummy_a"]
	($DummyB as Node2D).position = STAGE["dummy_b"]
	($Altar as Node2D).position = STAGE["altar"]

## 虚空落地（M4-62 重做，组长定的开场）：
##   黑场里从上方砸下来（影子越来越清楚）→ 砸地：扬尘 + 震屏 + 压扁
##   → 直接站起（蹲一下、弹起过头、站定，约 0.6 秒）→ 光从角色身上扩开、画面亮起。
## 为什么不用补间做下落：交给物理和重力，落地的速度和扬尘才是真的，
## 以前那种"先躺在地上等人扶起来"的 10 秒起身也一并删了。
const DROP_HEIGHT := 200.0       # 从出生点上方多高处掉下来（约 7 个身位）
const DROP_TIMEOUT := 4.0        # 兜底：万一没落下来也别把玩家锁死
const INTRO_ZOOM_SCALE := 1.25   # 开场镜头放大一点：人从中间掉下来，看得清
## 组长反馈（M5-01）：开场太赶，"10 多秒再进剧情"。落地缓冲 2→3.5 秒、照亮 5→6.5 秒，
## 加起来正好 10 秒整（再加 0.5 秒场景稳定，开场低语才开口）。
const LAND_BUFFER := 3.5         # 落地后先停 3.5 秒（还是黑着，只有人周围一圈）
const REVEAL_TIME := 6.5         # M5-01：之后用 6.5 秒慢慢把周围的黑暗照亮
## 亮圈半径（屏幕像素）。108 时人只有半个身子在圈里，稍大一点才看得清全身。
const INTRO_HOLE_PX := 132.0
const INTRO_HOLE_SOFT := 110.0
## 圈里给角色打的一盏灯（加色精灵，画在人身后）：
## 黑影本来就是纯黑，背景也是黑的，不加这层灯就"看不见角色"（组长反馈）。
### 灯的直径按亮圈半径的倍数算，亮度跟着照亮过程一起淡出。
const INTRO_SPOT_SCALE := 2.6
const INTRO_SPOT_ALPHA := 0.55

func _void_arrival(land_pos: Vector2) -> void:
	var cam := $Camera2D as Camera2D
	var player := $Player as Node2D
	if _fade_rect != null:
		# 开场改用"只有角色周围看得见"的黑幕（见 _build_intro_blackout），
		# 原来那层全屏黑幕一开始就藏起来，别两套叠着压
		_fade_rect.modulate = Color(1, 1, 1, 0)
	_build_intro_blackout()
	# 镜头跟着他一起往下掉（用和重力同一条加速曲线），人一直在画面里。
	# M4-67（组长定的构图）：**X 轴必须居中**。虚空的最后是一晃人在画面正中掉下去，
	# 教学关接住时也得在正中，否则两幕接起来会"人忽然跳到左边"。
	# 出生点在离左墙很近的位置，常规跟随会被地图 limit 夹到 x≈299 —— 那时人就在左边了，
	# 所以开场先把 limit 拆掉、把镜头怼在人的 x 上；亮起来那 5 秒里再慢慢挪回常规构图。
	cam.set_physics_process(false)
	var saved_limits := [cam.limit_left, cam.limit_right, cam.limit_top, cam.limit_bottom]
	cam.limit_left = -100000
	cam.limit_right = 100000
	cam.limit_top = -100000
	cam.limit_bottom = 100000
	cam.zoom = Vector2(CAMERA_ZOOM * INTRO_ZOOM_SCALE, CAMERA_ZOOM * INTRO_ZOOM_SCALE)
	var fall_time := 0.36
	cam.global_position = Vector2(land_pos.x, land_pos.y - DROP_HEIGHT - 30.0)
	var cam_tw := create_tween()
	cam_tw.tween_property(cam, "global_position", Vector2(land_pos.x, land_pos.y - 28.0), fall_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# ① 下坠：黑幕只留角色周围一个亮圈（和序章虚空里一样），等他自己落地
	var waited := 0.0
	while not player.is_on_floor() and waited < DROP_TIMEOUT:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	# 落地这一帧把镜头对到最终构图：补间可能早一点晚一点，落地必须准
	cam.global_position = Vector2(land_pos.x, land_pos.y - 28.0)

	# ② 砸地：扬尘和落地声是 player.gd 自己接的（速度够大就会触发），
	#    这里补镜头下压和"压扁 → 弹起 → 站定"那一下
	cam.set("offset", Vector2(0, 0))
	if cam.has_method("dip"):
		cam.call("dip", 10.0, 0.20)
	player.call("play_intro_land")
	# 落地后先缓冲 2 秒：屏幕上还是只有人周围一圈，让"砸下来"这件事落地
	await get_tree().create_timer(LAND_BUFFER).timeout

	# ③ 5 秒慢慢把周围照亮，同时镜头缓缓退回常规构图（放大 → 常规、居中 → 带 map limit）
	await _reveal_at(player, cam, CAMERA_ZOOM)

	# 镜头交还给常规跟随：先按正常 zoom 把位置摆到"带 limit 的合法位置"，再开跟随，
	# 否则一开就跟、一夹，画面会突然横跳一下
	cam.limit_left = int(saved_limits[0])
	cam.limit_right = int(saved_limits[1])
	cam.limit_top = int(saved_limits[2])
	cam.limit_bottom = int(saved_limits[3])
	if cam.has_method("_clamp_to_limits"):
		cam.call("_clamp_to_limits")
	player.set("_input_locked", false)
	cam.set_physics_process(true)

## 开场黑幕：整屏压黑，只在角色周围留一圈看得见（和序章虚空里一样）。
##
## M5-21（组长反馈"蒙版还是在左下角、还不动"）：原来洞心是拿 FRAGCOORD 算距离的。
## FRAGCOORD 是**渲染目标**的像素坐标，窗口一放大（比如 1920×1080）它就变成 1.5 倍，
## 而传进去的 center_px 还是 1280×720 这套逻辑坐标 —— 两套坐标系打架，
## 圈就跑到画面另一头，而且怎么跟着人走都不在脸上。
## 现在只用 UV（不管渲染目标多大，它永远是盖住整块屏幕的 0~1），
## 距离按"UV 差 × 视口逻辑尺寸"还原成像素，坐标系只有一个，窗口多大都对得上。
const INTRO_SHADER := """
shader_type canvas_item;
uniform vec2 view_px = vec2(1280.0, 720.0);
uniform vec2 center_px = vec2(640.0, 360.0);
uniform float hole_px = 132.0;
uniform float soft_px = 110.0;
uniform vec4 dark : source_color = vec4(0.012, 0.016, 0.020, 1.0);
void fragment() {
	vec2 d_px = (UV - center_px / view_px) * view_px;
	float d = length(d_px);
	float a = clamp((d - hole_px) / soft_px, 0.0, 1.0);
	COLOR = vec4(dark.rgb, dark.a * a);
}
"""

func _build_intro_blackout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "IntroBlackout"
	layer.layer = 20         # 压在所有 UI 之上：开场那一秒连血条都不该露出来（HUD 在 0 层）
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "Dome"
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = INTRO_SHADER
	mat.shader = sh
	# 半径和视口尺寸显式写一遍：shader 里那组默认值只是兜底，改常量得真的生效
	mat.set_shader_parameter("hole_px", INTRO_HOLE_PX)
	mat.set_shader_parameter("soft_px", INTRO_HOLE_SOFT)
	mat.set_shader_parameter("view_px", Vector2(get_viewport_rect().size))
	mat.set_shader_parameter("center_px", _intro_screen_center())
	rect.material = mat
	layer.add_child(rect)
	_intro_blackout = rect
	_intro_shader = mat
	# 灯：加色精灵画在角色身后（z_index -1，玩家是 0），位置和直径每帧跟着人走。
	# 用加色而不是普通精灵，是因为它只是"照亮"，不该盖住地面和背景。
	var spot := Sprite2D.new()
	spot.name = "IntroSpot"
	spot.texture = _radial_texture()
	spot.z_index = -1
	spot.modulate = Color(0.62, 0.78, 0.86, INTRO_SPOT_ALPHA)
	add_child(spot)
	_intro_spot = spot

## 亮圈中心 = 角色身体的中心，不是脚下。角色节点原点在碰撞盒中心，
## 视觉身体还要往上 6px，所以减掉 6；再减掉镜头 offset（落地那一下的 dip 也在这上面），
## 不然震屏/下压的时候人会被亮圈甩出去半截。
func _intro_screen_center() -> Vector2:
	var view := Vector2(get_viewport_rect().size)
	var world := _player.global_position + Vector2(0, -6.0)
	var cam := _camera
	return (world - cam.global_position - cam.offset) * cam.zoom + view * 0.5

## 灯的直径跟亮圈一样大（乘以一点余量），所以"圈里亮、圈外黑"两边始终对得上
func _update_intro_spot() -> void:
	if _intro_spot == null or not is_instance_valid(_intro_spot):
		return
	_intro_spot.global_position = _player.global_position + Vector2(0, -6.0)
	var tex_size := float(_intro_spot.texture.get_width())
	var world_px := (INTRO_HOLE_PX * INTRO_SPOT_SCALE) / _camera.zoom.x
	var k := world_px / maxf(tex_size, 1.0)
	_intro_spot.scale = Vector2(k, k)

## 亮起（M4-67）：5 秒里同时做三件事——
##   ① 亮圈（洞）从人周围一路撑到全屏，这就是"慢慢把周围的黑暗看清"
##   ② 镜头 zoom 从开场的放大缓缓退回常规
##   ③ 镜头位置从"X 轴居中"缓缓挪到常规构图（带地图 limit 的那个合法位置）
## 三件事用同一条时间轴，所以亮完的时候构图也正好归位，不会在最后一下横跳。
func _reveal_at(player: Node2D, cam: Camera2D, normal_zoom: float) -> void:
	var half_w := (get_viewport_rect().size.x / 2.0) / normal_zoom
	var half_h := (get_viewport_rect().size.y / 2.0) / normal_zoom
	var goal := Vector2(
		clampf(player.global_position.x, float(cam.limit_left) + half_w, float(cam.limit_right) - half_w),
		clampf(player.global_position.y - 28.0, float(cam.limit_top) + half_h, float(cam.limit_bottom) - half_h))
	var from_pos := cam.global_position
	var tw := create_tween()
	tw.set_parallel(true)
	if _intro_shader != null:
		tw.tween_method(
			func(v: float) -> void: _intro_shader.set_shader_parameter("hole_px", v),
			INTRO_HOLE_PX, 1400.0, REVEAL_TIME).set_trans(Tween.TRANS_SINE)
		tw.tween_method(
			func(v: float) -> void: _intro_shader.set_shader_parameter("soft_px", v),
			INTRO_HOLE_SOFT, 320.0, REVEAL_TIME).set_trans(Tween.TRANS_SINE)
	# 灯跟亮圈同一条时间轴淡出：圈子撑大时灯也慢慢退，剩最后一片均匀的微光
	if _intro_spot != null and is_instance_valid(_intro_spot):
		tw.tween_property(_intro_spot, "modulate:a", 0.0, REVEAL_TIME * 0.8) \
			.set_trans(Tween.TRANS_SINE)
	tw.tween_property(cam, "zoom", Vector2(normal_zoom, normal_zoom), REVEAL_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(p: Vector2) -> void: cam.global_position = p, from_pos, goal, REVEAL_TIME) \
		.set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(func() -> void:
		if _intro_blackout != null and is_instance_valid(_intro_blackout):
			_intro_blackout.get_parent().queue_free()
		_intro_blackout = null
		_intro_shader = null
		if _intro_spot != null and is_instance_valid(_intro_spot):
			_intro_spot.queue_free()
		_intro_spot = null)
	# 必须等这条时间轴走完（5 秒）才交还操作：不然"人已经能走了、画面还是黑的"
	await tw.finished

## 平台原点是中心：碰撞换成 rect 大小、子节点归零、视觉按原始多边形缩放。
## 原来 JumpPlatform 的碰撞挂在 +343.5 这种手调偏移上，挪平台就得连子节点一起改，
## 这里统一成“原点=中心”，以后只给 rect 就行。
##
## M5-25（组长反馈"有个多出来的一点没有碰撞体积"）：视觉的缩放不再用写死的 unit，
## 而是**按它自己多边形有多大**算 —— 祭坛台的 unit 写着 300 宽、多边形却是 350 宽，
## 于是画出来比碰撞盒宽 112px（两边各多 56px），走过去就是一块没有碰撞的灰。
## 现在多边形和碰撞盒永远同宽同高，改 rect 也不会再错开。
func _place_platform(body: StaticBody2D, rect: Rect2, _unit: Vector2) -> void:
	body.position = rect.position + rect.size * 0.5
	var col := body.get_node("CollisionShape2D") as CollisionShape2D
	var shape := col.shape as RectangleShape2D
	shape.size = rect.size
	col.position = Vector2.ZERO
	var vis := body.get_node("Visual") as Polygon2D
	var bounds := Rect2(vis.polygon[0], Vector2.ZERO)
	for p in vis.polygon:
		bounds = bounds.expand(p)
	var poly_size := Vector2(maxf(bounds.size.x, 1.0), maxf(bounds.size.y, 1.0))
	vis.scale = Vector2(rect.size.x / poly_size.x, rect.size.y / poly_size.y)
	# 把多边形的中心对到原点：不然缩放后有一边会鼓出碰撞盒
	vis.position = -(bounds.position + bounds.size * 0.5) * vis.scale

## 悬崖右岸（M5-11）：和左岸同高同画法的一块地面，长廊石台跳过来就落在它上面。
## 名字取 GroundRight，arena_art 的装饰表里也加了它，所以亮边/砖缝/苔痕一样有。
func _build_right_bank(from_x: float, to_x: float) -> void:
	var width := to_x - from_x
	if width <= 0.0:
		return
	var body := StaticBody2D.new()
	body.name = "GroundRight"
	body.collision_mask = 0
	# 同样是 _ready 里新建的：z 必须压到玩家后面，否则右岸会在人经过时盖住他
	body.z_index = -1
	body.position = Vector2(from_x + width * 0.5, 689)
	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 60)
	col.shape = shape
	body.add_child(col)
	var vis := Polygon2D.new()
	vis.name = "Visual"
	vis.color = Color(0.156, 0.156, 0.156, 1)
	vis.polygon = _box_polygon(Vector2(width, 60))
	body.add_child(vis)
	add_child(body)

## 悬崖底：掉下去直接判死（和第一层的 KillZone 一个做法，摔落没有"爬上来"的可能）
func _build_chasm_kill_zone(from_x: float, to_x: float) -> void:
	var area := Area2D.new()
	area.name = "ChasmKillZone"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2((from_x + to_x) * 0.5, 900)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(to_x - from_x + 40.0, 160)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		# 玩家掉下去必死；怪物掉下去也当场死（组长要求"怪物掉悬崖底自动死亡"），
		# 否则它会卡在崖底继续追人，掉落物也就全悬在空中
		if body.has_method("take_damage"):
			body.call("take_damage", 99))
	add_child(area)

func _box_polygon(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])

## 教程 8 个目标文字锚点（下标就是 tutorial.gd 的 Step 枚举）。
## 给 Tutorial 用，也给测试用：测试从这里读坐标，改布局就不用再抄一份数字。
## 只负责"这环的话写在哪"，不再有光点停在上面（M4-21 组长要求删掉指引光）。
##
## M5-25（组长定的新规则）：文字中心 = **这一环的落脚面往上 3 个角色身高**
## （角色高 28 → 84px）。原来的锚点是"人站的位置再往上一大截"，
## 结果字飘在半空，抬头才看得见；现在贴着这一环的地面/台面放。
##
## POGO 这一环例外：它要教的是"先从地上跳上下劈方台"，那句话得写在**方台下面**
## （台底 571 往上一点是方台，再往下是地面），所以单独给 y=597 ——
## 写在台面上方的话，人还站在地上时那句就顶到屏幕外面去了（组长反馈）。
const TEXT_HEIGHT_ABOVE_SURFACE := 84.0
## 每一环的落脚面（x, 这一环的地面/台面顶 y）；文字由它算出来
const STATION_SURFACES := [
	Vector2(380, 659),    # MOVE：就写在出生点旁边（角色还不会按键，得先看见这句）
	Vector2(3400, 659),   # JUMP：跳台前面 3 秒（还是平地）
	Vector2(5900, 571),   # WEAPON：铁剑前面 3 秒
	Vector2(8600, 571),   # ATTACK：木桩前面 3 秒
	# POGO：句子的左边是木桩乙、右边是下劈方台。方台从 440 一直堆到 571（和跳台面贴着），
	# 所以"平台下方"其实是方块里面，字写那儿会被埋进石头 —— 写方块左边，人站在跳台上就能看见。
	Vector2(10660, 571),
	Vector2(13400, 659),  # COMBAT：史莱姆前面 3 秒
	Vector2(14800, 659),  # PICKUP：肢体掉落处（离 combat 门够远，不压门）
	Vector2(20900, 572),  # SACRIFICE：祭坛前面 3 秒（右岸台地）
]
func station_anchors() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(STATION_SURFACES.size()):
		var spec: Vector2 = STATION_SURFACES[i]
		var lift := TEXT_HEIGHT_ABOVE_SURFACE
		out.append(Vector2(spec.x, spec.y - lift))
	return out

## 位置判定①：玩家是否已横向走到某个站位（MOVE 环用）
## 只看横向：这一段本来就是平地，纵向没什么可判的
func player_reached(mark_key: String, player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not STAGE.has(mark_key):
		return false
	var mark: Vector2 = STAGE[mark_key]
	return (player as Node2D).global_position.x >= mark.x

## 位置判定②：玩家是否**双脚站上**某块平台（JUMP / POGO 环用）
## 组长定稿：下劈成功的标志是站上那块方台，不是挥出下劈动作 —— 所以这里要求 is_on_floor，
## 且脚底贴住该平台顶面（±6px）、横向落在矩形内（左右各留 4px，别把边缘算成站上去）
func player_on_platform(rect_key: String, player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not STAGE.has(rect_key):
		return false
	var body := player as CharacterBody2D
	if body == null or not body.is_on_floor():
		return false
	var rect: Rect2 = STAGE[rect_key]
	var x := body.global_position.x
	if x < rect.position.x + 4.0 or x > rect.end.x - 4.0:
		return false
	var feet := body.global_position.y + PLAYER_HALF_HEIGHT
	return absf(feet - rect.position.y) <= 6.0

## 物理帧也刷一次：坠落时人每帧走十几像素，只在 _process 刷会差半帧，
## 亮圈看起来比人慢一点点（像在拖）。两个回合同写同一个值，最后一次生效就行。
func _physics_process(_delta: float) -> void:
	if _intro_blackout != null and is_instance_valid(_intro_blackout) and _intro_shader != null:
		# 窗口/视口尺寸也可能变（玩家拉窗口、全屏），每帧对齐一次，别让圈子按旧尺寸算
		_intro_shader.set_shader_parameter("view_px", Vector2(get_viewport_rect().size))
		_intro_shader.set_shader_parameter("center_px", _intro_screen_center())
		_update_intro_spot()

func _process(_delta: float) -> void:
	# 开场那层"只有角色周围看得见"的黑幕：洞心每帧跟着人走。
	# 不跟的话人一掉，他就从亮圈里出去，画面变成全黑（看起来像卡住）。
	if _intro_blackout != null and is_instance_valid(_intro_blackout) and _intro_shader != null:
		_intro_shader.set_shader_parameter("center_px", _intro_screen_center())
		_update_intro_spot()
	if _refusing:
		return
	# 教程跑完（献祭完成）就把门点亮；之后玩家走进门即切到第一层
	if not _door_open and _tutorial != null and _tutorial.has_method("is_completed"):
		if bool(_tutorial.call("is_completed")):
			_open_door()
	# 战斗门不跟教程的“第一只击杀”走：必须把战斗区史莱姆清空才开，
	# 否则玩家杀一只就能跳过第二只直接去祭坛。
	if _combat_started and not _is_gate_open("combat"):
		if get_tree().get_nodes_in_group("enemy").is_empty():
			_open_tutorial_gate("combat")

# ---------- 教学物理门 ----------

func _build_tutorial_gates() -> void:
	var holder := Node2D.new()
	holder.name = "TutorialGates"
	# 骨栅是探索到中途才落下的，晚于玩家建出来；z 压后一层，免得它的横杆画在人身上
	holder.z_index = -1
	add_child(holder)
	for gate_id in ["move", "jump", "attack", "pogo", "combat"]:
		var gate := TUTORIAL_GATE_SCENE.instantiate()
		gate.name = "Gate_%s" % gate_id
		gate.set("gate_id", gate_id)
		gate.set("gate_height", TUTORIAL_GATE_HEIGHTS[gate_id])
		gate.position = STAGE["%s_gate" % gate_id]
		holder.add_child(gate)
		_gates[gate_id] = gate

func open_tutorial_gate(gate_id: String) -> void:
	_open_tutorial_gate(gate_id)

func _open_tutorial_gate(gate_id: String) -> void:
	var gate: Node = _gates.get(gate_id)
	if gate != null and is_instance_valid(gate) and gate.has_method("open"):
		gate.call("open")
		GameManager.play_sfx("gate")

func _is_gate_open(gate_id: String) -> bool:
	var gate: Node = _gates.get(gate_id)
	if gate == null or not is_instance_valid(gate):
		return true
	return bool(gate.call("is_open"))

func _unhandled_input(event: InputEvent) -> void:
	# 反向测试（规范第 6 条）：只认按下沿，其它键、抬起、长按 echo 都不触发
	var key := event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	# 真 HE 二周目不能按 F2 跳回第一层，否则“还骨片”会被绕过
	if _true_he_mode:
		return
	if key.keycode == DEBUG_SKIP_KEY:
		_enter_floor1()
		return
	# M5-04：站在门口按 K 才进下一层（不再碰触自动传送）
	if _door_near and _door_open and not _entering and key.is_action_pressed("interact"):
		_enter_floor1()

# ---------- 下一层的门 ----------

## M4-03：史莱姆浅坑两侧各两级石阶。原来 PitFloor 是一块高 72px 的凸台，
## 从跳台走过去像突然踩到桌子；现在用 26/52px 两级台阶落下去，再对称爬上来。
func _build_hollow_steps() -> void:
	if (STAGE["pit_steps"] as Array).is_empty():
		return   # M5-30：没有台阶，就不建这个节点（空 holder 只会多一个没用的节点）
	_build_slab_holder("HollowSteps", STAGE["pit_steps"],
		["HollowStepL1", "HollowStepL2", "HollowStepR1", "HollowStepR2"])

## 祭坛后的可选阶梯（M4-07）：不参与教学门判定，走地面也能直达出口。
func _build_corridor_gallery() -> void:
	# M5-39：石台从 4 块加到 6 块（块数跟着 STAGE 表走，不再写死名字）
	var names := []
	for i in range((STAGE["gallery"] as Array).size()):
		names.append("GalleryStep%d" % (i + 1))
	_build_slab_holder("CorridorGallery", STAGE["gallery"], names)

## 浅坑台阶和长廊台阶是同一套画法（石台 + 顶面亮边），抽成一个函数，
## 免得两处各抄一份、以后改颜色只改一半。
func _build_slab_holder(holder_name: String, rects: Array, names: Array) -> void:
	var holder := Node2D.new()
	holder.name = holder_name
	# M5-19（组长反馈"阶梯处有一团灰色矩形，与碰撞体积不重合，导致玩家被覆盖"）：
	# 这些台阶是 _ready 里才 new 出来的，节点顺序在玩家之后 —— 而玩家和地形都是 z=0，
	# 后加的就画在前面，于是玩家走到台阶后面会被一整块灰色盖住（看起来像穿模）。
	# 地形必须永远压在人后面：整组挪到 z=-1（背景在 -3，所以不会掉到背景下面）。
	holder.z_index = -1
	add_child(holder)
	for i in range(rects.size()):
		var rect: Rect2 = rects[i]
		var body := StaticBody2D.new()
		body.name = str(names[i])
		body.collision_mask = 0
		body.position = rect.position + rect.size * 0.5
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		col.shape = shape
		body.add_child(col)
		var half := rect.size * 0.5
		var slab := Polygon2D.new()
		# M5-25：原来这块是比地面更暗的纯灰 (0.155,0.170,0.180)，在深色背景上就是一块"错误方块"。
		# 改成和主地面同一个色（0.170,0.190,0.200），再补上横缝和亮边，读起来才是石头台。
		slab.color = Color(0.176, 0.196, 0.208, 1)
		slab.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
		body.add_child(slab)
		# M4-23 组长反馈：这些台阶只有一整块纯色，看着像“错误地形”。
		# 现在按和主地面同一套画法补：顶面亮边 + 顶面暗线 + 两道接缝 + 一点苔痕，
		# 有厚度、有接缝，才读得出是石台而不是占位方块。
		var edge := Line2D.new()
		edge.width = 2.0
		edge.default_color = Color(0.34, 0.36, 0.36, 0.9)
		edge.points = PackedVector2Array([Vector2(-half.x + 1.0, -half.y + 1.0), Vector2(half.x - 1.0, -half.y + 1.0)])
		body.add_child(edge)
		var shade := Line2D.new()
		shade.width = 2.0
		shade.default_color = Color(0.03, 0.04, 0.05, 0.75)
		shade.points = PackedVector2Array([Vector2(-half.x + 2.0, -half.y + 3.5), Vector2(half.x - 2.0, -half.y + 3.5)])
		body.add_child(shade)
		for k in range(2):
			var seam := Line2D.new()
			seam.width = 1.2
			seam.default_color = Color(0.09, 0.10, 0.11, 0.7)
			var sx := -half.x + rect.size.x * float(k + 1) / 3.0
			seam.points = PackedVector2Array([
				Vector2(sx, -half.y + 2.0),
				Vector2(sx + 2.0, -half.y + rect.size.y * 0.45),
				Vector2(sx - 1.0, half.y - 2.0),
			])
			body.add_child(seam)
			var moss := Polygon2D.new()
			moss.color = Color(0.20, 0.28, 0.24, 0.55)
			moss.polygon = PackedVector2Array([
				Vector2(-half.x + 6.0, -half.y + 2.0), Vector2(-half.x + 26.0, -half.y + 2.0),
				Vector2(-half.x + 20.0, -half.y + 6.0), Vector2(-half.x + 8.0, -half.y + 5.0),
			])
			body.add_child(moss)
			# M5-25：再补两三条横缝（和主地面的"砌层"一个画法）。
			# 台阶只有 26~52px 高，光靠竖缝还是一整块板；有横缝才看得出是叠起来的石头。
			var course_y := -half.y + 12.0
			var course_i := 0
			while course_y < half.y - 6.0:
				var course := Line2D.new()
				course.width = 1.0
				course.default_color = Color(0.055, 0.070, 0.080, 0.55)
				var inset := 3.0 + float(course_i % 2) * 3.0
				course.points = PackedVector2Array([
					Vector2(-half.x + inset, course_y), Vector2(half.x - inset, course_y),
				])
				body.add_child(course)
				course_y += 14.0
				course_i += 1
			# M5-39：石台底下一串垂链 + 两块碎岩 —— 悬空的石头得有"吊着"的依据
			var chain := Line2D.new()
			chain.name = "SlabChain"
			chain.width = 1.4
			chain.default_color = Color(0.060, 0.070, 0.080, 0.75)
			var cxx := -half.x + rect.size.x * 0.5
			chain.points = PackedVector2Array([Vector2(cxx, half.y), Vector2(cxx + 3.0, half.y + 34.0)])
			body.add_child(chain)
		for k in range(2):
			var chunk := Polygon2D.new()
			chunk.name = "SlabChunk"
			var tone := 0.120 + 0.02 * float(k)
			chunk.color = Color(tone, tone * 1.05, tone * 1.1, 0.95)
			var cx2 := -half.x + rect.size.x * (0.3 + 0.4 * float(k))
			chunk.polygon = PackedVector2Array([
				Vector2(cx2 - 9, half.y + 2), Vector2(cx2 + 7, half.y + 1),
				Vector2(cx2 + 4, half.y + 12), Vector2(cx2 - 6, half.y + 14),
			])
			body.add_child(chunk)
		holder.add_child(body)

func _build_next_floor_door() -> void:
	_door_root = Node2D.new()
	_door_root.name = "NextFloorDoor"
	_door_root.position = STAGE["door"]
	# 门框压在玩家后面：走进去时人挡门，不是门挡人（背景 Backdrop z=-2）
	_door_root.z_index = -1
	add_child(_door_root)

	# 门后透出来的光：没开门时是一层很暗的冷光，开关门会调它
	_door_glow = Sprite2D.new()
	_door_glow.texture = _radial_texture()
	_door_glow.modulate = Color(0.35, 0.80, 0.82, 0.06)
	_door_glow.scale = Vector2(1.6, 1.6)
	_door_glow.position = Vector2(0, -80)
	_door_root.add_child(_door_glow)

	# ---------- 门体（M5-34 重做：原来就是两根竖条 + 一块横板） ----------
	var stone := Color(0.128, 0.148, 0.158)
	var stone_lit := Color(0.176, 0.200, 0.212)
	var stone_dark := Color(0.086, 0.100, 0.110)
	var glow_edge := Color(0.34, 0.52, 0.53, 0.55)

	# ① 门洞内壁：比门框暗一档，让门"有厚度"而不是贴在背景上
	var cavity := Polygon2D.new()
	cavity.color = Color(0.045, 0.056, 0.064)
	cavity.polygon = PackedVector2Array([
		Vector2(-52, -158), Vector2(52, -158), Vector2(52, -2), Vector2(-52, -2),
	])
	_door_root.add_child(cavity)

	# ② 立柱：柱身 + 柱头 + 柱础，三件套才像石柱
	for dx in [-56.0, 56.0]:
		var side := 1.0 if dx > 0.0 else -1.0
		var post := Polygon2D.new()
		post.color = stone
		post.polygon = PackedVector2Array([
			Vector2(dx - 20, -166), Vector2(dx + 20, -166),
			Vector2(dx + 18, -4), Vector2(dx - 18, -4),
		])
		_door_root.add_child(post)
		# 柱身上一道受光边
		var lit := Line2D.new()
		lit.width = 2.0
		lit.default_color = stone_lit
		lit.points = PackedVector2Array([
			Vector2(dx - side * 15.0, -160), Vector2(dx - side * 16.0, -10),
		])
		_door_root.add_child(lit)
		# 柱头：比柱身宽一圈，两级挑檐
		var capital := Polygon2D.new()
		capital.color = stone_lit
		capital.polygon = PackedVector2Array([
			Vector2(dx - 28, -176), Vector2(dx + 28, -176),
			Vector2(dx + 24, -166), Vector2(dx - 24, -166),
		])
		_door_root.add_child(capital)
		var capital2 := Polygon2D.new()
		capital2.color = stone
		capital2.polygon = PackedVector2Array([
			Vector2(dx - 25, -166), Vector2(dx + 25, -166),
			Vector2(dx + 21, -158), Vector2(dx - 21, -158),
		])
		_door_root.add_child(capital2)
		# 柱础
		var base := Polygon2D.new()
		base.color = stone_dark
		base.polygon = PackedVector2Array([
			Vector2(dx - 26, -8), Vector2(dx + 26, -8),
			Vector2(dx + 24, 0), Vector2(dx - 24, 0),
		])
		_door_root.add_child(base)
		# 门框内侧一圈冷色轮廓光
		var rim := Line2D.new()
		rim.width = 2.0
		rim.default_color = glow_edge
		rim.points = PackedVector2Array([
			Vector2(dx - side * 20.0, -158), Vector2(dx - side * 18.0, -6),
		])
		_door_root.add_child(rim)

	# ③ 门楣：两层（檐 + 梁），中间压一条浮雕线
	var lintel := Polygon2D.new()
	lintel.color = stone_lit
	lintel.polygon = PackedVector2Array([
		Vector2(-86, -186), Vector2(86, -186), Vector2(80, -172), Vector2(-80, -172),
	])
	_door_root.add_child(lintel)
	var beam := Polygon2D.new()
	beam.color = stone
	beam.polygon = PackedVector2Array([
		Vector2(-80, -172), Vector2(80, -172), Vector2(76, -156), Vector2(-76, -156),
	])
	_door_root.add_child(beam)
	var frieze := Line2D.new()
	frieze.width = 2.0
	frieze.default_color = Color(0.26, 0.34, 0.36, 0.7)
	frieze.points = PackedVector2Array([
		Vector2(-72, -164), Vector2(72, -164),
	])
	_door_root.add_child(frieze)
	# 门楣上方的山花：一个浅浅的三角，把门"顶"起来
	var pediment := Polygon2D.new()
	pediment.color = stone_dark
	pediment.polygon = PackedVector2Array([
		Vector2(-86, -186), Vector2(86, -186), Vector2(0, -205),
	])
	_door_root.add_child(pediment)
	var pediment_lit := Line2D.new()
	pediment_lit.width = 1.6
	pediment_lit.default_color = Color(0.30, 0.40, 0.42, 0.65)
	pediment_lit.points = PackedVector2Array([
		Vector2(-78, -187), Vector2(0, -201), Vector2(78, -187),
	])
	_door_root.add_child(pediment_lit)

	# ④ 两扇门板：半开，往里收，带门钉和横档
	for side in [-1.0, 1.0]:
		var leaf := Polygon2D.new()
		leaf.color = Color(0.070, 0.082, 0.092)
		leaf.polygon = PackedVector2Array([
			Vector2(side * 4.0, -152), Vector2(side * 46.0, -147),
			Vector2(side * 46.0, -8), Vector2(side * 4.0, -12),
		])
		_door_root.add_child(leaf)
		# 横档两道
		for bar_y in [-124.0, -74.0]:
			var bar := Line2D.new()
			bar.width = 2.0
			bar.default_color = Color(0.150, 0.170, 0.180, 0.85)
			bar.points = PackedVector2Array([
				Vector2(side * 8.0, bar_y), Vector2(side * 42.0, bar_y + 2.0),
			])
			_door_root.add_child(bar)
		# 门钉三颗
		for stud in [-136.0, -104.0, -58.0]:
			var dot := Polygon2D.new()
			dot.color = Color(0.230, 0.270, 0.280, 0.9)
			dot.polygon = PackedVector2Array([
				Vector2(side * 26.0 - 2.0, stud), Vector2(side * 26.0 + 2.0, stud),
				Vector2(side * 26.0 + 2.0, stud + 4.0), Vector2(side * 26.0 - 2.0, stud + 4.0),
			])
			_door_root.add_child(dot)

	# ⑤ 门槛两级：贴着地面，别让柱子浮着
	var sill := Polygon2D.new()
	sill.color = Color(0.190, 0.210, 0.215)
	sill.polygon = PackedVector2Array([
		Vector2(-74, -8), Vector2(74, -8), Vector2(74, 0), Vector2(-74, 0),
	])
	_door_root.add_child(sill)
	var sill2 := Polygon2D.new()
	sill2.color = Color(0.150, 0.168, 0.176)
	sill2.polygon = PackedVector2Array([
		Vector2(-88, 0), Vector2(88, 0), Vector2(84, 7), Vector2(-84, 7),
	])
	_door_root.add_child(sill2)

	# ⑥ 门侧墙垛：贴在两边的短墙，把门"嵌"进墙里
	for side in [-1.0, 1.0]:
		var pier := Polygon2D.new()
		pier.color = stone_dark
		pier.polygon = PackedVector2Array([
			Vector2(side * 76, -180), Vector2(side * 96, -180),
			Vector2(side * 96, 0), Vector2(side * 76, 0),
		])
		_door_root.add_child(pier)
		var pier_lit := Line2D.new()
		pier_lit.width = 1.4
		pier_lit.default_color = Color(0.24, 0.32, 0.34, 0.5)
		pier_lit.points = PackedVector2Array([
			Vector2(side * 77, -176), Vector2(side * 77, -4),
		])
		_door_root.add_child(pier_lit)

	# 门缝：整个门的"开关"就看这条线的亮度
	_door_seam = Line2D.new()
	_door_seam.name = "DoorSeam"
	_door_seam.width = 5.0
	_door_seam.default_color = Color(0.18, 0.30, 0.32, 0.25)
	_door_seam.points = PackedVector2Array([Vector2(0, -164), Vector2(0, -4)])
	_door_root.add_child(_door_seam)

	# 门牌：中文字体必须显式加载，否则方块
	# M5-22（组长反馈"大门这边还没有抬头，一直在后排"）：门框本身是 z=-1（人要挡门），
	# 但它下面的门牌跟着一起退到了地形后面，被地面亮边和道具压住、一直"抬不起头"。
	# 门牌和提示单独抬到 z=40（世界层里最高），门框该在后面还在后面。
	var label := Label.new()
	label.text = "第一层"
	label.position = Vector2(-40, -192)
	label.size = Vector2(80, 24)
	label.z_index = 40
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.56, 0.80, 0.82, 0.85))
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	_door_root.add_child(label)

	# 进入判定：只认玩家（collision_mask 2）。M5-04（组长要求）：不再"碰到就自动进"，
	# 改成走到门前按 K —— 先看到门上的提示，再自己决定进不进（自动传送容易误触）。
	var area := Area2D.new()
	area.name = "DoorArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(0, -90)
	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 180)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		_door_near = true
		_update_door_prompt())
	area.body_exited.connect(func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		_door_near = false
		_update_door_prompt())
	_door_root.add_child(area)

	# 门上的提示："进入第一层（K）"，只有门开了且人站在门口才亮。
	# M5-22（组长要求"可以打开就提示按 K 开门，和正常交互提示一样"）：
	# 改用统一的 InteractionPrompt（和火堆/钟绳/守钟人同一套字体描边阴影），
	# 层级也抬到 40：门框在后面，提示永远在人能看到的最上层。
	_door_prompt = InteractionPrompt.create(
		_door_root, "进入第一层（K）", Vector2(-80, -214), Vector2(160, 24),
		12, Color(0.78, 0.96, 0.92, 0.98), 2, 40
	)
	_door_prompt.name = "DoorPrompt"
	_door_prompt.visible = false

## 提示只在"门开了 + 人站在门口"时显示；其余时候藏起来，别在教程前半段就吊着人
## 门前圣所（M5-34）：祭坛搬到门口之后，这块空地要有东西衬。
## 供台、烛台、断柱、瓦砾、门楣旧布 —— 都画在 z=-1，和门框同层，不挡人也不参与碰撞。

## 一个椭圆的多边形顶点（门前圣所的烛光晕用；arena_art 里那个 _ellipse 是它的私有函数）
func _ring_points(center: Vector2, radii: Vector2, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

## 高草丛（M5-37）：一片一片种在地面和台面上，玩家走过去会被拨动。
## 每片草的 y 按它所在的地形给（跳台面 571，普通地面 659，右岸台地 572）。
const GRASS_PATCHES := [
	[180.0, 900.0, 659.0], [1400.0, 1900.0, 659.0], [2100.0, 2900.0, 659.0],
	[4000.0, 5000.0, 571.0], [6100.0, 7100.0, 571.0],
	[8200.0, 9100.0, 571.0], [10200.0, 11000.0, 571.0],
	[12300.0, 13200.0, 659.0], [15000.0, 16000.0, 659.0],
	[17000.0, 18200.0, 659.0], [20500.0, 21100.0, 572.0],
	[21300.0, 21900.0, 659.0],
]


## 前景遮挡（M5-41 重做）：压在角色前面的暗色剪影。
##
## 上一版是一堆 4~7px 的细线，读起来像栅栏，组长说难看。现在改成"有厚度"的剪影：
## 每根草叶是一个带弧度的填充多边形（中间宽、两头收），体量放大、数量减少，
## 另外配两块近景岩石，颜色压到 0.02 上下 —— 是"更近的一层"，不是"画糊了"。
func _build_foreground_occluders() -> void:
	var layer := Node2D.new()
	layer.name = "ForegroundOccluders"
	layer.z_index = 3
	add_child(layer)
	var leaf_dark := Color(0.022, 0.030, 0.034, 0.94)
	var leaf_edge := Color(0.048, 0.062, 0.058, 0.85)
	var rock_dark := Color(0.030, 0.038, 0.044, 0.96)
	var rock_edge := Color(0.070, 0.082, 0.086, 0.7)

	# 巨型草簇：五根粗叶 + 一根最高叶，体量到 700px 上下
	for cx in [1700.0, 7000.0, 12600.0, 18000.0]:
		var clump := Node2D.new()
		clump.name = "ForegroundGrass"
		clump.position = Vector2(cx, 676.0)
		layer.add_child(clump)
		var blades := [
			[-34.0, 520.0, 30.0, -0.22], [-14.0, 640.0, 26.0, -0.10],
			[6.0, 720.0, 24.0, 0.05], [28.0, 580.0, 28.0, 0.18],
			[52.0, 460.0, 24.0, 0.30],
		]
		for b in blades:
			var bx := float(b[0])
			var bh := float(b[1])
			var bw := float(b[2])
			var tilt := float(b[3])
			var leaf := Polygon2D.new()
			leaf.color = leaf_dark
			var tip := Vector2(bx + tilt * bh, -bh)
			leaf.polygon = PackedVector2Array([
				Vector2(bx - bw, 0), Vector2(bx - bw * 0.55, -bh * 0.45),
				tip + Vector2(-bw * 0.18, 6.0), tip, tip + Vector2(bw * 0.18, 6.0),
				Vector2(bx + bw * 0.55, -bh * 0.4), Vector2(bx + bw, 0),
			])
			clump.add_child(leaf)
			# 叶心一条极暗的芯，让剪影不是一块死黑
			var core := Line2D.new()
			core.width = 3.0
			core.default_color = leaf_edge
			core.points = PackedVector2Array([
				Vector2(bx, -6.0), Vector2(bx + tilt * bh * 0.5, -bh * 0.5), tip,
			])
			clump.add_child(core)

	# 近景岩石：两块，压在台边，挡住角色下半身
	for spec in [[4200.0, 300.0, 150.0], [15200.0, 260.0, 130.0]]:
		var rock := Node2D.new()
		rock.name = "ForegroundRock"
		rock.position = Vector2(float(spec[0]), 676.0)
		layer.add_child(rock)
		var rw := float(spec[2])
		var rh := float(spec[1])
		var body := Polygon2D.new()
		body.color = rock_dark
		body.polygon = PackedVector2Array([
			Vector2(-rw, 0), Vector2(-rw * 0.92, -rh * 0.42),
			Vector2(-rw * 0.45, -rh * 0.86), Vector2(rw * 0.25, -rh),
			Vector2(rw * 0.9, -rh * 0.5), Vector2(rw, 0),
		])
		rock.add_child(body)
		var edge := Line2D.new()
		edge.width = 2.4
		edge.default_color = rock_edge
		edge.points = PackedVector2Array([
			Vector2(-rw * 0.92, -rh * 0.42), Vector2(-rw * 0.45, -rh * 0.86),
			Vector2(rw * 0.25, -rh), Vector2(rw * 0.9, -rh * 0.5),
		])
		rock.add_child(edge)


## 路上的剧情节点（M5-40）：走到某个位置就念一段旁白，每段只播一次。
const STORY_BEATS := [
	{"x": 4300.0, "id": "tutorial_colossus"},
	{"x": 8500.0, "id": "tutorial_cage"},
	{"x": 18500.0, "id": "tutorial_chasm"},
]

var _story_seen: Dictionary = {}

func _build_story_beats() -> void:
	for spec in STORY_BEATS:
		var area := Area2D.new()
		area.name = "StoryBeat_%s" % str(spec["id"])
		area.collision_layer = 0
		area.collision_mask = 2
		area.position = Vector2(float(spec["x"]), 600.0)
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(60, 260)
		col.shape = shape
		area.add_child(col)
		area.body_entered.connect(func(body: Node2D) -> void:
			if not body.is_in_group("player"):
				return
			var id := str(spec["id"])
			if _story_seen.has(id):
				return
			# 只有真的播出来了才记账；如果这时别的话正在播，下次进来再试
			if _play_story_beat(id):
				_story_seen[id] = true)
		add_child(area)

func _play_story_beat(id: String) -> bool:
	var dialogue := get_node_or_null("Dialogue")
	if dialogue == null or not dialogue.has_method("play"):
		return false
	if bool(dialogue.call("is_playing")):
		return false
	dialogue.call("play", id)
	return true

func _build_tall_grass() -> void:
	for spec in GRASS_PATCHES:
		var grass := TALL_GRASS_SCRIPT.new()
		grass.from_x = float(spec[0])
		grass.to_x = float(spec[1])
		grass.ground_y = float(spec[2])
		grass.name = "TallGrass"
		add_child(grass)

func _build_door_shrine() -> void:
	var shrine := Node2D.new()
	shrine.name = "DoorShrine"
	shrine.z_index = -1
	add_child(shrine)
	var altar_x: float = (STAGE["altar"] as Vector2).x
	var door_x: float = (STAGE["door"] as Vector2).x
	var ground := 659.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261116

	var stone := Color(0.132, 0.150, 0.160)
	var stone_lit := Color(0.196, 0.216, 0.226)
	var stone_dark := Color(0.078, 0.092, 0.102)

	# ① 供台：祭坛左边一张矮石台，台上一只香灰碗
	var table := Node2D.new()
	table.name = "OfferingTable"
	table.position = Vector2(altar_x - 92.0, ground)
	shrine.add_child(table)
	var slab := Polygon2D.new()
	slab.color = stone_lit
	slab.polygon = PackedVector2Array([
		Vector2(-34, -30), Vector2(34, -30), Vector2(30, -22), Vector2(-30, -22),
	])
	table.add_child(slab)
	for lx in [-18.0, 16.0]:
		var leg := Polygon2D.new()
		leg.color = stone
		leg.polygon = PackedVector2Array([
			Vector2(lx - 5, lx * 0.0 - 22), Vector2(lx + 5, -22),
			Vector2(lx + 7, 0), Vector2(lx - 3, 0),
		])
		table.add_child(leg)
	var bowl := Polygon2D.new()
	bowl.color = Color(0.100, 0.112, 0.120)
	bowl.polygon = PackedVector2Array([
		Vector2(-13, -33), Vector2(13, -33), Vector2(9, -26), Vector2(-9, -26),
	])
	table.add_child(bowl)
	var ash := Polygon2D.new()
	ash.color = Color(0.230, 0.226, 0.220, 0.85)
	ash.polygon = PackedVector2Array([
		Vector2(-9, -32), Vector2(9, -32), Vector2(5, -29), Vector2(-5, -29),
	])
	table.add_child(ash)

	# ② 烛台三座：高低不一，火焰是一小块暖色 + 一圈很淡的光晕
	for spec in [
		{"dx": -56.0, "h": 44.0}, {"dx": -130.0, "h": 30.0}, {"dx": 62.0, "h": 38.0},
	]:
		var holder := Node2D.new()
		holder.name = "Candle"
		holder.position = Vector2(altar_x + float(spec["dx"]), ground)
		shrine.add_child(holder)
		var h := float(spec["h"])
		var stand := Polygon2D.new()
		stand.color = stone
		stand.polygon = PackedVector2Array([
			Vector2(-7, 0), Vector2(7, 0), Vector2(5, -4), Vector2(-5, -4),
		])
		holder.add_child(stand)
		var pole := Line2D.new()
		pole.width = 2.0
		pole.default_color = stone_lit
		pole.points = PackedVector2Array([Vector2(0, -4), Vector2(0, -h)])
		holder.add_child(pole)
		var cup := Polygon2D.new()
		cup.color = Color(0.150, 0.138, 0.122)
		cup.polygon = PackedVector2Array([
			Vector2(-5, -h), Vector2(5, -h), Vector2(3, -h - 6), Vector2(-3, -h - 6),
		])
		holder.add_child(cup)
		var flame := Polygon2D.new()
		flame.color = Color(1.0, 0.78, 0.42, 0.9)
		flame.polygon = PackedVector2Array([
			Vector2(0, -h - 16), Vector2(3, -h - 8), Vector2(0, -h - 5), Vector2(-3, -h - 8),
		])
		holder.add_child(flame)
		var halo := Polygon2D.new()
		halo.color = Color(1.0, 0.70, 0.34, 0.10)
		halo.polygon = _ring_points(Vector2(0, -h - 9), Vector2(11, 14), 12)
		holder.add_child(halo)

	# ③ 断柱两根：一高一矮，柱口不平，柱身带裂缝
	for spec in [
		{"dx": -170.0, "h": 96.0, "w": 16.0},
		{"dx": 190.0, "h": 58.0, "w": 14.0},
	]:
		var dx := float(spec["dx"])
		var ph := float(spec["h"])
		var pw := float(spec["w"])
		var col2 := Node2D.new()
		col2.name = "BrokenPillar"
		col2.position = Vector2(altar_x + dx, ground)
		shrine.add_child(col2)
		var body := Polygon2D.new()
		body.color = stone
		body.polygon = PackedVector2Array([
			Vector2(-pw, -ph), Vector2(pw, -ph + 6.0), Vector2(pw, 0), Vector2(-pw, 0),
		])
		col2.add_child(body)
		var lit := Line2D.new()
		lit.width = 1.6
		lit.default_color = stone_lit
		lit.points = PackedVector2Array([Vector2(-pw + 3.0, -ph + 4.0), Vector2(-pw + 3.0, -3.0)])
		col2.add_child(lit)
		var cap := Polygon2D.new()
		cap.color = stone_lit
		cap.polygon = PackedVector2Array([
			Vector2(-pw, -ph), Vector2(pw, -ph + 6.0), Vector2(pw - 3.0, -ph + 2.0), Vector2(-pw + 2.0, -ph - 4.0),
		])
		col2.add_child(cap)
		var crack := Line2D.new()
		crack.width = 1.0
		crack.default_color = Color(0.040, 0.050, 0.058, 0.7)
		crack.points = PackedVector2Array([
			Vector2(-2.0, -ph + 10.0), Vector2(2.0, -ph * 0.6), Vector2(-1.0, -6.0),
		])
		col2.add_child(crack)

	# ④ 地面瓦砾：祭坛和门之间撒一圈碎石
	var rubble_x := altar_x + 70.0
	while rubble_x < door_x - 70.0:
		var pile := Node2D.new()
		pile.name = "Rubble"
		pile.position = Vector2(rubble_x, ground)
		shrine.add_child(pile)
		for k in range(int(rng.randf_range(2.0, 5.0))):
			var bit := Polygon2D.new()
			var tone := rng.randf_range(0.110, 0.180)
			bit.color = Color(tone, tone * 1.05, tone * 1.10, 0.95)
			var bw := rng.randf_range(3.0, 9.0)
			var bh := rng.randf_range(2.0, 4.0)
			var bx := rng.randf_range(-18.0, 18.0)
			bit.polygon = PackedVector2Array([
				Vector2(bx - bw, 0), Vector2(bx - bw * 0.3, -bh),
				Vector2(bx + bw, -bh * 0.7), Vector2(bx + bw * 0.7, 0),
			])
			pile.add_child(bit)
		rubble_x += rng.randf_range(26.0, 64.0)

	# ⑤ 门楣两侧垂下来的旧布幔
	for side in [-1.0, 1.0]:
		var cloth := Node2D.new()
		cloth.name = "DoorBanner"
		cloth.position = Vector2(door_x + side * 104.0, ground - 196.0)
		shrine.add_child(cloth)
		var banner := Polygon2D.new()
		banner.color = Color(0.150, 0.115, 0.100, 0.85)
		banner.polygon = PackedVector2Array([
			Vector2(-13, 0), Vector2(13, 0), Vector2(11, 62), Vector2(4, 74),
			Vector2(-3, 64), Vector2(-11, 56),
		])
		cloth.add_child(banner)
		var banner_edge := Line2D.new()
		banner_edge.width = 1.2
		banner_edge.default_color = Color(0.26, 0.20, 0.17, 0.7)
		banner_edge.points = PackedVector2Array([
			Vector2(-13, 2), Vector2(-10, 56), Vector2(-3, 62),
		])
		cloth.add_child(banner_edge)

func _update_door_prompt() -> void:
	if _door_prompt == null or not is_instance_valid(_door_prompt):
		return
	_door_prompt.visible = _door_open and _door_near and not _entering
	_door_prompt.text = "进入第一层（K）" if _door_open else "门还锁着"

func _open_door() -> void:
	_door_open = true
	_door_seam.default_color = Color(0.55, 0.95, 0.92, 0.85)
	_door_glow.modulate = Color(0.45, 0.95, 0.90, 0.30)
	GameManager.play_sfx("gate")
	EventBus.log_event("floor_gate_open", {"floor": "floor1"})
	# 门一开就把提示挂上去（人要是已经在门口，不用退出去再进来）
	_update_door_prompt()

func _enter_floor1() -> void:
	if _entering:
		return
	_entering = true
	_update_door_prompt()
	GameManager.set_flag("floor1_unlocked")
	EventBus.player_moved_between_floors.emit("floor1")
	# M2-09：先黑屏 + 层名，再换场景；换场景必须延后，别在物理/输入回调里立刻切
	if _fade_rect != null:
		var tween := create_tween()
		tween.tween_property(_fade_rect, "modulate:a", 1.0, 0.50)
		tween.parallel().tween_property(_fade_label, "modulate:a", 0.9, 0.35)
		tween.tween_interval(0.28)
		tween.tween_callback(_change_to_floor1)
	else:
		get_tree().call_deferred("change_scene_to_file", FLOOR1_SCENE)

func _change_to_floor1() -> void:
	get_tree().change_scene_to_file(FLOOR1_SCENE)

## 黑场 + 层名：不靠图片，纯 CanvasLayer；黑场到 1 后换场景，floor1 自己再做淡入
func _build_hud() -> void:
	if get_node_or_null("GameHUD") != null:
		return
	var hud := GAME_HUD_SCENE.instantiate()
	hud.name = "GameHUD"
	add_child(hud)

## 篝火：放在祭坛之后、长廊台阶之前的地面中段，打完浅坑能补给一次再走
## 等一个物理帧再校准：`_apply_stage()` 是刚改完碰撞盒尺寸的，物理服务器还没刷新，
## 这时候打射线量到的是旧形状（祭坛那条射线会穿过平台直接打到 659 的地面，把祭坛按下去 85px）。
func _snap_props_deferred() -> void:
	await get_tree().physics_frame
	if is_inside_tree():
		_snap_props_to_ground()

## 摆在"地面/台面"上的东西（M5-31）：祭坛、火堆、尸体、铁剑、木桩甲。
## 木桩乙不在里面 —— 它是下劈反弹的踏板，本来就悬在方台前，落地就够不着台顶了。
const GROUNDED_PROPS := ["Altar", "Campfire", "Corpse", "WeaponPickup", "DummyA"]

## 把这些道具"视觉底边"精确贴到脚下地面上。
##
## 为什么不再手填 y：地形现在是岩体轮廓（顶边严格贴碰撞顶边，但每块图的视觉底边高低不一），
## 道具每挪一次位置、每换一次美术，手填的数字就会差两三像素 —— 看着就是"陷进去"或"浮着"。
## 这里统一量一次：往下打射线找到地面，再把道具自己的视觉最低点挪到那条线上。
func _snap_props_to_ground() -> void:
	var space := get_world_2d().direct_space_state
	for prop_name in GROUNDED_PROPS:
		var node := get_node_or_null(str(prop_name)) as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var pos := node.global_position
		var from := Vector2(pos.x, pos.y - 160.0)
		var ray := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 400.0), 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var surface := float(hit["position"].y)
		var bottom := _visual_bottom(node)
		if absf(bottom - surface) < 0.01:
			continue
		# 只改 y：横向由 STAGE 表管，别让校准把道具左右挪偏
		node.position.y += surface - bottom

## 一个节点（含所有子节点）在世界坐标下的最低点：Polygon2D 顶点、Line2D 顶点、Sprite2D 贴图底边
func _visual_bottom(root: Node2D) -> float:
	var worst := -1.0e9
	var stack: Array = [[root, root.global_transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform2D = item[1]
		for child in n.get_children():
			var t := xf
			if child is Node2D:
				t = xf * (child as Node2D).transform
			if child is Polygon2D:
				for p in (child as Polygon2D).polygon:
					worst = maxf(worst, (t * p).y)
			elif child is Line2D:
				for p in (child as Line2D).points:
					worst = maxf(worst, (t * p).y)
			elif child is Sprite2D:
				var sp := child as Sprite2D
				if sp.texture != null:
					var sz := sp.texture.get_size() * sp.scale
					var top_left := sp.position if not sp.centered else sp.position - sz * 0.5
					worst = maxf(worst, (t * (top_left + Vector2(0.0, sz.y))).y)
			if child.get_child_count() > 0:
				stack.append([child, t])
	return worst

func _build_campfire() -> void:
	var fire := CAMPFIRE_SCENE.instantiate()
	fire.name = "Campfire"
	# M5-22（组长反馈"火堆往前移，剧情受伤、剧情过了之后才遇到火堆"）：
	# 原来火在 4650、剧情触发点在它后面，等于先看见火、后挨打，教学顺序是反的。
	# 现在火挪到 4820（剧情和战斗之后），玩家是带着伤口走到火边的，才有"该回血了"的动机。
	fire.position = Vector2(CAMPFIRE_X, CAMPFIRE_Y)
	add_child(fire)

# ---------- 火堆前那一战（M5-18） ----------
##
## 组长定的教学节奏：走到火堆前方 → 过一段剧情 → 剧情末尾有东西扑上来咬你一口（固定掉 1 颗心）
## → 这时候才交还操作、开始打它 → 打完回火边歇一下学会回血。
##
## 为什么掉血放在"剧情末尾"而不是让怪物自己随机打：这一段的目的就是教"血会掉、火能补"，
## 掉血必须是确定发生的一次，不能看玩家闪不闪得开。
## 怪物就用史莱姆（同一套跳扑 AI），只是血加厚，算"稍简单的小 boss"：
## 它不会一招秒人，也不会放弹幕，代价是它就在悬崖边上 —— 打急了会被自己撞下去。
const BEAST_TRIGGER := Vector2(13300, 620)
const BEAST_SPAWN := Vector2(14000, 646)
## 篝火位置：必须在剧情和战斗之后（见 _build_campfire 的注释）
const CAMPFIRE_X := 16500.0
## 火堆的 y：地面 659 往下让 22px（石圈 + 石块自身的高度），不然会陷进地里
const CAMPFIRE_Y := 637.0
const BEAST_HP := 14
const BEAST_DIALOGUE := "tutorial_beast"
const CAMPFIRE_HINT := "血掉了。回火边歇一下（K）"
## 层门提示也用统一组件：和火堆/钟绳/守钟人长一个样（白字、黑描边、居中）
const InteractionPrompt := preload("res://components/interaction_prompt.gd")

var _beast: Node2D
var _beast_started := false
var _beast_killed := false
var _beast_hint: Label

## M5-36：场景刚挂进树时还在"装配子节点"，这时候 add_child 会被引擎拒绝
## （Parent node is busy setting up children）。等一帧再建触发区和史莱姆。
func _build_beast_encounter_deferred() -> void:
	await get_tree().process_frame
	if is_inside_tree():
		_build_beast_encounter()

func _build_beast_encounter() -> void:
	var area := Area2D.new()
	area.name = "BeastTrigger"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = BEAST_TRIGGER
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(90, 220)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player"):
			_beast_encounter())
	add_child(area)
	# M5-35（组长）：史莱姆一开始就站在前面。这里必须延迟生成 ——
	# 这个函数是在 _ready 装子节点的过程中被调用的，直接 add_child 会报
	# "Parent node is busy setting up children"
	_spawn_beast()

## M5-35（组长重新定的走线）：
##   ① 场景一开始，史莱姆就站在前面（不是走到触发区才刷出来）
##   ② 走到能看见它的时候触发这段旁白
##   ③ 旁白念完，它扑过来；真咬到玩家（掉血）之后，这段剧情才结束，然后提示玩家还手
##   ④ 打完再走 10 秒到火堆
func _beast_encounter() -> void:
	if _beast_started:
		return
	_beast_started = true
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_inside_tree():
		return
	# ② 先念旁白（对话会冻结场上的怪，所以这时候史莱姆只是站着）
	var dialogue := get_node_or_null("Dialogue")
	if dialogue != null and dialogue.has_method("play"):
		while is_instance_valid(dialogue) and bool(dialogue.call("is_playing")):
			await get_tree().process_frame
		if not is_inside_tree():
			return
		dialogue.call("play", BEAST_DIALOGUE)
		while is_instance_valid(dialogue) and bool(dialogue.call("is_playing")):
			await get_tree().process_frame
	if not is_inside_tree():
		return
	# ③ 念完把它挪到玩家跟前，让 AI 自己扑过来（真掉血才算这一下）
	if _beast != null and is_instance_valid(_beast) and is_instance_valid(player):
		(_beast as Node2D).global_position = Vector2(
			player.global_position.x - 150.0, player.global_position.y)
	var hp_before := int(player.get("hp"))
	while is_instance_valid(player) and is_inside_tree():
		if int(player.get("hp")) < hp_before:
			break
		await get_tree().process_frame
	if not is_inside_tree():
		return
	# 咬到之后才交还操作，并提示玩家还手
	_show_beast_fight_hint()

## 咬到之后挂在玩家头顶的一句提示（和火堆那句同一个样式，但只挂 4 秒）
func _show_beast_fight_hint() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var label := Label.new()
	label.name = "BeastFightHint"
	label.text = "它在咬你 —— 砍它（J）"
	label.size = Vector2(320, 24)
	label.position = player.global_position + Vector2(-160.0, -90.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.60, 0.95))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	add_child(label)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.queue_free())

func _spawn_beast() -> void:
	if _beast_killed or not is_inside_tree():
		return
	var beast := SLIME_SCENE.instantiate()
	beast.name = "CaveBeast"
	beast.position = BEAST_SPAWN
	add_child(beast)
	beast.set("hp", BEAST_HP)
	_beast = beast
	# 用 tree_exited 而不是每帧比对空指针：节点被 queue_free 之后，
	# 手里的引用会变成一个"已释放对象"，拿它和 null 比不一定为真 —— 提示就可能永远不出现。
	# tree_exited 在节点真正离开场景树时发一次，这时候还能判断、也只发一次。
	beast.tree_exited.connect(_on_beast_gone)

## 怪死了（被打死或者自己掉进悬崖）：在火堆上方挂一句提示，把玩家领回火边。
func _on_beast_gone() -> void:
	# tree_exited 会随节点释放只发一次，但角色死亡/切场景也会走到这里，多一道保险
	if _beast_killed:
		return
	_beast_killed = true
	_beast = null
	# M5-36：关卡本身正在被拆（切场景/退出）时，不能再往里面挂提示 ——
	# 那会让引擎报 "Parent node is busy setting up children"，玩家反正也看不到
	if not is_inside_tree():
		return
	if _beast_hint != null and is_instance_valid(_beast_hint):
		return
	var label := Label.new()
	label.name = "CampfireHint"
	label.text = CAMPFIRE_HINT
	label.position = Vector2(CAMPFIRE_X - 160.0, 520.0)
	label.size = Vector2(320, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.60, 0.95))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	var hint_font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if hint_font != null:
		label.add_theme_font_override("font", hint_font)
	add_child(label)
	_beast_hint = label

## 从序章的黑场接进来：整屏先黑，再慢慢亮起（序章结尾已渐黑，这里保证两幕之间没有硬切）
func _build_fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FadeIn"
	layer.layer = 4
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "Black"
	rect.color = Color(0.0, 0.0, 0.0, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tw := create_tween()
	# M4-25：从虚空掉下来时黑场退得慢一些（1.6s），让人看清自己是从上面砸下来的；
	# 正常进关还是 0.15s 黑 + 0.95s 淡出。
	if _drop_in:
		tw.tween_interval(0.35)
		tw.tween_property(rect, "color:a", 0.0, 1.65)
	else:
		tw.tween_interval(0.15)
		tw.tween_property(rect, "color:a", 0.0, 0.95)
	tw.tween_callback(layer.queue_free)

func _build_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FloorTransition"
	_fade_layer.layer = 4
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color(0.015, 0.020, 0.024, 1.0)
	_fade_rect.modulate = Color(1, 1, 1, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)
	_fade_label = Label.new()
	_fade_label.name = "FloorName"
	_fade_label.text = "第一层 · 锈钟回廊"
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.modulate = Color(0.72, 0.88, 0.86, 0.0)
	_fade_label.add_theme_font_size_override("font_size", 22)
	_fade_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fade_label.position = Vector2(-150, -20)
	_fade_label.size = Vector2(300, 40)
	var font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
	if font != null:
		_fade_label.add_theme_font_override("font", font)
	_fade_layer.add_child(_fade_label)

func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

## 生成史莱姆（教程战斗步骤调用；可重复调用会叠加，调用方保证只调一次）
func spawn_enemies() -> void:
	_combat_started = true
	var points: Array = STAGE["slimes"]
	for i in range(points.size()):
		var slime := SLIME_SCENE.instantiate()
		slime.position = points[i]
		slime.name = "Slime%d" % (i + 1)
		add_child(slime)

func _play_intro_dialogue() -> void:
	if _refusing:
		return
	# Dialogue 是挂 dialogue.gd 组件的普通 Node，用 call() 动态调用，
	# 避免静态类型检查把 play() 当作 Node 上不存在的方法报错
	var dialogue := get_node_or_null("Dialogue")
	if dialogue != null and dialogue.has_method("play"):
		dialogue.call("play", TRUE_HE_RETURN_DIALOGUE if _true_he_mode else INTRO_DIALOGUE_ID)

## 真 HE 二周目：教学已完成过，只开全部门、给剑、在起点放一块骨片。
## 不再走 Tutorial 状态机，避免玩家被“走到光点”重新锁一遍。
func _setup_true_he_return() -> void:
	_true_he_mode = true
	GameManager.current_floor = "start"
	if _tutorial != null:
		_tutorial.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := get_node_or_null("ObjectiveHUD")
	if hud != null:
		hud.visible = false
		if hud.has_method("hide_bubble"):
			hud.call("hide_bubble")
	# 二周目不重新走门：全开，玩家能直接跑到祭坛
	for gate_id in TUTORIAL_GATE_HEIGHTS.keys():
		_open_tutorial_gate(str(gate_id))
	var player := get_node_or_null("Player")
	if player != null:
		player.set("has_weapon", true)
	var sword_ground := get_node_or_null("WeaponPickup")
	if sword_ground != null:
		sword_ground.queue_free()
	if not GameManager.has_flag("true_he_relic"):
		var holder := Node2D.new()
		holder.name = "TrueHEProps"
		add_child(holder)
		_relic = ORIGIN_RELIC_SCENE.instantiate()
		_relic.name = "OriginRelic"
		_relic.position = TRUE_HE_RELIC_POS
		holder.add_child(_relic)

## M1-07：新手祭坛的拒绝出口。只有“手里有肢体、还没献祭、教程未完成”时才生效，
## 避免在普通祭坛/已完成教学/真 HE 里误触。
func _on_refuse_requested() -> void:
	if _refusing or _true_he_mode or _tutorial == null:
		return
	if bool(_tutorial.call("is_completed")):
		return
	if int(GameManager.sacrifice_count) > 0:
		return
	if int(GameManager.monster_limb_count) <= 0:
		if _altar != null and _altar.has_method("show_no_limb"):
			_altar.call("show_no_limb")
		return
	_refuse()

func _refuse() -> void:
	_refusing = true
	if _altar != null and _altar.has_method("set_refuse_allowed"):
		_altar.call("set_refuse_allowed", false)
	if _tutorial != null:
		_tutorial.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := get_node_or_null("ObjectiveHUD")
	if hud != null:
		hud.visible = false
		if hud.has_method("hide_bubble"):
			hud.call("hide_bubble")
	_dialogue.call("play", "refuse_die")
	await EventBus.dialogue_finished
	if not is_inside_tree():
		return
	var fade := create_tween()
	fade.tween_property(_fade_rect, "modulate:a", 1.0, 0.65)
	await fade.finished
	if not is_inside_tree():
		return
	GameManager.set_flag("refuse_die")
	GameManager.set("state", GameManager.GameState.ENDING)
	EventBus.ending_reached.emit("refuse_die")
	EventBus.log_event("ending_reached", {"ending": "refuse_die", "sacrifice_count": GameManager.sacrifice_count})
	if _ending_screen == null:
		_ending_screen = ENDING_SCENE.instantiate() as CanvasLayer
		add_child(_ending_screen)
		_ending_screen.restart_requested.connect(_restart_from_refuse)
	_ending_screen.call("show_ending", "refuse_die")

func _restart_from_refuse() -> void:
	_refusing = false
	GameManager.start_new_game()
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func show_true_he() -> void:
	if _true_he_shown:
		return
	_true_he_shown = true
	GameManager.set("state", GameManager.GameState.ENDING)
	EventBus.ending_reached.emit("true_he")
	EventBus.log_event("ending_reached", {"ending": "true_he", "sacrifice_count": GameManager.sacrifice_count})
	if _ending_screen == null:
		_ending_screen = ENDING_SCENE.instantiate() as CanvasLayer
		add_child(_ending_screen)
		_ending_screen.restart_requested.connect(_restart_from_true_he)
	_ending_screen.call("show_ending", "true_he")

func _restart_from_true_he() -> void:
	_true_he_shown = false
	GameManager.start_new_game()
	get_tree().change_scene_to_file("res://scenes/world/test_arena.tscn")
