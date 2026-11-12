"""用录音库的真实乐器渲染 BGM、一次性音乐层和环境音。

为什么换掉合成：之前的 BGM 是正弦 + 白噪声堆出来的，听感就是“电子嗡嗡”，
再怎么调参数也不会像真乐器。这里改成采样真实录音（VSCO 2 CE 的弦乐 / 竖琴 /
管钟 / 定音鼓，Meta 的钢琴和环境录音），乐谱仍是原来那份，只换音色。

素材不进仓库：tools/fetch_audio_samples.ps1 负责下载，tools/audio_fundamentals.json
记录每个素材的音高，tools/audio_samples.py 负责按音高触发。

44100Hz 而不是 22050：真实录音的细节在 11kHz 以上，沿用旧采样率会把“空气感”砍掉。

运行：python tools/generate_music.py [--stems]
输出：client/assets/audio/*.wav（44100Hz / 单声道 / PCM16）
"""

import math
import random
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import lfilter

import audio_samples as smp

OUT = Path(__file__).resolve().parents[1] / "client" / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 44100
DEBUG_STEMS = "--stems" in sys.argv


# ---------------------------------------------------------------------------
# 基础设施
# ---------------------------------------------------------------------------

def add(buf: np.ndarray, seg, start: float = 0.0) -> None:
    seg = np.asarray(seg, dtype=np.float64)
    at = max(0, int(start * RATE))
    if at >= len(buf):
        return
    end = min(len(buf), at + len(seg))
    buf[at:end] += seg[:end - at]


def mix() -> np.ndarray:
    return np.zeros(0, dtype=np.float64)


def normalize(samples: np.ndarray, peak: float = 0.8) -> np.ndarray:
    top = float(np.max(np.abs(samples))) if len(samples) else 0.0
    if top < 1e-9:
        return samples
    return samples * (peak / top)


def highpass(samples: np.ndarray, cutoff: float) -> np.ndarray:
    """一阶 RC 高通。

    y[n] = α(y[n-1] + x[n] − x[n-1])，α = 1/(1 + 2πfc/fs)。
    极点必须落在 α 上；写成 (1−α) 极点在 0 附近，截止频率会跑到 fs/8 左右，
    等于把 5kHz 以下全砍掉、只剩录音的高频噪声——那就是“电视沙沙”。
    """
    alpha = 1.0 / (1.0 + math.tau * cutoff / RATE)
    return lfilter([alpha, -alpha], [1.0, -alpha], samples)


def loop_crossfade(samples: np.ndarray, seconds: float = 1.0) -> np.ndarray:
    """把尾巴叠回开头，循环接缝才不会突然断掉。"""
    fade_n = max(1, int(RATE * seconds))
    if len(samples) <= fade_n * 2:
        return samples
    body_n = len(samples) - fade_n
    head = samples[:fade_n].copy()
    tail = samples[body_n:body_n + fade_n]
    ramp = np.sqrt(np.linspace(0.0, 1.0, fade_n))
    samples[:fade_n] = head * ramp + tail * (1.0 - ramp)
    return samples[:body_n]


def write_wav(path: Path, samples: np.ndarray) -> None:
    """原样写盘；电平由调用方（finalize / to_peak）决定，这里只做钳位。"""
    pcm = np.clip(np.asarray(samples, dtype=np.float64), -1.0, 1.0)
    data = (pcm * 32767.0).astype("<i2").tobytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data)


def rms(samples) -> float:
    arr = np.asarray(samples, dtype=np.float64)
    if arr.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(arr * arr)))


def db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-9))


def to_rms(samples, target_db: float):
    """按均方根把一层摆到目标电平。持续层用它，不受素材本身录音电平影响。"""
    samples = np.asarray(samples, dtype=np.float64)
    cur = rms(samples)
    if cur < 1e-9:
        return samples
    return samples * (10.0 ** (target_db / 20.0) / cur)


def to_peak(samples, target_db: float):
    """按峰值摆电平。钟、拨弦这类瞬态层用 RMS 摆会被瞬态骗。"""
    samples = np.asarray(samples, dtype=np.float64)
    top = float(np.max(np.abs(samples))) if len(samples) else 0.0
    if top < 1e-9:
        return samples
    return samples * (10.0 ** (target_db / 20.0) / top)


