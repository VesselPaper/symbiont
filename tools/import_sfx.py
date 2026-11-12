"""把录音库里的素材裁成游戏用的音效。

为什么单独一个脚本：合成器写不出真实质感，这两批素材来自 Meta Oculus Audio Pack
和 VSCO 2 CE（CC0 / CC BY 4.0）。这里只做裁切、淡入淡出、峰值归一，不改音色。

依赖 ffmpeg（在 PATH 里）。原始素材由 tools/fetch_audio_samples.ps1 下到
tools/audio_samples/，不进仓库。

用法：python tools/import_sfx.py
"""

import array
import math
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import lfilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_samples as smp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "audio_samples")
OUT = os.path.join(ROOT, "client", "assets", "audio")
RATE = 44100


def one_pole_lowpass(x: np.ndarray, cutoff: float, order: int = 1,
                    invert: bool = False) -> np.ndarray:
    alpha = 1.0 - math.exp(-math.tau * cutoff / RATE)
    raw = x
    for _ in range(max(1, order)):
        x = lfilter([alpha], [1.0, -(1.0 - alpha)], x)
    return raw - x if invert else x


def one_pole_highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """一阶 RC 高通，极点必须落在 α 上；写成 (1−α) 会变成 5kHz 高通。"""
    alpha = 1.0 / (1.0 + math.tau * cutoff / RATE)
    return lfilter([alpha, -alpha], [1.0, -alpha], x)


def thump(duration: float, freq: float = 72.0, decay: float = 0.035, amp: float = 0.4) -> np.ndarray:
    """低频一记闷响。

    打击感不是把音量调大，是让手“感到”东西：高频给材质，低频给重量。
    每个命中音都垫一层几十毫秒的低频，重一点的材质垫得重一点。
    """
    n = max(1, int(duration * RATE))
    t = np.arange(n) / RATE
    return np.sin(2.0 * math.pi * freq * t) * np.exp(-t / decay) * amp


def mix_into(buf: np.ndarray, layer, at: float = 0.0, gain: float = 1.0) -> None:
    src = np.asarray(layer, dtype=np.float64)
    start = int(at * RATE)
    end = min(len(buf), start + len(src))
    if end > start:
        buf[start:end] += src[:end - start] * gain


def stretch(x: np.ndarray, factor: float) -> np.ndarray:
    """线性插值拉长时间。噪声类素材拉长不会出音调伪影，正好用来把撕裂声变“稠”。"""
    n = int(len(x) * factor)
    if n <= 0:
        return x
    return np.interp(np.arange(n) / factor, np.arange(len(x)), x)


def build_slime_voice() -> np.ndarray:
    """史莱姆的叫声：一声拖长的粘液声。

    组长两次否掉了旧版：先是恐怖怪物低吼“太吓人”，再是合成正弦“不是粘液”。
    素材库里唯一的湿声就是这条黏稠撕裂（GORESqsh_BloodSquishSlimy），
    放慢一倍多、低通压到 2kHz，把它从“血肉被撕”变成“软体在地上蹭”。
    """
    raw = np.asarray(decode(find_source("meta_squish")))
    seg = raw[int(0.02 * RATE):int(0.58 * RATE)]
    slow = one_pole_lowpass(stretch(seg, 2.2), 2000.0, 3)
    t = np.linspace(0.0, 1.0, len(slow))
    env = np.minimum(1.0, t / 0.06) * (1.0 - t) ** 1.6
    out = slow * env
    top = float(np.max(np.abs(out)))
    return out * (0.50 / top) if top > 1e-6 else out


def _cut(src_key: str, start: float, length: float) -> np.ndarray:
    return np.asarray(decode(find_source(src_key)), dtype=np.float64)[
        int(start * RATE):int((start + length) * RATE)]


