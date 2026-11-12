"""按倍频程看能量分布，找“沙沙”底噪。

频段用功率求和，并按带宽归一，不然高频段 bin 多，会把宽带噪声算得虚高。
另外单独量“安静段”的噪声底：一段音乐里的沙沙声，在不发声的空隙最明显。
"""

import sys
import wave
from pathlib import Path

import numpy as np

BANDS = [
    ("sub   ", 20.0, 80.0),
    ("bass  ", 80.0, 250.0),
    ("lowmid", 250.0, 800.0),
    ("mid   ", 800.0, 2500.0),
    ("himid ", 2500.0, 6000.0),
    ("high  ", 6000.0, 12000.0),
    ("air   ", 12000.0, 20000.0),
]


def read(path: Path):
    with wave.open(str(path), "rb") as f:
        rate = f.getframerate()
        data = np.frombuffer(f.readframes(f.getnframes()), dtype="<i2")
    return data.astype(np.float64) / 32768.0, rate


def bands(x: np.ndarray, rate: int):
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / rate)
    total = float(spec.sum())
    out = []
    for label, lo, hi in BANDS:
        sel = (freqs >= lo) & (freqs < hi)
        width = max(1, int(sel.sum()))
        out.append((label, float(spec[sel].sum()) / width if width else 0.0, float(spec[sel].sum())))
    return out, max(total, 1e-12)


def floor(x: np.ndarray, rate: int, seconds: float = 0.35) -> float:
    """取最安静的 10% 窗口，算它们的平均 RMS，代表这条音频的噪声底。"""
    n = int(rate * seconds)
    if len(x) < n * 2:
        return 0.0
    rms = []
    for i in range(0, len(x) - n, n // 2):
        chunk = x[i:i + n]
        rms.append(float(np.sqrt(np.mean(chunk * chunk))))
    rms = np.array(rms)
    quiet = rms[rms <= np.percentile(rms, 10)]
    return float(np.sqrt(np.mean(quiet ** 2))) if len(quiet) else 0.0


def report(path_str: str) -> None:
    if path_str.startswith("@"):
        # @素材名：直接查 tools/audio_samples 里的原始录音，不经过任何处理
        import audio_samples as smp

        key = path_str[1:]
        x = np.asarray(smp.load(key), dtype=np.float64)
        rate = smp.RATE
        label = key
    else:
        x, rate = read(Path(path_str))
        label = Path(path_str).name
    rows, total = bands(x, rate)
    print(f"\n{label}  {len(x)/rate:.1f}s  {rate}Hz")
    print("        " + " ".join(f"{lab:>7}" for lab, _, _ in rows))
    # 每段占总能量的百分比；安静段噪声底另列
    pct = " ".join(f"{share / total * 100:7.1f}" for _, _, share in rows)
    print("  能量% " + pct)
    q = floor(x, rate)
    db = 20.0 * np.log10(max(q, 1e-9))
    print(f"  噪声底 {db:6.1f} dBFS（最安静的 10% 窗口）")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
