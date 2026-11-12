"""音频资产覆盖检查：名字、文件、调用三边必须对得上。

这个文件存在的原因：音效是散在几十个脚本里按字符串点播的，
写了 `play_sfx("limb_pickup")` 但没生成文件，或者生成了文件却没人播，
在无头测试里都不会报错——只有真玩到那一步才发现没声音。
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
AUDIO = ROOT / "client" / "assets" / "audio"
DIRECTOR = ROOT / "client" / "scripts" / "audio" / "audio_director.gd"


def _sfx_names() -> list[str]:
    text = DIRECTOR.read_text(encoding="utf-8")
    block = text.split("const SFX_NAMES := [")[1].split("]")[0]
    return re.findall(r'"([a-z_]+)"', block)


def _file_map(const_name: str) -> dict[str, str]:
    text = DIRECTOR.read_text(encoding="utf-8")
    block = text.split(f"const {const_name} := {{")[1].split("}")[0]
    return dict(re.findall(r'"([a-z0-9_]+)": "([a-z0-9_]+\.wav)"', block))


def test_every_sfx_name_has_file() -> None:
    names = _sfx_names()
    assert len(names) >= 30, f"SFX 目录太短：{len(names)}"
    missing = [n for n in names if not (AUDIO / f"sfx_{n}.wav").is_file()]
    assert not missing, f"缺少音频文件：{missing}"


def test_no_orphan_sfx_file() -> None:
    names = set(_sfx_names())
    files = {p.name[4:-4] for p in AUDIO.glob("sfx_*.wav")}
    orphans = sorted(files - names)
    assert not orphans, f"有文件但目录里没登记：{orphans}"


def test_play_sfx_literals_are_registered() -> None:
    names = set(_sfx_names())
    unknown: list[str] = []
    for path in ROOT.glob("client/**/*.gd"):
        for name in re.findall(r'play_sfx\("([a-z_]+)"', path.read_text(encoding="utf-8")):
            # "hit_" 是动态拼材质后缀的半截名字，单独放行
            if name.endswith("_") or name in names:
                continue
            unknown.append(f"{path.name}: {name}")
    assert not unknown, f"点播了没登记的音效：{sorted(set(unknown))}"


def test_music_tracks_have_files() -> None:
    bgm = _file_map("BGM_TRACKS")
    amb = _file_map("AMB_TRACKS")
    assert len(bgm) == 7, f"BGM 曲目数不对：{len(bgm)}"
    for key, file in list(bgm.items()) + list(amb.items()):
        assert (AUDIO / file).is_file(), f"{key} -> {file} 不存在"


def test_four_ambience_files() -> None:
    found = sorted(p.name for p in AUDIO.glob("amb_*.wav"))
    assert len(found) >= 4, f"环境音不足四条：{found}"