def finalize(samples, *, rms_db: float, ceiling: float):
    """先摆 RMS，再压峰值上限，最后交给 write_wav 原样写盘。"""
    samples = to_rms(samples, rms_db)
    top = float(np.max(np.abs(samples))) if len(samples) else 0.0
    if top > ceiling:
        samples = samples * (ceiling / top)
    return samples


def stem(label: str, seg) -> None:
    if DEBUG_STEMS:
        print(f"    stem {label:<12} rms={db(rms(seg)):6.1f} dBFS  len={len(seg)/RATE:5.2f}s")


def schroeder(samples: np.ndarray, wet: float = 0.26, decay: float = 1.9) -> np.ndarray:
    """梳状 + 全通混响。

    不用卷积混响：卷积要一条噪声脉冲响应，那本身就是“沙沙”底噪的来源。
    """
    dry = samples.copy()
    wet_sum = np.zeros_like(samples)
    for delay_s, fb in ((0.0297, 0.72), (0.0371, 0.70), (0.0411, 0.68), (0.0437, 0.66)):
        d = int(delay_s * RATE)
        g = fb * decay / 2.0
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -g
        wet_sum += lfilter([1.0], a, samples)
    out = dry * (1.0 - wet) + (wet_sum / 4.0) * wet
    for delay_s in (0.0051, 0.0017):
        d = int(delay_s * RATE)
        g = 0.7
        b = np.zeros(d + 1)
        b[0] = -g
        b[d] = 1.0
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -g
        out = lfilter(b, a, out)
    return out


# ---------------------------------------------------------------------------
# 乐器选择：按“离素材音高最近”挑采样。
#
# 先前用音域分档，82Hz 的和弦音被送到 220Hz 的大提琴上，等于降 17 个半音，
# 音色整个变形。改成按音分距离取最近，谁都只挪几个半音。
# ---------------------------------------------------------------------------

PAD_BANK = ["vsco_contrabass", "vsco_cello_a2", "vsco_cello", "vsco_violin_c4", "vsco_violin"]
PLUCK_BANK = ["vsco_harp_c3", "vsco_harp_c5", "meta_piano_c4"]


def _nearest(bank, freq: float) -> str:
    return min(bank, key=lambda k: abs(12.0 * math.log2(freq / smp.base_freq(k))))


def pick(freq: float) -> str:
    return _nearest(PAD_BANK, freq)


def pluck(freq: float) -> str:
    return _nearest(PLUCK_BANK, freq)


def pad_chord(freqs, duration: float, amp: float, seed: int, attack: float = 0.5,
              release: float = 1.4) -> np.ndarray:
    """弦乐和声垫。每个音轻微失谐，才有群奏的厚度，不然像一根合成器长音。"""
    out = np.zeros(int(duration * RATE), dtype=np.float64)
    rng = random.Random(seed)
    for f in freqs:
        detune = 1.0 + rng.choice((-1.0, 1.0)) * 0.0028
        add(out, smp.note(
            pick(f), f * detune, duration, gain=amp,
            attack=attack + rng.random() * 0.2, release=release,
            offset=0.28 + rng.random() * 0.18,
        ))
    return out


def pluck_note(freq: float, duration: float, amp: float) -> np.ndarray:
    return np.asarray(smp.note(pluck(freq), freq, max(0.25, duration), gain=amp,
                               attack=0.005, release=min(1.0, duration * 0.6), offset=0.0))


def bell_note(freq: float, amp: float, tail: float) -> np.ndarray:
    return np.asarray(smp.hit("vsco_bell_c4", tail, gain=amp, hz=freq,
                              release=min(1.6, tail * 0.4)))


def timp(freq: float, amp: float, duration: float = 1.6) -> np.ndarray:
    return np.asarray(smp.hit("vsco_timpani", duration, gain=amp, hz=freq, release=0.8))


def cue(key: str, duration: float, start: float, gain: float) -> np.ndarray:
    """从一条真实录音里截一段（音乐层、环境音都用它）。"""
    src = np.asarray(smp.load(key), dtype=np.float64)
    a = int(start * RATE)
    b = min(len(src), a + int(duration * RATE))
    seg = src[a:b].copy()
    if len(seg) < int(duration * RATE):
        seg = np.pad(seg, (0, int(duration * RATE) - len(seg)))
    return seg * gain


