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

**核心原则：我们的操作是"更新"（在别人最新代码的基础上增量修改），永远不是"覆盖"。**
Git 默认会阻止你把旧代码直接推上去覆盖别人的新代码，但错误的操作习惯仍可能造成混乱。
下面的流程照做，就能保证：你永远基于最新代码工作，你的提交永远不会盖掉别人的修改。

### 0. 首次使用 Git 的准备

```powershell
# 安装 Git（https://git-scm.com）后，配置一次身份（改成自己的名字/邮箱）
git config --global user.name "你的名字"
git config --global user.email "你的邮箱@xxx.com"
# 让中文文件名正常显示（否则 git status 里中文会变转义符）
git config --global core.quotepath false
```

### 1. 第一次把项目拉到本地（克隆）

```powershell
git clone https://github.com/VesselPaper/symbiont.git
cd symbiont
scripts\setup.ps1          # 自动装 Godot 依赖、server 虚拟环境、生成游戏数据
# 然后打开 client/project.godot，按 F5 运行
```

⚠️ **如果你电脑上已经有一个旧的 symbiont 文件夹**（上一轮实验留下的），**不要**直接在里面改代码后提交——
旧文件夹的本地状态和线上不一致，提交会把旧文件、旧内容带回去，覆盖掉我们新写的代码。
安全做法（二选一）：
- **推荐**：删掉旧文件夹，按上面重新 clone 一份干净的；
- 或先执行第 2 节的同步流程，确认本地已是最新再开工。

### 2. 开工前 / 线上项目更新了：把最新代码拉到本地

```powershell
git fetch origin            # 查看线上是否有新提交
git status                  # 本地落后(behind)还是领先(ahead)
git pull origin main        # 把线上最新代码合并到本地（= fetch + merge）
```

- 如果 `git pull` 报"本地有未提交的修改，无法合并"：
  ```powershell
  git stash                  # 把未提交的改动暂时收起来
  git pull origin main       # 再拉取
  git stash pop              # 把改动放回来（如有冲突按第 4 节解决）
  ```
- 拉取后建议跑一次 `scripts\test_all.ps1`，确认环境和数据没问题再开工。

### 3. 干完活：把改动更新到 GitHub（提交 + 推送）

**标准六步**（每一步都有目的，别跳）：

```powershell
# ① 看自己到底改了哪些文件
git status

# ② 检查改动内容是否符合预期
git diff

# ③ 只添加【自己这次改的文件】—— 不要偷懒 git add -A 全加，
#    否则容易把别人的文件、生成物(.godot/、.venv/、client/data/ 等)一起提交
git add <你改的文件或目录>      # 例: git add client/scenes/player/ docs/02-系统接口设计文档.md

# ④ 提交（写清楚改了什么）
git commit -m "feat(client): 新增玩家控制器"

# ⑤ ★推送前必做★：先把线上新提交合并进本地。
#    如果这期间别人推了新代码，这一步会把它们合进来，避免推送被拒/冲突
git pull --rebase origin main

# ⑥ 推送到 GitHub
git push origin main
```

- 如果 ⑤ 出现冲突（CONFLICT），按第 4 节处理；
- 如果 ⑥ 被拒绝（`non-fast-forward` / `fetch first`）：说明线上又有新提交，回到 ⑤ 再来一次即可，**不要**用 `--force`。

### 4. 冲突（CONFLICT）怎么办

多人改同一个文件时，Git 无法自动合并就会报冲突，这是**正常现象**，不是出错：

```powershell
git status                  # 看哪些文件冲突（显示 both modified）
# 用编辑器打开冲突文件，会看到这样的标记：
#   <<<<<<< HEAD
#   线上已有的内容
#   =======
#   你本地改的内容
#   >>>>>>> your-branch
# 手动把两边合理的内容合并保留，删掉 <<<<<<< ======= >>>>>>> 标记行
git add <解决好的文件>       # 标记为已解决
git pull --rebase --continue   # 继续完成合并
git push origin main
```

拿不准怎么合并时：**别乱删、别乱提交**，把冲突文件截图发群里一起解决。

### 5. 红线（千万别做）

| ❌ 禁止 | 后果 |
|---|---|
| `git push --force` / `-f` | 强制推送会**直接覆盖**线上历史，别人代码全没——绝对禁止 |
| 在旧仓库上不 pull 就提交推送 | 旧文件/旧内容会被带回，盖掉新代码 |
| `git add -A` 无脑全加 | 可能把生成物和别人的改动一起提交 |
| 手改 `client/data/` 下的 JSON | 那是生成物，改 `database/game_data/*.sql` 后重新导出 |
| 提交 `.godot/`、`server/.venv/`、`*.log` | 已在 .gitignore，正常 add 不会带上；别用 `-f` 强行加 |

### 6. 提交信息规范

格式：`类型(范围): 一句话描述`，例：

- `feat(client): 新增玩家控制器`
- `fix(server): 修复登录接口 500`
- `docs: 更新接口文档 02`
- `chore: 更新依赖`

类型：`feat` 新功能 / `fix` 修 bug / `docs` 文档 / `refactor` 重构 / `chore` 杂项 / `test` 测试。

### 7. 常见问题速查

| 问题 | 解决 |
|---|---|
| push 被拒（non-fast-forward） | `git pull --rebase origin main` 后再 push |
| 忘了自己改过什么 | `git status` + `git diff` |
| 想撤销最后一次提交但保留改动 | `git reset --soft HEAD~1` |
| 改乱了想丢弃未提交改动 | `git checkout -- <文件>`（⚠️ 会丢改动，慎用） |
| 想看看提交历史 | `git log --oneline` |
| 谁改的这行代码 | `git blame <文件>` |

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
