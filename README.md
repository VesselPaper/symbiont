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
│  client/  Godot 4.5 客户端（纯 GDScript）                │
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
└───────────┬────────────┘   │            │ tools/db_export.py
            │                │            │
┌───────────▼────────────┐   │  ┌─────────┴────────────────┐
│  deploy/ docker-compose │   │  │  database/game_data/     │
│  mysql8 + server +      │   └──│  SQLite 游戏内容库        │
│  game-web(nginx)        │      │  (schema.sql/seed.sql)   │
└─────────────────────────┘      └──────────────────────────┘
```

**数据驱动**：游戏静态数据源在 `database/game_data`（SQLite，schema+seed 即课程"数据库脚本文件"），
经 `tools/db_export.py` 导出为 `client/data/*.json`，运行时由 `DataDB` 单例加载。改数据 = 改 SQL → 重新导出，不碰代码。

**课程交付**：`docs/` 下 00–07 七份文档对齐老师要求（功能分析/接口设计/详细设计/部署文档/操作说明/源文件说明/数据库脚本），周报在 `docs/weekly/`。

## 三、快速开始

怎么打开游戏玩：

1. 打开 Godot 软件（如果电脑上没装，见下面"团队协作"一节的第 1 步，运行一次 `scripts\setup.ps1` 就会自动装好）
2. 在 Godot 的项目管理器里点"导入"，找到项目里的 `client\project.godot` 文件，点确定
3. 点运行按钮（▶，在窗口上方），或直接按 **F5**，游戏就启动了

就这 3 步，其他都不用管。

## 四、团队协作：成员同步与提交指南

代码都放在 GitHub 上。组员只需要记住两句话：**开工前先更新本地，干完活开分支发 PR**。照着下面的步骤复制命令就行。

> `main` 分支已开启保护，不能直接 push；所有改动都要走"分支 → PR → review → CI 绿 → 合并"。详细规则见根目录 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

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

### 干完活：开分支 + 发 PR（不要直接推 main）

main 有保护，直接 push 会被挡下。每次干活开一个分支：

```
git checkout main
git pull
git checkout -b feature/你的任务
git add .
git commit -m "feat: 写一句话：你这次改了啥，比如：加了玩家移动"
git push -u origin feature/你的任务
```

推完后到 GitHub 网页上点 **Compare & pull request** 开 PR，按模板勾选验收清单，等 CI 变绿、组长 review 通过后合并，再删掉这个分支。

- 分支名：`feature/<任务卡编号>-<简述>`、`fix/<简述>`、`docs/<简述>`、`chore/<简述>`
- 提交信息：`类型: 干了啥`，类型用 feat / fix / docs / chore
- 一次只做一张任务卡，小步提交，方便随时回退

### 出问题了怎么办

- **`git push` 报错**（提示 fetch first / non-fast-forward）：说明 main 上有了新东西。先 `git checkout main` 再 `git pull`，回到你的分支后 `git rebase main`（或 `git merge main`），再 push。
- **文件里出现 `<<<<<<<` 和 `>>>>>>>` 符号**：说明你和别人改了同一个地方（这叫冲突）。**不要乱删**，把这个文件截图发群里，组长来帮你合并。
- **忘了自己改过哪些文件**：运行 `git status` 会列出来。

### 千万别做

- ❌ 不要直接 `git push` 到 main（会被分支保护挡下）
- ❌ 不要运行 `git push -f`（会直接把别人的代码覆盖掉）
- ❌ 不要删掉别人的文件再提交
- ❌ 提交信息不要只写"更新""修改"，写清楚具体改了啥

## 五、项目结构

```
client/     Godot 4.5 工程（autoload/scenes/scripts/components/data/assets/tests）
server/     FastAPI 后端（账号/存档/埋点/排行榜）
database/   数据库工程（服务器 MySQL schema + 游戏内容库 SQLite）
tools/      工具（build_game_data.py / db_export.py 及测试）
deploy/     docker 部署（mysql8 + server + game-web nginx）
art/        建模库源文件（概念图/精灵源/瓦片源/UI 源/音频源）
docs/       课程文档（00-07）+ GDD/任务卡/周报
scripts/    构建与发布脚本
webadmin/   （stretch）管理看板
```

## 六、致谢（第三方资产）

- [Kenney](https://kenney.nl) —— `kenney_tiny-dungeon`、`kenney_fantasy-ui-borders`（CC0，见 `client/assets/CREDITS.md`）
- [Noto Sans CJK](https://github.com/googlefonts/noto-cjk)（SIL OFL，中文字体）
- [Godot Engine](https://godotengine.org)（MIT）
