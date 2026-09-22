#!/usr/bin/env python3
"""
Merge the vanilla VoiceOver data pack and MelloUI's Forever pack into one
addon, MelloUI_VoiceOverData, for distribution as a single download.

  AI_VoiceOverData_Vanilla   every vanilla quest and greeting (wow-voiceover project, Unlicense)
  AI_VoiceOverData_Forever   Forever's own quests and greetings (Tools/build_voice_pack.py)

The Forever pack wins where both have a line. The result has the same layout
the packs use (generated/*.lua lookup tables and generated/sounds/...), the
TOC fields the Voice Over module discovers packs by, and priority 150 so it
sits between the two originals if someone keeps those installed as well.

Usage:
  python Tools/merge_voice_packs.py                      -> MelloUI-BuildData/output/MelloUI_VoiceOverData
  python Tools/merge_voice_packs.py --zip                 also writes MelloUI_VoiceOverData.zip next to it
  python Tools/merge_voice_packs.py --install             also copies the pack into the game's AddOns
"""

import argparse
import os
import shutil
import sys
import time
import zipfile

import lupa
from paths import OUTPUT

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = "F:/World of Warcraft/_classic_beta_/Interface/AddOns"
OUT = os.path.join(OUTPUT, "MelloUI_VoiceOverData")
NAME = "MelloUI_VoiceOverData"
TABLES = {
    "gossip_file_lookups": "GossipLookupByNPCID",
    "npc_name_gossip_file_lookups": "GossipLookupByNPCName",
    "npc_name_lookups": "NPCNameLookupByNPCID",
    "quest_id_lookups": "QuestIDLookup",
    "questlog_npc_lookups": "NPCIDLookupByQuestID",
    "sound_length_table": "SoundLengthLookupByFileName",
}


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, file=sys.stderr, flush=True)


def load_tables(pack_dir, global_name):
    """The pack's lookup tables as Python dicts, keys kept as Lua gave them."""
    runtime = lupa.LuaRuntime()
    runtime.execute("VoiceOver = { DataModules = { Register = function() end } }")
    runtime.execute(f"{global_name} = {{}}")
    for base in TABLES:
        path = os.path.join(pack_dir, "generated", f"{base}.lua")
        if os.path.exists(path):
            runtime.execute(open(path, encoding="utf-8", errors="replace").read())
    root = runtime.globals()[global_name]

    def convert(v):
        if lupa.lua_type(v) == "table":
            out = {}
            for k, x in v.items():
                if isinstance(k, float) and k.is_integer():
                    k = int(k)
                out[k] = convert(x)
            return out
        return v

    return {field: convert(root[field]) for _, field in TABLES.items() if root[field] is not None}


def merge(base, over):
    """Deep merge: nested dicts merge, scalars from `over` win."""
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = merge(out[k], v)
        else:
            out[k] = v
    return out


def lua_value(v, indent):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, dict):
        pad = "\t" * (indent + 1)
        parts = []
        for k in sorted(v, key=lambda x: (isinstance(x, str), x)):
            key = f"[{k}]" if isinstance(k, int) else "[" + lua_value(k, 0) + "]"
            parts.append(f"{pad}{key} = {lua_value(v[k], indent + 1)},\n")
        return "{\n" + "".join(parts) + "\t" * indent + "}"
    raise TypeError(type(v))


