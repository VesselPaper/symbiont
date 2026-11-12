"""音频体检：时长、峰值、RMS、频谱重心、循环接缝，不替代人耳试听。

用法：
  python tools/audio_audit.py            # 打印全部摘要
  python tools/audio_audit.py --sheet    # 另出 tmp/audio_sheet.png 频谱图
"""
from __future__ import annotations

import math
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "client" / "assets" / "audio"


def read(path: Path) -> tuple[np.ndarray, int]:
    """返回波形和采样率。素材库是 44100，老合成音效是 22050，不能写死任何一个。"""
    with wave.open(str(path), "rb") as f:
        assert f.getnchannels() == 1 and f.getsampwidth() == 2
        rate = f.getframerate()
        data = np.frombuffer(f.readframes(f.getnframes()), dtype="<i2")
    return data.astype(np.float32) / 32768.0, rate


def db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-9))


def centroid(x: np.ndarray, rate: int) -> float:
    if len(x) < 256:
        return 0.0
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1.0 / rate)
    total = float(spec.sum())
    return float((spec * freqs).sum() / total) if total else 0.0


def metrics(path: Path) -> dict:
    x, rate = read(path)
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x * x)))
    # 循环接缝：只量最后一帧到第一帧的跳变；5ms 窗口差会被音乐内容本身误导
    seam = float(abs(x[-1] - x[0])) if len(x) > 1 else 0.0
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1.0 / rate)
    total = max(1e-9, float(spec.sum()))
    bands = [
        float(spec[freqs < 200].sum() / total),
        float(spec[(freqs >= 200) & (freqs < 1000)].sum() / total),
        float(spec[(freqs >= 1000) & (freqs < 4000)].sum() / total),
        float(spec[freqs >= 4000].sum() / total),
    ]
    return {
        "rate": rate,
        "dur": len(x) / rate,
        "peak": peak,
        "rms": rms,
        "db": db(rms),
        "crest": peak / max(rms, 1e-9),
        "centroid": centroid(x, rate),
        "seam": seam,
        "bands": bands,
        "dc": float(np.mean(x)),
    }


def sheet(names: list[str], out: Path) -> None:
    w, h = 900, 110
    rows = len(names)
    img = Image.new("RGB", (w, h * rows), (12, 12, 16))
    draw = ImageDraw.Draw(img)
    for row, name in enumerate(names):
        x, rate = read(AUDIO / name)
        # 8 段平均频谱，低频在左；亮度归一化，避免大峰值把细节压没
        seg = rate // 2
        spec = []
        for i in range(0, max(1, len(x) - seg), seg):
            s = np.abs(np.fft.rfft(x[i:i + seg] * np.hanning(min(seg, len(x) - i))))
            spec.append(s[:220])
        if not spec:
            continue
        m = np.log1p(np.array(spec).T * 60.0)
        m = m / max(1e-6, m.max())
        pix = Image.fromarray((m * 255.0).astype(np.uint8)).resize((w, h - 16))
        img.paste(pix.convert("RGB"), (0, row * h + 16))
        draw.text((4, row * h + 2), name, fill=(210, 200, 180))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


if __name__ == "__main__":
    names = sorted(p.name for p in AUDIO.glob("*.wav"))
    print(f"{'file':28} {'dur':>6} {'peak':>7} {'rms':>7} {'dB':>7} {'cent':>6} "
          f"{'<200':>6} {'200-1k':>7} {'1-4k':>6} {'>4k':>5} {'bnd':>5}")
    for name in names:
        m = metrics(AUDIO / name)
        print(f"{name:28} {m['dur']:6.2f} {m['peak']:7.3f} {m['rms']:7.3f} {m['db']:7.2f} "
              f"{m['centroid']:6.0f} " + " ".join(f"{b * 100:6.1f}" for b in m["bands"]) +
              f" {m['seam']:5.3f}")
    if "--sheet" in sys.argv:
        key = [
            "bgm_menu.wav", "bgm_tutorial.wav", "bgm_floor1.wav", "bgm_floor2.wav",
            "bgm_floor3.wav", "bgm_combat.wav", "bgm_ending.wav",
            "music_transition.wav", "music_sacrifice.wav", "music_death.wav",
            "sfx_jump.wav", "sfx_swing.wav", "sfx_hit.wav", "sfx_pogo.wav",
            "sfx_bell.wav", "sfx_boss_roar.wav", "sfx_voice_murmur.wav", "sfx_slime_voice.wav",
        ]
        sheet(key, ROOT / "tmp" / "audio_sheet.png")
        print(f"sheet -> {ROOT / 'tmp' / 'audio_sheet.png'}")
