# 共生之缚 Symbiont

类恶魔城（Metroidvania）2D 游戏 —— 软件工程课程设计项目（2 组，自主选题）。

无魔法、蒸汽时代、神明存在的深渊地牢里，一名普通骑士在"献祭获得力量"与"守住人性"之间抉择。
自下而上探索固定三层地牢：献祭流（收集怪物肢体 → 祭坛献祭 → 部位改造）与探索流（钩锁、二段跳、武器升级）双路线并存；
第二层在异教徒与工程师之间二选一，决定成长分支；结局按献祭次数结算（人类 / 异化 / 真结局 HE）。

## 一、目录

- [一、目录](#一目录)
- [二、技术架构](#二技术架构)
- [三、快速开始](#三快速开始)
- [四、团队协作：成员同步与提交指南](#四团队协作成员同步与提交指南)
- [五、项目结构](#五项目结构)
- [六、致谢（第三方资产）](#六致谢第三方资产)

## 二、技术架构

```
┌─────────────────────────────────────────────────────────┐
│  client/  Godot 4.7 客户端（纯 GDScript）                │
│  autoload 单例: EventBus / GameManager / DataDB /        │
│  SaveSystem / Settings / Network（离线优先）             │
│  scenes / scripts / components / data(JSON)              │
└───────────────┬───────────────────────┬─────────────────┘
                │ REST (离线队列)         │ JSON 数据读取
                ▼                       ▼
┌────────────────────────┐   ┌────────────────────────────┐
│  server/ FastAPI 后端   │   │  client/data/*.json         │
│  MySQL: 账号/远程存档/   │   │  (由 database 生成，勿手改)  │
│  统计埋点/排行榜         │   │            ▲                │
└───────────┬────────────┘   │            │ tools/data/db_export.py
            │                │            │
┌───────────▼────────────┐   │  ┌─────────┴────────────────┐
│  deploy/ docker-compose │   │  │  database/game_data/     │
│  mysql8 + server +      │   └──│  SQLite 游戏内容库        │
│  game-web(nginx)        │      │  (schema.sql/seed.sql)   │
└─────────────────────────┘      └──────────────────────────┘
```

**数据驱动**：游戏静态数据源在 `database/game_data`（SQLite，schema+seed 即课程"数据库脚本文件"），
经 `tools/data/db_export.py` 导出为 `client/data/*.json`，运行时由 `DataDB` 单例加载。改数据 = 改 SQL → 重新导出，不碰代码。

**课程交付**：`doc/` 下 00–07 七份文档对齐老师要求（功能分析/接口设计/详细设计/部署文档/操作说明/源文件说明/数据库脚本）。

## 三、快速开始

怎么打开游戏玩：

1. 打开 Godot 软件（如果电脑上没装，见下面"团队协作"一节的第 1 步，运行一次 `scripts\setup.ps1` 就会自动装好）
2. 在 Godot 的项目管理器里点"导入"，找到项目里的 `client\project.godot` 文件，点确定
3. 点运行按钮（▶，在窗口上方），或直接按 **F5**，游戏就启动了

就这 3 步，其他都不用管。

想跑回归测试：在项目根目录运行 `scripts\test_all.ps1`（55 张 Godot 无头测试 + 后端 pytest + 数据管道）。

当前可玩内容：新手教学（八环：移动 → 跳跃 → 拿剑 → 攻击 → 下劈 → 战斗 → 拾取肢体 → 献祭）→ 第一层「锈钟回廊」（入口 / 钟厅 / 台阶 / 祭坛厅 / 层门）→ 第二层（铸炉与圣坛，NPC 二选一、封印门）→ 第三层（守门者之厅，Boss 与两种结局；入口旧货梯可回起点走真 HE）。只想看第一层，在教学关里按 F2 直接跳过去。角色有待机/走路/跳跃/挥砍/下劈/受击/倒地/复活动作；史莱姆、木桩、祭坛、铁剑、尸体和关卡装饰都是代码建模，音频由 `tools/audio/audio_synth.py` 合成。教学提示是刻在地图上的路标，做完会变暗留在原地。

## 四、团队协作：成员同步与提交指南

代码都放在 GitHub 上。组员只需要记住两句话：**开工前先更新本地，干完活提交上去**。照着下面的步骤复制命令就行。

> 小组约定：**小改动可以直接推 main**（main 没有分支保护，方便大家随时看到最新版本）。美术重做、动画系统、存档格式、剧情大段重写这类大改，先开分支或备份分支，跑完全量回归再合回 main。规矩写在根目录 [`AGENTS.md`](AGENTS.md)。

### 第一次（每人只做一次）：把项目下载到电脑

1. 打开电脑上的"命令提示符"（开始菜单搜 cmd）或 PowerShell
2. 运行下面这行命令，回车（会自动把整个项目下载到当前文件夹）：

```
git clone https://github.com/VesselPaper/symbiont.git
```

3. 如果提示"git 不是内部或外部命令"：先到 https://git-scm.com 下载安装 Git（一直点下一步装完），再重开一个窗口重新运行
4. 进入项目文件夹并初始化环境：

```
cd symbiont
scripts\setup.ps1
```

5. 打开 `client/project.godot`，按 F5 就能运行游戏

⚠️ 如果你的电脑上**已经有一个旧版本的 symbiont 文件夹**：不要在里面改东西，直接删掉它，再按上面第 1 步重新 clone 一份新的。

### 每次开工前：更新本地仓库（把线上最新代码拉到电脑）

在项目文件夹里运行：

```
git pull
```

看到 `Already up to date` 就是已经最新，看到 `Updating` 就是在更新。

### 干完活：提交

小改动（改个数值、修个提示、补一句台词）：直接在 main 上提交推送就行。

```
git checkout main
git pull
git add .
git commit -m "fix: 写一句话：你这次改了啥，比如：改了火堆回血提示"
git push
```

大改动（美术重做、动画系统、存档格式、剧情大段重写）：先开分支，推上去让别人也能看，确认没问题再合回 main。

```
git checkout -b feature/你的任务
git add .
git commit -m "feat: 干了啥"
git push -u origin feature/你的任务
```

- 分支名：`feature/<任务卡编号>-<简述>`、`fix/<简述>`、`docs/<简述>`、`chore/<简述>`
- 提交信息：`类型: 干了啥`，类型用 feat / fix / docs / chore
- 一次只做一张任务卡，小步提交，方便随时回退
- 动大手术之前先留退路：`git branch backup/local-日期`，再 `git push -u origin backup/local-日期`
- 推之前本地跑一遍 `scripts/test_all.ps1`（要全绿）；组里的规范细节见根目录 [`AGENTS.md`](AGENTS.md)

### 出问题了怎么办

- **`git push` 报错**（提示 fetch first / non-fast-forward）：说明 main 上有了新东西。先 `git checkout main` 再 `git pull`，回到你的分支后 `git rebase main`（或 `git merge main`），再 push。
- **文件里出现 `<<<<<<<` 和 `>>>>>>>` 符号**：说明你和别人改了同一个地方（这叫冲突）。**不要乱删**，把这个文件截图发群里，组长来帮你合并。
- **忘了自己改过哪些文件**：运行 `git status` 会列出来。

### 千万别做

- ❌ 不要运行 `git push -f`（会直接把别人的代码覆盖掉）
- ❌ 不要删掉别人的文件再提交
- ❌ 提交信息不要只写"更新""修改"，写清楚具体改了啥
- ⚠️ 要动大手术（美术、动画、存档格式）先开一个备份分支再动手：`git branch backup/local-日期`，并推上去

## 五、项目结构

每个目录放什么、代码怎么分类、怎么写、怎么验，全部写在 [`项目结构与代码规范.md`](项目结构与代码规范.md)。这里只列一层：

```
client/     Godot 4.7 工程（autoload/scenes/scripts/components/data/assets/tests）
server/     FastAPI 后端（账号/存档/埋点/排行榜）
database/   数据库工程（服务器 MySQL schema + 游戏内容库 SQLite）
tools/      工具（build_game_data.py / db_export.py 及测试）
deploy/     docker 部署（mysql8 + server + game-web nginx）
art/        建模库源文件（概念图/精灵源/瓦片源/UI 源/音频源）
doc/        课程文档（00-07）+ GDD/任务卡/周报
scripts/    构建与发布脚本
webadmin/   （stretch）管理看板
```

## 六、致谢（第三方资产）

- [Noto Sans CJK](https://github.com/googlefonts/noto-cjk)（SIL OFL，中文字体）
- 早期规划用过 [Kenney](https://kenney.nl) 的 CC0 素材，实际没接进游戏，2026-11-16 已从仓库删掉（详见 `client/assets/CREDITS.md`）
- [Godot Engine](https://godotengine.org)（MIT）