def _fade_edges(seg: np.ndarray, fade_in: float = 0.003, fade_out: float = 0.06) -> np.ndarray:
    n_in = max(1, int(fade_in * RATE))
    n_out = max(1, int(fade_out * RATE))
    seg = seg.copy()
    seg[:n_in] *= np.linspace(0.0, 1.0, n_in)
    seg[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return seg


def _normalize(x: np.ndarray, peak: float) -> np.ndarray:
    top = float(np.max(np.abs(x)))
    return x * (peak / top) if top > 1e-6 else x


def _soft_env(n: int, attack: float = 0.03, decay: float = 0.10) -> np.ndarray:
    """先起后落的一段包络：用来给空气声一个“推出去”的形状。"""
    t = np.arange(n) / RATE
    return np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-np.maximum(t - attack, 0.0) / decay)


def build_jump() -> np.ndarray:
    """跳跃：身体腾空带起的布料和空气声。

    组长说的是“不该是超级玛丽那种东东东”。合成版是音阶上跳，
    所以换成一段真的空气声就行：快一点、切掉 220Hz 以下（那个“咚”），
    压到 5kHz，起手 20 毫秒，再垫一丝 60Hz 当体重。
    """
    seg = _cut("meta_swoosh", 0.05, 0.22)
    seg = one_pole_lowpass(stretch(seg, 0.9), 220.0, 1, invert=True)
    seg = one_pole_lowpass(seg, 5000.0, 1)
    seg = _normalize(seg, 1.0) * _soft_env(len(seg), 0.02, 0.07)
    weight = _normalize(thump(0.09, 60.0, 0.026, 1.0), 0.08)
    out = seg.copy()
    out[:len(weight)] += weight
    out = _fade_edges(out, 0.004, 0.05)
    return _normalize(out, 0.62)


def build_double_jump() -> np.ndarray:
    """二段跳：同一口气的更短一记，稍高一点，听起来是“再蹬一次”。"""
    seg = _cut("meta_swoosh", 0.10, 0.18)
    seg = one_pole_lowpass(stretch(seg, 0.85), 260.0, 1, invert=True)
    seg = one_pole_lowpass(seg, 6000.0, 1)
    seg = _normalize(seg, 1.0) * _soft_env(len(seg), 0.015, 0.06)
    out = _fade_edges(seg.copy(), 0.004, 0.04)
    return _normalize(out, 0.58)


def _to_rms_db(x: np.ndarray, db: float, ceiling: float = 0.92) -> np.ndarray:
    """按 RMS 定档，再卡住峰值。

    短促的撞击声峰值高、RMS 低，只按峰值归一化会听起来比别的音效轻一截。
    """
    rms = float(np.sqrt(np.mean(np.square(x))))
    y = x * (10.0 ** (db / 20.0) / max(rms, 1e-9))
    peak = float(np.max(np.abs(y)))
    if peak > ceiling:
        y = y * (ceiling / peak)
    return y


def _mix(base: np.ndarray, layer: np.ndarray, at: float = 0.0, gain: float = 1.0) -> np.ndarray:
    """把一层叠到另一层上，返回加长后的结果。"""
    shift = int(at * RATE)
    n = max(len(base), shift + len(layer))
    out = np.zeros(n, dtype=np.float64)
    out[:len(base)] += base
    out[shift:shift + len(layer)] += layer * gain
    return out


def build_ui_hover() -> np.ndarray:
    """按钮悬停：骨/陶的一声轻叩。

    合成版是一个正弦“嘀”，太像儿童游戏。这里用陶片撞击的头 70 毫秒，
    压掉高频的尖，做得很轻，只在鼠标划过去时给一点“有这个按钮”的触感。
    """
    seg = one_pole_lowpass(_cut("meta_ceramic", 0.0, 0.07), 4500.0, 1)
    out = _fade_edges(seg, 0.002, 0.03)
    return _to_rms_db(out, -20.0)


def build_ui() -> np.ndarray:
    """按钮确认：木头的短叩，比悬停实一点、长一点。"""
    seg = one_pole_lowpass(_cut("meta_woodconfirm", 0.0, 0.18), 7000.0, 1)
    out = _fade_edges(seg, 0.002, 0.05)
    return _to_rms_db(out, -24.0)


