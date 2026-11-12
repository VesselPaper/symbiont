"""录音素材的采样器：把 VSCO / Meta 的真乐器录音改成能按音高触发的音源。

为什么不用合成振荡器：加法合成的正弦堆叠听感就是“电子嗡嗡”，无论怎么调参数都
不像真乐器。这里直接读真实录音，按音高重采样，用包络收尾。

依赖 ffmpeg（在 PATH 里）；素材由 tools/fetch_audio_samples.ps1 下载。
"""

import array
import json
import math
import os
import subprocess
import tempfile
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAMPLE_DIR = os.path.join(ROOT, "tools", "audio_samples")
FUND_CACHE = os.path.join(ROOT, "tools", "audio_fundamentals.json")
RATE = 44100

_cache = {}
_fund = None


# --------------------------------------------------------------------------
# 读文件
# --------------------------------------------------------------------------

def _decode(path: str) -> list[float]:
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, "t.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(RATE),
             "-c:a", "pcm_s16le", out],
            check=True,
        )
        with wave.open(out, "rb") as w:
            raw = w.readframes(w.getnframes())
    buf = array.array("h")
    buf.frombytes(raw)
    return [x / 32768.0 for x in buf]


def load(key: str) -> list[float]:
    if key in _cache:
        return _cache[key]
    for ext in (".wav", ".ogg", ".flac"):
        path = os.path.join(SAMPLE_DIR, key + ext)
        if os.path.isfile(path):
            break
    else:
        raise FileNotFoundError(f"缺少素材 {key}，先跑 tools/fetch_audio_samples.ps1")
    buf = _decode(path)
    _cache[key] = buf
    return buf


# --------------------------------------------------------------------------
# 基频检测：文件名里的八度写法各家不一样，靠测出来的频率更可靠
# --------------------------------------------------------------------------

def detect_fundamental(buf: list[float], lo=40.0, hi=900.0) -> float:
    """谐波求和找基频。

    为什么不用“最强峰”：弦乐的二倍频经常比基频还响（实测大提琴 A、钢琴 C4
    都会被认成高八度），单看最大峰会错一个八度。这里对每个候选频率 f，累加
    f、2f…6f 处的能量，谁累加得高谁才是基频。

    注意：钟、锣、定音鼓不是谐波音，这个函数给它们的值只当“大致音高”，
    不用于调音。
    """
    import numpy as np

    start = int(len(buf) * 0.3)
    seg = buf[start:start + int(2.0 * RATE)]
    if len(seg) < int(0.5 * RATE):
        seg = buf
    windowed = np.asarray(seg, dtype=np.float64) * np.hanning(len(seg))
    spec = np.abs(np.fft.rfft(windowed))
    freqs = np.fft.rfftfreq(len(seg), 1.0 / RATE)

    candidates = np.arange(lo, hi, 0.5)
    score = np.zeros_like(candidates)
    for k in range(1, 7):
        for i, f in enumerate(candidates):
            at = k * f
            if at >= freqs[-1]:
                break
            score[i] += np.interp(at, freqs, spec) / k
    best = candidates[int(np.argmax(score))]
    # 在 ±1Hz 内细化，避免 0.5Hz 网格误差
    fine = np.arange(best - 1.0, best + 1.0, 0.05)
    fscore = np.zeros_like(fine)
    for k in range(1, 7):
        for i, f in enumerate(fine):
            at = k * f
            if at >= freqs[-1]:
                break
            fscore[i] += np.interp(at, freqs, spec) / k
    return float(fine[int(np.argmax(fscore))])


def fundamentals() -> dict:
    global _fund
    if _fund is not None:
        return _fund
    with open(FUND_CACHE, "r", encoding="utf-8") as f:
        doc = json.load(f)
    _fund = doc["samples"]
    return _fund


def base_freq(key: str) -> float:
    """素材的音高。以 tools/audio_fundamentals.json 为准；表里没有才现场测。"""
    table = fundamentals()
    if key in table:
        return float(table[key]["hz"])
    buf = load(key)
    f = detect_fundamental(buf)
    print(f"[warn] {key} 不在音高表里，实测 {f:.2f}Hz，请人工确认后补进 audio_fundamentals.json")
    table[key] = {"hz": round(f, 2), "measured": round(f, 2), "note": "?", "kind": "color"}
    with open(FUND_CACHE, "w", encoding="utf-8", newline="\n") as fp:
        json.dump({"note": "自动补录，需人工核对", "samples": table}, fp, ensure_ascii=False,
                  indent=2, sort_keys=True)
        fp.write("\n")
    return f


# --------------------------------------------------------------------------
# 变调 / 包络
# --------------------------------------------------------------------------

def resample(buf: list[float], ratio: float) -> list[float]:
    """ratio > 1 变高变短。线性插值，够用且没有额外依赖。"""
    if abs(ratio - 1.0) < 1e-6:
        return list(buf)
    n_out = int(len(buf) / ratio)
    out = [0.0] * n_out
    for i in range(n_out):
        src = i * ratio
        j = int(src)
        frac = src - j
        a = buf[j] if j < len(buf) else 0.0
        b = buf[j + 1] if j + 1 < len(buf) else 0.0
        out[i] = a + (b - a) * frac
    return out