# ---------------------------------------------------------------------------
# BGM
# ---------------------------------------------------------------------------

# 每层摆到固定的电平，混出来才不会“垫子听不见、钟又炸耳朵”。
# 这一组数是听感参数，觉得哪层不对就改这里，不用去翻到每首曲子。
LAYER_RMS = {
    "drone": -31.0,
    "fifth": -37.0,
    "pad": -25.0,
    "pad_high": -31.0,
    "voiced": -29.0,
}
LAYER_PEAK = {
    "bell": -17.0,
    "pluck": -20.0,
    "timp": -20.0,
}
BGM_RMS = -19.5
BGM_CEILING = 0.76


def melody_note(inst: str, freq: float, duration: float, level: float = 0.0) -> np.ndarray:
    """一个旋律音。按乐器分档摆电平：拨弦和钟是瞬态，弦乐是持续层。"""
    if inst == "bell":
        return to_peak(bell_note(freq, 1.0, min(6.0, duration + 2.0)), LAYER_PEAK["bell"] + level)
    if inst == "harp":
        return to_peak(pluck_note(freq, duration, 1.0), LAYER_PEAK["pluck"] + level)
    if inst == "bass":
        key = "vsco_cello_a2"     # 低音区用 A2 那支，往下变调只要半个八度，不会糊
    elif inst == "cello":
        key = "vsco_cello"
    else:
        key = "vsco_violin"
    return to_rms(
        np.asarray(smp.note(key, freq, duration, gain=1.0,
                            attack=min(0.25, duration * 0.2),
                            release=min(1.4, duration * 0.5))),
        LAYER_RMS["voiced"] + level,
    )


def render_bgm(name: str, duration: float, *, root: float, chords,
               melody=(), figure=None, perc: str = "", perc_period: float = 0.75,
               bells=(), pad_gain: float = 0.0, high_pad: bool = True, drone_db: float = 0.0,
               seed: int = 0) -> None:
    """一首循环曲。

    之前七首听着一样，是因为都用同一个模板：持续音 + 和弦垫 + 同样的稀疏拨弦，
    只换了根音和音区。现在每首给一件“主奏乐器”和一条自己的动机：
    菜单只有钟、教学是竖琴四音上行、第一层是下行五音、第二层是机械脉冲、
    第三层只有心跳和低音、战斗是小提琴快 ostinato、结局是一条完整旋律线。
    """
    buf = np.zeros(int(duration * RATE), dtype=np.float64)

    drone = to_rms(np.asarray(smp.note("vsco_contrabass", root * 0.5 if root > 70 else root,
                                       duration, gain=0.30, attack=2.2, release=3.2)),
                   LAYER_RMS["drone"] + drone_db)
    add(buf, drone)
    fifth = to_rms(np.asarray(smp.note("vsco_contrabass", root * 0.75 if root > 70 else root * 1.5,
                                       duration, gain=0.14, attack=2.8, release=3.2)),
                   LAYER_RMS["fifth"])
    add(buf, fifth)

    for start, length, freqs in chords:
        low = to_rms(pad_chord(freqs, length, 1.0, seed + int(start * 7)),
                     LAYER_RMS["pad"] + pad_gain)
        add(buf, low, start)
        if high_pad:
            high = to_rms(pad_chord([f * 2.0 for f in freqs], length, 1.0, seed + int(start * 7) + 5),
                          LAYER_RMS["pad_high"] + pad_gain)
            add(buf, high, start)

    if figure:
        period = float(figure["period"])
        inst = figure["inst"]
        dur = float(figure.get("dur", 2.0))
        level = float(figure.get("level", 0.0))
        t = 0.0
        while t < duration - 0.4:
            for off, freq in figure["notes"]:
                if t + off < duration - 0.4:
                    add(buf, melody_note(inst, freq, dur, level), t + off)
            t += period

    for start, freq, length, inst in melody:
        add(buf, melody_note(inst, freq, length), start)

    for start, freq, level in bells:
        add(buf, to_peak(bell_note(freq, 1.0, 5.0), LAYER_PEAK["bell"] + level), start)

    if perc == "timp":
        t = 0.0
        while t < duration - 0.5:
            add(buf, to_peak(timp(root, 1.0, 1.2), LAYER_PEAK["timp"] + 2.0), t)
            t += perc_period
    elif perc == "heart":
        t = 0.0
        while t < duration - 1.0:
            add(buf, to_peak(timp(root, 1.0, 1.4), LAYER_PEAK["timp"] + 3.0), t)
            add(buf, to_peak(timp(root, 1.0, 1.2), LAYER_PEAK["timp"] + 7.0), t + 0.28)
            t += 1.34

    samples = loop_crossfade(schroeder(highpass(buf, 30.0), 0.22, 2.0), 1.1)
    samples = finalize(samples, rms_db=BGM_RMS, ceiling=BGM_CEILING)
    write_wav(OUT / (name + ".wav"), samples)
    print(f"{name}.wav: {len(samples) / RATE:.2f}s  rms={db(rms(samples)):.1f} dBFS"
          f"  peak={np.max(np.abs(samples)):.2f}")


