"""Print a coarse energy envelope for raw source files, so trimming can be decided
from structure instead of guesswork."""

import array
import math
import os
import subprocess
import sys
import tempfile
import wave

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "audio_samples")


def decode(path, rate=44100):
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, "t.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(rate),
             "-c:a", "pcm_s16le", out],
            check=True,
        )
        with wave.open(out, "rb") as w:
            n = w.getnframes()
            raw = w.readframes(n)
    a = array.array("h")
    a.frombytes(raw)
    return [x / 32768.0 for x in a], rate


def envelope(samples, rate, step_ms=50):
    step = max(1, int(rate * step_ms / 1000))
    out = []
    for i in range(0, len(samples), step):
        chunk = samples[i:i + step]
        rms = math.sqrt(sum(x * x for x in chunk) / len(chunk))
        db = 20 * math.log10(max(rms, 1e-6))
        out.append(db)
    return out


def main():
    names = sys.argv[1:]
    if not names:
        names = sorted(os.listdir(SRC))
    for name in names:
        path = os.path.join(SRC, name)
        if not os.path.isfile(path):
            continue
        samples, rate = decode(path)
        env = envelope(samples, rate)
        peak = max(abs(x) for x in samples)
        print(f"\n{name}  {len(samples)/rate:.2f}s  peak={peak:.2f}")
        for i in range(0, len(env), 10):
            block = env[i:i + 10]
            t0 = i * 0.05
            bar = "".join("#" if db > -12 else ("+" if db > -24 else ("-" if db > -42 else ".")) for db in block)
            print(f"  {t0:5.2f}s |{bar}|")


if __name__ == "__main__":
    main()
