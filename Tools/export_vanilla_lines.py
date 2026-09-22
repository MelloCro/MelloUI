#!/usr/bin/env python3
"""
List every vanilla quest line the installed voice pack has no recording for,
as a manifest the generator can run on.

The vanilla pack (the wow-voiceover project) is not complete. Against the
cmangos classic database it holds the offer line of 2832 of 3671 quests, the
turn-in line of 3413 of 4214, and the progress line ("come back when you are
done") of only 574 of 3797, so a quest giver who talks on the offer can be
silent on the return. This script reads the cmangos quest texts, drops what
the pack already has, keeps the quests Forever actually has
(Media/QuestListData.lua, unless --all), finds the NPC who says each line (the
quest's starter for the offer, its ender for progress and turn-in; objects and
items narrate) with race and gender from Media/NPCVoiceData.lua, and writes

  MelloUI-BuildData/output/vanilla_missing_lines.json   manifest for generate_voice_lines.py / build_voice_pack.py
  MelloUI-BuildData/output/vanilla_missing_lines.csv    the same, for review
  MelloUI-BuildData/output/vanilla_missing_lines.txt    grouped by NPC

Lines whose words depend on the player's gender ($G...:...;) become two
files, m-<id>-<kind>.mp3 and f-<id>-<kind>.mp3, as in the vanilla pack.

Usage:
  python Tools/export_vanilla_lines.py                   everything missing (progress lines are most of it)
  python Tools/export_vanilla_lines.py --skip-progress   offers and turn-ins only
  python Tools/export_vanilla_lines.py --max-level 30    only quests up to that level
  python Tools/export_vanilla_lines.py --all             also quests Forever's list does not have

then
  python Tools/generate_voice_lines.py --no-export --manifest MelloUI-BuildData/output/vanilla_missing_lines.json --dry-run
  python Tools/generate_voice_lines.py --no-export --manifest MelloUI-BuildData/output/vanilla_missing_lines.json

Needs lupa (pip install lupa) like export_voice_lines.py.
"""

import argparse
import csv
import gzip
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from extract_npc_voices import parse_sql_values, fetch, CMANGOS_SQL  # noqa: E402
from export_voice_lines import load_pack, log, PLACEHOLDERS  # noqa: E402
from paths import OUTPUT, CACHE

try:
    import lupa
except ImportError:
    sys.exit("pip install lupa")

DEFAULT_PACK = "F:/World of Warcraft/_classic_beta_/Interface/AddOns/MelloUI_VoiceOverData"
KIND_COLUMN = {"accept": "Details", "progress": "RequestItemsText", "complete": "OfferRewardText"}
TABLES = {
    "quest_template", "creature_template",
    "creature_questrelation", "creature_involvedrelation",
    "gameobject_questrelation", "gameobject_involvedrelation",
}


def read_tables(path, wanted):
    """Rows of the wanted cmangos tables as dicts, in one pass over the dump."""
    columns = {}
    rows = defaultdict(list)
    current = None
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("CREATE TABLE `"):
                name = line[14:line.index("`", 14)]
                current = name if name in wanted else None
                if current:
                    columns[current] = []
                continue
            if current:
                m = re.match(r"\s*`(\w+)`", line)
                if m:
                    columns[current].append(m.group(1))
                elif line.startswith(")"):
                    current = None
                continue
            if line.startswith("INSERT INTO `"):
                name = line[13:line.index("`", 13)]
                if name in wanted:
                    cols = columns[name]
                    for row in parse_sql_values(line[line.index("VALUES") + 6:]):
                        rows[name].append(dict(zip(cols, row)))
    return rows


