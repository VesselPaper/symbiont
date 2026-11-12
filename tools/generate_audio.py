"""生成《共生之缚》的程序化音效。

运行：python tools\\generate_audio.py
输出：client/assets/audio/*.wav（22050Hz / 单声道 / PCM16）

M4-15 起分工变了：
- 这个脚本只管合成音效；
- BGM、一次性音乐层、环境音改由 tools/generate_music.py 用真实录音渲染
  （合成器做不出真乐器音色，之前整套 BGM 听起来是“电子嗡嗡”）；
- 其中八条音效（挥砍、下劈、脚步、落地、受击、怪物、钟、拾取）改由
  tools/import_sfx.py 从录音库切，这里跳过，避免把真录音又覆盖回合成音。

旧的合成版 BGM 还留着，加 --legacy-music 才会跑，仅用于对照。
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

from audio_synth import (
    RATE, TAU, add, bandpass, choir_note, heartbeat_layer, highpass, karplus, lowpass,
    loop_crossfade, metal_tick, modal_bell, noise, normalize, pad_chord, pulse_layer,
    reverb, silence, soft_noise, sweep_band, thump, tone_sweep, wet_hit, whoosh,
    wind_bed, write_wav,
)

OUT = Path(__file__).resolve().parents[1] / "client" / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
SFX_ONLY = "--sfx-only" in sys.argv
BGM_ONLY = "--bgm-only" in sys.argv
MUSIC_LEGACY = "--legacy-music" in sys.argv

# 这八条由 tools/import_sfx.py 出（六条从录音库剪、两条现场拼），
# 合成器不要再生成，否则重跑会把它们覆盖回电子音。
CUSTOM_SFX = {"swing", "jump", "double_jump", "pogo", "step", "land", "hit",
              "slime_voice", "bell", "pickup", "ui", "ui_hover", "pause",
              "chest_open", "weapon_pickup", "boots_pickup", "relic_pickup"}


def gain(samples: list[float], amp: float) -> list[float]:
    """列表不能直接乘 float；统一走这里，避免 numpy 依赖。"""
    return [s * amp for s in samples]


def mix(*tracks: list[float]) -> list[float]:
    n = max((len(t) for t in tracks), default=1)
    out = [0.0] * n
    for t in tracks:
        add(out, t)
    return out


def fade_edges(samples: list[float], attack: float = 0.004, release: float = 0.06) -> list[float]:
    n = len(samples)
    a = max(1, int(RATE * attack))
    r = max(1, int(RATE * release))
    for i in range(min(a, n)):
        samples[i] *= i / a
    for i in range(min(r, n)):
        samples[n - 1 - i] *= i / r
    return samples


SFX_PEAK = {
    # 短促的高频噪声按峰值归一会显得比命中还响，这几类单独压一点
    "jump": 0.55, "double_jump": 0.62, "step": 0.60, "land": 0.68, "swing": 0.72,
    "hurt": 0.72, "ui": 0.62, "ui_hover": 0.52,
}


## 只给“有空间感”的冲击/器物加一点短反射；移动、UI、人声一律干声，
## 否则每一刀都拖一条混响尾巴，连起来就像噪声。
SFX_REVERB = {
    "hit": 0.05, "pogo": 0.06, "enemy_die": 0.05, "boss_hit": 0.05,
    "boss_slam": 0.08, "boss_down": 0.10, "bell": 0.10, "chain": 0.06,
    "gate": 0.06, "chest_open": 0.06, "death": 0.08, "sacrifice": 0.08,
    "ending": 0.08, "true_he": 0.08, "altar": 0.05,
}


def make_sfx(name: str, duration: float, builder) -> None:
    samples = builder()
    want = int(RATE * duration)
    if len(samples) < want:
        samples += [0.0] * (want - len(samples))
    samples = samples[:want]
    samples = fade_edges(samples, 0.003, min(0.18, duration * 0.25))
    mix = SFX_REVERB.get(name, 0.0)
    if mix > 0:
        samples = reverb(samples, mix, 0.22)
    write_wav(OUT / ("sfx_" + name + ".wav"), samples, peak=SFX_PEAK.get(name, 0.78))
    print(f"sfx_{name}.wav: {duration:.2f}s")


def render_bgm(
    name: str,
    duration: float,
    root: float,
    chords: list[tuple[float, float, list[float]]],
    notes: list[tuple[float, float, float, str, float]],
    *,
    wind: float = 0.0,
    pulse: float = 0.0,
    heartbeat: float = 0.0,
    bells: tuple[tuple[float, float, float], ...] = (),
    high_bells: tuple[tuple[float, float, float], ...] = (),
    motif: tuple[tuple[float, float, float], ...] = (),
    seed: int = 0,
    peak: float = 0.54,
) -> None:
    """分层渲染一首 BGM：低频 drone + 和弦垫 + 事件音符 + 噪声/脉冲 + 钟。"""
    if SFX_ONLY or not MUSIC_LEGACY:
        return
    n = int(RATE * duration)
    buf = [0.0] * n
    # 低频 drone：根音和五度，慢速拍频，给石廊/炉膛的“空间底”
    for i in range(n):
        t = i / RATE
        beat = 0.5 + 0.5 * math.sin(TAU * 0.045 * t + 0.6)
        v = 0.07 * math.sin(TAU * root * t + 0.2) * (0.7 + 0.3 * beat)
        v += 0.035 * math.sin(TAU * root * 1.5 * t + 1.1)
        buf[i] += v
    for start, length, freqs in chords:
        add(buf, pad_chord(length, freqs, 0.9, seed + int(start * 7)), start)
        # 高八度垫层：低频给空间，中高频给“石廊里有弦”的存在感
        add(buf, pad_chord(length, [f * 2.0 for f in freqs], 0.32, seed + int(start * 7) + 5), start)
    for start, length, freq, kind, amp in notes:
        if kind == "string":
            add(buf, karplus(length, freq, amp, 0.994, seed + int(start * 13)), start)
        elif kind == "bell":
            add(buf, modal_bell(length, freq, amp, 2.2, seed + int(start * 11)), start)
        else:
            add(buf, choir_note(length, freq, amp, seed + int(start * 17), 0.04, 0.55), start)
    for start, freq, amp in bells:
        add(buf, modal_bell(4.6, freq, amp, 1.7, seed + int(start * 19), 0.09), start)
    for start, freq, amp in high_bells:
        add(buf, modal_bell(2.2, freq, amp, 3.0, seed + int(start * 23), 0.04), start)
    # 明确的中音动机：每首曲子有一句可记住的短旋律，而不是只有一层和声垫
    for start, freq, amp in motif:
        add(buf, modal_bell(1.7, freq, amp, 3.4, seed + int(start * 29), 0.02), start)
    if wind > 0:
        # 只留很轻的低频风床；原来那层 1700Hz 带通白噪是 BGM 里的“沙沙”主因
        add(buf, wind_bed(duration, wind, seed + 31, 140.0))
    if pulse > 0:
        add(buf, pulse_layer(duration, pulse, 0.16, seed + 47))
    if heartbeat > 0:
        add(buf, heartbeat_layer(duration, 1.34, heartbeat))
    # 去掉 30Hz 以下、笔记本扬声器根本放不出来的次低频，避免只剩一片“嗡嗡”被当成噪声
    samples = normalize(highpass(buf, 30.0), peak)
    # BGM 不需要逐音 reverb，靠 pad 自身的 release 和 loop crossfade 衔接
    samples = loop_crossfade(samples, 1.1)
    write_wav(OUT / (name + ".wav"), samples, peak=peak)
    print(f"{name}.wav: {len(samples) / RATE:.2f}s")


def render_sting(name: str, duration: float, builder, *, peak: float = 0.5) -> None:
    if SFX_ONLY or not MUSIC_LEGACY:
        return
    samples = builder()
    want = int(RATE * duration)
    if len(samples) < want:
        samples += [0.0] * (want - len(samples))
    samples = samples[:want]
    samples = fade_edges(samples, 0.008, 0.35)
    write_wav(OUT / (name + ".wav"), samples, peak=peak)
    print(f"{name}.wav: {duration:.2f}s")


# ---------------------------------------------------------------------------
# BGM：七首循环 + 四段一次性音乐层
# ---------------------------------------------------------------------------

render_bgm(
    "bgm_menu", 36.0, 55.0,
    [(0.0, 10.5, [55, 82, 110]), (9.0, 10.5, [55, 82, 123]),
     (18.0, 10.5, [49, 73, 110]), (27.0, 10.5, [55, 82, 110])],
    [(2.0, 3.2, 220.0, "string", 0.12), (7.0, 4.0, 277.0, "choir", 0.10),
     (13.0, 5.0, 196.0, "choir", 0.11), (20.0, 3.0, 220.0, "string", 0.10),
     (28.0, 5.0, 165.0, "choir", 0.12)],
    wind=0.010,
    bells=((5.0, 110.0, 0.18), (23.5, 82.0, 0.14)),
    high_bells=((3.2, 330.0, 0.05), (14.0, 392.0, 0.04), (29.0, 440.0, 0.035)),
    motif=((0.0, 261.6, 0.06), (3.4, 329.6, 0.05), (8.0, 392.0, 0.05), (13.0, 329.6, 0.04)),
    seed=101,
)
render_bgm(
    "bgm_tutorial", 34.0, 110.0,
    [(0.0, 9.5, [110, 165, 220]), (8.0, 9.5, [110, 165, 247]),
     (16.5, 9.5, [98, 147, 196]), (25.0, 9.5, [110, 165, 220])],
    [(1.5, 2.4, 440.0, "string", 0.12), (5.2, 3.0, 494.0, "string", 0.09),
     (10.0, 3.5, 392.0, "string", 0.11), (15.0, 2.2, 440.0, "bell", 0.08),
     (20.0, 4.0, 330.0, "choir", 0.10), (27.0, 3.0, 550.0, "string", 0.09)],
    motif=((1.0, 440.0, 0.05), (4.2, 494.0, 0.045), (8.5, 392.0, 0.05), (13.0, 440.0, 0.04)),
    wind=0.004, seed=202,
)
render_bgm(
    "bgm_floor1", 38.0, 82.0,
    [(0.0, 10.5, [82, 123, 164]), (9.5, 10.5, [82, 123, 174]),
     (19.0, 10.5, [73, 110, 147]), (28.5, 10.5, [82, 123, 164])],
    [(3.0, 4.0, 246.0, "choir", 0.10), (8.0, 2.8, 196.0, "string", 0.10),
     (12.0, 5.0, 329.0, "choir", 0.09), (17.0, 2.0, 246.0, "bell", 0.10),
     (22.0, 4.5, 196.0, "choir", 0.11), (31.0, 3.5, 329.0, "string", 0.09)],
    wind=0.012,
    bells=((4.2, 110.0, 0.24), (24.0, 82.0, 0.18)),
    high_bells=((1.8, 330.0, 0.04), (7.0, 440.0, 0.08), (15.5, 587.0, 0.06),
                (21.0, 330.0, 0.05), (33.0, 392.0, 0.07)),
    motif=((0.5, 246.0, 0.06), (5.0, 329.0, 0.045), (10.0, 293.0, 0.05), (16.0, 246.0, 0.045)),
    seed=303,
)
render_bgm(
    "bgm_floor2", 36.0, 65.0,
    [(0.0, 10.0, [65, 98, 130]), (9.0, 10.0, [65, 98, 139]),
     (18.0, 10.0, [58, 87, 116]), (27.0, 10.0, [65, 98, 130])],
    [(2.0, 3.5, 196.0, "string", 0.11), (6.0, 4.0, 261.0, "choir", 0.09),
     (12.0, 2.5, 220.0, "string", 0.10), (18.0, 4.0, 174.0, "choir", 0.10),
     (25.0, 3.0, 196.0, "string", 0.09), (30.0, 4.0, 261.0, "choir", 0.08)],
    wind=0.005, pulse=0.88,
    bells=((8.0, 130.0, 0.12), (21.0, 98.0, 0.10)),
    motif=((0.5, 196.0, 0.05), (4.0, 261.0, 0.04), (9.0, 220.0, 0.05), (14.0, 174.0, 0.045)),
    seed=404,
)
render_bgm(
    "bgm_floor3", 40.0, 49.0,
    [(0.0, 11.0, [49, 73, 98]), (10.0, 11.0, [49, 73, 104]),
     (20.0, 11.0, [46, 69, 92]), (30.0, 11.0, [49, 73, 98])],
    [(2.0, 5.0, 147.0, "choir", 0.10), (9.0, 4.0, 196.0, "string", 0.08),
     (15.0, 6.0, 123.0, "choir", 0.11), (24.0, 3.0, 98.0, "string", 0.09),
     (31.0, 5.0, 147.0, "choir", 0.10)],
    wind=0.012, heartbeat=0.20,
    bells=((12.0, 73.0, 0.14), (34.0, 55.0, 0.12)),
    high_bells=((6.0, 293.0, 0.04), (22.0, 196.0, 0.05), (37.0, 293.0, 0.04)),
    motif=((0.5, 147.0, 0.05), (4.5, 196.0, 0.04), (10.0, 123.0, 0.045), (16.0, 147.0, 0.04)),
    seed=505,
)
render_bgm(
    "bgm_combat", 28.0, 55.0,
    [(0.0, 7.5, [55, 65, 82]), (7.0, 7.5, [55, 69, 82]),
     (14.0, 7.5, [49, 58, 73]), (21.0, 7.5, [55, 65, 82])],
    [(1.0, 3.0, 110.0, "choir", 0.16), (3.2, 2.0, 330.0, "string", 0.10),
     (5.0, 2.0, 165.0, "string", 0.13), (9.0, 4.0, 82.0, "choir", 0.15),
     (12.0, 2.5, 311.0, "string", 0.10), (14.0, 2.5, 147.0, "string", 0.14),
     (19.0, 3.0, 110.0, "choir", 0.16), (21.0, 2.0, 392.0, "string", 0.09),
     (23.0, 2.0, 220.0, "string", 0.12)],
    wind=0.006, pulse=0.54, heartbeat=0.34,
    motif=((0.5, 165.0, 0.06), (3.0, 196.0, 0.05), (6.0, 220.0, 0.05), (9.0, 165.0, 0.045)),
    seed=606,
)
render_bgm(
    "bgm_ending", 24.0, 55.0,
    [(0.0, 8.5, [55, 110, 165]), (8.0, 8.5, [55, 110, 196]),
     (16.0, 8.5, [49, 98, 147])],
    [(1.0, 5.0, 330.0, "choir", 0.12), (6.0, 4.0, 440.0, "string", 0.10),
     (11.0, 4.0, 392.0, "choir", 0.11), (17.0, 5.0, 554.0, "choir", 0.10)],
    wind=0.002, bells=((4.0, 110.0, 0.10), (19.0, 82.0, 0.08)),
    high_bells=((2.0, 440.0, 0.05), (9.0, 550.0, 0.04), (15.0, 392.0, 0.04),
                (22.0, 554.0, 0.03)),
    motif=((0.5, 330.0, 0.05), (4.0, 440.0, 0.045), (9.0, 554.0, 0.04), (13.0, 440.0, 0.04)),
    seed=707,
)


def sting_transition() -> list[float]:
    return mix(
        wind_bed(7.0, 0.035, 808, 180.0),
        choir_note(5.0, 220.0, 0.18, 809, 0.05, 0.55),
        choir_note(4.0, 164.0, 0.16, 810, 0.04, 0.55),
        choir_note(3.0, 110.0, 0.18, 811, 0.05, 0.45),
        modal_bell(5.0, 82.0, 0.20, 1.8, 812, 0.06),
        thump(1.2, 38.0, 0.35, 5.0, 813),
    )


def sting_sacrifice() -> list[float]:
    n = int(RATE * 6.0)
    buf = [0.0] * n
    add(buf, heartbeat_layer(5.5, 0.72, 0.30))
    add(buf, choir_note(5.0, 110.0, 0.16, 901, 0.08, 0.7), 0.2)
    add(buf, choir_note(4.0, 146.0, 0.15, 902, 0.07, 0.7), 1.2)
    add(buf, choir_note(3.0, 196.0, 0.14, 903, 0.06, 0.7), 2.2)
    add(buf, modal_bell(4.0, 73.0, 0.22, 1.4, 904, 0.08), 0.0)
    add(buf, tone_sweep(4.0, 110.0, 180.0, 0.10, 2.0, ((1.0, 0.7), (2.0, 0.15)), 905))
    return buf


def sting_death() -> list[float]:
    n = int(RATE * 8.0)
    buf = [0.0] * n
    add(buf, modal_bell(7.0, 55.0, 0.34, 0.9, 1001, 0.10))
    add(buf, modal_bell(6.0, 82.0, 0.22, 1.2, 1002, 0.05), 0.3)
    add(buf, choir_note(5.0, 110.0, 0.14, 1003, 0.10, 0.5), 1.0)
    add(buf, choir_note(4.0, 82.0, 0.13, 1004, 0.10, 0.4), 2.5)
    add(buf, wind_bed(8.0, 0.018, 1005, 110.0))
    return buf


render_sting("music_transition", 7.0, sting_transition, peak=0.48)
render_sting("music_sacrifice", 6.0, sting_sacrifice, peak=0.5)
render_sting("music_death", 8.0, sting_death, peak=0.46)


# ---------------------------------------------------------------------------
# 环境：保留四层，但低频更轻、颗粒更清楚
# ---------------------------------------------------------------------------

def ambience(name: str, duration: float, *, wind: float, seed: int, drips=(),
             hammer=False, heartbeat=False, whisper=False) -> None:
    if SFX_ONLY or not MUSIC_LEGACY:
        return
    buf = [0.0] * int(RATE * duration)
    add(buf, wind_bed(duration, wind, seed, 150.0))
    for at in drips:
        add(buf, karplus(0.9, 620.0, 0.10, 0.992, seed + int(at * 10)), at)
        add(buf, karplus(0.7, 930.0, 0.06, 0.994, seed + int(at * 10) + 1), at + 0.06)
    if hammer:
        add(buf, pulse_layer(duration, 0.95, 0.10, seed + 3))
    if heartbeat:
        add(buf, heartbeat_layer(duration, 1.6, 0.10))
    if whisper:
        add(buf, gain(bandpass(noise(len(buf), seed + 4), 520.0, 1.2), 0.04))
    samples = normalize(highpass(buf, 28.0), 0.34)
    samples = loop_crossfade(samples, 0.7)
    write_wav(OUT / ("amb_" + name + ".wav"), samples, peak=0.34)
    print(f"amb_{name}.wav: {len(samples) / RATE:.2f}s")


ambience("menu", 9.0, wind=0.06, seed=1201, drips=(2.2, 5.8))
ambience("floor1", 9.0, wind=0.055, seed=1202, drips=(1.2, 3.8, 6.1))
ambience("floor2", 9.0, wind=0.05, seed=1203, hammer=True)
ambience("floor3", 9.0, wind=0.055, seed=1204, heartbeat=True)


# ---------------------------------------------------------------------------
# SFX：战斗、移动、剧情、道具、UI
# ---------------------------------------------------------------------------

def cloth(seconds: float, amp: float, seed: int) -> list[float]:
    # 布料只留 700Hz 以下的软气声；原来整段带通白噪声就是“沙沙”噪源
    return soft_noise(seconds, 700.0, amp, seed, attack=0.02)


def sfx_swing() -> list[float]:
    # 以 520→240Hz 的短音为主体，只留一丝低频气声；不要整段白噪扫频
    return mix(
        tone_sweep(0.24, 520.0, 240.0, 0.42, 7.0, ((1.0, 0.58), (2.0, 0.16), (3.0, 0.04)), 2001),
        metal_tick(0.18, 420.0, 0.10, 2002),
        soft_noise(0.14, 650.0, 0.07, 2003),
    )


def sfx_hit() -> list[float]:
    # 低频膜 + 短木/骨体，噪声只留 3ms 起振，听起来是“打到东西”而不是“喷气”
    return mix(
        thump(0.24, 78.0, 0.55, 14.0, 2101),
        modal_bell(0.20, 196.0, 0.24, 6.0, 2102, 0.025),
        soft_noise(0.08, 520.0, 0.10, 2103),
    )


def sfx_pogo() -> list[float]:
    # 下劈比普通命中更“金属”：低冲击 + 523Hz 短鸣，不用 whoosh
    return mix(
        thump(0.32, 62.0, 0.55, 12.0, 2201),
        modal_bell(0.28, 523.0, 0.20, 5.0, 2202, 0.02),
        tone_sweep(0.18, 784.0, 392.0, 0.12, 10.0, ((1.0, 0.6), (2.0, 0.15)), 2203),
        soft_noise(0.10, 700.0, 0.05, 2204),
    )


def sfx_enemy_hit() -> list[float]:
    return mix(
        thump(0.18, 120.0, 0.32, 16.0, 2301),
        modal_bell(0.16, 294.0, 0.16, 7.0, 2302, 0.015),
        soft_noise(0.06, 500.0, 0.06, 2303),
    )


def sfx_enemy_die() -> list[float]:
    return mix(
        thump(0.55, 55.0, 0.34, 5.0, 2401),
        tone_sweep(0.55, 280.0, 90.0, 0.24, 4.0, ((1.0, 0.7), (2.0, 0.18)), 2402),
        soft_noise(0.60, 380.0, 0.14, 2403),
    )


def sfx_jump() -> list[float]:
    # 短促上行音，像身体离开地面；不是一段“呼”的白噪
    return mix(
        tone_sweep(0.20, 170.0, 260.0, 0.36, 7.0, ((1.0, 0.7), (2.0, 0.2), (3.0, 0.05)), 2501),
        soft_noise(0.13, 600.0, 0.08, 2502),
        thump(0.14, 90.0, 0.10, 22.0, 2503),
    )


def sfx_double_jump() -> list[float]:
    # 蒸汽是低通气声 + 上行哨音；高频白噪压到很低，避免“嘶”一声
    return mix(
        tone_sweep(0.38, 300.0, 520.0, 0.30, 4.5, ((1.0, 0.6), (2.0, 0.18)), 2601),
        soft_noise(0.42, 1100.0, 0.22, 2602, attack=0.04),
        thump(0.22, 105.0, 0.10, 14.0, 2603),
    )


def sfx_land() -> list[float]:
    return mix(
        thump(0.30, 62.0, 0.62, 12.0, 2701),
        soft_noise(0.20, 380.0, 0.12, 2702),
    )


def sfx_step() -> list[float]:
    return mix(
        thump(0.11, 100.0, 0.28, 28.0, 2801),
        soft_noise(0.06, 300.0, 0.05, 2802),
    )


def sfx_hurt() -> list[float]:
    return mix(
        thump(0.24, 80.0, 0.34, 15.0, 2901),
        tone_sweep(0.22, 240.0, 150.0, 0.20, 8.0, ((1.0, 0.6), (2.0, 0.15)), 2902),
        soft_noise(0.10, 450.0, 0.07, 2903),
    )


def sfx_death() -> list[float]:
    n = int(RATE * 2.4)
    buf = [0.0] * n
    add(buf, modal_bell(2.3, 55.0, 0.45, 1.2, 3001, 0.08))
    add(buf, thump(1.0, 40.0, 0.25, 4.0, 3002))
    add(buf, choir_note(1.5, 82.0, 0.12, 3003, 0.12, 0.4), 0.15)
    add(buf, wind_bed(2.4, 0.04, 3004, 140.0))
    return buf


def sfx_bell() -> list[float]:
    return mix(
        modal_bell(4.4, 110.0, 0.72, 1.1, 3101, 0.16),
        modal_bell(4.2, 196.0, 0.30, 1.8, 3102, 0.06),
        modal_bell(3.6, 293.0, 0.14, 2.2, 3103, 0.03),
    )


def sfx_chain() -> list[float]:
    n = int(RATE * 0.75)
    buf = [0.0] * n
    rng = random.Random(3201)
    for _ in range(8):
        at = rng.uniform(0.0, 0.55)
        f = rng.uniform(520.0, 1100.0)
        add(buf, metal_tick(0.30, f, rng.uniform(0.10, 0.22), int(f)), at)
    add(buf, thump(0.3, 70.0, 0.10, 12.0, 3202), 0.0)
    return buf


def sfx_gate() -> list[float]:
    # 石闸下沉：低频移动感 + 少量摩擦，金属锁扣单独响
    n = int(RATE * 1.4)
    buf = [0.0] * n
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.12) * min(1.0, (1.4 - t) / 0.5)
        buf[i] = (0.18 * math.sin(TAU * (48.0 + 6.0 * math.exp(-3.0 * t)) * t)
                  + 0.10 * math.sin(TAU * 96.0 * t + 0.7)) * env
    add(buf, soft_noise(1.0, 380.0, 0.16, 3301, 0.08))
    add(buf, metal_tick(0.5, 180.0, 0.16, 3302), 0.08)
    add(buf, metal_tick(0.4, 260.0, 0.10, 3303), 0.32)
    return buf


def voice_murmur(duration: float = 0.42, freq: float = 105.0, formant: float = 620.0,
                 amp: float = 0.20, seed: int = 3401) -> list[float]:
    n = int(RATE * duration)
    # 声门脉冲是主体；带通噪声只做一点点气声，不能反客为主
    breath = bandpass(soft_noise(duration, 900.0, 1.0, seed, 0.02), formant, 1.6)
    out = []
    for i in range(n):
        t = i / RATE
        p = i / max(1, n - 1)
        glottal = (0.58 * math.sin(TAU * freq * t)
                   + 0.20 * math.sin(TAU * freq * 2.0 * t + 0.5)
                   + 0.07 * math.sin(TAU * freq * 3.01 * t + 1.1))
        vowel = 0.18 * math.sin(TAU * formant * t + 0.8)
        shape = math.sin(math.pi * min(1.0, p * 1.15)) ** 0.8
        trem = 0.82 + 0.18 * math.sin(TAU * 7.0 * t)
        out.append((glottal * 0.78 + vowel * 0.16 + breath[i] * 0.14) * shape * trem * amp)
    return out


def sfx_dialogue() -> list[float]:
    return mix(
        voice_murmur(0.38, 118.0, 640.0, 0.16, 3402),
        karplus(0.2, 520.0, 0.05, 0.995, 3403),
    )


def sfx_voice_murmur() -> list[float]:
    # 比 dialogue 更纯粹：不叠拨弦提示音，专门给 NPC 每句开头
    return voice_murmur(0.42, 100.0, 560.0, 0.20, 3404)


def sfx_voice_whisper() -> list[float]:
    return mix(
        voice_murmur(0.75, 92.0, 480.0, 0.08, 3405),
        sfx_whisper(),
    )


def sfx_whisper() -> list[float]:
    # 气声压低频、并加一点极轻的声带音，避免变成纯白噪
    n = int(RATE * 1.1)
    body = soft_noise(1.1, 1100.0, 0.10, 3501, 0.02)
    out = []
    for i in range(n):
        t = i / RATE
        p = i / max(1, n - 1)
        syl = max(0.0, math.sin(math.pi * (p * 2.4 % 1.0))) ** 2
        tone = 0.015 * math.sin(TAU * (180.0 + 30.0 * math.sin(TAU * 2.0 * t)) * t)
        out.append((body[i] + tone) * syl * (0.4 + 0.6 * math.sin(math.pi * p)))
    return out


def sfx_slime_voice() -> list[float]:
    return mix(
        tone_sweep(0.40, 135.0, 88.0, 0.32, 5.0, ((1.0, 0.65), (2.0, 0.2)), 3601),
        soft_noise(0.36, 300.0, 0.10, 3602),
        thump(0.28, 90.0, 0.10, 12.0, 3603),
    )


def sfx_spore_voice() -> list[float]:
    return mix(
        tone_sweep(0.42, 190.0, 140.0, 0.24, 6.0, ((1.0, 0.6), (2.0, 0.18)), 3701),
        soft_noise(0.40, 850.0, 0.12, 3702),
    )


def sfx_boss_roar() -> list[float]:
    n = int(RATE * 1.8)
    buf = [0.0] * n
    raw = noise(n, 3801)
    growl = bandpass(raw, 170.0, 0.7)
    for i in range(n):
        t = i / RATE
        p = i / max(1, n - 1)
        vib = 1.0 + 0.045 * math.sin(TAU * 5.2 * t)
        body = (0.55 * math.sin(TAU * 55.0 * vib * t)
                + 0.25 * math.sin(TAU * 73.0 * t + 0.4)
                + 0.10 * math.sin(TAU * 109.0 * t + 1.1))
        shape = math.sin(math.pi * min(1.0, p * 1.1)) ** 0.7
        # 胸腔低频为主，噪声只做粗糙边缘
        buf[i] = (body * 0.78 + growl[i] * 0.30) * shape
    return buf


def sfx_boss_charge() -> list[float]:
    return mix(
        thump(0.6, 43.0, 0.46, 4.0, 3901),
        tone_sweep(0.6, 38.0, 62.0, 0.18, 3.0, ((1.0, 0.6), (2.0, 0.15)), 3902),
        soft_noise(0.55, 260.0, 0.16, 3903),
    )


def sfx_boss_slam() -> list[float]:
    return mix(
        thump(0.8, 38.0, 0.70, 4.0, 4001),
        thump(0.7, 74.0, 0.35, 6.0, 4002),
        tone_sweep(0.7, 120.0, 42.0, 0.20, 3.5, ((1.0, 0.6), (2.0, 0.15)), 4003),
        soft_noise(0.5, 420.0, 0.18, 4004),
    )


def sfx_shockwave() -> list[float]:
    return mix(
        thump(0.55, 55.0, 0.48, 5.0, 4101),
        tone_sweep(0.5, 90.0, 45.0, 0.22, 5.0, ((1.0, 0.6), (2.0, 0.15)), 4102),
        soft_noise(0.45, 480.0, 0.16, 4103),
    )


def sfx_boss_down() -> list[float]:
    return mix(
        thump(1.3, 36.0, 0.58, 3.0, 4201),
        modal_bell(2.2, 55.0, 0.34, 1.3, 4202, 0.08),
        soft_noise(1.2, 320.0, 0.12, 4203),
    )


def sfx_heal() -> list[float]:
    return mix(
        modal_bell(0.7, 392.0, 0.20, 4.0, 4301, 0.03),
        modal_bell(0.9, 523.0, 0.14, 5.0, 4302, 0.02),
        choir_note(0.6, 330.0, 0.06, 4303, 0.03, 0.25),
    )


def sfx_checkpoint() -> list[float]:
    return mix(
        modal_bell(0.8, 330.0, 0.20, 4.0, 4401),
        modal_bell(0.8, 440.0, 0.14, 5.0, 4402),
        soft_noise(0.18, 500.0, 0.05, 4403),
    )


def sfx_pickup() -> list[float]:
    return mix(
        modal_bell(0.65, 660.0, 0.20, 5.0, 4501, 0.02),
        modal_bell(0.55, 990.0, 0.12, 6.0, 4502, 0.01),
        choir_note(0.45, 550.0, 0.05, 4503, 0.02, 0.2),
    )


def sfx_weapon_pickup() -> list[float]:
    return mix(
        metal_tick(0.65, 220.0, 0.35, 4601),
        metal_tick(0.55, 440.0, 0.20, 4602),
        modal_bell(0.9, 880.0, 0.08, 4.0, 4603, 0.02),
        thump(0.35, 90.0, 0.15, 10.0, 4604),
    )


def sfx_boots_pickup() -> list[float]:
    return mix(
        soft_noise(0.50, 850.0, 0.18, 4701, 0.03),
        tone_sweep(0.45, 320.0, 520.0, 0.16, 4.0, ((1.0, 0.6), (2.0, 0.15)), 4702),
        metal_tick(0.30, 180.0, 0.10, 4703),
    )


def sfx_relic_pickup() -> list[float]:
    n = int(RATE * 1.3)
    buf = [0.0] * n
    add(buf, modal_bell(1.2, 196.0, 0.35, 1.6, 4801, 0.04))
    add(buf, modal_bell(1.1, 392.0, 0.22, 2.2, 4802, 0.02), 0.12)
    add(buf, choir_note(1.0, 294.0, 0.12, 4803, 0.05, 0.3), 0.2)
    add(buf, tone_sweep(0.7, 300.0, 620.0, 0.10, 4.0, ((1.0, 0.6), (2.0, 0.15)), 4804), 0.0)
    return buf


def sfx_chest_open() -> list[float]:
    n = int(RATE * 1.1)
    buf = [0.0] * n
    # 木头吱呀用低通噪声，加 180/240Hz 的木腔音；不再用整段高频白噪
    raw = soft_noise(1.1, 450.0, 0.18, 4901, 0.05)
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.18) * min(1.0, (1.1 - t) / 0.4)
        buf[i] += raw[i] * env * (0.7 + 0.3 * math.sin(TAU * 3.3 * t))
    add(buf, metal_tick(0.4, 480.0, 0.18, 4902), 0.16)
    add(buf, tone_sweep(0.7, 220.0, 160.0, 0.14, 3.0, ((1.0, 0.65), (2.0, 0.18)), 4903), 0.02)
    add(buf, modal_bell(0.5, 260.0, 0.10, 4.0, 4904, 0.02), 0.2)
    return buf


def sfx_altar() -> list[float]:
    n = int(RATE * 1.2)
    buf = [0.0] * n
    add(buf, choir_note(1.1, 110.0, 0.18, 5001, 0.04, 0.4))
    add(buf, modal_bell(1.0, 147.0, 0.18, 2.0, 5002, 0.03))
    add(buf, heartbeat_layer(1.0, 0.8, 0.12))
    return buf


def sfx_sacrifice() -> list[float]:
    n = int(RATE * 2.0)
    buf = [0.0] * n
    add(buf, heartbeat_layer(1.9, 0.62, 0.28))
    add(buf, choir_note(1.8, 110.0, 0.18, 5101, 0.08, 0.5))
    add(buf, choir_note(1.4, 164.0, 0.14, 5102, 0.06, 0.5), 0.35)
    add(buf, modal_bell(1.6, 73.0, 0.22, 1.5, 5103, 0.05))
    add(buf, tone_sweep(1.1, 90.0, 160.0, 0.10, 3.0, ((1.0, 0.65), (2.0, 0.15)), 5104))
    return buf


def sfx_transition() -> list[float]:
    return mix(
        tone_sweep(1.1, 70.0, 140.0, 0.28, 3.0, ((1.0, 0.7), (2.0, 0.16)), 5201),
        soft_noise(0.9, 500.0, 0.10, 5202),
        thump(0.9, 42.0, 0.30, 6.0, 5203),
        choir_note(1.1, 82.0, 0.10, 5204, 0.04, 0.35),
    )


def sfx_ending() -> list[float]:
    return mix(
        modal_bell(2.2, 220.0, 0.22, 2.0, 5301, 0.02),
        modal_bell(2.0, 330.0, 0.16, 2.5, 5302, 0.01),
        choir_note(2.0, 110.0, 0.10, 5303, 0.04, 0.3),
    )


def sfx_true_he() -> list[float]:
    n = int(RATE * 3.0)
    buf = [0.0] * n
    add(buf, modal_bell(2.8, 330.0, 0.22, 1.8, 5401, 0.03))
    add(buf, modal_bell(2.5, 440.0, 0.18, 2.0, 5402, 0.02), 0.25)
    add(buf, modal_bell(2.2, 554.0, 0.15, 2.2, 5403, 0.01), 0.55)
    add(buf, choir_note(2.6, 220.0, 0.10, 5404, 0.05, 0.3), 0.2)
    return buf


def sfx_spore_charge() -> list[float]:
    return mix(
        tone_sweep(0.50, 130.0, 240.0, 0.26, 4.0, ((1.0, 0.65), (2.0, 0.18)), 5501),
        soft_noise(0.45, 600.0, 0.16, 5502),
        thump(0.35, 120.0, 0.10, 10.0, 5503),
    )


def sfx_spore_fire() -> list[float]:
    return mix(
        tone_sweep(0.26, 520.0, 300.0, 0.26, 7.0, ((1.0, 0.6), (2.0, 0.18)), 5601),
        soft_noise(0.24, 700.0, 0.12, 5602),
        thump(0.20, 160.0, 0.10, 14.0, 5603),
    )


def sfx_steam() -> list[float]:
    return mix(
        soft_noise(0.50, 900.0, 0.34, 5701, 0.03),
        thump(0.40, 110.0, 0.10, 10.0, 5702),
        metal_tick(0.25, 320.0, 0.06, 5703),
    )


def sfx_ui() -> list[float]:
    # UI 只要一个短木/骨提示音，不铺噪声
    return mix(
        modal_bell(0.18, 880.0, 0.10, 9.0, 5801, 0.0),
        metal_tick(0.18, 880.0, 0.05, 5802),
    )


def sfx_ui_hover() -> list[float]:
    return modal_bell(0.12, 660.0, 0.06, 12.0, 5901, 0.0)


def sfx_pause() -> list[float]:
    return mix(
        tone_sweep(0.22, 260.0, 140.0, 0.22, 6.0, ((1.0, 0.65), (2.0, 0.18)), 6001),
        thump(0.20, 110.0, 0.16, 18.0, 6002),
        soft_noise(0.14, 500.0, 0.04, 6003),
    )


def sfx_boss_hit() -> list[float]:
    return mix(
        metal_tick(0.28, 118.0, 0.35, 6101),
        metal_tick(0.22, 236.0, 0.18, 6102),
        thump(0.28, 58.0, 0.30, 12.0, 6103),
    )


SFX_TABLE = [
    ("hit", 0.24, sfx_hit),
    ("swing", 0.24, sfx_swing),
    ("pogo", 0.32, sfx_pogo),
    ("enemy_hit", 0.20, sfx_enemy_hit),
    ("enemy_die", 0.75, sfx_enemy_die),
    ("boss_hit", 0.28, sfx_boss_hit),
    ("boss_roar", 1.80, sfx_boss_roar),
    ("boss_charge", 0.60, sfx_boss_charge),
    ("boss_slam", 0.80, sfx_boss_slam),
    ("shockwave", 0.55, sfx_shockwave),
    ("boss_down", 1.60, sfx_boss_down),
    ("jump", 0.20, sfx_jump),
    ("double_jump", 0.40, sfx_double_jump),
    ("land", 0.30, sfx_land),
    ("step", 0.11, sfx_step),
    ("hurt", 0.28, sfx_hurt),
    ("death", 2.40, sfx_death),
    ("heal", 0.90, sfx_heal),
    ("checkpoint", 0.80, sfx_checkpoint),
    ("pickup", 0.65, sfx_pickup),
    ("weapon_pickup", 0.90, sfx_weapon_pickup),
    ("boots_pickup", 0.55, sfx_boots_pickup),
    ("relic_pickup", 1.30, sfx_relic_pickup),
    ("chest_open", 1.10, sfx_chest_open),
    ("ui", 0.18, sfx_ui),
    ("ui_hover", 0.12, sfx_ui_hover),
    ("pause", 0.22, sfx_pause),
    ("dialogue", 0.38, sfx_dialogue),
    ("whisper", 1.10, sfx_whisper),
    ("bell", 4.40, sfx_bell),
    ("gate", 1.40, sfx_gate),
    ("chain", 0.75, sfx_chain),
    ("altar", 1.20, sfx_altar),
    ("sacrifice", 2.00, sfx_sacrifice),
    ("transition", 1.20, sfx_transition),
    ("ending", 2.20, sfx_ending),
    ("true_he", 3.00, sfx_true_he),
    ("spore_charge", 0.50, sfx_spore_charge),
    ("spore_fire", 0.26, sfx_spore_fire),
    ("steam", 0.50, sfx_steam),
    ("voice_murmur", 0.42, sfx_voice_murmur),
    ("voice_whisper", 1.10, sfx_voice_whisper),
    ("slime_voice", 0.40, sfx_slime_voice),
    ("spore_voice", 0.42, sfx_spore_voice),
]
# --sfx-only 只重跑音效，--bgm-only 只重跑曲子；避免每次调一层都等全部
if not BGM_ONLY:
    for name, duration, fn in SFX_TABLE:
        # 这几条由 tools/import_sfx.py 从录音库切，重跑合成会把真录音覆盖掉
        if name in CUSTOM_SFX:
            continue
        make_sfx(name, duration, fn)

print(f"done -> {OUT}")