# ---------------------------------------------------------------------------
# 一次性音乐层：直接剪真实录音，不再重新合成
# ---------------------------------------------------------------------------

def render_sting(name: str, duration: float, build, *, peak: float = 0.5) -> None:
    samples = np.asarray(build(), dtype=np.float64)
    want = int(duration * RATE)
    if len(samples) < want:
        samples = np.pad(samples, (0, want - len(samples)))
    samples = samples[:want]
    n_in = int(0.02 * RATE)
    n_out = int(0.45 * RATE)
    samples[:n_in] *= np.sqrt(np.linspace(0.0, 1.0, n_in))
    samples[-n_out:] *= np.sqrt(np.linspace(1.0, 0.0, n_out))
    samples = to_peak(schroeder(samples, 0.3, 2.2), db(peak))
    write_wav(OUT / (name + ".wav"), samples)
    print(f"{name}.wav: {duration:.2f}s  rms={db(rms(samples)):.1f} dBFS"
          f"  peak={np.max(np.abs(samples)):.2f}")


def sting_transition() -> np.ndarray:
    buf = np.zeros(int(7.0 * RATE), dtype=np.float64)
    add(buf, cue("meta_organ", 5.0, 0.0, 0.55), 1.2)
    add(buf, smp.note("vsco_contrabass", 55.0, 5.5, gain=0.22, attack=1.2, release=2.0))
    add(buf, smp.hit("vsco_gong", 4.0, gain=0.16, hz=73.42, release=2.0), 0.6)
    return buf


def sting_sacrifice() -> np.ndarray:
    """献祭是高频动作，别再上一次大编制。

    原来六秒、管风琴 + 锣 + 两下定音鼓，每次献祭都来一遍，动静比动作还大。
    现在三秒半：一声低钟、一下闷鼓、一记轻钟，不用弦乐。
    """
    buf = np.zeros(int(3.6 * RATE), dtype=np.float64)
    add(buf, to_peak(smp.hit("vsco_bell_c4", 3.4, gain=1.0, hz=196.0, release=1.2), -13.0))
    add(buf, to_peak(smp.hit("vsco_timpani", 2.0, gain=1.0, hz=65.41, release=1.0), -20.0), 0.15)
    add(buf, to_peak(smp.hit("vsco_bell_c4", 1.8, gain=1.0, hz=392.0, release=0.8), -26.0), 0.6)
    return buf


def sting_death() -> np.ndarray:
    """死亡：一条低音提琴长音 + 一条大提琴 + 一声钟，收干净。

    之前结尾接了一段不谐和弦乐，听着刺耳；那层已经去掉。
    """
    buf = np.zeros(int(8.0 * RATE), dtype=np.float64)
    add(buf, to_rms(np.asarray(smp.note("vsco_contrabass", 55.0, 7.5, gain=1.0,
                                        attack=1.6, release=2.4)), -20.0))
    add(buf, to_rms(np.asarray(smp.note("vsco_cello", 65.41, 6.0, gain=1.0,
                                        attack=2.0, release=2.0)), -25.0), 0.8)
    add(buf, to_peak(smp.hit("vsco_bell_c4", 6.0, gain=1.0, hz=65.41, release=2.0), -18.0), 0.3)
    return buf


# ---------------------------------------------------------------------------
# 环境音：真实房间底噪 + 风铃
# ---------------------------------------------------------------------------

