#!/usr/bin/env python3
"""
Generate the pending Forever voice lines with ElevenLabs and package them.

One command does the whole loop:
  1. export_voice_lines.py   collect the latest session, list lines needing audio
  2. ElevenLabs              generate each line with the voice named <race>-<gender>
                             in your account (the saved settings of that voice are used)
  3. build_voice_pack.py     file the MP3s and add them to MelloUI_VoiceOverData

API key: put it in  %USERPROFILE%\\.elevenlabs.key  (one line, nothing else) or set
the ELEVENLABS_API_KEY environment variable. It is never stored in the project.

Voices: name your ElevenLabs voices "<race>-<gender>", e.g. human-male, goblin-male,
undead-female. Case does not matter. Races without a voice fall back along
VOICE_FALLBACKS below (night elves to elf, ogres to orc, anything else to human).

Usage:
  python Tools/generate_voice_lines.py --player Warr            generate everything pending
  python Tools/generate_voice_lines.py --player Warr --dry-run  show what would be generated and the cost
  python Tools/generate_voice_lines.py --player Warr --only 147-progress.mp3
  python Tools/generate_voice_lines.py --list-voices            show the voices found in the account
  python Tools/generate_voice_lines.py --no-export --manifest Tools/output/vanilla_missing_lines.json
                                                                the vanilla lines the pack never had
                                                                (Tools/export_vanilla_lines.py lists them)

Options:
  --model         eleven_multilingual_v2 (default)
  --stability / --similarity / --style   override the voice's saved settings (0..1)
  --no-export     skip step 1 (use the existing manifest)
  --no-build      skip step 3
  --skip-progress leave quest progress lines out (the vanilla pack did too)

Only the Python standard library is needed.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://api.elevenlabs.io/v1"
KEY_FILE = os.path.join(os.path.expanduser("~"), ".elevenlabs.key")

# race code from NPCVoiceData -> voice names to try, in order
VOICE_FALLBACKS = {
    "human": ["human"],
    "dwarf": ["dwarf", "human"],
    "gnome": ["gnome", "dwarf", "human"],
    "nightelf": ["nightelf", "elf", "human"],
    "highelf": ["highelf", "elf", "nightelf", "human"],
    "orc": ["orc", "human"],
    "troll": ["troll", "orc", "human"],
    "tauren": ["tauren", "orc", "human"],
    "undead": ["undead", "scourge", "human"],
    "goblin": ["goblin", "gnome", "human"],
    "ogre": ["ogre", "orc", "tauren", "human"],
    "giant": ["giant", "ogre", "tauren", "orc", "human"],
    "kobold": ["kobold", "goblin", "gnome", "human"],
    "murloc": ["murloc", "goblin", "human"],
    "gnoll": ["gnoll", "orc", "human"],
    "trogg": ["trogg", "orc", "human"],
    "furbolg": ["furbolg", "tauren", "orc", "human"],
    "naga": ["naga", "nightelf", "elf", "human"],
    "satyr": ["satyr", "nightelf", "elf", "human"],
    "harpy": ["harpy", "nightelf", "elf", "human"],
    "centaur": ["centaur", "tauren", "orc", "human"],
    "quilboar": ["quilboar", "orc", "human"],
    "dragon": ["dragon", "tauren", "orc", "human"],
    "demon": ["demon", "undead", "orc", "human"],
    "imp": ["imp", "goblin", "gnome", "human"],
    "succubus": ["succubus", "undead", "human"],
    "elemental": ["elemental", "tauren", "human"],
    "spirit": ["spirit", "undead", "nightelf", "human"],
    "treant": ["treant", "tauren", "human"],
    "keeper": ["keeper", "nightelf", "tauren", "human"],
    "dryad": ["dryad", "nightelf", "elf", "human"],
    "insect": ["insect", "undead", "human"],
    "mechanical": ["mechanical", "gnome", "human"],
    "beast": ["beast", "orc", "human"],
    "other": ["narrator", "human"],
    "": ["narrator", "human"],
}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Troll patois: the accent lives in the voice, but respelling a few words the
# way the game's trolls say them ("de", "dem", "mon") makes it land. Applied
# to the spoken text only; the lookup tables keep the original wording.
# ---------------------------------------------------------------------------

PATOIS_RACES = {"troll"}
PATOIS_WORDS = {
    "the": "de", "this": "dis", "that": "dat", "these": "dese", "those": "dose",
    "them": "dem", "they": "dey", "their": "dere", "theirs": "deres", "there": "dere",
    "then": "den", "than": "dan", "with": "wit", "without": "witout",
    "thing": "ting", "things": "tings", "think": "tink", "thinking": "tinkin'",
    "nothing": "nuttin'", "something": "somethin'", "anything": "anyting", "everything": "everyting",
    "you": "ya", "your": "ya", "yours": "yours", "man": "mon", "brother": "brudda", "little": "likkle",
    "my": "me", "mother": "mudda", "father": "fadda", "through": "tru", "three": "tree",
}
PATOIS_KEEP_ING = {"king", "ring", "sing", "wing", "thing", "bring", "spring", "string", "sting", "swing", "fling", "cling", "ding", "ping", "evening", "morning", "nothing", "something", "anything", "everything", "during"}


def patois(text):
    import re as _re

    def word(m):
        w = m.group(0)
        lower = w.lower()
        out = PATOIS_WORDS.get(lower)
        if out is None and lower.endswith("ing") and len(lower) > 4 and lower not in PATOIS_KEEP_ING:
            out = lower[:-1] + "'"
        if out is None:
            return w
        if w.isupper():
            return out.upper()
        if w[0].isupper():
            return out[0].upper() + out[1:]
        return out

    return _re.sub(r"[A-Za-z']+", word, text)


def api_key():
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key and os.path.exists(KEY_FILE):
        # utf-8-sig drops the byte-order mark PowerShell likes to add.
        key = open(KEY_FILE, encoding="utf-8-sig").read().strip().strip('"').strip()
    if not key:
        sys.exit(f"No ElevenLabs API key. Put it in {KEY_FILE} or set ELEVENLABS_API_KEY.")
    if any(ord(c) > 126 or ord(c) < 33 for c in key):
        sys.exit(f"The key in {KEY_FILE} contains unexpected characters; save it as plain text with nothing else in the file.")
    return key


def request(method, path, key, body=None, query=""):
    url = f"{API}{path}{query}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "xi-api-key": key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg, application/json",
    })
    return urllib.request.urlopen(req, timeout=120)


def fetch_voices(key):
    try:
        with request("GET", "/voices", key) as resp:
            voices = json.load(resp)["voices"]
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:300]
        sys.exit(f"ElevenLabs refused the voice list (HTTP {exc.code}): {detail}\n"
                 f"Check the key in {KEY_FILE} and that it has the voices_read permission.")
    by_name = {}
    for voice in voices:
        name = voice["name"].strip().lower()
        by_name[name] = voice["voice_id"]
    return by_name


# Object text (shrines, bonfires, corpses) is narration: a storyteller voice,
# either one named narrator-<gender> in the account or a stock ElevenLabs one.
NARRATOR_VOICES = ["narrator-male", "narrator", "george - warm, captivating storyteller", "bill - wise, mature, balanced", "daniel - steady broadcaster"]


def narrator_voice(by_name):
    for name in NARRATOR_VOICES:
        if name in by_name:
            return name, by_name[name]
    return None, None


def pick_voice(by_name, race, gender):
    if not gender:
        # No gender means no speaker: an object or an unknown; narrate it.
        return narrator_voice(by_name)
    gender = "female" if gender == "f" else "male"
    for candidate in VOICE_FALLBACKS.get(race or "", VOICE_FALLBACKS[""]):
        name = f"{candidate}-{gender}"
        if name in by_name:
            return name, by_name[name]
    for name in (f"human-{gender}", f"narrator-{gender}"):
        if name in by_name:
            return name, by_name[name]
    return None, None


def generate(key, voice_id, text, model, settings, dest):
    body = {"text": text, "model_id": model}
    if settings:
        body["voice_settings"] = settings
    for attempt in range(1, 4):
        try:
            with request("POST", f"/text-to-speech/{voice_id}", key, body, "?output_format=mp3_44100_128") as resp:
                audio = resp.read()
            if not audio or audio[:3] not in (b"ID3", b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"):
                raise RuntimeError("response was not MP3 audio")
            with open(dest, "wb") as fh:
                fh.write(audio)
            return True
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:300]
            if exc.code == 429 and attempt < 3:
                log(f"   rate limited, waiting {10 * attempt} s")
                time.sleep(10 * attempt)
                continue
            log(f"   HTTP {exc.code}: {detail}")
            if "quota" in detail.lower() or exc.code == 402:
                raise SystemExit("ElevenLabs credits are used up; stopping here. The remaining lines stay pending for the next run.")
            return False
        except Exception as exc:  # noqa: BLE001
            log(f"   {exc}")
            if attempt < 3:
                time.sleep(3)
                continue
            return False
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--player", default=None, help="your character name (passed to the export)")
    ap.add_argument("--manifest", default=os.path.join(HERE, "output", "forever_voice_lines.json"))
    ap.add_argument("--sources", default=os.path.join(HERE, "pack_sources"))
    ap.add_argument("--model", default="eleven_multilingual_v2")
    ap.add_argument("--stability", type=float, default=None)
    ap.add_argument("--similarity", type=float, default=None)
    ap.add_argument("--style", type=float, default=None)
    ap.add_argument("--only", action="append", default=[], help="file name(s) to generate, others are skipped")
    ap.add_argument("--skip-progress", action="store_true")
    ap.add_argument("--no-patois", action="store_true", help="do not respell troll lines in patois")
    ap.add_argument("--allow-unknown", action="store_true",
                    help="also generate lines whose NPC has no known gender (they get the human male voice)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--list-voices", action="store_true")
    ap.add_argument("--no-export", action="store_true")
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    key = api_key()
    by_name = fetch_voices(key)
    if args.list_voices:
        for name in sorted(by_name):
            print(f"{name:24s} {by_name[name]}")
        return

    python = sys.executable
    if not args.no_export:
        cmd = [python, os.path.join(HERE, "export_voice_lines.py")]
        if args.player:
            cmd += ["--player", args.player]
        subprocess.run(cmd, check=True)

    lines = json.load(open(args.manifest, encoding="utf-8"))["lines"]
    os.makedirs(args.sources, exist_ok=True)
    todo = []
    unknown = []
    for row in lines:
        if os.path.exists(os.path.join(args.sources, row["file"])):
            continue
        if args.only and row["file"] not in args.only:
            continue
        if args.skip_progress and row["kind"] == "progress":
            continue
        if not any(c.isalpha() for c in row["text"]):
            continue  # "..." and the like: nothing to say
        if not row.get("gender") and not args.allow_unknown and not narrator_voice(by_name)[0]:
            unknown.append(row)
            continue
        todo.append(row)
    if unknown:
        names = sorted({row["npc"] or "?" for row in unknown})
        log(f"{len(unknown)} lines held back: NPC gender unknown ({', '.join(names[:12])}{' ...' if len(names) > 12 else ''}). "
            "Add them to Media/NPCVoiceOverrides.lua, meet them in game, or pass --allow-unknown.")
    # Starting zones first, so limited credits go to what is met earliest.
    todo.sort(key=lambda row: (row.get("level") or 0, str(row.get("questID") or ""), row["kind"] != "accept"))
    if not todo:
        log("nothing to generate")
    else:
        settings = {}
        if args.stability is not None:
            settings["stability"] = args.stability
        if args.similarity is not None:
            settings["similarity_boost"] = args.similarity
        if args.style is not None:
            settings["style"] = args.style
        chars = sum(len(row["text"]) for row in todo)
        log(f"{len(todo)} lines to generate, {chars} characters")
        done = failed = 0
        for row in todo:
            voice_name, voice_id = pick_voice(by_name, row.get("race", ""), row.get("gender", ""))
            label = row["title"] and f'{row["kind"]} of "{row["title"]}"' or row["kind"]
            if not voice_id:
                log(f"skip {row['file']}: no voice for {row.get('race') or 'unknown'} {row.get('gender')} ({row['npc']})")
                failed += 1
                continue
            text = row["text"]
            if row.get("race") in PATOIS_RACES and not args.no_patois:
                text = patois(text)
            log(f"{row['file']}  {row['npc']}  {label}  ->  {voice_name}")
            if args.dry_run:
                continue
            dest = os.path.join(args.sources, row["file"])
            if generate(key, voice_id, text, args.model, settings, dest):
                done += 1
            else:
                failed += 1
        log(f"generated {done}, failed {failed}" if not args.dry_run else "dry run, nothing generated")

    if not args.no_build and not args.dry_run:
        subprocess.run([python, os.path.join(HERE, "build_voice_pack.py"), "build",
                        "--manifest", args.manifest, "--sources", args.sources], check=True)


if __name__ == "__main__":
    main()