def npc_voices():
    """NPC entry -> (race, gender) from the module's data and overrides."""
    info = {}
    # The lists are Lua strings joined with ".." over many lines: let Lua read them.
    runtime = lupa.LuaRuntime()
    runtime.execute(open(os.path.join(HERE, "..", "Media", "NPCVoiceData.lua"), encoding="utf-8").read())
    for key, ids in runtime.globals()["MelloUI_NPCVoiceData"].items():
        m = re.match(r"^(\w+)_(\w)$", str(key))
        if m and isinstance(ids, str):
            for entry in re.findall(r"\d+", ids):
                info[int(entry)] = (m.group(1), m.group(2))
    path = os.path.join(HERE, "..", "Media", "NPCVoiceOverrides.lua")
    if os.path.exists(path):
        over = open(path, encoding="utf-8").read()
        for entry, race, gender in re.findall(r'\[(\d+)\]\s*=\s*\{\s*race\s*=\s*"(\w+)"\s*,\s*gender\s*=\s*"(\w)"', over):
            info[int(entry)] = (race.lower(), gender.lower())
    return info


def forever_quests():
    """Quest ID -> level for the quests in Forever's quest list data."""
    runtime = lupa.LuaRuntime()
    runtime.execute(open(os.path.join(HERE, "..", "Media", "QuestListData.lua"), encoding="utf-8").read())
    data = runtime.globals()["MelloUI_QuestListData"]
    return {int(row[1]): int(row[3] or 0) for row in data["quests"].values()}


