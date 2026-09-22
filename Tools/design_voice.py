#!/usr/bin/env python3
"""
Design a race voice from a description with ElevenLabs Voice Design, for
accents and characters that cloning the vanilla pack cannot give (trolls with
their Caribbean lilt, gravelly ogres, and so on).

Two steps, because you should listen before committing a voice slot:

  1. preview   generates three candidate voices from the description and
               saves them as MP3s under MelloUI-BuildData/output/voice_designs/<name>-N.mp3
  2. keep      saves candidate N in the account under <name>; if a voice with
               that name already exists it is renamed to <name>-old first

Usage:
  python Tools/design_voice.py preview troll-male --description "..." [--text "..."]
  python Tools/design_voice.py keep troll-male 2

Built in descriptions exist for the common race / gender pairs (see PRESETS);
--description overrides them. The API key is read like the other tools.
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from generate_voice_lines import api_key, fetch_voices, API  # noqa: E402
from paths import OUTPUT

OUT = os.path.join(OUTPUT, "voice_designs")

PRESETS = {
    "troll-male": "A deep, laid-back male troll voice from World of Warcraft with a strong Jamaican accent: relaxed Caribbean rhythm, rolling vowels, gravelly and warm, a touch mischievous. Fantasy tribal warrior, not a modern speaker.",
    "troll-female": "A confident female troll voice from World of Warcraft with a strong Jamaican accent: melodic Caribbean rhythm, husky and warm, playful and sharp-witted. Fantasy tribal hunter.",
    "orc-male": "A deep, gruff male orc voice: rough, booming, guttural, proud warrior, slow and heavy delivery, slight growl.",
    "orc-female": "A strong, husky female orc voice: rough-edged, proud, commanding, with a low warm register.",
    "dwarf-male": "A hearty male dwarf voice with a thick Scottish accent: gruff, jovial, booming, rolling r's, fond of ale and battle.",
    "dwarf-female": "A warm female dwarf voice with a Scottish accent: sturdy, friendly, cheerful, rolling r's.",
    "gnome-male": "A high-pitched, quick, chirpy male gnome voice: enthusiastic inventor, nasal, fast-talking, clever.",
    "gnome-female": "A high, bright, quick female gnome voice: cheerful tinkerer, perky, fast and precise.",
    "goblin-male": "A nasal, scheming male goblin voice with a New York or Brooklyn accent: fast-talking salesman, greedy, wheezy laugh.",
    "goblin-female": "A sharp, nasal female goblin voice with a Brooklyn accent: fast-talking dealmaker, sly, energetic.",
    "tauren-male": "A very deep, slow, calm male tauren voice: resonant, wise, gentle giant, unhurried, earthy.",
    "tauren-female": "A deep, calm, warm female tauren voice: resonant, wise, motherly, unhurried.",
    "undead-male": "A dry, raspy male undead voice: hollow, sardonic, weary, slightly sinister, aristocratic diction.",
    "undead-female": "A raspy, cold female undead voice: hollow, sardonic, weary, faintly elegant.",
    "nightelf-male": "A calm, noble male night elf voice: low, measured, solemn, ancient, faintly mystical.",
    "nightelf-female": "A graceful female night elf voice: calm, clear, solemn, ancient, faintly mystical.",
    "human-male": "A clear, earnest male human voice: medieval fantasy townsman or soldier, neutral accent, warm.",
    "human-female": "A clear, warm female human voice: medieval fantasy villager, neutral accent, kind.",
}
SAMPLE_TEXT = ("Greetings, adventurer. The road ahead is long and the beasts in yonder woods grow bolder by the day. "
               "If you have the courage, bring me proof of their leader's demise and I shall see you rewarded. "
               "Go now, and may the spirits watch over you.")


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def post(key, path, body):
    req = urllib.request.Request(f"{API}{path}", data=json.dumps(body).encode("utf-8"), method="POST", headers={
        "xi-api-key": key, "Content-Type": "application/json", "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.load(resp)


def call_with_fallback(key, attempts):
    last = None
    for path, body in attempts:
        try:
            return post(key, path, body), path
        except urllib.error.HTTPError as exc:
            last = f"{path}: HTTP {exc.code}: {exc.read().decode('utf-8', 'replace')[:300]}"
            log(f"   {last}")
    sys.exit(f"voice design failed: {last}")


def cmd_preview(args, key):
    description = args.description or PRESETS.get(args.name)
    if not description:
        sys.exit(f"no preset for {args.name}; pass --description")
    text = args.text or SAMPLE_TEXT
    log(f"designing {args.name}: {description}")
    body = {"voice_description": description, "text": text, "model_id": args.model}
    if args.guidance is not None:
        body["guidance_scale"] = args.guidance
    result, path = call_with_fallback(key, [
        ("/text-to-voice/design", body),
        ("/text-to-voice/design", {"voice_description": description, "text": text, "model_id": "eleven_multilingual_ttv_v2"}),
        ("/text-to-voice/create-previews", {"voice_description": description, "text": text}),
    ])
    previews = result.get("previews") or []
    os.makedirs(OUT, exist_ok=True)
    state = {"name": args.name, "description": description, "endpoint": path, "candidates": []}
    for i, preview in enumerate(previews, 1):
        dest = os.path.join(OUT, f"{args.name}{('-' + args.tag) if args.tag else ''}-{i}.mp3")
        open(dest, "wb").write(base64.b64decode(preview["audio_base_64"]))
        state["candidates"].append({"index": i, "generated_voice_id": preview["generated_voice_id"], "file": dest})
        log(f"   candidate {i}: {dest} ({preview.get('duration_secs', '?')} s)")
    json.dump(state, open(os.path.join(OUT, f"{args.name}{('-' + args.tag) if args.tag else ''}.json"), "w", encoding="utf-8"), indent=1)
    log(f"{len(previews)} candidates saved; listen, then: design_voice.py keep {args.name} <number>")


def cmd_keep(args, key):
    state_path = os.path.join(OUT, f"{args.name}{('-' + args.tag) if args.tag else ''}.json")
    if not os.path.exists(state_path):
        sys.exit(f"no previews for {args.name}; run preview first")
    state = json.load(open(state_path, encoding="utf-8"))
    candidate = next((c for c in state["candidates"] if c["index"] == args.pick), None)
    if not candidate:
        sys.exit(f"candidate {args.pick} not found; available: {[c['index'] for c in state['candidates']]}")
    existing = fetch_voices(key)
    if args.name in existing:
        # Keep the old one under another name rather than deleting anything.
        old_id = existing[args.name]
        req = urllib.request.Request(f"{API}/voices/{old_id}/edit", data=json.dumps({"name": args.name + "-old"}).encode("utf-8"),
                                     method="POST", headers={"xi-api-key": key, "Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=60)
            log(f"renamed the existing {args.name} to {args.name}-old")
        except urllib.error.HTTPError as exc:
            # Some accounts require multipart for edit; fall back to the multipart form.
            from clone_voices import multipart  # noqa: E402
            body, ctype = multipart({"name": args.name + "-old"}, [])
            req = urllib.request.Request(f"{API}/voices/{old_id}/edit", data=body, method="POST",
                                         headers={"xi-api-key": key, "Content-Type": ctype})
            urllib.request.urlopen(req, timeout=60)
            log(f"renamed the existing {args.name} to {args.name}-old")
    labels = {"source": "MelloUI voice design", "race": args.name.split("-")[0], "gender": args.name.split("-")[1]}
    result, path = call_with_fallback(key, [
        ("/text-to-voice", {"voice_name": args.name, "voice_description": state["description"],
                            "generated_voice_id": candidate["generated_voice_id"], "labels": labels}),
        ("/text-to-voice/create-voice-from-preview", {"voice_name": args.name, "voice_description": state["description"],
                                                      "generated_voice_id": candidate["generated_voice_id"], "labels": labels}),
    ])
    log(f"saved {args.name} as voice {result.get('voice_id', '?')}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["preview", "keep"])
    ap.add_argument("name", help="voice name, e.g. troll-male")
    ap.add_argument("pick", nargs="?", type=int, help="keep: the candidate number")
    ap.add_argument("--description", default=None)
    ap.add_argument("--text", default=None, help="sample text for the previews (100 to 1000 characters)")
    ap.add_argument("--model", default="eleven_ttv_v3", help="voice design model: eleven_ttv_v3 or eleven_multilingual_ttv_v2")
    ap.add_argument("--guidance", type=float, default=None, help="how strictly to follow the description (higher = stricter)")
    ap.add_argument("--tag", default="", help="suffix for the preview file names, e.g. v2")
    args = ap.parse_args()
    key = api_key()
    if args.command == "preview":
        cmd_preview(args, key)
    else:
        if args.pick is None:
            sys.exit("keep needs the candidate number")
        cmd_keep(args, key)


if __name__ == "__main__":
    main()
