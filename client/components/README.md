# client/components/ —— 可复用组件

与场景/实体解耦的通用组件（GDScript，纯逻辑，尽量不依赖具体场景）：

- `state_machine.gd`：通用状态机（敌人 AI / 玩家动作状态）
- `health.gd`：生命值组件（HP/最大 HP/受伤/治疗/死亡信号）
- `damageable.gd`：可受击接口约定（配合 area2d 判定）
- `hookshot.gd`：钩锁组件（M2）
- `inventory.gd`：背包组件（M2）
- `dialogue.gd`：对话组件（M1）

组件接口定稿后同步 `docs/02-系统接口设计文档.md §2.3`。
