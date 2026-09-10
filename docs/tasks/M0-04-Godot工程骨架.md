# M0-04 Godot 工程骨架（project.godot + autoload + 主场景 + 冒烟测试）

- 编号：M0-04 ｜ 指派：agent
- 输入：`docs/00 §4`（技术栈）；`docs/03`（客户端架构草案）
- 改动范围：`client/project.godot`、`client/autoload/`、`client/scenes/main/`、`client/tests/`、`client/icon.svg`
- 实现要求：
  1. `project.godot`：Godot 4.5、GL Compatibility、1280x720、主场景指向 `scenes/main/main.tscn`、注册 6 个 autoload（EventBus/GameManager/DataDB/SaveSystem/Settings/Network）
  2. autoload 骨架：EventBus 信号表（player_hurt/enemy_killed/item_picked/sacrifice_done/ending_reached/save_* 等）+ log_event；GameManager 状态机与献祭计数/楼层/阵营/旗标 + to_dict/from_dict；SaveSystem 存档 v1（user://saves/slot_N.json）；Settings；Network 离线事件队列（flush/POST /events）
  3. 主场景占位（标题 Label）+ `tests/smoke_test.gd`（SceneTree 无头断言：autoload 齐全/状态机/DataDB 表结构）
- 验收标准：
  - [ ] `Godot_v4.5.1-stable_win64.exe --headless --path client --quit-after 30` 无报错
  - [ ] `--script res://tests/smoke_test.gd` 退出码 0
  - [ ] 编辑器可打开、F5 可运行
- 禁止：实现玩家控制器/输入映射（属 M1）；改 autoload 注册顺序
- 产出：骨架 + 冒烟测试 + 完成报告