def semitones(from_hz: float, to_hz: float) -> float:
    return 12.0 * math.log2(to_hz / from_hz)


def _extend(body: list[float], need: int, fade_seconds: float = 0.12) -> list[float]:
    """素材不够长就把中段接起来。

    接缝处必须做等功率交叉淡化：直接首尾拼接，长音每隔几秒就会“咔”一下，
    低频持续音上尤其明显。
    """
    if len(body) >= need:
        return body[:need]
    fade_n = max(1, min(int(fade_seconds * RATE), len(body) // 4))
    seg = list(body)
    while len(seg) < need:
        head = body[:fade_n]
        at = len(seg) - fade_n
        for i in range(fade_n):
            t = math.sqrt(i / fade_n)
            seg[at + i] = seg[at + i] * (1.0 - t) + head[i] * t
        seg.extend(body[fade_n:])
    return seg[:need]


def note(
    key: str,
    hz: float,
    duration: float,
    *,
    gain: float = 1.0,
    attack: float = 0.12,
    release: float = 0.35,
    offset: float = 0.0,
) -> list[float]:
    """取素材中间一段、按音高变调、加淡入淡出，返回 duration 长度的单音。"""
    src = load(key)
    base = base_freq(key)
    if base <= 0:
        base = hz
    ratio = hz / base
    # 允许 ±2 个八度的重采样；超出这个范围音色会崩，说明调用方选错了乐器
    while ratio > 4.0:
        ratio /= 2.0
    while ratio < 0.25:
        ratio *= 2.0
    shifted = resample(src, ratio)

    start = int((offset if offset > 0 else 0.35 * len(shifted) / RATE) * RATE)
    start = max(0, min(start, len(shifted) - 1))
    need = int(duration * RATE)
    # 需要的长度超过素材剩余部分时，先尽量往后挪；还放不下就把中段接起来，
    # 不然长音的后半截会变成静音
    if need > len(shifted) - start:
        start = max(0, len(shifted) - need)
    seg = shifted[start:start + need]
    if len(seg) < need:
        body = shifted[max(0, int(0.2 * len(shifted))):]
        seg = _extend(body, need)

    n_in = max(1, int(attack * RATE))
    n_out = max(1, int(release * RATE))
    for i in range(min(n_in, len(seg))):
        # 用平方根曲线，起音比线性更自然
        seg[i] *= math.sqrt(i / n_in)
    for i in range(min(n_out, len(seg))):
        seg[len(seg) - 1 - i] *= math.sqrt(i / n_out)
    if gain != 1.0:
        seg = [x * gain for x in seg]
    return seg


def hit(key: str, duration: float, *, gain: float = 1.0, hz: float = 0.0, release: float = 0.25) -> list[float]:
    """打击类（钟、锣、定音鼓）：从 0 开始取，可选变调。"""
    src = load(key)
    if hz > 0:
        base = base_freq(key)
        if base > 0:
            src = resample(src, hz / base)
    seg = src[:int(duration * RATE)]
    if len(seg) < int(duration * RATE):
        seg += [0.0] * (int(duration * RATE) - len(seg))
    n_out = max(1, int(release * RATE))
    for i in range(min(n_out, len(seg))):
        seg[len(seg) - 1 - i] *= math.sqrt(i / n_out)
    if gain != 1.0:
        seg = [x * gain for x in seg]
    return seg


def _selftest() -> int:
    """渲染指定音高再测回来，音分偏差超过 30 说明变调或音高表有问题。"""
    print("素材自检：目标音高 vs 渲染后实测")
    bad = 0
    for key, targets in [
        ("vsco_cello", [130.81, 196.0, 261.63, 329.63]),
        ("vsco_cello_a2", [110.0, 164.81, 220.0]),
        ("vsco_violin", [261.63, 329.63, 523.25, 659.26]),
        ("vsco_violin_c4", [196.0, 261.63, 329.63]),
        ("vsco_contrabass", [55.0, 73.42, 98.0]),
        ("vsco_harp_c3", [130.81, 261.63, 392.0]),
        ("meta_piano_c4", [130.81, 261.63, 392.0, 523.25]),
    ]:
        for hz in targets:
            buf = note(key, hz, 1.2, gain=0.5, attack=0.05, release=0.2)
            got = detect_fundamental(buf, lo=40.0, hi=900.0)
            # 按音级比较：钢琴基频弱，检测器常锁到二倍频，八度差不算调音错误
            raw = 1200.0 * math.log2(got / hz) if got > 0 else 9999
            cents = ((raw + 600.0) % 1200.0) - 600.0
            flag = "ok" if abs(cents) <= 30 else "BAD"
            if flag == "BAD":
                bad += 1
            print(f"  {key:<18} 目标 {hz:7.2f}Hz  实测 {got:7.2f}Hz  {cents:+7.1f} 音分"
                  f"（原始 {raw:+8.1f}）  {flag}")
    print(f"自检结束，异常 {bad} 条")
    return bad


if __name__ == "__main__":
    import sys

    if "--selftest" in sys.argv:
        raise SystemExit(1 if _selftest() else 0)
    print(__doc__)