def build_pause() -> np.ndarray:
    """暂停：木头合上的一记，比确认更重，收尾短。"""
    seg = one_pole_lowpass(_cut("meta_woodclose", 0.0, 0.34), 6000.0, 1)
    out = _fade_edges(seg, 0.003, 0.07)
    return _to_rms_db(out, -23.0)


def build_chest_open() -> np.ndarray:
    """开箱：先是金属搭扣松开，再是箱里的东西翻动，最后一点余响。

    原来是一条上滑的合成音，完全是另一种语言。这里两层实录叠起来：
    金属面板开合给“扣子开了”，皮革包开合给“里面的东西翻了一下”。
    """
    latch = _normalize(_fade_edges(_cut("meta_panel", 0.0, 0.55), 0.002, 0.06), 1.0)
    rummage = _normalize(_fade_edges(_cut("meta_bagopen", 0.0, 0.90), 0.004, 0.08), 1.0)
    out = _mix(latch, rummage, 0.06, 0.75)
    out = _fade_edges(out, 0.002, 0.10)
    return _to_rms_db(out, -24.0)


def build_straw_hit() -> np.ndarray:
    """打到稻草人/木桩：干草碎裂 + 木棍实心的一记。

    原来这条是陶瓷撞击加低频，听起来像敲陶罐，和稻草人的视觉对不上。
    草这一层用踩干草的实录加速、压窄频段，得到“沙沙一炸”的碎响；
    木这一层用木头落地的头一下，再垫一点低频给重量。
    """
    straw = _cut("meta_grasswalk", 0.0, 0.34)
    straw = stretch(straw, 0.72)
    straw = one_pole_lowpass(straw, 9000.0, 1)
    straw = one_pole_highpass(straw, 500.0)
    straw = _normalize(straw, 1.0) * _soft_env(len(straw), 0.01, 0.16)
    # 木这一层用“木头合上”的干脆头一下；落地闷响那条整体太闷，
    # 铺上来会把草声糊住，听着像敲泥。
    wood = _cut("meta_woodclose", 0.0, 0.10)
    wood = one_pole_lowpass(wood, 6000.0, 1)
    wood = _normalize(wood, 1.0) * _soft_env(len(wood), 0.003, 0.07)
    body = _mix(straw, wood, 0.0, 0.75)
    body = _mix(body, thump(0.20, 110.0, 0.035, 0.30), 0.006, 1.0)
    out = _fade_edges(body, 0.002, 0.10)
    return _to_rms_db(out, -20.0)


def build_weapon_pickup() -> np.ndarray:
    """捡到铁剑：小件金属落地/入手的一声，干净的金属头，不要音阶。"""
    # 拿起一把剑：先是刀身刮过鞘/石的金属摩擦，再来一下入手的分量。
    # 只用“金属落地”一声太单薄，听着像掉了个铁片。
    scrape = _cut("meta_swordscrape", 0.04, 0.42)
    scrape = one_pole_lowpass(scrape, 9000.0, 1)
    scrape = one_pole_highpass(scrape, 320.0)
    scrape = _normalize(scrape, 1.0) * _soft_env(len(scrape), 0.01, 0.22)
    clink = _cut("meta_metaldrop", 0.0, 0.22)
    clink = one_pole_lowpass(clink, 7000.0, 1)
    clink = one_pole_highpass(clink, 240.0)
    clink = _normalize(clink, 1.0) * _soft_env(len(clink), 0.002, 0.10)
    out = _mix(scrape, clink, 0.20, 0.45)
    out = _mix(out, thump(0.14, 130.0, 0.02, 0.08), 0.24, 1.0)
    out = _fade_edges(out, 0.004, 0.12)
    return _to_rms_db(out, -21.0)


def build_boots_pickup() -> np.ndarray:
    """捡到蒸汽靴：一小股蒸汽的嘶声，低频掐掉，只留气。"""
    seg = one_pole_lowpass(_cut("meta_machine", 0.40, 0.32), 220.0, 1, invert=True)
    seg = _normalize(seg, 1.0) * _soft_env(len(seg), 0.02, 0.14)
    out = _fade_edges(seg, 0.004, 0.05)
    return _to_rms_db(out, -21.0)


