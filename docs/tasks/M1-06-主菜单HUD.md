# M1-06 主菜单 + HUD 雏形

- 编号：M1-06 ｜ 指派：待认领（agent）
- 依赖：M1-01、M1-05
- 输入：docs/02、GDD、Kenney fantasy-ui-borders 素材（client/assets/vendor）
- 改动范围：`client/scenes/main/main.tscn`（替换占位）、`client/scenes/ui/hud.*`、`client/scripts/ui/`、`client/project.godot`（主场景改回 main）
- 实现要求：
  1. 主菜单：标题"共生之缚 Symbiont"、按钮"开始新游戏 / 继续游戏（有存档时显示）/ 退出"；背景用 Kenney UI 边框或纯色
  2. 场景切换协议：简单封装 change_scene（M1 用 get_tree().change_scene_to_file 即可，接口留好）
  3. HUD：血量（红心占位）、献祭计数、拾取提示区
  4. 主场景改回 main.tscn：启动进主菜单，开始新游戏进 test_arena（或后续 M3 的第一层）
- 验收标准：
  - [ ] 无头启动无报错，smoke_test 通过
  - [ ] F5：主菜单 → 新游戏 → 进入场景；HUD 显示血量/献祭数
- 禁止：实现设置界面/音量（M4）；改动画/特效
- 产出：代码 + 完成报告
