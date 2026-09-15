## 这个 PR 做了什么

<!-- 一句话说清楚：做了什么、对应哪张任务卡 -->

## 关联

- 任务卡：`docs/tasks/M?-??-*.md`（没有任务卡的改动请先补卡）
- Issue：Closes #

## 改动范围

<!-- 列出改动的目录/文件，必须与任务卡"改动文件范围"一致；范围外文件不许动 -->

- 

## 验收（全过才能合并）

- [ ] 数据管道：`python tools/build_game_data.py` + `python tools/db_export.py` 无报错
- [ ] 测试：`pytest tools/tests server` 全绿
- [ ] 客户端冒烟：`godot --headless --path client --script res://tests/smoke_test.gd` 输出 `[smoke] PASS`
- [ ] CI 绿
- [ ] 未改范围外代码、未改已定接口/信号签名、未发明新功能
- [ ] 数值未写死（一律进 `database/game_data` 或 JSON）
- [ ] 若改了接口/信号/表结构：已同步更新 `docs/02` 或 `docs/03`

## 截图 / 试玩说明

<!-- 涉及画面、手感、UI 时必填；纯逻辑/文档可写"不涉及" -->

## 遗留问题

<!-- 没有就写"无" -->
