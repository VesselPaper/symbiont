# 贡献指南（CONTRIBUTING）

本项目是软件工程课程设计（2 组）的协作项目。开工前请先读 [`docs/标准与规范.md`](docs/标准与规范.md)；本文件只讲**怎么提代码**。

## 一、核心规则

1. **main 受保护，禁止直接 push。** 所有改动走：`feature/xx` 分支 → Pull Request → 至少 1 人 review → CI 绿 → 合并。
2. **一次只做一张任务卡**（`docs/tasks/`）。每张卡：实现 → 无头验证跑通 → 合并 → 组长试玩验收 → 通过后才开下一张。
3. **agent 只实现任务卡内容**，不发明功能、不改已定接口、不调数值。

## 二、开工流程

```bash
git checkout main
git pull                                  # 先同步线上最新
git checkout -b feature/你的任务            # 例：feature/m1-01-player-move
# ... 改代码 ...
```

分支命名：`feature/<任务卡编号>-<简述>`（新功能）、`fix/<简述>`（修 bug）、`docs/<简述>`、`chore/<简述>`。

## 三、提交前自检（本地必须全过）

```bash
# 1) 数据管道（改了 database/ 或 tools/ 才需要）
python tools/build_game_data.py
python tools/db_export.py

# 2) 测试
pytest tools/tests server

# 3) 客户端无头冒烟（应输出 [smoke] PASS）
godot --headless --path client --script res://tests/smoke_test.gd
```

提交信息格式：`类型: 干了啥`，类型用 `feat` / `fix` / `docs` / `chore`。
- 好例子：`feat(M1): 玩家移动与跳跃`
- 坏例子：`更新`、`修改`

## 四、提 PR

```bash
git add .
git commit -m "feat(M1): 玩家移动与跳跃"
git push -u origin feature/m1-01-player-move
```

然后在 GitHub 上开 PR，按模板填写。要求：

- 关联任务卡编号；
- 勾选验收清单，CI 必须全绿；
- 由 CODEOWNERS 指定的人 review，通过后合并（推荐 Squash merge）。

## 五、红线

- ❌ 不 `git push -f`；不删别人的文件；不绕过 PR 直接推 main。
- ❌ 不改范围外代码、不改已定接口/信号签名、不发明功能。
- ❌ 数值不写死进代码（一律进 `database/game_data` 或 JSON）。
- ❌ `client/data/*.json` 是生成物，禁止手改（改 SQL → 重新导出）。
- ❌ 新增依赖前先写决策日志 `docs/design/决策日志.md`（D-xxx）。

## 六、冲突处理

PR 出现冲突或 `git pull` 后文件里出现 `<<<<<<<` / `>>>>>>>`：不要乱删，截图发群里，由组长合并。

## 七、文档与周报

- 接口以 `docs/02-系统接口设计文档.md` 为唯一权威，改接口必须同步。
- 每周日提交实施周报到 `docs/weekly/`，命名 `组2-共生之缚-实施周报-yyyymmdd`。
