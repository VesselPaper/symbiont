# 工具集 tools/

按用途分成四个目录（M5-23 整理）：

```
tools/
├─ data/     数据管道：build_game_data.py（SQL→SQLite）、db_export.py（SQLite→JSON）
├─ audio/    音频生成与体检：audio_synth / generate_audio / generate_music / import_sfx /
│             make_drum / audio_audit / audio_hiss / audio_levels / audio_samples / sfx_audit
│             + 清单 audio_sources.json、音高表 audio_fundamentals.json、拉素材脚本
├─ report/   文档工具：md_to_docx.py、fill_weekly_report.py
├─ tests/    pytest（数据链路 + 音效三边一致性）
└─ README.md
```

下面两条流水线里的命令是这套目录下的真实路径。

数据管道（游戏内容库 → 运行时 JSON）：

```
database/game_data/*.sql
      │  python tools/data/build_game_data.py
      ▼
database/game_data/game_data.db   (SQLite，.gitignore 忽略)
      │  python tools/data/db_export.py
      ▼
client/data/<表>/*.json           (Godot 运行时由 DataDB 加载)
```

- `build_game_data.py`：执行 schema.sql + seed.sql 生成 SQLite。
- `db_export.py`：按表导出 JSON（每主键一个文件 + `*_index.json` 索引）。
- `tests/test_db_export.py`：链路测试（pytest）。

**铁律**：`client/data/` 下的 JSON 是生成物，禁止手改。改数据 = 改 SQL → 重新导出。

音频生成：

```
tools/audio/audio_synth.py      合成底层（滤波/模态钟/拨弦/合唱/和弦垫）
      │
tools/audio/generate_audio.py   曲目与音效定义
      │  python tools/audio/generate_audio.py
      │  python tools/audio/generate_audio.py --sfx-only   # 只改音效时省时间
      ▼
client/assets/audio/*.wav + *.import
```

- `audio_audit.py`：打印时长、峰值、RMS、频谱分布、循环接缝；用带 numpy 的 Python 跑，只做客观体检。
- 生成后必须让 Godot 重新导入：`--headless --editor --path client --quit`。

后续可在此增加：`asset_audit.py`（素材引用完整性检查）、AI 精灵图处理脚本等。
