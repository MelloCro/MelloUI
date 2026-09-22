#!/usr/bin/env python3
"""
Package generated MP3s into a VoiceOver data pack for WoW: Forever.

Works with the manifest written by export_voice_lines.py
(MelloUI-BuildData/output/forever_voice_lines.json). Every line there has a target file
name; the MP3s you generate are collected under Tools/pack_sources with those
names, and `build` turns them into the addon

    <AddOns>/MelloUI_VoiceOverData   (the merged pack; its other lines are kept)

which the MelloUI Voice Over module loads ahead of the vanilla pack (it also
works with the VoiceOver player addon, the layout and tables are the same).

Commands:
  assign <mp3> <target>   copy a downloaded MP3 to its line's file name, e.g.
                          assign "C:/Users/me/Downloads/ElevenLabs_....mp3" 438f1d33c45224f28ca6ff36f57f50b9.mp3
  assign-latest <target>  same, taking the newest MP3 in --downloads
  pending                 list lines from the manifest that have no MP3 yet
  build                   write the addon folder from the assigned MP3s
  status                  what is assigned, what is missing

Options:
  --manifest  MelloUI-BuildData/output/forever_voice_lines.json
  --sources   Tools/pack_sources          (assigned MP3s, kept out of the game folder)
  --downloads C:/Users/<you>/Downloads/VoiceOver_GossipQuest
  --addons    F:/World of Warcraft/_classic_beta_/Interface/AddOns
  --name      MelloUI_VoiceOverData
  --priority  200                          (higher than the vanilla pack's 100)

Only the Python standard library is needed; MP3 durations are read from the
frame headers directly.
"""

import argparse
import glob
import hashlib
import json
import os
import shutil
import struct
import sys
from paths import OUTPUT, CACHE

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = "if not VoiceOver or not VoiceOver.DataModules then return end"

# ---------------------------------------------------------------------------
# MP3 duration
# ---------------------------------------------------------------------------

