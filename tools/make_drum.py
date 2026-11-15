"""生成一个低频鼓点 sfx_drum.wav（只这一个文件，不重跑全套音频）。

背景：序章下落的节拍原来借用受击音（听起来像史莱姆叫）。这里用 audio_synth 的
thump + 噪声瞬态合成一记"咚"，按秒数控制衰减，导入后直接用。
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import audio_synth as A  # noqa: E402

RATE = 22050
DURATION = 0.9
OUT = ROOT / "client/assets/audio/sfx_drum.wav"


def drum() -> list[float]:
    n = int(RATE * DURATION)
    buf = [0.0] * n

    # 低频鼓皮：52Hz 衰减
    A.add(buf, A.thump(DURATION, 52.0, 1.0, 7.0))

    # 二次谐波，给一点"木箱"的厚度
    A.add(buf, A.thump(DURATION * 0.7, 84.0, 0.45, 11.0))

    # 起手瞬态：短噪声，只在最前 30ms
    click = A.noise(int(RATE * 0.05), seed=7)
    click = A.bandpass(click, 900.0, 0.9)
    click = [s * (1.0 - i / len(click)) for i, s in enumerate(click)]
    A.add(buf, [s * 0.55 for s in click])

    buf = A.lowpass(buf, 420.0)
    return A.normalize(A.soft_clip(buf, 1.4), peak=0.85)


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    A.write_wav(OUT, drum(), peak=0.85)
    print(f"drum -> {OUT}")


if __name__ == "__main__":
    main()