def lowpass(samples: np.ndarray, cutoff: float, order: int = 1) -> np.ndarray:
    """一阶 RC 低通，串 order 级就是 order 阶（每级 −6dB/oct）。

    单级下不去：机房底噪单级 2200Hz 只把 8kHz 压 11dB，剩下的全是“沙沙”。
    """
    alpha = 1.0 - math.exp(-math.tau * cutoff / RATE)
    out = samples
    for _ in range(max(1, order)):
        out = lfilter([alpha], [1.0, -(1.0 - alpha)], out)
    return out


def _window_levels(src: np.ndarray, seconds: float, start_min: float = 4.0):
    """把素材按 1 秒窗口扫一遍，返回 (起点秒数列表, 每窗 RMS)。"""
    win = int(1.0 * RATE)
    span = int(seconds * RATE)
    pos, level = [], []
    i = int(start_min * RATE)
    while i + max(win, span) <= len(src):
        seg = src[i:i + win]
        pos.append(i / RATE)
        level.append(float(np.sqrt(np.mean(seg * seg))))
        i += win // 2
    return pos, np.array(level)


def bed_window(src: np.ndarray, seconds: float) -> float:
    """挑一段有代表性的底噪：靠近整条素材的中上音量。

    不能只按这一段自己的 RMS 归一：安静的段会被整体拉起来，
    连同素材的噪声底一起放大，听感就是持续沙沙。
    """
    pos, level = _window_levels(src, seconds)
    if len(level) == 0:
        return 4.0
    target = float(np.percentile(level, 70))
    return pos[int(np.argmin(np.abs(level - target)))]


def bed_median_rms(src: np.ndarray) -> float:
    _, level = _window_levels(src, 1.0)
    return float(np.median(level)) if len(level) else 0.0


def ambience(name: str, duration: float, bed: str, *, lp: float = 0.0, order: int = 2,
             start_at: float = -1.0, chimes_db: float = -999.0, chimes_at: float = 3.0) -> None:
    src = np.asarray(smp.load(bed), dtype=np.float64)
    if start_at < 0:
        start_at = bed_window(src, duration)
    buf = highpass(cue(bed, duration, start_at, 1.0), 20.0)
    if lp > 0:
        buf = lowpass(buf, lp, order)
    # 电平按整条素材的中位音量摆，不按这一段自己的音量摆：
    # 安静段按自己的 RMS 拉起来，噪声底会一起被放大成沙沙声
    median = max(bed_median_rms(src), 1e-9)
    buf = buf * (10.0 ** (-30.0 / 20.0) / median)
    if chimes_db > -900.0:
        # 风铃是稀疏瞬态，按峰值摆；按 RMS 摆会被它自己的静音段骗到很轻
        add(buf, to_peak(cue("meta_chimes", duration * 0.8, chimes_at, 1.0), chimes_db))
    samples = loop_crossfade(buf, 0.7)
    top = float(np.max(np.abs(samples))) if len(samples) else 0.0
    if top > 0.55:
        samples = samples * (0.55 / top)
    write_wav(OUT / ("amb_" + name + ".wav"), samples)
    print(f"amb_{name}.wav: {len(samples) / RATE:.2f}s  rms={db(rms(samples)):.1f} dBFS"
          f"  peak={np.max(np.abs(samples)):.2f}  start={start_at:.1f}s")


# ---------------------------------------------------------------------------
# 曲目数据（与 M4-14 版一致：调式、和弦、动机都没改，只换音色）
# ---------------------------------------------------------------------------

