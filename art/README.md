# art/ —— 建模库（源文件区）

美术源文件与中间产物存放处，**不入库到 client/ 运行时**；最终用到的素材经处理后放入 `client/assets/`。

| 子目录 | 内容 |
|---|---|
| concepts/ | 概念图、世界观参考、角色设定草图 |
| sprites_src/ | 精灵图源文件（Aseprite/PSD）、AI 生成原始图、序列帧切分前的整图 |
| tiles_src/ | 瓦片源文件、自绘/生成的瓦片集 |
| ui_src/ | UI 源文件（面板、图标、字体草稿） |
| audio_src/ | 音频源文件与选型记录 |

**工作流**：源文件 →（处理：切分/对齐/压缩）→ `client/assets/` 对应目录 → Godot 导入。
新增素材请同步登记 `client/assets/CREDITS.md`。
