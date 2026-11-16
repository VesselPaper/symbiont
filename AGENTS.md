# AGENTS.md —— 共生之缚 项目记忆

> 给接手这个仓库的 agent / 人看的。**先读这一份，再动代码。**
> 课程层的规范在 `软件工程课程/AGENTS.md`（老师要求、文档放哪）；这一份是**仓库自己的**：怎么改、怎么测、坑在哪。

## 一、这是什么

Godot 4.7.2 制作的横版动作探索游戏（Hollow Knight 风格）+ FastAPI/MySQL 后端 + docker 全栈，软件工程课程设计（2 组）。

```
symbiont/
├─ client/        Godot 4.7.2 客户端（主战场）
│  ├─ scenes/     .tscn 场景
│  ├─ scripts/    .gd 逻辑
│  ├─ components/ 可复用组件（交互提示、对话、美术底座、教程…）
│  ├─ autoload/   GameManager / EventBus / SaveSystem / Settings / Network
│  ├─ data/       ⚠️ 生成物，禁止手改（改 SQL 再重新导出）
│  ├─ tests/      *_test.gd 无头回归（不进游戏，只跑断言）
│  └─ assets/     字体、音效、美术
├─ server/        FastAPI 后端 + pytest
├─ database/      schema.sql + seed.sql + game_data（游戏数值的唯一真源）
├─ tools/         数据管道（build_game_data.py / db_export.py）、测试工具
├─ doc/           老师要的七份文档（00–07）
├─ share/         技术分享材料（报告 docx/图）
└─ scripts/       test_all.ps1 全量回归入口
```

## 二、Git 规矩（组长定的，和课上写的那份不一样，以这里为准）

- **可以直接推 main。** 组长明确说过 main 不受保护、正常改动直接进 main，方便同组同学随时看到最新版本。
- **但"直接推 main"不等于"在 main 上乱改"**：
  - 大改/危险改动（美术重做、动画系统、存档格式、剧情大段重写）仍然开 `feature/<卡号>-<简述>`，改完再合回 main。
  - 每次合之前先跑 `scripts/test_all.ps1`，**全绿才推**。
  - 本地改坏了要留退路：动大手术之前先 `git branch backup/local-YYYYMMDD`，并 `git push -u origin backup/local-YYYYMMDD`。现有备份：`backup/local-20261114`、`-1115`、`-1116`。
- **提交信息**：`类型: 干了啥`，类型用 `feat` / `fix` / `docs` / `chore`，括号里写模块或里程碑。
  - 好：`fix(arena): 开场蒙版重新对齐角色、提示文字缩小下移（M5-22）`
  - 坏：`更新`、`修一下`
- **提交/推送/删文件前先说一声**（组长要能预见 diff 里出现什么）。删旧美术、删旧脚本这类，点名确认后再删。
- 别强推（`--force`）、别改写别人已经推上去的提交。

## 三、工作方式

- **一次只做一张任务卡**：实现 → 无头验证 → 合入 → 组长 F5 试玩说「通过」→ 才开下一张。
- **手感、剧情、数值、范围不自己拍板**。拿不准就停下来问；能先给出"我按 X 理解的，对不对"再动手比闷头改完强。
- 说人话、大白话，不要 AI 味；注释写「**为什么这么写**」，不写"这里赋值"这种废话。

## 四、工程规范（踩过的坑都在里面）

1. **数值不写死进代码**：跑速、血量、时长、伤害等进 `database/game_data/seed.sql`（或对应 json），改完跑：
   ```powershell
   python tools/build_game_data.py
   python tools/db_export.py        # 重新生成 client/data/*，别手改
   ```
2. **`client/data/*` 是生成物**，手改会在下次导出时被覆盖。
3. `doc/02-系统接口设计文档.md` 是接口唯一权威，改了 API 必须同步。
4. **输入触发的逻辑要做反向测试**：只认按下沿、不认抬起/长按 echo/其它键（仓库里所有交互都这么写）。
5. `.tscn` 里写 `Color(...)` 必须 **4 个分量**，3 个会解析失败。
6. **不要用 PowerShell 文本管道改 `.gd`**：会破坏 UTF-8 中文（`Get-Content -Raw ... | Set-Content` 尤其危险）。改代码用编辑工具/写文件，别 cat -replace。
7. 中文字体必须显式加载 `res://assets/fonts/NotoSansCJKsc-Regular.otf`，否则渲染成方块。
8. 世界空间的 UI（提示/门牌）用 `components/interaction_prompt.gd`，不要各处自己 new Label。
9. 运行时 new 出来的地形/道具，**z_index 要压到玩家后面**（玩家是 0），否则会把角色盖住（M5-19 踩过）。
10. 对话（`components/dialogue.gd`）开播时会**冻结已有的 enemy**：要"先放 boss 再念旁白"，反过来念完再放，boss 会边念边砸人（M5-16 踩过）。
11. `test_arena.gd` 里的开场黑幕**只用 UV 算距离**，不要用 `FRAGCOORD`：它是渲染目标坐标，窗口一放大就和 1280×720 的逻辑坐标打架（M5-21 踩过）。