def render_all() -> None:
    """按下面这份曲目表重新渲染全部音乐资产。","""
    # 主菜单：只有低音持续、钟声和一点点竖琴。没有人声、没有鼓，坐着等门开。
    render_bgm(
        "bgm_menu", 72.0,
        root=55.0,
        chords=[(0.0, 12.0, [55, 82, 110]), (12.0, 12.0, [55, 82, 123]),
                (24.0, 12.0, [49, 73, 110]), (36.0, 12.0, [55, 82, 110]),
                (48.0, 12.0, [49, 73, 98]), (60.0, 12.0, [55, 82, 123])],
        melody=[(0.4, 261.6, 2.4, "harp"), (26.0, 246.0, 3.0, "harp"),
                (38.0, 261.6, 2.6, "harp"), (62.0, 220.0, 3.2, "harp")],
        bells=[(5.0, 110.0, 0.0), (18.5, 82.0, -2.0), (30.0, 110.0, -3.0),
               (44.0, 82.0, -1.0), (58.0, 98.0, -2.0), (68.0, 110.0, -3.0)],
        pad_gain=-2.0,
        seed=101,
    )
    # 教学关：竖琴四音上行，2.4 秒一轮，明快好记。这是唯一带固定上行小句的曲子。
    render_bgm(
        "bgm_tutorial", 76.8,
        root=110.0,
        chords=[(0.0, 4.8, [110, 165, 220]), (4.8, 4.8, [110, 165, 247]),
                (9.6, 4.8, [98, 147, 196]), (14.4, 4.8, [110, 165, 220]),
                (19.2, 4.8, [110, 165, 247]), (24.0, 4.8, [98, 147, 196]),
                (28.8, 4.8, [110, 165, 220]), (33.6, 4.8, [110, 165, 247]),
                (38.4, 4.8, [98, 147, 196]), (43.2, 4.8, [110, 165, 220]),
                (48.0, 4.8, [98, 147, 196]), (52.8, 4.8, [110, 165, 247]),
                (57.6, 4.8, [110, 165, 220]), (62.4, 4.8, [110, 165, 247]),
                (67.2, 4.8, [98, 147, 196]), (72.0, 4.8, [110, 165, 220])],
        figure={"period": 2.4, "inst": "harp", "dur": 1.4, "level": 0.0,
                "notes": [(0.0, 440.0), (0.6, 494.0), (1.2, 587.0), (1.8, 494.0)]},
        pad_gain=-3.0,
        seed=202,
    )
    # 第一层：下行五音动机（E-D-C-A-G），8 秒一轮，钟声只在和声换的地方敲。
    render_bgm(
        "bgm_floor1", 80.0,
        root=82.0,
        chords=[(0.0, 10.0, [82, 123, 164]), (10.0, 10.0, [82, 123, 174]),
                (20.0, 10.0, [73, 110, 147]), (30.0, 10.0, [82, 123, 164]),
                (40.0, 10.0, [73, 110, 147]), (50.0, 10.0, [78, 117, 156]),
                (60.0, 10.0, [82, 123, 164]), (70.0, 10.0, [86, 129, 172])],
        figure={"period": 8.0, "inst": "harp", "dur": 1.6, "level": 0.0,
                "notes": [(0.0, 329.0), (1.2, 294.0), (2.4, 262.0), (3.6, 220.0), (5.4, 196.0)]},
        melody=[(3.0, 246.0, 4.0, "cello"), (22.0, 196.0, 4.5, "cello"),
                (31.0, 246.0, 3.5, "cello"), (43.0, 220.0, 4.0, "cello"),
                (52.0, 196.0, 4.0, "cello"), (63.0, 246.0, 4.0, "cello"),
                (72.0, 262.0, 4.0, "cello")],
        bells=[(4.2, 110.0, 1.5), (24.0, 82.0, 0.5), (46.0, 110.0, 1.0), (66.0, 86.0, 0.0)],
        pad_gain=-1.0,
        seed=303,
    )
    # 第二层：机械。没有旋律，只有每 0.75 秒一下的鼓和每 3 秒一记金属敲击。
    render_bgm(
        "bgm_floor2", 76.0,
        root=65.0,
        chords=[(0.0, 9.5, [65, 98, 130]), (9.5, 9.5, [65, 98, 139]),
                (19.0, 9.5, [58, 87, 116]), (28.5, 9.5, [65, 98, 130]),
                (38.0, 9.5, [58, 87, 116]), (47.5, 9.5, [62, 93, 124]),
                (57.0, 9.5, [65, 98, 130]), (66.5, 9.5, [58, 87, 116])],
        figure={"period": 3.0, "inst": "harp", "dur": 1.0, "level": -2.0,
                "notes": [(0.0, 196.0), (1.5, 175.0)]},
        perc="timp",
        bells=[(8.0, 130.0, -4.0), (21.0, 98.0, -5.0), (45.0, 116.0, -4.0),
               (64.0, 87.0, -5.0)],
        pad_gain=-2.0,
        seed=404,
    )
    # 第三层：没有旋律。低频持续 + 心跳 + 很久一次的高钟。
    render_bgm(
        "bgm_floor3", 80.0,
        root=49.0,
        chords=[(0.0, 13.3, [49, 73, 98]), (13.3, 13.3, [49, 73, 104]),
                (26.6, 13.3, [46, 69, 92]), (39.9, 13.3, [49, 73, 98]),
                (53.2, 13.3, [46, 69, 92]), (66.5, 13.5, [49, 73, 104])],
        melody=[(2.0, 147.0, 7.0, "cello"), (23.0, 123.0, 8.0, "cello"),
                (41.0, 147.0, 7.0, "cello"), (60.0, 110.0, 9.0, "cello")],
        perc="heart",
        bells=[(12.0, 73.0, -3.0), (34.0, 55.0, -4.0), (50.0, 73.0, -3.0),
               (72.0, 55.0, -4.0)],
        pad_gain=-3.0,
        seed=505,
    )
    # Boss 战：整首压低。原来是小提琴 440/494Hz 每 0.5 秒一下，又高又密，吵。
    # 现在低音提琴在底下持续，大提琴在 110/130Hz 走慢一倍的 ostinato，
    # 鼓点跟着同一拍走，不加八度上方的和弦垫。靠重量和节拍压人，不靠音高。
    render_bgm(
        "bgm_combat", 44.0,
        root=55.0,
        chords=[(0.0, 4.0, [55, 65, 82]), (4.0, 4.0, [55, 69, 82]),
                (8.0, 4.0, [49, 58, 73]), (12.0, 4.0, [55, 65, 82]),
                (16.0, 4.0, [55, 69, 82]), (20.0, 4.0, [49, 58, 73]),
                (24.0, 4.0, [55, 65, 82]), (28.0, 4.0, [52, 62, 78]),
                (32.0, 4.0, [49, 58, 73]), (36.0, 4.0, [55, 69, 82]),
                (40.0, 4.0, [49, 58, 73])],
        figure={"period": 1.0, "inst": "cello", "dur": 0.85, "level": 0.0,
                "notes": [(0.0, 220.0), (0.5, 262.0)]},
        melody=[(2.0, 147.0, 2.0, "bass"), (6.0, 165.0, 2.0, "bass"),
                (10.0, 147.0, 2.2, "bass"), (14.0, 130.0, 2.0, "bass"),
                (18.0, 165.0, 2.0, "bass"), (21.5, 147.0, 2.2, "bass"),
                (26.0, 130.0, 2.0, "bass"), (30.0, 147.0, 2.2, "bass"),
                (34.0, 130.0, 2.0, "bass"), (38.0, 165.0, 2.4, "bass"),
                (41.5, 147.0, 2.4, "bass")],
        perc="timp",
        perc_period=1.0,
        pad_gain=-1.0,
        high_pad=False,
        drone_db=-5.0,
        seed=606,
    )
    # 结局：一条完整旋律线（上行到 554 再回落），小提琴主奏、大提琴对位，没有鼓。
    render_bgm(
        "bgm_ending", 22.0,
        root=55.0,
        chords=[(0.0, 7.5, [55, 110, 165]), (7.0, 7.5, [55, 110, 196]),
                (14.5, 7.0, [49, 98, 147])],
        melody=[(0.5, 330.0, 2.2, "violin"), (3.0, 392.0, 2.2, "violin"),
                (5.5, 440.0, 2.6, "violin"), (8.5, 494.0, 2.2, "violin"),
                (11.0, 554.0, 3.2, "violin"), (15.0, 440.0, 2.2, "violin"),
                (18.0, 392.0, 3.0, "violin"),
                (2.0, 165.0, 5.0, "cello"), (12.0, 196.0, 6.0, "cello")],
        bells=[(6.0, 110.0, -2.0), (19.0, 82.0, -3.0)],
        seed=707,
    )

    render_sting("music_transition", 7.0, sting_transition, peak=0.48)
    render_sting("music_sacrifice", 3.6, sting_sacrifice, peak=0.42)
    render_sting("music_death", 8.0, sting_death, peak=0.34)

    ambience("menu", 9.0, "meta_machine", lp=350.0, order=4)
    ambience("floor1", 9.0, "meta_machine", lp=1200.0, order=3, chimes_db=-34.0, chimes_at=5.0)
    ambience("floor2", 9.0, "meta_machine", lp=1600.0, order=3)
    ambience("floor3", 9.0, "meta_underwater", lp=420.0, order=4)


if __name__ == "__main__":
    render_all()