def build_relic_pickup() -> np.ndarray:
    """捡到遗物：石/陶的触感，加一层很轻的钟，给“这东西有分量”。"""
    tap = _normalize(_fade_edges(_cut("meta_ceramic", 0.0, 0.30), 0.002, 0.08), 1.0)
    ring = _normalize(np.asarray(smp.note("vsco_bell_c4", 392.0, 2.0, gain=1.0),
                                 dtype=np.float64), 1.0)
    out = _mix(tap, ring, 0.05, 0.32)
    out = _fade_edges(out, 0.002, 0.18)
    return _to_rms_db(out, -23.0)


def build_pickup() -> np.ndarray:
    """通用拾取：布料/包袋收拢的一记闷响，不是硬币也不是电音。"""
    seg = one_pole_lowpass(_cut("meta_bagclose", 0.0, 0.32), 7000.0, 1)
    out = _fade_edges(seg, 0.003, 0.06)
    return _to_rms_db(out, -24.0)


def build_hit(material: str) -> np.ndarray:
    """命中：材质声 + 低频重量。三种材质各一条。

    只用素材原声偏“薄”，尤其是短促的一下，玩家感觉不到东西被砍到。
    统一在尾部垫一层低频，重量按材质排：肉最轻、木头居中、铁最重。
    """
    if material == "wood":
        return build_straw_hit()
    recipe = {
        "flesh": ("meta_squish", 0.02, 0.18, 72.0, 0.25, 0.030),
        "wood": ("meta_ceramic", 0.0, 0.22, 82.0, 0.32, 0.028),
        "metal": ("meta_anvil", 0.0, 0.34, 62.0, 0.42, 0.045),
    }[material]
    src, start, length, freq, amp, decay = recipe
    seg = _cut(src, start, length)
    if material == "flesh":
        # 肉声太靠高频会变成“咔啦”，压到 5kHz 才像湿的
        seg = one_pole_lowpass(seg, 5000.0, 2)
    # 材质声先占满，低频按固定比例垫在下面，不然闷响会盖住材质
    seg = _normalize(seg, 1.0)
    weight = _normalize(thump(length, freq, decay, 1.0), amp)
    out = seg.copy()
    out[:len(weight)] += weight
    out = _fade_edges(out, 0.002, 0.05)
    return _normalize(out, 0.78)


