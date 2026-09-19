#!/usr/bin/env python3
"""
Turn the dialog lines collected in game by the Voice Over module into the list
of lines that need recording for a WoW: Forever sound pack.

The module stores what it sees in the MelloUIVoiceLines saved variable. On the
Forever beta the client writes that file on /reload but never reads it back,
so run this after every session (before restarting the client): it merges the
session into Tools/cache/voice_lines.json and rebuilds the outputs from the
merged store.

Outputs (in Tools/output/):
  forever_voice_lines.csv   one row per line to record, for review / spreadsheets
  forever_voice_lines.txt   the same grouped by NPC, ready to paste into ElevenLabs
  forever_voice_lines.json  manifest used by build_voice_pack.py to package the MP3s

Only lines without a usable recording in the installed VoiceOver pack are
listed. Each line has a status:
  new-quest    quest ID unknown to the vanilla database
  rewritten    vanilla quest exists but Forever changed the text
  unrecorded   same text as vanilla, the pack just has no file for it
  greeting     NPC greeting with no matching recording

Usage:
  python Tools/export_voice_lines.py [--wtf "F:/World of Warcraft/_classic_beta_/WTF"]
        [--pack "F:/World of Warcraft/_classic_beta_/Interface/AddOns/AI_VoiceOverData_Vanilla"]
        [--store Tools/cache/voice_lines.json] [--out Tools/output]

Needs the lupa package (pip install lupa) to read the Lua files.
"""

import argparse
import csv
import glob
import gzip
import hashlib
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(__file__))
from extract_npc_voices import parse_sql_values, fetch, CMANGOS_SQL  # noqa: E402

try:
    import lupa
except ImportError:
    sys.exit("pip install lupa")

DEFAULT_WTF = "F:/World of Warcraft/_classic_beta_/WTF"
DEFAULT_PACK = "F:/World of Warcraft/_classic_beta_/Interface/AddOns/AI_VoiceOverData_Vanilla"

# How placeholders are spoken. $n is the player's name, $c class, $r race,
# $g male;female; picks by player gender.
# Same words the vanilla pack's generator used, so new lines sound consistent.
PLACEHOLDERS = {"$n": "adventurer", "$N": "Adventurer", "$c": "adventurer", "$C": "Adventurer", "$r": "traveler", "$R": "Traveler", "$b": " ", "$B": " "}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def lua_to_python(value):
    # Every table becomes a dict with string keys: the store is keyed by NPC
    # and quest IDs, which are numbers in Lua but must not turn into lists.
    if lupa.lua_type(value) == "table":
        out = {}
        for k, v in value.items():
            if isinstance(k, float) and k.is_integer():
                k = int(k)
            out[str(k)] = lua_to_python(v)
        return out
    return value


def run_lua_file(runtime, path, globals_needed=()):
    src = open(path, encoding="utf-8", errors="replace").read()
    for name in globals_needed:
        runtime.execute(f"{name} = {name} or {{}}")
    runtime.execute(src)


def load_saved_variables(wtf):
    files = glob.glob(os.path.join(wtf, "Account", "*", "SavedVariables", "MelloUI.lua"))
    sessions = []
    for path in files:
        runtime = lupa.LuaRuntime()
        try:
            runtime.execute(open(path, encoding="utf-8", errors="replace").read())
        except Exception as exc:  # noqa: BLE001
            log(f"could not read {path}: {exc}")
            continue
        lines = runtime.globals().MelloUIVoiceLines
        if lines is not None:
            data = lua_to_python(lines)
            data["_file"] = path
            data["_mtime"] = os.path.getmtime(path)
            sessions.append(data)
            log(f"session data: {path} ({len(data.get('quests', {}))} quests, {sum(len(v) for v in data.get('gossip', {}).values())} greetings)")
    return sessions


def merge_store(store, session):
    for key, kinds in session.get("quests", {}).items():
        store.setdefault("quests", {}).setdefault(key, {}).update(kinds)
    for npc_id, texts in session.get("gossip", {}).items():
        store.setdefault("gossip", {}).setdefault(npc_id, {}).update(texts)
    for npc_id, rec in session.get("npcs", {}).items():
        store.setdefault("npcs", {}).setdefault(npc_id, {}).update({k: v for k, v in rec.items() if v is not None})
    if session.get("player"):
        store["player"] = session["player"]


def migrate_placeholders(store, player):
    """Rewrite stored texts so name / class / race are placeholders; lines
    collected before the module did this itself still carry the real words."""
    if not player:
        return
    for kinds in store.get("quests", {}).values():
        for kind, rec in kinds.items():
            if kind.startswith("_"):
                continue
            rec["text"] = placeholdered(rec["text"], player)
    for npc_id, texts in list(store.get("gossip", {}).items()):
        fixed = {}
        for text, rec in texts.items():
            new_text = placeholdered(text, player)
            rec["text"] = new_text
            fixed[new_text] = rec
        store["gossip"][npc_id] = fixed


