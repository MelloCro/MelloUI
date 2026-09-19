#!/usr/bin/env python3
"""
Create the missing <race>-<gender> voices in your ElevenLabs account by cloning
the vanilla sound pack's own lines.

The vanilla pack uses one voice per race and gender. For every combination the
generator can use (see COMBOS) that your account does not have yet, this script
picks a few clean quest lines spoken by NPCs of that race and gender (found
through Media/NPCVoiceData.lua and the pack's quest-to-NPC table), uploads them
as an instant voice clone named "<race>-<gender>", and the generator then uses
that voice directly instead of a fallback.

Usage:
  python Tools/clone_voices.py --dry-run          show what would be created and from which files
  python Tools/clone_voices.py                    create every missing voice
  python Tools/clone_voices.py --combos troll-male orc-female
  python Tools/clone_voices.py --samples 8 --seconds 120

The API key is read the same way as generate_voice_lines.py. Instant voice
cloning needs an ElevenLabs plan that allows it, and each voice takes one of
the account's custom voice slots.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from generate_voice_lines import api_key, fetch_voices, API, KEY_FILE  # noqa: E402
from build_voice_pack import mp3_duration  # noqa: E402

DEFAULT_PACK = "F:/World of Warcraft/_classic_beta_/Interface/AddOns/AI_VoiceOverData_Vanilla"
NPC_DATA = os.path.join(HERE, "..", "Media", "NPCVoiceData.lua")

# Race / gender voices worth having; others have no talking NPCs in the pack.
COMBOS = [
    "human-male", "human-female", "dwarf-male", "dwarf-female", "gnome-male", "gnome-female",
    "nightelf-male", "nightelf-female", "orc-male", "orc-female", "troll-male", "troll-female",
    "tauren-male", "tauren-female", "undead-male", "undead-female", "goblin-male", "goblin-female",
]
GENDER_WORD = {"m": "male", "f": "female"}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def npc_race_gender():
    text = open(NPC_DATA, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'\["(\w+)_(\w)"\] = ((?:"[^"]*"\s*(?:\.\.\s*)?)+)', text):
        race, gender = m.group(1), m.group(2)
        for npc_id in " ".join(re.findall(r'"([^"]*)"', m.group(3))).split():
            out[int(npc_id)] = (race, GENDER_WORD.get(gender))
    return out


def sample_files(pack, combo, npcs, max_files, max_seconds):
    """Quest lines spoken by NPCs of this race and gender, longest first."""
    race, gender = combo.split("-")
    lookup = open(os.path.join(pack, "generated", "questlog_npc_lookups.lua"), encoding="utf-8").read()
    quest_to_npc = {int(a): int(b) for a, b in re.findall(r"\[(\d+)\] = (\d+),", lookup)}
    folder = os.path.join(pack, "generated", "sounds", "quests")
    candidates = []
    for quest_id, npc_id in quest_to_npc.items():
        if npcs.get(npc_id) != (race, gender):
            continue
        for kind in ("accept", "complete"):
            path = os.path.join(folder, f"{quest_id}-{kind}.mp3")
            if os.path.exists(path):
                candidates.append(path)
    # Medium length lines clone best: skip very short and very long ones.
    scored = []
    for path in candidates:
        seconds = mp3_duration(path)
        if 5 <= seconds <= 25:
            scored.append((seconds, path))
    scored.sort(reverse=True)
    chosen, total = [], 0.0
    for seconds, path in scored:
        if len(chosen) >= max_files or total + seconds > max_seconds:
            continue
        chosen.append((path, seconds))
        total += seconds
    return chosen, len(candidates)


def multipart(fields, files):
    boundary = "----MelloUI" + uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode("utf-8")
    for path in files:
        data = open(path, "rb").read()
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; filename=\"{os.path.basename(path)}\"\r\n"
                 f"Content-Type: audio/mpeg\r\n\r\n").encode("utf-8") + data + b"\r\n"
    body += f"--{boundary}--\r\n".encode("utf-8")
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def create_voice(key, name, files, description):
    body, content_type = multipart({
        "name": name,
        "description": description,
        "labels": json.dumps({"source": "MelloUI clone of the VoiceOver vanilla pack", "race": name.split("-")[0], "gender": name.split("-")[1]}),
        "remove_background_noise": "false",
    }, files)
    req = urllib.request.Request(f"{API}/voices/add", data=body, method="POST", headers={
        "xi-api-key": key, "Content-Type": content_type, "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.load(resp)


def subscription(key):
    req = urllib.request.Request(f"{API}/user/subscription", headers={"xi-api-key": key, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.load(resp)
    except Exception:  # noqa: BLE001
        return {}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", default=DEFAULT_PACK)
    ap.add_argument("--combos", nargs="*", default=None, help="only these, e.g. troll-male orc-female")
    ap.add_argument("--samples", type=int, default=8, help="files per voice")
    ap.add_argument("--seconds", type=int, default=120, help="total audio per voice")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    key = api_key()
    existing = fetch_voices(key)
    sub = subscription(key)
    limit = sub.get("voice_limit") or sub.get("voice_slots_limit")
    custom = len([n for n in existing if "-" in n and n.split("-")[-1] in ("male", "female")])
    if sub:
        log(f"plan: {sub.get('tier', '?')}, cloning allowed: {sub.get('can_use_instant_voice_cloning', '?')}, "
            f"voice slots: {sub.get('voice_count', '?')}/{limit if limit is not None else '?'} used")
    npcs = npc_race_gender()

    todo = []
    for combo in (args.combos or COMBOS):
        if combo.lower() in existing:
            continue
        files, available = sample_files(args.pack, combo, npcs, args.samples, args.seconds)
        if len(files) < 3:
            log(f"{combo}: only {available} pack lines for this race and gender, not enough to clone")
            continue
        todo.append((combo, files))

    if not todo:
        log("nothing to create: every voice already exists")
        return
    for combo, files in todo:
        total = sum(s for _, s in files)
        log(f"{combo}: {len(files)} samples, {total:.0f} s")
        for path, seconds in files:
            log(f"    {os.path.basename(path)}  {seconds:.1f} s")
    if args.dry_run:
        log(f"dry run: {len(todo)} voices would be created")
        return
    if limit is not None and sub.get("voice_count") is not None and sub["voice_count"] + len(todo) > limit:
        log(f"warning: {len(todo)} new voices would exceed the plan's {limit} slots; some may fail")

    created = 0
    for combo, files in todo:
        try:
            result = create_voice(key, combo, [p for p, _ in files],
                                  f"{combo.replace('-', ' ')} NPC voice cloned from the VoiceOver vanilla pack")
            log(f"created {combo}: voice {result.get('voice_id')}")
            created += 1
        except urllib.error.HTTPError as exc:
            log(f"{combo}: HTTP {exc.code}: {exc.read().decode('utf-8', 'replace')[:300]}")
        except Exception as exc:  # noqa: BLE001
            log(f"{combo}: {exc}")
    log(f"created {created} of {len(todo)} voices")


if __name__ == "__main__":
    main()
