"""清点音效：目录、文件、调用三边对不上就是缺口。"""

import pathlib
import re

gd = pathlib.Path("client/scripts/audio/audio_director.gd").read_text(encoding="utf-8")
block = gd.split("const SFX_NAMES := [")[1].split("]")[0]
names = re.findall(r'"([a-z_]+)"', block)
files = {p.stem[4:] for p in pathlib.Path("client/assets/audio").glob("sfx_*.wav")}

called = set()
for p in pathlib.Path("client").rglob("*.gd"):
    called.update(re.findall(r'play_sfx\("([a-z_]+)"', p.read_text(encoding="utf-8")))

print("SFX_NAMES:", len(names), "文件:", len(files), "被调用:", len(called))
print("\n在目录里但没文件:", sorted(set(names) - files))
print("\n有文件但不在目录:", sorted(files - set(names)))
print("\n在目录里但从没被调用:", sorted(set(names) - called))
print("\n调用了但不在目录:", sorted(called - set(names)))

sizes = {}
for p in pathlib.Path("client/assets/audio").glob("sfx_*.wav"):
    sizes[p.stem[4:]] = p.stat().st_size / 1024
never = sorted(set(names) - called)
print("\n没被调用的文件大小：")
for n in never:
    print("  %-16s %6.1fKB" % (n, sizes.get(n, 0)))