def load_pack(pack_dir):
    """Return (quest_files set, gossip_by_npc_id, gossip_by_name) from a VoiceOver data pack."""
    runtime = lupa.LuaRuntime()
    runtime.execute("VoiceOver = { DataModules = {} }")
    name = os.path.basename(pack_dir.rstrip("/\\"))
    runtime.execute(f"{name} = {{}}")
    gen = os.path.join(pack_dir, "generated")
    for f in ("sound_length_table.lua", "gossip_file_lookups.lua", "npc_name_gossip_file_lookups.lua"):
        path = os.path.join(gen, f)
        if os.path.exists(path):
            runtime.execute(open(path, encoding="utf-8", errors="replace").read())
    data = runtime.globals()[name]
    lengths = lua_to_python(data.SoundLengthLookupByFileName) if data.SoundLengthLookupByFileName else {}
    by_id = lua_to_python(data.GossipLookupByNPCID) if data.GossipLookupByNPCID else {}
    by_name = lua_to_python(data.GossipLookupByNPCName) if data.GossipLookupByNPCName else {}
    return set(lengths.keys()), by_id, by_name


def normalise(text):
    text = text.lower()
    text = re.sub(r"\$g[^;]*;[^;]*;", " ", text)
    text = re.sub(r"[^\w$\s]", " ", text)
    return text


def similarity(a, b):
    ta, tb = set(normalise(a).split()), set(normalise(b).split())
    if not ta and not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def load_vanilla_quests(cache_dir):
    path = fetch(CMANGOS_SQL, os.path.join(cache_dir, "ClassicDB.sql.gz"))
    quests = {}
    columns = None
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        in_create = False
        for line in fh:
            if line.startswith("CREATE TABLE `quest_template`"):
                in_create, columns = True, []
                continue
            if in_create:
                m = re.match(r"\s*`(\w+)`", line)
                if m:
                    columns.append(m.group(1))
                elif line.startswith(")"):
                    in_create = False
                continue
            if line.startswith("INSERT INTO `quest_template`"):
                for row in parse_sql_values(line[line.index("VALUES") + 6:]):
                    rec = dict(zip(columns, row))
                    quests[int(rec["entry"])] = {
                        "title": rec.get("Title", ""),
                        "accept": rec.get("Details", ""),
                        "progress": rec.get("RequestItemsText", ""),
                        "complete": rec.get("OfferRewardText", ""),
                    }
    log(f"vanilla quests: {len(quests)}")
    return quests


def placeholdered(text, player):
    """Turn the player's name / class / race back into $n / $c / $r (the module
    does this at collection time now; older stored lines still need it)."""
    if not player:
        return text
    for key, placeholder in (("name", "$n"), ("class", "$c"), ("race", "$r")):
        value = player.get(key)
        if value:
            text = re.sub(r"\b" + re.escape(value) + r"\b", placeholder, text, flags=re.IGNORECASE)
    return text


def spoken_text(text, player=None):
    out = placeholdered(text, player)
    out = re.sub(r"\$g([^;]*);([^;]*);", r"\1", out)
    for key, word in PLACEHOLDERS.items():
        out = out.replace(key, word)
    out = re.sub(r"\s+", " ", out).strip()
    return out


