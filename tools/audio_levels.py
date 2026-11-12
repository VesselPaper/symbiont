"""粗看一首曲子的能量走向：每 0.1s 一个 dB 值，用来发现长静音、突发尖峰。"""

import sys
import wave

import numpy as np


def show(path: str, step_ms: int = 100) -> None:
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    step = int(rate * step_ms / 1000)
    levels = []
    for i in range(0, len(data), step):
        chunk = data[i:i + step]
        rms = float(np.sqrt(np.mean(chunk * chunk)))
        levels.append(20.0 * np.log10(max(rms, 1e-6)))
    peak = float(np.max(np.abs(data)))
    print(f"\n{path}  {len(data)/rate:.1f}s  peak={peak:.2f}")
    for i in range(0, len(levels), 10):
        block = levels[i:i + 10]
        bar = "".join("#" if v > -18 else ("+" if v > -26 else ("-" if v > -40 else ".")) for v in block)
        print(f"  {i*step_ms/1000:6.1f}s |{bar}|  {np.mean(block):6.1f} dB")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        show(p)