def spoken(text, player_gender):
    """The text as it is to be read: placeholders as words, the $G form for
    the given player gender, line breaks as spaces."""
    out = re.sub(r"\$[gG]([^;]*);([^;]*);", r"\1" if player_gender == "m" else r"\2", text)
    for key, word in PLACEHOLDERS.items():
        out = out.replace(key, word)
    out = re.sub(r"\$[bB]", " ", out)
    return re.sub(r"\s+", " ", out).strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", default=DEFAULT_PACK)
    ap.add_argument("--out", default=OUTPUT)
    ap.add_argument("--skip-progress", action="store_true", help="leave the progress lines out")
    ap.add_argument("--max-level", type=int, default=0, help="only quests up to this level (0: all)")
    ap.add_argument("--all", action="store_true", help="every vanilla quest, not only those in Forever's quest list")
    ap.add_argument("--sources", default=os.path.join(HERE, "pack_sources"),
                    help="folder of MP3s already generated; lines with a file there are not listed")
    args = ap.parse_args()

    if not os.path.isdir(args.pack):
        sys.exit(f"pack not found: {args.pack}")
    quest_files, _, _ = load_pack(args.pack)
    log(f"pack: {len(quest_files)} recorded lines")

    sql = fetch(CMANGOS_SQL, os.path.join(CACHE, "ClassicDB.sql.gz"))
    log("reading the cmangos quest texts, givers and NPC names")
    tables = read_tables(sql, TABLES)
    names = {int(r["Entry"]): r.get("Name", "") for r in tables["creature_template"]}
    starters, enders = defaultdict(list), defaultdict(list)
    for r in tables["creature_questrelation"]:
        starters[int(r["quest"])].append(("npc", int(r["id"])))
    for r in tables["gameobject_questrelation"]:
        starters[int(r["quest"])].append(("object", int(r["id"])))
    for r in tables["creature_involvedrelation"]:
        enders[int(r["quest"])].append(("npc", int(r["id"])))
    for r in tables["gameobject_involvedrelation"]:
        enders[int(r["quest"])].append(("object", int(r["id"])))
    voices = npc_voices()
    wanted = None if args.all else forever_quests()

    def speaker(candidates):
        """The NPC to voice a line: an NPC with voice data first, any NPC, else nothing (narration)."""
        npcs = sorted(entry for kind, entry in candidates if kind == "npc")
        for entry in npcs:
            if entry in voices:
                return entry
        return npcs[0] if npcs else None

    rows = []
    quests = set()
    unknown_npcs = set()
    for rec in tables["quest_template"]:
        qid = int(rec["entry"])
        if wanted is not None and qid not in wanted:
            continue
        level = wanted[qid] if wanted is not None and wanted.get(qid) else int(rec.get("QuestLevel") or 0)
        if args.max_level and level > args.max_level:
            continue
        title = rec.get("Title", "") or ""
        for kind, column in KIND_COLUMN.items():
            if kind == "progress" and args.skip_progress:
                continue
            text = (rec.get(column) or "").strip()
            if not text or not any(c.isalpha() for c in text):
                continue
            if f"{qid}-{kind}" in quest_files or f"m-{qid}-{kind}" in quest_files or f"f-{qid}-{kind}" in quest_files:
                continue
            npc = speaker(starters.get(qid, []) if kind == "accept" else enders.get(qid, []))
            race, gender = voices.get(npc, ("", "")) if npc else ("", "")
            if npc and not gender:
                unknown_npcs.add(npc)
            variants = [("m", "m-"), ("f", "f-")] if re.search(r"\$[gG][^;]*;[^;]*;", text) else [("m", "")]
            for player_gender, prefix in variants:
                file_name = f"{prefix}{qid}-{kind}.mp3"
                if os.path.exists(os.path.join(args.sources, file_name)):
                    continue
                rows.append({
                    "kind": kind,
                    "status": "vanilla-unrecorded",
                    "file": file_name,
                    "questID": qid,
                    "title": title,
                    "npcID": npc or "",
                    "npc": names.get(npc, "") if npc else "",
                    "race": race,
                    "gender": gender,
                    "creatureType": "",
                    "text": spoken(text, player_gender),
                    "rawText": text,
                    "level": level,
                })
                quests.add(qid)

    rows.sort(key=lambda row: (row["level"], row["questID"], row["kind"] != "accept", row["file"]))
    os.makedirs(args.out, exist_ok=True)
    base = os.path.join(args.out, "vanilla_missing_lines")
    columns = ["kind", "status", "file", "questID", "title", "npcID", "npc", "race", "gender", "creatureType", "text", "rawText", "level"]
    with open(base + ".csv", "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=columns)
        w.writeheader()
        for row in rows:
            w.writerow(row)
    by_npc = defaultdict(list)
    for row in rows:
        by_npc[(row["npc"] or "Narrator (object or item)", row["npcID"])].append(row)
    with open(base + ".txt", "w", encoding="utf-8") as fh:
        fh.write(f"Vanilla quest lines without a recording  ({len(rows)} lines, {len(quests)} quests, {len(by_npc)} speakers)\n")
        fh.write("One block per NPC. Voice hint = race / gender. File = name to save the MP3 as.\n\n")
        for (npc, npc_id), items in sorted(by_npc.items(), key=lambda kv: (kv[0][0], str(kv[0][1]))):
            first = items[0]
            hint = " ".join(x for x in (first["race"], first["gender"]) if x) or "race unknown"
            fh.write(f"=== {npc} (NPC {npc_id or '?'}) - {hint}\n")
            for row in items:
                fh.write(f"[{row['file']}] {row['kind']} of \"{row['title']}\" (level {row['level']})\n{row['text']}\n\n")
    json.dump({"lines": rows}, open(base + ".json", "w", encoding="utf-8"), indent=1, ensure_ascii=False)

    counts = defaultdict(int)
    chars = defaultdict(int)
    for row in rows:
        counts[row["kind"]] += 1
        chars[row["kind"]] += len(row["text"])
    log(f"wrote {len(rows)} lines for {len(quests)} quests to {base}.json / .csv / .txt")
    for kind in KIND_COLUMN:
        if counts[kind]:
            log(f"  {kind:9s} {counts[kind]:5d} lines  {chars[kind]:7d} characters")
    log(f"  total     {len(rows):5d} lines  {sum(chars.values()):7d} characters (ElevenLabs bills per character)")
    if unknown_npcs:
        log(f"  {len(unknown_npcs)} speaking NPCs have no race / gender in Media/NPCVoiceData.lua; the generator narrates "
            f"them unless they are added to Media/NPCVoiceOverrides.lua (e.g. {', '.join(str(n) for n in sorted(unknown_npcs)[:8])})")


if __name__ == "__main__":
    main()