def gossip_hash(text):
    return hashlib.md5(normalise(text).encode("utf-8")).hexdigest()


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wtf", default=DEFAULT_WTF)
    ap.add_argument("--pack", default=DEFAULT_PACK)
    ap.add_argument("--store", default=os.path.join(here, "cache", "voice_lines.json"))
    ap.add_argument("--out", default=os.path.join(here, "output"))
    ap.add_argument("--player", default=None, help="your character name, replaced by $n before the text is spoken")
    ap.add_argument("--player-class", default=None, help="your class name as shown in game (Warrior), replaced by $c; newer sessions record it themselves")
    ap.add_argument("--player-race", default=None, help="your race name as shown in game (Human), replaced by $r")
    ap.add_argument("--sources", default=os.path.join(here, "pack_sources"),
                    help="folder of MP3s already generated (build_voice_pack.py assign); lines with a file there are not listed")
    args = ap.parse_args()

    store = {}
    if os.path.exists(args.store):
        store = json.load(open(args.store, encoding="utf-8"))
    for session in load_saved_variables(args.wtf):
        merge_store(store, session)
    player = dict(store.get("player") or {})
    if args.player:
        player["name"] = args.player
    if args.player_class:
        player["class"] = args.player_class
    if args.player_race:
        player["race"] = args.player_race
    migrate_placeholders(store, player)
    if player:
        # Remember name / class / race so later runs migrate without flags.
        store["player"] = player
    os.makedirs(os.path.dirname(args.store), exist_ok=True)
    json.dump(store, open(args.store, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    log(f"store: {len(store.get('quests', {}))} quests, {sum(len(v) for v in store.get('gossip', {}).values())} greetings, {len(store.get('npcs', {}))} NPCs")

    quest_files, gossip_by_id, gossip_by_name = load_pack(args.pack) if os.path.isdir(args.pack) else (set(), {}, {})
    vanilla = load_vanilla_quests(os.path.join(here, "cache"))
    npcs = store.get("npcs", {})

    rows = []
    for key, kinds in sorted(store.get("quests", {}).items(), key=lambda kv: (not kv[0].isdigit(), kv[0].zfill(8))):
        quest_id = int(key) if key.isdigit() else None
        level = kinds.get("_level", 0)
        for kind, rec in kinds.items():
            if kind.startswith("_"):
                continue
            if quest_id is not None and (f"{quest_id}-{kind}" in quest_files or f"m-{quest_id}-{kind}" in quest_files):
                continue
            status = "new-quest"
            if quest_id in vanilla:
                old = vanilla[quest_id].get(kind, "") or ""
                status = "rewritten" if similarity(old, rec["text"]) < 0.85 else "unrecorded"
            npc_id = rec.get("npcID")
            npc = npcs.get(str(npc_id), {}) if npc_id else {}
            rows.append({
                "kind": kind,
                "status": status,
                "file": f"{quest_id}-{kind}.mp3" if quest_id is not None else f"title-{re.sub(r'[^A-Za-z0-9]+', '_', rec.get('title', ''))}-{kind}.mp3",
                "questID": quest_id or "",
                "title": rec.get("title", ""),
                "npcID": npc_id or "",
                "npc": rec.get("npc") or npc.get("name", ""),
                "race": npc.get("race", ""),
                "gender": npc.get("gender", ""),
                "creatureType": npc.get("type", ""),
                "text": spoken_text(rec["text"], player),
                "rawText": rec["text"],
                "level": level,
            })

    for npc_id, texts in store.get("gossip", {}).items():
        npc = npcs.get(str(npc_id), {})
        recorded_texts = {}
        try:
            recorded_texts.update(gossip_by_id.get(str(int(npc_id)), {}))
        except ValueError:
            pass
        if npc.get("name"):
            recorded_texts.update(gossip_by_name.get(npc["name"].replace('"', "'"), {}))
        for text, rec in texts.items():
            best = max((similarity(text, t) for t in recorded_texts), default=0.0)
            if best >= 0.4:
                continue
            rows.append({
                "kind": "gossip",
                "status": "greeting",
                "file": f"{gossip_hash(text)}.mp3",
                "questID": "",
                "title": "",
                "npcID": npc_id,
                "npc": rec.get("npc") or npc.get("name", ""),
                "race": npc.get("race", ""),
                "gender": npc.get("gender", ""),
                "creatureType": npc.get("type", ""),
                "text": spoken_text(text, player),
                "rawText": text,
            })

    already = [row for row in rows if os.path.exists(os.path.join(args.sources, row["file"]))]
    if already:
        log(f"{len(already)} lines already have an MP3 in {args.sources} and are left out")
        rows = [row for row in rows if row not in already]

    os.makedirs(args.out, exist_ok=True)
    columns = ["kind", "status", "file", "questID", "title", "npcID", "npc", "race", "gender", "creatureType", "text", "rawText", "level"]
    for row in rows:
        row.setdefault("level", "")
    with open(os.path.join(args.out, "forever_voice_lines.csv"), "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=columns)
        w.writeheader()
        for row in rows:
            w.writerow(row)

    by_npc = defaultdict(list)
    for row in rows:
        by_npc[(row["npc"] or "Unknown NPC", row["npcID"])].append(row)
    with open(os.path.join(args.out, "forever_voice_lines.txt"), "w", encoding="utf-8") as fh:
        fh.write(f"Lines to record for WoW: Forever  ({len(rows)} lines, {len(by_npc)} NPCs)\n")
        fh.write("One block per NPC. Voice hint = race / gender. File = name to save the MP3 as.\n\n")
        for (npc, npc_id), items in sorted(by_npc.items(), key=lambda kv: (kv[0][0], str(kv[0][1]))):
            first = items[0]
            hint = " ".join(x for x in (first["race"], first["gender"], first["creatureType"]) if x) or "race unknown"
            fh.write(f"=== {npc} (NPC {npc_id or '?'}) - {hint}\n")
            for row in items:
                label = row["title"] and f"{row['kind']} of \"{row['title']}\"" or row["kind"]
                fh.write(f"[{row['file']}] {label} ({row['status']})\n{row['text']}\n\n")
    json.dump({"lines": rows}, open(os.path.join(args.out, "forever_voice_lines.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)

    counts = defaultdict(int)
    for row in rows:
        counts[row["status"]] += 1
    log(f"wrote {len(rows)} lines to {args.out}: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main()