BITRATES = {
    # (version, layer): [bitrates kbps by index]
    (1, 3): [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
    (2, 3): [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
}
SAMPLE_RATES = {1: [44100, 48000, 32000], 2: [22050, 24000, 16000], 25: [11025, 12000, 8000]}


def mp3_duration(path):
    """Duration in seconds by walking the MPEG frames (handles ID3v2 and VBR)."""
    data = open(path, "rb").read()
    pos = 0
    if data[:3] == b"ID3":
        size = 0
        for b in data[6:10]:
            size = (size << 7) | (b & 0x7F)
        pos = 10 + size
    seconds = 0.0
    n = len(data)
    while pos + 4 <= n:
        b1, b2, b3 = data[pos], data[pos + 1], data[pos + 2]
        if b1 == 0xFF and (b2 & 0xE0) == 0xE0:
            version_bits = (b2 >> 3) & 0x03
            layer_bits = (b2 >> 1) & 0x03
            bitrate_index = (b3 >> 4) & 0x0F
            rate_index = (b3 >> 2) & 0x03
            padding = (b3 >> 1) & 0x01
            version = {3: 1, 2: 2, 0: 25}.get(version_bits)
            layer = {1: 3, 2: 2, 3: 1}.get(layer_bits)
            if version and layer == 3 and bitrate_index not in (0, 15) and rate_index != 3:
                table = BITRATES[(1 if version == 1 else 2, 3)]
                bitrate = table[bitrate_index] * 1000
                sample_rate = SAMPLE_RATES[version][rate_index]
                samples = 1152 if version == 1 else 576
                frame_len = (samples // 8 * bitrate) // sample_rate + padding
                if frame_len > 4:
                    # Skip a Xing/Info header frame: it holds no audio.
                    body = data[pos + 4:pos + frame_len]
                    if b"Xing" not in body and b"Info" not in body:
                        seconds += samples / sample_rate
                    pos += frame_len
                    continue
        pos += 1
    return round(seconds, 3)


# ---------------------------------------------------------------------------
# Lua output
# ---------------------------------------------------------------------------

def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", " ").replace("\n", " ") + '"'


def lua_key(key):
    if isinstance(key, int):
        return f"[{key}]"
    return f"[{lua_string(key)}]"


def lua_table(obj, indent=1):
    pad = "\t" * indent
    if isinstance(obj, dict):
        lines = ["{"]
        for key in sorted(obj, key=lambda k: (isinstance(k, str), k)):
            lines.append(f"{pad}{lua_key(key)} = {lua_table(obj[key], indent + 1)},")
        lines.append("\t" * (indent - 1) + "}")
        return "\n".join(lines)
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if isinstance(obj, (int, float)):
        return repr(obj)
    return lua_string(str(obj))


def write_lua(path, name, table_name, value):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(GUARD + "\n")
        fh.write(f"{name}.{table_name} = {lua_table(value)}\n")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def load_manifest(path):
    if not os.path.exists(path):
        sys.exit(f"manifest not found: {path} (run export_voice_lines.py first)")
    return json.load(open(path, encoding="utf-8"))["lines"]


def load_all_lines(manifest_path, store_path):
    """Every line ever collected, not only the pending ones: a line leaves the
    manifest once it has a recording, but the pack must keep carrying it."""
    sys.path.insert(0, HERE)
    from export_voice_lines import gossip_hash  # noqa: E402

    rows = {row["file"]: row for row in load_manifest(manifest_path)}
    if not os.path.exists(store_path):
        return list(rows.values())
    store = json.load(open(store_path, encoding="utf-8"))
    npcs = store.get("npcs", {})

    def add(row):
        rows.setdefault(row["file"], row)

    for key, kinds in store.get("quests", {}).items():
        if not key.isdigit():
            continue
        for kind, rec in kinds.items():
            if kind.startswith("_"):
                continue
            npc = npcs.get(str(rec.get("npcID")), {})
            add({
                "kind": kind, "status": "stored", "file": f"{key}-{kind}.mp3", "questID": int(key),
                "title": rec.get("title", ""), "npcID": rec.get("npcID") or "",
                "npc": rec.get("npc") or npc.get("name", ""), "race": npc.get("race", ""),
                "gender": npc.get("gender", ""), "creatureType": npc.get("type", ""),
                "text": rec["text"], "rawText": rec["text"],
            })
    for npc_id, texts in store.get("gossip", {}).items():
        npc = npcs.get(str(npc_id), {})
        for text, rec in texts.items():
            add({
                "kind": "gossip", "status": "stored", "file": f"{gossip_hash(text)}.mp3", "questID": "",
                "title": "", "npcID": npc_id, "npc": rec.get("npc") or npc.get("name", ""),
                "race": npc.get("race", ""), "gender": npc.get("gender", ""), "creatureType": npc.get("type", ""),
                "text": text, "rawText": text,
            })
    return list(rows.values())


def cmd_pending(args, lines):
    missing = [row for row in lines if not os.path.exists(os.path.join(args.sources, row["file"]))]
    for row in missing:
        label = row["title"] and f'{row["kind"]} of "{row["title"]}"' or row["kind"]
        print(f'{row["file"]}  {row["npc"]}  {label}')
    print(f"{len(missing)} of {len(lines)} lines still need an MP3", file=sys.stderr)


def cmd_assign(args, lines, source, target):
    targets = {row["file"] for row in lines}
    if target not in targets:
        sys.exit(f"{target} is not a file name in the manifest (see `pending`)")
    if not os.path.exists(source):
        sys.exit(f"not found: {source}")
    os.makedirs(args.sources, exist_ok=True)
    dest = os.path.join(args.sources, target)
    shutil.copyfile(source, dest)
    print(f"assigned {os.path.basename(source)} -> {dest} ({mp3_duration(dest)} s)")


def cmd_assign_latest(args, lines, target):
    files = sorted(glob.glob(os.path.join(args.downloads, "*.mp3")), key=os.path.getmtime)
    if not files:
        sys.exit(f"no MP3 files in {args.downloads}")
    cmd_assign(args, lines, files[-1], target)


def cmd_build(args, lines):
    name = args.name
    root = os.path.join(args.addons, name)
    gen = os.path.join(root, "generated")
    sounds = os.path.join(gen, "sounds")
    os.makedirs(os.path.join(sounds, "quests"), exist_ok=True)
    os.makedirs(os.path.join(sounds, "gossip"), exist_ok=True)

    # The pack may already hold other lines (the merged pack carries the
    # vanilla ones): start from its tables and lay the Forever lines on top.
    sys.path.insert(0, HERE)
    from merge_voice_packs import load_tables, merge as merge_tables
    existing = {}
    if os.path.exists(os.path.join(gen, "sound_length_table.lua")):
        existing = load_tables(root, name)
        print(f"keeping {len(existing.get('SoundLengthLookupByFileName', {}))} lines already in {name}")
    existing_quests = existing.get("QuestIDLookup", {})

    lengths = {}
    gossip_by_id = {}
    gossip_by_name = {}
    npc_names = {}
    quest_lookup = {"accept": {}, "progress": {}, "complete": {}}
    npc_by_quest = {}
    used = 0
    for row in lines:
        src = os.path.join(args.sources, row["file"])
        if not os.path.exists(src):
            continue
        base = row["file"][:-4]
        folder = "gossip" if row["kind"] == "gossip" else "quests"
        dest = os.path.join(sounds, folder, row["file"])
        if not os.path.exists(dest) or os.path.getmtime(dest) < os.path.getmtime(src):
            shutil.copyfile(src, dest)
        lengths[base] = mp3_duration(dest)
        used += 1
        npc_id = int(row["npcID"]) if str(row["npcID"]).isdigit() else None
        if npc_id and row["npc"]:
            npc_names[npc_id] = row["npc"]
        if row["kind"] == "gossip":
            text = row["rawText"].replace('"', "'")
            if npc_id:
                gossip_by_id.setdefault(npc_id, {})[text] = base
            if row["npc"]:
                gossip_by_name.setdefault(row["npc"].replace('"', "'"), {})[text] = base
        else:
            quest_id = int(row["questID"]) if str(row["questID"]).isdigit() else None
            if quest_id:
                title = row["title"].replace('"', "'")
                # A title the pack already resolves through NPC / text (a
                # table) keeps that; a plain number would flatten it.
                if not isinstance(existing_quests.get(row["kind"], {}).get(title), dict):
                    quest_lookup[row["kind"]][title] = quest_id
                if npc_id and row["kind"] == "accept":
                    npc_by_quest[quest_id] = npc_id

    tables = merge_tables(existing, {
        "SoundLengthLookupByFileName": lengths,
        "GossipLookupByNPCID": gossip_by_id,
        "GossipLookupByNPCName": gossip_by_name,
        "NPCNameLookupByNPCID": npc_names,
        "QuestIDLookup": quest_lookup,
        "NPCIDLookupByQuestID": npc_by_quest,
    })

    # Drop MP3s that no table entry refers to any more (a line whose text was
    # re-keyed), so the pack folder holds only what the tables list.
    listed = tables["SoundLengthLookupByFileName"]
    for folder in ("quests", "gossip"):
        for path in glob.glob(os.path.join(sounds, folder, "*.mp3")):
            if os.path.basename(path)[:-4] not in listed:
                os.remove(path)
                print(f"removed stale {folder}/{os.path.basename(path)}")

    write_lua(os.path.join(gen, "sound_length_table.lua"), name, "SoundLengthLookupByFileName", tables["SoundLengthLookupByFileName"])
    write_lua(os.path.join(gen, "gossip_file_lookups.lua"), name, "GossipLookupByNPCID", tables["GossipLookupByNPCID"])
    write_lua(os.path.join(gen, "npc_name_gossip_file_lookups.lua"), name, "GossipLookupByNPCName", tables["GossipLookupByNPCName"])
    write_lua(os.path.join(gen, "npc_name_lookups.lua"), name, "NPCNameLookupByNPCID", tables["NPCNameLookupByNPCID"])
    write_lua(os.path.join(gen, "quest_id_lookups.lua"), name, "QuestIDLookup", tables["QuestIDLookup"])
    write_lua(os.path.join(gen, "questlog_npc_lookups.lua"), name, "NPCIDLookupByQuestID", tables["NPCIDLookupByQuestID"])

    with open(os.path.join(root, "Module.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(f"""{GUARD}

{name} = {name} or {{}}

function {name}:GetSoundPath(fileName, event)
    setfenv(1, VoiceOver)
    if Enums.SoundEvent:IsQuestEvent(event) then
        return format([[generated\\sounds\\quests\\%s.mp3]], fileName)
    elseif Enums.SoundEvent:IsGossipEvent(event) then
        return format([[generated\\sounds\\gossip\\%s.mp3]], fileName)
    end
end

VoiceOver.DataModules:Register("{name}", {name})
""")
    with open(os.path.join(root, f"{name}.toc"), "w", encoding="utf-8", newline="\r\n") as fh:
        fh.write(f"""## Interface: 16001
## Title: MelloUI VoiceOver Data
## Notes: Recorded quest and greeting lines for World of Warcraft: Forever: the vanilla lines of the wow-voiceover project and MelloUI's Forever lines in one pack.
## Version: 1.0
## LoadOnDemand: 1
## OptionalDeps: AI_VoiceOver_Continued, AI_VoiceOver, MelloUI
## X-Part-Of: VoiceOver
## X-Child-Of: VoiceOver
## X-VoiceOver-DataModule-Version: 1
## X-VoiceOver-DataModule-Priority: {args.priority}

Module.lua
generated\\gossip_file_lookups.lua
generated\\npc_name_gossip_file_lookups.lua
generated\\npc_name_lookups.lua
generated\\quest_id_lookups.lua
generated\\questlog_npc_lookups.lua
generated\\sound_length_table.lua
""")
    print(f"built {root}: {used} Forever lines added or refreshed, {len(tables['SoundLengthLookupByFileName'])} lines in the pack")
    print("/reload in game to pick up the new files (tick the pack in the addon list the first time).")


def cmd_status(args, lines):
    have = [row for row in lines if os.path.exists(os.path.join(args.sources, row["file"]))]
    print(f"{len(have)} of {len(lines)} manifest lines have an MP3 in {args.sources}")
    for row in have:
        print(f'  {row["file"]}  {row["npc"]}  {row["kind"]}  {mp3_duration(os.path.join(args.sources, row["file"]))} s')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["assign", "assign-latest", "pending", "build", "status"])
    ap.add_argument("params", nargs="*")
    ap.add_argument("--manifest", default=os.path.join(OUTPUT, "forever_voice_lines.json"))
    ap.add_argument("--sources", default=os.path.join(HERE, "pack_sources"))
    ap.add_argument("--downloads", default=os.path.join(os.path.expanduser("~"), "Downloads", "VoiceOver_GossipQuest"))
    ap.add_argument("--addons", default="F:/World of Warcraft/_classic_beta_/Interface/AddOns")
    ap.add_argument("--name", default="MelloUI_VoiceOverData")
    ap.add_argument("--priority", type=int, default=150)
    ap.add_argument("--store", default=os.path.join(CACHE, "voice_lines.json"))
    args = ap.parse_args()
    # `pending` is about lines still needing audio (the manifest); everything
    # else must see every line ever collected so recorded ones stay packaged.
    lines = load_manifest(args.manifest) if args.command == "pending" else load_all_lines(args.manifest, args.store)

    if args.command == "pending":
        cmd_pending(args, lines)
    elif args.command == "assign":
        if len(args.params) != 2:
            sys.exit("usage: assign <mp3> <target file name>")
        cmd_assign(args, lines, args.params[0], args.params[1])
    elif args.command == "assign-latest":
        if len(args.params) != 1:
            sys.exit("usage: assign-latest <target file name>")
        cmd_assign_latest(args, lines, args.params[0])
    elif args.command == "build":
        cmd_build(args, lines)
    elif args.command == "status":
        cmd_status(args, lines)


if __name__ == "__main__":
    main()
