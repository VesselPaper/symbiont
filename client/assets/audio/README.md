# audio

《共生之缚》的音频。一部分是程序合成的，一部分是真实录音素材剪出来的——以录音为主。

之前全套都是 `tools/audio_synth.py` 合成的正弦 + 白噪声，组长试听的结论是“声音全是噪声”“电子的，嗡嗡的那种”。合成器做不出真乐器的起振、弓压和共鸣，所以音乐和环境音改成采样真实录音，只保留合成版做音效主体。

## 现在是哪套

| 类别 | 来源 | 采样率 |
| --- | --- | --- |
| `bgm_*.wav` 7 首 | `tools/generate_music.py`，VSCO 2 CE 的弦乐/竖琴/管钟/定音鼓 + Meta 钢琴 | 44100Hz |
| `music_*.wav` 3 段 | 同上，直接剪 Meta 的管风琴、弦乐不谐和音，配 VSCO 锣/定音鼓/大提琴 | 44100Hz |
| `amb_*.wav` 4 条 | 同上，剪 Meta 的机房底噪 / 水下环境，低通成不同楼层的音色 | 44100Hz |
| 21 条音效 | `tools/import_sfx.py`：从 Oculus Audio Pack / VSCO 剪，挥砍、跳跃、二段跳、三条命中、史莱姆叫声、残肢拾取、UI 三件、开箱、四种拾取是现场拼的（命中 = 材质声 + 一层低频重量） | 44100Hz |
| 其余 36 条音效 | `tools/generate_audio.py` 合成 | 22050Hz |

混合采样率在 Godot 里没问题，各自按原采样率解码。

BGM 每首用低频持续音、高八度弦垫、事件拨弦/钟声、定音鼓脉冲/心跳分层，不是固定 6 秒和弦循环。`music_*` 由 `AudioDirector/Music` 叠在 BGM 上，播完自动把 BGM 抬回来。

## UI 与拾取为什么也换成实录

组长原话：“鼠标放在按钮的声音不好。和我们这个游戏的氛围很不符合，还有开箱子，捡东西，这些都要写实风格的声音，而不是那种儿童游戏的逼逼声音”。

合成器做按钮就是正弦“嘀”，做拾取就是上滑音，语言上属于休闲游戏。这一批改成从实录素材里剪：

| 音效 | 做法 |
| --- | --- |
| `ui_hover` / `ui` / `pause` | 陶片撞击的头 70/180/340 毫秒，压掉高频尖峰，悬停最轻、暂停最重 |
| `chest_open` | 金属搭扣松开（面板开合）+ 箱内东西翻动（皮革包开合）叠起来 |
| `weapon_pickup` | 小件金属入手的一声 |
| `boots_pickup` | 掐掉低频、只留一小股蒸汽嘶声 |
| `relic_pickup` | 陶/石的触感 + 一层很轻的钟，给遗物一点分量 |
| `pickup` | 布包收拢的一记闷响，不用硬币声 |

## 素材来源与许可

素材不进仓库，`tools/audio_sources.json` 记了每条素材的地址、许可和署名；`tools/fetch_audio_samples.ps1` 按这份清单下载到 `tools/audio_samples/`（已在 `.gitignore` 里）。换机器或 CI 上重跑一次即可。

- “Oculus Audio Pack 01” by Oculus VR, LLC — CC BY 4.0。文件名按 UCS 命名规范，OGG 预览版由原始 WAV 转码。
- “VSCO 2 Community Edition” by Versilian Studios LLC — CC0 1.0。
- “Meta Piano” by Meta Creative Audio team — CC0 1.0。

CC BY 4.0 的那部分要求署名，游戏里“致谢”页和 `doc/` 的致谢段落都带着上面这行，别删。

## 生成流程

```
tools/fetch_audio_samples.ps1                 # 下载素材到 tools/audio_samples/
python tools/import_sfx.py                    # 21 条音效（剪素材 / 现场拼混合）
python tools/generate_music.py                # BGM、音乐层、环境音
python tools/generate_audio.py                # 其余合成音效
Godot ... --headless --path client --import   # 让 Godot 重新导入
```

`generate_audio.py` 默认不再碰 BGM/环境音，也不会覆盖 `import_sfx.py` 管的那些音效（`CUSTOM_SFX` 里列了名字）——旧的合成版还留着，加 `--legacy-music` 才会跑，只用于对照。

## 几个坑

- **一阶滤波器的极点**：高通写成 `lfilter([alpha, -alpha], [1, -(1-alpha)])` 的话，极点落在 0 附近，截止频率会跑到 5kHz 左右——标称 32Hz 却把音乐低频全砍掉，剩下的高频噪声被归一化拉满，听起来就是“电视沙沙”。正确写法是 `a=[1, -alpha]`。`generate_music.py` 里已经踩过并改正，`audio_hiss.py` 的频谱重心能一眼看出来（正常 BGM 在 1～1.8kHz，出问题会跑到 5kHz 以上）。
- **导入必须无损**：所有 `.import` 固定 `compress/mode=0`。Godot 默认的 QOA 有损档会把短音效和低电平 BGM 的量化误差变成持续“沙沙”底噪，导入后 8.8KB 的跳跃音只剩 2.2KB 就是信号；`audio_test` 会断言 BGM 的 `format` 必须是 16-bit PCM。
- **音高表**：`tools/audio_fundamentals.json` 记每个素材的实测基频。变调按这张表算，不能靠现场测——测偏几十音分，几层叠起来就跑调。`vsco_violin_c4` 那条录音本身就偏高 22 音分，表里写的是实测值 265Hz。
- **循环接缝**：`loop_crossfade` 会把尾巴叠回开头，长度会短 1.1s（36s 的曲子写出来是 34.9s），这是正常的。
- `.import` 是 Godot 导入生成的边车文件，需要和 wav 一起保留，否则新环境首次无头测试会找不到资源。

## 体检

- `python tools/audio_audit.py`：打印时长、峰值、RMS、频谱重心和循环接缝。
- `python tools/audio_hiss.py xxx.wav`：按倍频程打能量占比 + 最安静段的噪声底，专门查“沙沙”。
- `python tools/audio_levels.py xxx.wav`：每 0.1s 一格的 dB 走向，一眼能看出长静音和突发尖峰。
- `python tools/audio_samples.py --selftest`：把素材按目标音高渲染回来再测音分，验证变调没跑偏。
- python -m pytest tools/tests/test_audio_coverage.py：查名字/文件/调用三边对不对得上，孤儿文件和未登记的音效都会被抓出来。scripts/test_all.ps1 里会一起跑。
- 这几个工具都不能替代人耳试听，最终还是要组长 F5。

运行时入口是 `GameManager.play_sfx(name, volume_db, pitch)`；战斗/死亡/转场/献祭音乐走 `AudioDirector.play_music(name, volume_db)`。音频总监在窗口模式下才创建，无头回归不启动 AudioServer。
