"""《共生之缚》程序化音频合成底层（标准库，无外部素材）。

这一层只负责“声音怎么长出来”，不负责哪一关放哪首曲子：
- 噪声经低通/带通/扫频，做成风、蒸汽、挥剑、湿土冲击；
- 模态叠加做旧钟、铁链、金属；
- 多声部失谐 + 慢速颤音做弦垫/低语合唱；
- Karplus-Strong 做拨弦，避免纯正弦的电子味。

所有函数返回 list[float]（单声道，22050Hz），由 generate_audio.py 拼成 BGM/SFX。
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
TAU = math.tau


def write_wav(path: Path, samples: list[float], *, peak: float = 0.75) -> None:
    top = max(1e-9, max(abs(s) for s in samples))
    scale = peak / top
    pcm = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
        for s in samples
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm)


def silence(duration: float) -> list[float]:
    return [0.0] * max(1, int(RATE * duration))


def add(buf: list[float], samples: list[float], start: float = 0.0) -> None:
    """把一段声音叠加到缓冲区；超出尾部直接裁掉，避免索引越界。"""
    at = max(0, int(start * RATE))
    end = min(len(buf), at + len(samples))
    for i in range(at, end):
        buf[i] += samples[i - at]


def normalize(samples: list[float], peak: float = 0.8) -> list[float]:
    top = max(1e-9, max(abs(s) for s in samples))
    return [s * (peak / top) for s in samples]


def soft_clip(samples: list[float], drive: float = 1.0) -> list[float]:
    return [math.tanh(s * drive) for s in samples]


def env(t: float, duration: float, attack: float, decay: float, sustain: float, release: float) -> float:
    """ADSR；攻击/释放按秒，decay 到 sustain，尾段再 release 到 0。"""
    if t < 0 or t >= duration:
        return 0.0
    if attack > 0 and t < attack:
        a = t / attack
    else:
        a = 1.0
    if t < attack + decay:
        d = 1.0 - (1.0 - sustain) * ((t - attack) / max(decay, 1e-6))
    else:
        d = sustain
    if release > 0 and t > duration - release:
        r = (duration - t) / release
    else:
        r = 1.0
    return max(0.0, a * d * r)


def sine(t: float, freq: float, phase: float = 0.0) -> float:
    return math.sin(TAU * freq * t + phase)


def triangle(t: float, freq: float, phase: float = 0.0) -> float:
    p = (t * freq + phase / TAU) % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def saw(t: float, freq: float, phase: float = 0.0) -> float:
    # 低频弦垫用；高音区不靠它，避免明显混叠。
    p = (t * freq + phase / TAU) % 1.0
    return 2.0 * p - 1.0


def lowpass(samples: list[float], cutoff: float) -> list[float]:
    alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
    y = 0.0
    out: list[float] = []
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def highpass(samples: list[float], cutoff: float) -> list[float]:
    # 一阶 RC 高通：alpha = RC/(RC+dt)，不能沿用低通的 1-exp(-...)；
    # 用错会把 50Hz 的 BGM 根音压掉 20dB，只剩起振时的低频冲击，整首听起来像噪声。
    alpha = 1.0 / (1.0 + TAU * cutoff / RATE)
    y = 0.0
    prev = 0.0
    out: list[float] = []
    for x in samples:
        y = alpha * (y + x - prev)
        prev = x
        out.append(y)
    return out


def bandpass(samples: list[float], center: float, q: float = 1.0) -> list[float]:
    """Chamberlin 状态变量带通；q 越大越窄，适合做风/蒸汽/嗓音共振。"""
    low = band = 0.0
    f = 2.0 * math.sin(math.pi * min(center, RATE * 0.45) / RATE)
    damp = 1.0 / max(q, 0.1)
    out: list[float] = []
    for x in samples:
        high = x - low - damp * band
        band += f * high
        low += f * band
        out.append(band)
    return out


def sweep_band(samples: list[float], f0: float, f1: float, q: float = 1.0) -> list[float]:
    """中心频率随时间从 f0 扫到 f1，做挥剑/跳跃的空气感。"""
    low = band = 0.0
    damp = 1.0 / max(q, 0.1)
    out: list[float] = []
    n = max(1, len(samples) - 1)
    for i, x in enumerate(samples):
        p = i / n
        center = f0 + (f1 - f0) * p
        f = 2.0 * math.sin(math.pi * min(center, RATE * 0.45) / RATE)
        high = x - low - damp * band
        band += f * high
        low += f * band
        out.append(band)
    return out


def noise(n: int, seed: int) -> list[float]:
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def wind_bed(duration: float, amp: float, seed: int, cutoff: float = 180.0) -> list[float]:
    raw = noise(max(1, int(RATE * duration)), seed)
    body = lowpass(lowpass(raw, cutoff), cutoff * 0.7)
    # 慢速强弱变化，避免一条死平的风声
    return [body[i] * amp * (0.72 + 0.28 * math.sin(TAU * 0.11 * i / RATE + 0.6))
            for i in range(len(body))]


def thump(duration: float, freq: float, amp: float = 1.0, decay: float = 12.0,
          seed: int = 0) -> list[float]:
    n = int(RATE * duration)
    rng = random.Random(seed)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        body = sine(t, freq * (1.0 + 0.035 * math.exp(-18.0 * t))) * math.exp(-decay * t)
        click = rng.uniform(-1.0, 1.0) * math.exp(-70.0 * t)
        out.append((body * 0.8 + click * 0.25) * amp)
    return out


def modal_bell(duration: float, freq: float, amp: float = 1.0, decay: float = 2.0,
               seed: int = 0, strike: float = 0.12) -> list[float]:
    """旧铁钟：非整数分音 + 轻微音高下坠 + 起振噪声。"""
    n = int(RATE * duration)
    rng = random.Random(seed)
    partials = [
        (1.00, 0.62, 1.0),
        (2.01, 0.24, 1.35),
        (3.87, 0.13, 1.75),
        (5.43, 0.08, 2.10),
        (7.12, 0.05, 2.50),
        (9.33, 0.03, 2.90),
    ]
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        drop = 1.0 - 0.018 * math.exp(-2.2 * t)
        v = 0.0
        for ratio, a, d in partials:
            v += a * math.sin(TAU * freq * ratio * drop * t + ratio * 0.7) * math.exp(-decay * d * t)
        if strike > 0 and t < 0.05:
            v += rng.uniform(-1.0, 1.0) * strike * math.exp(-60.0 * t)
        out.append(v * amp)
    return out


def metal_tick(duration: float, freq: float, amp: float = 1.0, seed: int = 0) -> list[float]:
    n = int(RATE * duration)
    rng = random.Random(seed)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        # 单次短金属不用再跑一遍整段模态，直接三阶分音
        v = (0.7 * sine(t, freq) + 0.2 * sine(t, freq * 2.03) + 0.08 * sine(t, freq * 4.1)) * math.exp(-18.0 * t)
        if t < 0.012:
            v += rng.uniform(-1.0, 1.0) * 0.25
        out.append(v * amp)
    return out


def karplus(duration: float, freq: float, amp: float = 1.0, decay: float = 0.996,
            seed: int = 0) -> list[float]:
    """Karplus-Strong 拨弦：初始噪声经延迟反馈，像湿石廊里的短拨弦。"""
    n = int(RATE * duration)
    delay = max(2, int(RATE / max(freq, 20.0)))
    rng = random.Random(seed)
    buf = [rng.uniform(-1.0, 1.0) for _ in range(delay)]
    out: list[float] = []
    idx = 0
    for _ in range(n):
        cur = buf[idx]
        nxt = buf[(idx + 1) % delay]
        filtered = 0.5 * (cur + nxt) * decay
        buf[idx] = filtered
        out.append(cur * amp)
        idx = (idx + 1) % delay
    # 起始 8ms 淡入，避免爆音
    fade = max(1, int(RATE * 0.008))
    for i in range(min(fade, n)):
        out[i] *= i / fade
    return out


def choir_note(duration: float, freq: float, amp: float = 1.0, seed: int = 0,
               breath: float = 0.0, vibrato: float = 0.35) -> list[float]:
    """低语合唱：三个失谐声部 + 轻微颤音 + 可选呼吸噪声，不做清晰歌词。"""
    n = int(RATE * duration)
    rng = random.Random(seed)
    detunes = (0.986, 1.0, 1.014)
    phases = (0.0, 1.9, 4.1)
    breath_raw = lowpass(noise(n, seed + 99), 900.0)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        vib = 1.0 + 0.006 * vibrato * math.sin(TAU * 0.55 * t + phases[1])
        v = 0.0
        for j, det in enumerate(detunes):
            f = freq * det * vib
            # 弦/人声都用奇偶混合分音，低频厚一点，高频不刺
            v += (0.42 * sine(t, f, phases[j])
                  + 0.30 * sine(t, f * 2.0, phases[j] + 1.1)
                  + 0.16 * sine(t, f * 3.0, phases[j] + 2.0)
                  + 0.08 * sine(t, f * 4.02, phases[j] + 0.4))
        v /= 1.8
        if breath > 0:
            v += breath * breath_raw[i]
        out.append(v * amp)
    return out


def pad_chord(duration: float, freqs: list[float], amp: float = 1.0, seed: int = 0) -> list[float]:
    """和弦垫：每个音两层失谐 + 奇数分音，慢起慢收。"""
    n = int(RATE * duration)
    out = [0.0] * n
    for j, f in enumerate(freqs):
        note = choir_note(duration, f, amp / max(1, len(freqs)), seed + j * 17, vibrato=0.18)
        add(out, note)
    return out


def pulse_layer(duration: float, period: float, amp: float, seed: int) -> list[float]:
    """铸炉/战鼓：低频冲击 + 短噪声，每 period 一次，相位略有漂移。"""
    n = int(RATE * duration)
    out = [0.0] * n
    rng = random.Random(seed)
    at = 0.0
    k = 0
    while at < duration:
        body = thump(0.16, 46.0 + (k % 3) * 5.0, amp, 15.0, seed + k)
        add(out, body, at)
        for i in range(int(RATE * 0.06)):
            t = i / RATE
            pos = int(at * RATE) + i
            if pos < n:
                out[pos] += rng.uniform(-1.0, 1.0) * amp * 0.25 * math.exp(-40.0 * t)
        at += period * (0.96 + 0.08 * rng.random())
        k += 1
    return out


def heartbeat_layer(duration: float, period: float, amp: float) -> list[float]:
    n = int(RATE * duration)
    out = [0.0] * n
    at = 0.0
    while at < duration:
        add(out, thump(0.22, 42.0, amp, 14.0, 9), at)
        add(out, thump(0.18, 36.0, amp * 0.72, 16.0, 10), at + period * 0.18)
        at += period
    return out


def whoosh(duration: float, f0: float, f1: float, amp: float = 1.0,
           seed: int = 0, body: float = 0.0) -> list[float]:
    n = int(RATE * duration)
    raw = noise(n, seed)
    air = sweep_band(raw, f0, f1, 0.7)
    # 两端收干净，中间最响；body 给低频“呼”的一下
    out: list[float] = []
    for i in range(n):
        p = i / max(1, n - 1)
        shape = math.sin(math.pi * min(1.0, p * 1.05)) ** 1.2
        v = air[i] * shape
        if body > 0:
            v += body * sine(i / RATE, 90.0 + 40.0 * p) * math.exp(-8.0 * i / RATE) * shape
        out.append(v * amp)
    return out


def tone_sweep(duration: float, f0: float, f1: float, amp: float = 1.0, decay: float = 10.0,
               partials: tuple[tuple[float, float], ...] = ((1.0, 0.72), (2.0, 0.22), (3.0, 0.08)),
               seed: int = 0, attack: float = 0.003) -> list[float]:
    """干净的音高扫频：相位累加保证滑音不产生爆音，噪声只留一个极小起振点。

    攻击/跳跃/拾取这类短音优先用它；不要再用整段带通白噪声，
    否则听起来就是“噪声”而不是“动作”。
    """
    n = max(1, int(RATE * duration))
    rng = random.Random(seed)
    phase = 0.0
    out: list[float] = []
    a = max(1, int(RATE * attack))
    for i in range(n):
        p = i / max(1, n - 1)
        f = f0 + (f1 - f0) * p
        phase += TAU * f / RATE
        v = 0.0
        for ratio, weight in partials:
            v += weight * math.sin(phase * ratio + ratio * 0.7)
        env = math.exp(-decay * i / RATE) * math.sin(math.pi * min(1.0, p * 1.1)) ** 0.35
        if i < a:
            env *= i / a
        v *= env * amp
        if i < 4:  # 只有 0.18ms 的起振点，够让瞬态不闷，不会变成嘶声
            v += rng.uniform(-1.0, 1.0) * 0.04 * amp
        out.append(v)
    return out


def soft_noise(duration: float, cutoff: float, amp: float = 1.0, seed: int = 0,
               attack: float = 0.02) -> list[float]:
    """低通噪声：做布料/蒸汽/低语的气声底，高频已经滤掉，不刺耳。"""
    n = max(1, int(RATE * duration))
    body = lowpass(lowpass(noise(n, seed), cutoff), max(40.0, cutoff * 0.75))
    a = max(1, int(RATE * attack))
    out: list[float] = []
    for i, v in enumerate(body):
        p = i / max(1, n - 1)
        env = math.sin(math.pi * min(1.0, p * 1.1)) ** 0.7
        if i < a:
            env *= i / a
        out.append(v * amp * env)
    return out


def wet_hit(duration: float, freq: float, amp: float = 1.0, seed: int = 0) -> list[float]:
    """湿软身体/泥土冲击：低频形体 + 带通噪声喷溅，不用金属。"""
    n = int(RATE * duration)
    raw = noise(n, seed)
    squelch = bandpass(raw, freq, 1.4)
    body = thump(duration, freq * 0.45, 1.0, 18.0, seed + 1)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        out.append((squelch[i] * math.exp(-24.0 * t) * 0.55 + body[i] * 0.55) * amp)
    return out


def reverb(samples: list[float], mix: float = 0.18, decay: float = 0.35) -> list[float]:
    """三条固定延迟的廉价房间反射；只给短音效尾巴，不做大教堂卷积。"""
    n = len(samples)
    delays = [int(RATE * 0.031), int(RATE * 0.047), int(RATE * 0.071)]
    gains = [0.72, 0.55, 0.38]
    out = list(samples)
    for d, g in zip(delays, gains):
        for i in range(d, n):
            out[i] += out[i - d] * g * decay * mix
    return out


def loop_crossfade(samples: list[float], seconds: float = 1.0) -> list[float]:
    """把尾巴叠回开头，保证 loop 接缝不出现静音空档。"""
    fade_n = max(1, int(RATE * seconds))
    if len(samples) <= fade_n * 2:
        return samples
    body_n = len(samples) - fade_n
    for i in range(fade_n):
        w = i / float(fade_n)
        samples[i] = samples[i] * w + samples[body_n + i] * (1.0 - w)
    return samples[:body_n]
