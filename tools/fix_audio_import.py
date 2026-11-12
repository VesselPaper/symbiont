"""把所有音频 .import 强制改成无损 16-bit PCM。

为什么需要：Godot 4 默认用 QOA 有损压缩导入 WAV，短音效和低电平 BGM 的量化噪声
会被放大成“沙沙”底噪——这就是之前整套音效听起来全是噪声的主因之一。
每次新增音频后跑一遍，再让 Godot 重新导入。

用法：python tools/fix_audio_import.py
"""

import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "client", "assets", "audio")


def main():
    changed = 0
    for path in sorted(glob.glob(os.path.join(AUDIO, "*.wav.import"))):
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        if re.search(r"compress/mode=0$", text, re.M):
            continue
        new = re.sub(r"compress/mode=\d+", "compress/mode=0", text)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
        changed += 1
        print(f"fixed {os.path.basename(path)}")
    print(f"done, {changed} files changed")


if __name__ == "__main__":
    main()