def write_pack(tables, out_dir, sources):
    os.makedirs(os.path.join(out_dir, "generated"), exist_ok=True)
    with open(os.path.join(out_dir, f"{NAME}.toc"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("## Interface: 16001\n")
        fh.write("## Title: MelloUI VoiceOver Data\n")
        fh.write("## Notes: Recorded quest and greeting lines for World of Warcraft: Forever: the vanilla lines of the wow-voiceover project and MelloUI's Forever lines in one pack.\n")
        fh.write("## Version: 1.0\n")
        fh.write("## LoadOnDemand: 1\n")
        fh.write("## OptionalDeps: MelloUI, AI_VoiceOver_Continued, AI_VoiceOver\n")
        fh.write("## X-Part-Of: VoiceOver\n")
        fh.write("## X-Child-Of: VoiceOver\n")
        fh.write("## X-VoiceOver-DataModule-Version: 1\n")
        fh.write("## X-VoiceOver-DataModule-Priority: 150\n\n")
        fh.write("Module.lua\n")
        for base in TABLES:
            fh.write(f"generated\\{base}.lua\n")
    with open(os.path.join(out_dir, "Module.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("if not VoiceOver or not VoiceOver.DataModules then return end\n\n")
        fh.write(f"{NAME} = {NAME} or {{}}\n\n")
        fh.write(f"function {NAME}:GetSoundPath(fileName, event)\n")
        fh.write("    setfenv(1, VoiceOver)\n")
        fh.write("    if Enums.SoundEvent:IsQuestEvent(event) then\n")
        fh.write("        return format([[generated\\sounds\\quests\\%s.mp3]], fileName)\n")
        fh.write("    elseif Enums.SoundEvent:IsGossipEvent(event) then\n")
        fh.write("        return format([[generated\\sounds\\gossip\\%s.mp3]], fileName)\n")
        fh.write("    end\n")
        fh.write("end\n\n")
        fh.write(f'VoiceOver.DataModules:Register("{NAME}", {NAME})\n')
    for base, field in TABLES.items():
        with open(os.path.join(out_dir, "generated", f"{base}.lua"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("if not VoiceOver or not VoiceOver.DataModules then return end\n")
            fh.write(f"{NAME}.{field} = {lua_value(tables.get(field, {}), 0)}\n")
    with open(os.path.join(out_dir, "SOURCES.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("This pack merges:\n")
        for s in sources:
            fh.write(f"  {s}\n")
        fh.write("\nVanilla lines: the wow-voiceover project (https://github.com/mrthinger/wow-voiceover), released under the Unlicense.\n")
        fh.write("Forever lines: generated for MelloUI with ElevenLabs voices (Tools/generate_voice_lines.py).\n")


def copy_sounds(pack_dir, out_dir, seen):
    """Copy generated/sounds/** ; hard links when on the same drive. Later packs overwrite."""
    src_root = os.path.join(pack_dir, "generated", "sounds")
    count = 0
    for root, _, files in os.walk(src_root):
        rel = os.path.relpath(root, src_root)
        dst_dir = os.path.join(out_dir, "generated", "sounds", rel)
        os.makedirs(dst_dir, exist_ok=True)
        for f in files:
            src, dst = os.path.join(root, f), os.path.join(dst_dir, f)
            if os.path.exists(dst):
                os.remove(dst)
            try:
                os.link(src, dst)
            except OSError:
                shutil.copy2(src, dst)
            seen.add(os.path.join(rel, f))
            count += 1
    return count


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vanilla", default=os.path.join(ADDONS, "AI_VoiceOverData_Vanilla"),
                    help="the original vanilla pack; skipped when it is gone (its lines live in the merged pack then)")
    ap.add_argument("--forever", default=os.path.join(ADDONS, "AI_VoiceOverData_Forever"),
                    help="the Forever-only pack; when it is gone the installed merged pack is packaged instead")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--zip", action="store_true", help="also write <out>.zip (stored, MP3s do not compress)")
    ap.add_argument("--install", action="store_true", help="also copy the pack into the game's AddOns folder")
    args = ap.parse_args()

    packs = [(args.vanilla, "AI_VoiceOverData_Vanilla"), (args.forever, "AI_VoiceOverData_Forever")]
    installed = os.path.join(ADDONS, NAME)
    if not os.path.isdir(args.forever) and os.path.isdir(installed) and os.path.abspath(args.out) != os.path.abspath(installed):
        # Tools/build_voice_pack.py now builds straight into the merged pack.
        packs.append((installed, NAME))
    tables = {}
    sources = []
    for pack_dir, global_name in packs:
        if not os.path.isdir(pack_dir):
            log(f"missing pack: {pack_dir}")
            continue
        log(f"reading {global_name}")
        tables = merge(tables, load_tables(pack_dir, global_name))
        sources.append(pack_dir)
    if not sources:
        sys.exit("no packs found")
    log(f"{len(tables.get('SoundLengthLookupByFileName', {}))} lines in the merged table")
    if os.path.isdir(args.out):
        shutil.rmtree(args.out)
    write_pack(tables, args.out, sources)
    seen = set()
    for pack_dir, _ in packs:
        if os.path.isdir(pack_dir):
            n = copy_sounds(pack_dir, args.out, seen)
            log(f"  {n} sound files from {os.path.basename(pack_dir)}")
    log(f"pack written: {args.out} ({len(seen)} sound files)")
    if args.install:
        dst = os.path.join(ADDONS, NAME)
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        shutil.copytree(args.out, dst)
        log(f"installed to {dst}")
    if args.zip:
        zip_path = args.out.rstrip("/\\") + ".zip"
        log(f"zipping to {zip_path} (stored)")
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_STORED) as zf:
            for root, _, files in os.walk(args.out):
                for f in files:
                    full = os.path.join(root, f)
                    zf.write(full, os.path.join(NAME, os.path.relpath(full, args.out)))
        log(f"zip done: {os.path.getsize(zip_path) / 1e9:.2f} GB")


if __name__ == "__main__":
    main()
