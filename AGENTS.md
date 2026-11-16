# AGENTS.md

## 一、Git

这个项目可以直接推 main。main 不受保护，正常改动直接推，方便组里同学随时看到最新版本。

大改动或者可能改坏的东西，先开一个备份分支再动手，名字按日期起，比如 backup/local-20261116，然后推上去。

提交信息写 `类型: 干了啥`，类型用 feat / fix / docs / chore。删别人文件、强推之前先说一声。

## 二、目录

| 目录 | 放什么 |
|---|---|
| `client/` | Godot 4.7 游戏本体 |
| `client/scenes/` | `.tscn`：main（主菜单）、world（序章+三层）、player、entities、items、ui、audio |
| `client/scripts/` | `.gd` 逻辑，按归属分：world、player、entities、items、ui、audio |
| `client/components/` | 跨场景复用的零件：对话、交互提示、美术底座、教程、魂模型、粒子 |
| `client/autoload/` | 全局单例：EventBus、GameManager、DataDB、SaveSystem、Settings、Network |
| `client/data/` | 生成物（SQL 导出的 JSON），**禁止手改** |
| `client/assets/` | art/player（主角 7 张分层图）、audio（全部 wav）、fonts、shaders |
| `client/tests/` | `*_test.gd` 无头回归；`*_shots.gd` 截图探针（不进回归） |
| `client/shots/` | 开发期截图 |
| `server/` | FastAPI 后端：app/（main/models/db/config）、tests/ |
| `database/` | game_data（schema.sql + seed.sql，**数值唯一真源**）、migrations（服务端迁移） |
| `tools/` | data（数据管道）、audio（音频生成与体检）、report（文档转换）、tests |
| `doc/` | 交付文档 00–07、需求分析文档、class1/2/3、CHANGELOG |
| `share/` | 技术分享材料 |
| `deploy/` | docker-compose、Dockerfile、nginx、证书 |
| `scripts/` | 本机脚本：test_all.ps1、setup、run_server、导出与备份 |
| `art/` `backups/` `tmp/` | 美术源文件占位 / 数据库备份 / 临时产物（tmp 不进库） |

## 三、代码分类

| 类型 | 特征 | 放哪 |
|---|---|---|
| 单例 | 全场唯一、大家都要用 | `autoload/` |
| 关卡 | 一场景一主脚本，搭地形、放怪、串剧情 | `scripts/world/` |
| 实体 | 会动、会挨打、会掉东西 | `scripts/entities/` |
| 道具 | 摆着不动、交互才响应 | `scripts/items/` |
| 界面 | 只画不改状态 | `scripts/ui/` |
| 组件 | 多场景复用的零件 | `components/` |

判断标准：只有一关用 → 进那个关卡的脚本；两关以上用 → 抽到 `components/`。

## 四、怎么写

- 命名：文件 `snake_case`，节点 `PascalCase`，私有变量 `_snake`，常量 `UPPER_SNAKE`；信号写 `<主体>_<过去式>`（`player_hurt`、`sacrifice_done`）。
- 注释只写"为什么这么写"：踩过的坑、组长定的规矩、为什么不用另一种写法。数字写清单位和出处。
- 数值不许写死：血量、伤害、时长、距离、手感一律进 `database/game_data/seed.sql`，改完跑 `python tools/data/build_game_data.py` → `python tools/data/db_export.py`。
- 取节点用 `@onready` 或 `get_node_or_null`；中文字体必须显式 `load("res://assets/fonts/NotoSansCJKsc-Regular.otf")`；世界提示统一用 `components/interaction_prompt.gd`；运行时 new 出来的地形/道具 `z_index` 要压在玩家后面（玩家是 0）。
- 输入只认按下沿（`pressed` 且 `not is_echo()`），每个输入逻辑配一条反向测试。
- 跨模块走 `EventBus` 信号；状态（楼层、旗标、献祭数、武器）只放 `GameManager`。
- `.tscn` 里 `Color(...)` 必须 4 个分量；关卡布局数字集中在脚本的 `STAGE`/`PLATFORMS` 表，改布局只改表。

## 五、加新东西

- 剧情：`seed.sql` 的 `dialogues` 插一行 → 跑数据管道 → 代码 `dialogue.play("新 id")`。台词不进代码。
- 敌人：`scenes/entities/` 建场景 + `scripts/entities/` 写脚本，挂 `damageable`/`enemy` 组、实现 `take_damage()`/`get_hp()`，在关卡刷怪表登记坐标。
- 交互：抄 `bell_mechanism.gd` 或 `inspect_point.gd`，`Area2D` + `interaction_prompt.gd` + 只认 K 的按下沿 + 一条 `*_test.gd`。
- 音效：`tools/audio/generate_audio.py` 的 SFX_TABLE 和 `scripts/audio/audio_director.gd` 的 SFX_NAMES 两边同时加，再 `GameManager.play_sfx("名字")`。
- 美术：源图进 `art/`，分层图进 `client/assets/art/player/`，`knight_body.tscn` 里按"后→前"挂 Sprite2D，`centered=false`、`scale=0.1458`。

## 六、怎么验

```powershell
.\scripts\test_all.ps1 -GodotExe "D:/Applications/Development/Tools/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
```

串三件事：数据管道 + 后端 pytest + 每个 `client/tests/*_test.gd` 单开一次 headless Godot，看到 `==> 全部通过` 才算完。

- 断言不数帧（headless 帧率不受限），等时间用 `create_timer`。
- 视觉断言查节点状态（z_index、visible、坐标、常量），不查像素。
- 量坐标、算亮度这类数值探针比读截图快，也别靠眼睛猜。

## 七、坑

1. `.gd` 别用 PowerShell 的 `Get-Content | Set-Content` 改，中文会变乱码；用编辑工具或 Python。
2. `.ps1` 必须是 UTF-8 **带 BOM**，否则 PowerShell 5.1 按 ANSI 读，中文注释变乱码、整个脚本语法错。
3. 对话开播会冻结"已经在场的 enemy"：boss 要先出场再念旁白，不能反过来。
4. 开场黑幕算亮圈只用 UV，不用 `FRAGCOORD`（渲染目标坐标，窗口一放大就对不上）。
5. 提示别堆在同一点，两行会叠；深色背景下字号别低于 10。

## 八、分享材料

`share/` 下的 PPT、演讲稿、演示手册，按这几条来。

- 大标题用一个词：现状、问题、流程、坑、职责、取舍、代价、实测、结论、演示。写成主题词，不写整句，也不写问句。
- 标题下不写小字解释。要想说的话，放到正文里当正文。
- 尽量不用表格。用列表、阶梯、对照行、大数字，靠字号和留白分层。
- 白底深字，只用一个主色做竖线和强调，不加投影、渐变、第二种装饰色。
- 数字必须来自实测或仓库里的配置，不编。每句话要么是事实，要么是能对着代码指出来的做法。

