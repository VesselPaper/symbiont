# 共生之缚 Symbiont

类恶魔城（Metroidvania）2D 游戏 —— 软件工程课程设计项目（2 组，自主选题）。

无魔法、蒸汽时代、神明存在的深渊地牢里，一名普通骑士在"献祭获得力量"与"守住人性"之间抉择。
自下而上探索固定三层地牢：献祭流（收集怪物肢体 → 祭坛献祭 → 部位改造）与探索流（钩锁、二段跳、武器升级）双路线并存；
第二层在异教徒与工程师之间二选一，决定成长分支；结局按献祭次数结算（人类 / 异化 / 真结局 HE）。

## 技术架构

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

## 快速开始

前置：Git、[Godot 4.5.1](https://godotengine.org/download/)（或运行 `scripts/setup.ps1` 自动安装，Windows）、Python 3.12+。

```powershell
# 1) 初始化环境（Godot + server 虚拟环境）
scripts/setup.ps1

# 2) 生成游戏数据（SQLite → client/data JSON）
python tools/build_game_data.py
python tools/db_export.py

# 3) 打开游戏
#    Godot 编辑器打开 client/project.godot，按 F5 运行

# 4) （可选）启动后端
scripts/run_server.ps1        # 浏览器访问 http://127.0.0.1:8000/docs

# 5) （可选）一键全栈
docker compose -f deploy/docker-compose.yml up -d
#    游戏 Web 版: http://localhost:8080
```

## 团队协作：成员同步与提交指南

代码都放在 GitHub 上。组员只需要记住两句话：**开工前先更新本地，干完活把改动传上去**。照着下面的步骤复制命令就行。

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

### 干完活：把改动传到 GitHub

在项目文件夹里，**依次运行下面 4 条命令**：
```
git add .
git commit -m "写一句话：你这次改了啥，比如：加了玩家移动"
git pull
git push
```
- 第 3 条 `git pull` 很关键：先把别人新传的代码合并进来，再传你的，这样不会盖掉别人的改动，**不能跳过**
- 第 4 条看到 `main -> main` 就成功了

### 出问题了怎么办

- **`git push` 报错**（提示 fetch first / non-fast-forward）：说明别人先传了新东西。再运行一次 `git pull`，然后再 `git push`，直到成功。
- **`git pull` 后文件里出现 `<<<<<<<` 和 `>>>>>>>` 符号**：说明你和别人改了同一个地方（这叫冲突）。**不要乱删**，把这个文件截图发群里，组长来帮你合并。
- **忘了自己改过哪些文件**：运行 `git status` 会列出来。

### 千万别做

- ❌ 不要运行 `git push -f`（会直接把别人的代码覆盖掉）
- ❌ 不要删掉别人的文件再提交
- ❌ 提交信息不要只写"更新""修改"，写清楚具体改了啥

## 测试

```powershell
scripts/test_all.ps1          # 数据管道 + server pytest + Godot headless 冒烟
```

CI（GitHub Actions，`.github/workflows/ci.yml`）会在每次 push/PR 自动执行同样检查。

## 项目结构

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

## 致谢（第三方资产）

- [Kenney](https://kenney.nl) —— `kenney_tiny-dungeon`、`kenney_fantasy-ui-borders`（CC0，见 `client/assets/CREDITS.md`）
- [Noto Sans CJK](https://github.com/googlefonts/noto-cjk)（SIL OFL，中文字体）
- [Godot Engine](https://godotengine.org)（MIT）

## 里程碑

M0 基建 → M1 垂直切片（第一层可玩）→ M2 系统完善+后端全量 → M3 内容完成（三结局）→ M4 打磨交付。详见 `docs/00-项目计划与流程.md`。
