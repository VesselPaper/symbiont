# 关卡与叙事改动汇总（本轮交付）

> 范围：`client/` 下的关卡、剧情、交互与手感改动；不含美术素材新增。
> 验证基线：56 张 GDScript 无头测试全绿（原 55 张 + 新增篝火 1 张），6 个场景冒烟退出码 0。

---

## 一、逐项状态

| # | 需求 | 状态 | 落点 |
|---|---|---|---|
| 1 | 坑边灰色矩形（无碰撞却像平台） | 完成 | `components/arena_art.gd` 远景断柱压暗 0.190→0.105，轮廓光减弱 |
| 2 | 教学关史莱姆只留一只 | 完成 | `scripts/world/test_arena.gd` → `STAGE["slimes"]` 单点 |
| 3 | 怪物之间防完全重合 | 完成 | `scenes/entities/slime.tscn` collision_mask 1→5 |
| 4 | 空中死亡尸体/掉落物悬空 | 完成 | `scripts/entities/slime.gd` 死亡时向下射线探地（1200px）后落位 |
| 5 | 蒸汽靴改为工程师处获得 | 完成 | 宝箱从教学关移到 `floor2.gd` 锅炉房工作台右侧（1330, 640） |
| 6 | 工程师前架子悬空 | 完成 | `floor2.gd` 工作台桌面 42→32px、腿加粗并插入地面 |
| 7 | 地图物件间距拉开 | **部分完成** | 教学关横向整体 ×1.25（5000→6250）；三层遭遇点重新铺开；二/三层静物布局未整体拉开 |
| 8 | 祭坛对话时有时无 + 数量过多 | 完成 | `items/altar.gd` 低语最多等 3 秒补播；第二层祭坛移除（3→2 座） |
| 9 | 教程提示剧情化、非"按 X 键" | 完成 | `components/tutorial.gd` 八环全部改为寄生体低语短句 |
| 10 | 每层约 20 分钟 | **未完成** | 需真人试玩数据校准；已内置计时埋点 |
| 11 | 按新剧情重构 | 完成 | 序章、三段结局文案、深渊终章、结局链路 |

---

## 二、重点改动说明

### 剧情链路

```
主菜单 → 序章（虚无中苏醒 / 触碰黑色身影 / 获得躯体）
      → 教学关（献祭肢体换取感知）
      → 第一层 · 锈钟回廊 → 第二层 · 铸炉与圣坛 → 第三层 · 守门者之厅
      → 击败守门者
      → 异化结局（假结局：畸变重塑成新的守门者）
      → 按 K 坠入深渊
      → 深渊终章（心跳节奏对抗，顶回去 7 次）
      → 真结局（夺回身体，变回普通人）
```

- 序章：`scenes/world/prologue.tscn`，`CanvasModulate` 压暗 + 灵魂自带 `PointLight2D` 形成"小视野"；背景有冷色渐变天空、三座断拱、贴地冷雾与尘埃。
- 深渊终章：`scenes/world/abyss.tscn`，解剖学心脏（左右心室、左右心房、主动脉弓、肺动脉干、上腔静脉、冠状血管）。
- 结局文案：`data/endings/*.json` 已按新剧情重写。

### 篝火

- `scenes/world/campfire.tscn` + `scripts/world/campfire.gd`，四张地图各一座，位于中段且避开敌人刷新点：

| 关卡 | 坐标 |
|---|---|
| 教学关 | (4650, 659) |
| 第一层 | (2500, 760) |
| 第二层 | (2500, 600) |
| 第三层 | (2300, 620) |

- 交互：站入范围按 K 休息 → 回满血；满血时提示「火光很暖。你歇了一会儿。」
- 动画三段：放剑（0~0.35s）→ 坐下（至结束前 0.75s）→ 抓剑撑地起身；按方向键可立刻起身。
- 视觉：石圈、交叉柴堆、四层火舌（暗红/橙/亮橙/白芯）、上升火星、会呼吸的暖光。

### 战斗手感

- 只按 J：仅前方横砍（地面与空中一致）。
- 按住 S + J：地面为原地朝下劈；空中进入下劈判定，**不再强制加速下坠**。
- 空中挥砍**不再钉脚**，保留水平惯性（无后坐力）。

### 灵魂形态

- `components/soul_flame.gd`：三片错相位的白色火舌 + 上升火星，循环"升起→拉长变淡→熄灭"；融合瞬间调用 `set_rise(1.9)` 让火焰暴涨。

### 节奏埋点

- `autoload/game_manager.gd`：`mark_floor_start(id)`、`floor_seconds`、`current_floor_seconds()`。
- 换层时打印：`[pacing] floor1 用时 812.4 秒（13.5 分钟）`，同时写 `floor_time` 事件。

---

## 三、新增文件

| 文件 | 用途 |
|---|---|
| `client/scenes/world/prologue.tscn` | 灵魂序章场景 |
| `client/scenes/world/abyss.tscn` | 深渊终章场景 |
| `client/scenes/world/campfire.tscn` | 篝火 |
| `client/scripts/world/prologue.gd` | 序章逻辑与美术 |
| `client/scripts/world/abyss.gd` | 终章心跳对抗 + 解剖学心脏 |
| `client/scripts/world/campfire.gd` | 篝火交互与火焰 |
| `client/components/soul_flame.gd` | 灵魂火焰状消逝 |
| `client/tests/campfire_test.gd` | 篝火回归（四层位置/落地/回血/满血不重复） |
| `client/tests/prologue_shots.gd` `abyss_shots.gd` `campfire_shots.gd` | 开发用截图脚本 |

---

## 四、验证

```powershell
# 全量回归（56 张）
$exe = "D:\Applications\Godot\Godot_v4.7.2-stable_win64_console.exe"
Get-ChildItem client\tests\*_test.gd | ForEach-Object {
    & $exe --headless --path client --script ("res://tests/" + $_.Name)
    if ($LASTEXITCODE -ne 0) { Write-Host "FAIL $($_.Name)" }
}

# 场景冒烟
foreach ($s in "prologue","test_arena","floor1","floor2","floor3","abyss") {
    & $exe --headless --path client "res://scenes/world/$s.tscn" --quit-after 60
}

# 截图
& $exe --path client --script res://tests/prologue_shots.gd
& $exe --path client --script res://tests/abyss_shots.gd
& $exe --path client --script res://tests/campfire_shots.gd
```

结果：56/56 通过；6 个场景冒烟退出码 0；截图见 `client/shots/`。

---

## 五、仍需你确认 / 参与

1. **每层 20 分钟**：请正常玩一遍，把控制台打印的四层分钟数发我；不足的层我按缺口加路段或加密遭遇。
2. **祭坛数量**：现为「教学关 + 第一层」两座，第二层已移除；第三层要不要再补一座？
3. **下劈下落手感**：去掉强制下坠后，从高处下劈会比以前慢；需要的话我可以改成"比重力快 30%"的柔和加速。
4. **二/三层静物间距**：目前只加密了遭遇点，静物（拱门、烛台、货梯）没有整体拉开——需要的话我按教学关那套 ×1.25 的方式重排。