## 五、怎么测（提交前必跑）

```powershell
cd 项目/symbiont
.\scripts\test_all.ps1 -GodotExe "D:/Applications/Development/Tools/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
# 全绿会打印 ==> 全部通过（退出码 0）
```

它串三件事：数据管道（build_game_data + db_export + tools/tests）→ 后端 pytest → **每个 `client/tests/*_test.gd` 单独起一次 headless Godot**。
单张测试可以这样跑：
```powershell
$env:SYMBIONT_NETWORK_OFF='1'; $env:SYMBIONT_NO_AUTOSAVE='1'
& "D:/.../Godot_..._console.exe" --headless --path client --script res://tests/void_transition_test.gd
```
- `SYMBIONT_NETWORK_OFF=1` 断网侧埋点、`SYMBIONT_NO_AUTOSAVE=1` 不写存档——不加会污染本机存档/真实数据库。
- **断言里不要数帧**：headless 帧率不受限，等时间用 `create_timer` 轮询。
- 视觉类断言检查**节点状态**（z_index、visible、位置、常量），不要检查像素。

## 六、当前状态快照（2026-11-16，M5 这轮之后）

已完成并全绿（70 张头测）：

- **开场**：虚空坠落 → 落地缓冲 3.5s → 6.5s 照亮，合计 10 秒才进剧情；黑幕亮圈钉在角色身上（UV 版 shader）。
- **教学关**：长廊下方挖成悬崖（跳四块石台过河，掉下去判死）；地形装饰铺满全图（美术层改成关卡铺完再画）。
- **火堆**：按 K 原地不动、只回 1 颗心、烧完自己慢慢熄灭；位置 4820（在剧情和战斗之后）。
- **火堆前那一战**：走到 4520 触发 `tutorial_beast` 旁白 → 固定掉 1 颗心 → 出 14 血洞穴怪 → 打完火堆上方提示回血。
- **层门**：走到门前按 K 进第一层，提示用统一交互样式（z=40）。
- **钟绳**：先和守钟人聊过（`floor1_watchman_talked` 旗标）才能拉；钟厅那座篝火删掉。
- **死亡**：头盔按射线落地（脚下是悬崖就跟着掉、出画面淡掉）；血量 ≤1 屏幕四周黑雾 + "血量危险"。
- **祭坛**：第一层调查点删掉；教学关祭坛常驻提示关掉（只留教程那行）；献祭不再从角色身上长肢体。
- **关底**：灵魂聚合体战前播 `floor1_soul_boss`（顺序：先放 boss 再播）；模型重做（三层魂壳 + 绕飞魂片 + 魂须）；血条靠近才显、走远重置。
- **战斗**：按住攻击不再连刀（按下沿闩）、空中攻击 0.34s 后摇、下劈命中加剑魂特效。
- **存档**：ESC 菜单可返回主菜单；单存档默认（只认 1 号槽），多存档可切、可命名。
- **怪物**：史莱姆追击会探崖边（不追对岸、不跳坑）、怪掉悬崖即死、尸体/肢体落地面（探不到地面就不生成）。

## 七、还没做（按优先级）

1. **教学关扩容**：文档说这是最大缺口（实测 6250px ≈ 20 多秒，目标 10 分钟）。`client/tests/estimate_playtime.gd` 里还写死 `RUN_SPEED := 300`，实际是 250，估时偏短。
2. **技术分享 PPT**：材料齐了（`share/应用代理与负载均衡-技术报告.docx` + fig1/fig2），PPT 还没做。
3. **灵魂模型统一**：`client/components/soul_visual.gd` 是共用件，序章还在用自己的 `_build_soul`，两份会漂移。
4. **`POST /auth/bind`**：`users` 表已支持匿名行升级，只差接口。
5. **文档同步**：`doc/02-系统接口设计文档.md` 自 M4-58 没更新；`软件工程课程/doc/agent交接文档/交接文档1.md` 的 §8.1/§8.4/§11 常量表全过期了（RUN_SPEED、CAMERA_ZOOM、序章时长、`INTRO_*` 都变了）。
6. **数值进数据表**：跑速 250、镜头 12 倍身高、死亡 1.15s 这些还在代码里，按规范该搬进 `database/game_data`。

## 八、别碰的东西

- `client/components/shadow_mass.gd`、`client/tests/shadow_*.gd`、`tmp_growth_*.gd`、`tmp_shadow_watch.gd` —— 是**别的成员**在做的东西，不是这条线的活儿，别改别删别提交。
- `tmp_*.gd` 是我做验证时留的探针（`tmp_intro_shot` / `tmp_art_check` / `tmp_floor1_shot` / `tmp_hole_center`），**不是 `*_test.gd`，不进回归**。要删先问。

## 九、验证习惯（省 token 也省时间）

- 改完先跑**相关的那几张**测试，再整轮 `test_all.ps1`；整轮要几分钟，别每改一行就跑一遍。
- 别为了"看一眼"去读整张截图——用数值探针（算像素质心、量节点坐标）比看图快得多，也更不容易骗自己。
- 真要截图给人看，存 `client/shots/`，说清楚是哪一版、哪个坐标拍的。
