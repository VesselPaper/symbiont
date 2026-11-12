#!/usr/bin/env python3
"""把对话里的「系统」旁白清掉（M4-21 组长定稿：对话不要有“系统”）。

做法：只动 database/game_data/seed.sql 里含 "系统" 的台词行，解析单引号里的 JSON，
丢掉 speaker == "系统" 的行；少数几句是流程/篇幅上必须有台词的（拒绝献祭、真 HE 骨片），
按寄生体口吻改写一句顶上，其余一律删掉。改完由 build_game_data + db_export 重新生成 JSON。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "database" / "game_data" / "seed.sql"

# 删掉“系统”之后必须补一句的地方（按对话 id 指定），否则流程断掉或对话变成独白
REPLACE: dict[str, list[dict[str, str]]] = {
    # 拒绝献祭：这是整条拒绝路线的唯一台词，删空了对话组件不会 started，
    # 结局画面就永远等不到 finished（流程卡死）
    "refuse_die": [
        {"speaker": "寄生体", "text": "你拒绝了。那就慢慢看着自己散掉——剩下的，我收下。"},
    ],
    # 真 HE 骨片：原来两句（旁白 + 寄生体），删完只剩一句，撑不起一次“对话”
    "true_he_relic_pickup": [
        {"speaker": "寄生体", "text": "一块发白的旧骨片，没被消化干净——留好，回去要用。"},
        {"speaker": "寄生体", "text": "那是你第一次献出去的东西。拿回祭坛，放回碗里。这一次，别求它收下。"},
    ],
}

ROW_JSON = re.compile(r"'(?P<json>\[.*?\])'")


def main() -> int:
    text = SEED.read_text(encoding="utf-8")
    lines = text.split("\n")
    changed: list[str] = []
    removed = 0
    # 每条对话的 id 在 JSON 上一行（('id', npc, '标题',）
    for i, line in enumerate(lines):
        m = ROW_JSON.search(line)
        if not m:
            continue
        raw = m.group("json")
        if "系统" not in raw:
            continue
        dialogue_id = ""
        if i >= 1:
            id_match = re.search(r"\('(?P<id>[a-z0-9_]+)'", lines[i - 1])
            if id_match:
                dialogue_id = id_match.group("id")
        rows = json.loads(raw)
        kept = [row for row in rows if row.get("speaker") != "系统"]
        removed += len(rows) - len(kept)
        if dialogue_id in REPLACE:
            kept = REPLACE[dialogue_id]
        if not kept:
            print(f"!! {dialogue_id or '?'} 删完没有台词了，检查 REPLACE")
            return 1
        new_raw = json.dumps(kept, ensure_ascii=False, separators=(", ", ": "))
        lines[i] = line.replace(raw, new_raw)
        changed.append(dialogue_id or "?")
    SEED.write_text("\n".join(lines), encoding="utf-8")
    print(f"改了 {len(changed)} 条对话，删掉 {removed} 句“系统”台词：")
    for cid in changed:
        print("  -", cid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