def build_limb_pickup() -> np.ndarray:
    """拾起史莱姆肢体：一下湿响，不加任何乐器音。

    检测到的两处湿响里，0.0-0.35 秒这一下更短更脆，适合“拿到手”，
    1.0 秒那一下留给史莱姆自己叫。
    """
    raw = np.asarray(decode(find_source("meta_squish")))
    seg = raw[int(0.02 * RATE):int(0.36 * RATE)]
    seg = one_pole_lowpass(seg, 6000.0, 1)
    n_in = int(0.004 * RATE)
    n_out = int(0.10 * RATE)
    seg[:n_in] *= np.linspace(0.0, 1.0, n_in)
    seg[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    top = float(np.max(np.abs(seg)))
    return seg * (0.50 / top) if top > 1e-6 else seg


# 每条：源文件前缀、裁切起点（秒）、保留长度（秒）、淡出长度（秒）、目标峰值。
# 起点看 tools/audio_envelope.py 打出来的能量包络定，不靠顺耳瞎猜。
# 带 "build" 的两条不是裁素材，而是现场拼出来（原因见各自函数注释）。
SFX_TABLE = [
    # sword 文件前 0.3s 是挥动，后面是静音
    {"name": "swing", "src": "meta_swoosh", "start": 0.03, "length": 0.38, "fade_out": 0.08, "peak": 0.72},
    {"name": "jump", "build": build_jump},
    {"name": "double_jump", "build": build_double_jump},
    # swoosh 是单次破空，0.03 起最干净
    {"name": "pogo", "src": "meta_swoosh", "start": 0.03, "length": 0.45, "fade_out": 0.08, "peak": 0.72},
    # 一步只有 0.12s，取第一下落脚
    {"name": "step", "src": "meta_step", "start": 0.0, "length": 0.16, "fade_out": 0.04, "peak": 0.60},
    # 落地 0-0.25 是冲击，0.8s 尾巴收干净
    {"name": "land", "src": "meta_land", "start": 0.0, "length": 0.55, "fade_out": 0.12, "peak": 0.72},
    # 出招命中：拳击落点本身，去掉后段室内反射
    {"name": "hit", "src": "meta_hit", "start": 0.0, "length": 0.42, "fade_out": 0.08, "peak": 0.72},
    {"name": "hit_flesh", "build": lambda: build_hit("flesh")},
    {"name": "hit_wood", "build": lambda: build_hit("wood")},
    {"name": "hit_metal", "build": lambda: build_hit("metal")},
    # 拉钟绳：真管钟，0-0.2 是敲击，3.5s 后基本听不见
    {"name": "bell", "src": "vsco_bell_c4", "start": 0.0, "length": 4.20, "fade_out": 0.60, "peak": 0.80},
    # 通用拾取：小物件落地/入手的那一下，素材库注释里就写着 “a pickup”
    {"name": "slime_voice", "build": build_slime_voice},
    {"name": "limb_pickup", "build": build_limb_pickup},
    {"name": "ui_hover", "build": build_ui_hover},
    {"name": "ui", "build": build_ui},
    {"name": "pause", "build": build_pause},
    {"name": "chest_open", "build": build_chest_open},
    {"name": "weapon_pickup", "build": build_weapon_pickup},
    {"name": "boots_pickup", "build": build_boots_pickup},
    {"name": "relic_pickup", "build": build_relic_pickup},
    {"name": "pickup", "build": build_pickup},
]


def find_source(prefix: str) -> str:
    for ext in (".ogg", ".wav", ".flac"):
        path = os.path.join(SRC, prefix + ext)
        if os.path.isfile(path):
            return path
    raise FileNotFoundError(f"缺少素材 {prefix}，先跑 tools/fetch_audio_samples.ps1")


def decode(path: str):
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


def write_wav(path: str, samples):
    data = array.array("h")
    for x in samples:
        v = int(round(max(-1.0, min(1.0, x)) * 32767))
        data.append(v)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def trim(samples, start, length, fade_out):
    a = int(start * RATE)
    b = min(len(samples), a + int(length * RATE))
    seg = samples[a:b]
    n_out = int(fade_out * RATE)
    # 进声给 2ms，避免裁切点出现“咔”
    n_in = int(0.002 * RATE)
    for i in range(min(n_in, len(seg))):
        seg[i] *= i / n_in
    for i in range(min(n_out, len(seg))):
        seg[len(seg) - 1 - i] *= i / n_out
    return seg


def normalize(seg, peak):
    cur = max((abs(x) for x in seg), default=0.0)
    if cur < 1e-6:
        return seg
    g = peak / cur
    return [x * g for x in seg]


def main():
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for item in SFX_TABLE:
        if "build" in item:
            seg = item["build"]()
            origin = "现场拼"
        else:
            raw = decode(find_source(item["src"]))
            seg = normalize(trim(raw, item["start"], item["length"], item["fade_out"]),
                            item["peak"])
            origin = item["src"]
        dst = os.path.join(OUT, f"sfx_{item['name']}.wav")
        write_wav(dst, seg)
        rms = math.sqrt(sum(x * x for x in seg) / len(seg))
        kb = os.path.getsize(dst) / 1024
        print(f"sfx_{item['name']:<12} {len(seg)/RATE:5.2f}s"
              f"  rms={20*math.log10(max(rms,1e-6)):6.1f} dBFS  {kb:5.1f}KB  <- {origin}")
        total += 1
    print(f"\n共写入 {total} 条，采样率 {RATE} Hz，单声道 16-bit")


if __name__ == "__main__":
    main()
