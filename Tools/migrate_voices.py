#!/usr/bin/env python3
"""
Copy the race voices from one ElevenLabs workspace to another.

  export   with the source workspace's key: downloads every custom voice's
           samples and settings to MelloUI-BuildData/output/voice_export/<name>/, and notes
           library voices (which are re-added from the library, not cloned).
  import   with the destination workspace's key (--key-file): recreates each
           exported voice under the same name, restores its settings, and adds
           the library voices.

Usage:
  python Tools/migrate_voices.py export
  python Tools/migrate_voices.py import --key-file "C:/Users/me/.elevenlabs.daniel.key"

The destination key needs voices read and write permissions. Voices that
already exist there (same name) are skipped.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from generate_voice_lines import api_key, API  # noqa: E402
from clone_voices import multipart  # noqa: E402
from paths import OUTPUT

OUT = os.path.join(OUTPUT, "voice_export")


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def call(key, path, method="GET", body=None, content_type="application/json", raw=False):
    data = body if isinstance(body, (bytes, bytearray)) else (json.dumps(body).encode("utf-8") if body is not None else None)
    req = urllib.request.Request(f"{API}{path}", data=data, method=method,
                                 headers={"xi-api-key": key, "Content-Type": content_type, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        return resp.read() if raw else json.load(resp)


def read_key(path):
    key = open(path, encoding="utf-8-sig").read().strip().strip('"').strip()
    if not key.startswith("sk_"):
        sys.exit(f"{path} does not hold an ElevenLabs key (they start with sk_)")
    return key


def cmd_export(key):
    voices = call(key, "/voices")["voices"]
    custom = [v for v in voices if v.get("category") != "premade"]
    os.makedirs(OUT, exist_ok=True)
    manifest = []
    for v in custom:
        name = v["name"].strip()
        folder = os.path.join(OUT, "".join(c if c.isalnum() or c in "-_" else "_" for c in name))
        os.makedirs(folder, exist_ok=True)
        entry = {"name": name, "voice_id": v["voice_id"], "category": v.get("category"), "labels": v.get("labels") or {},
                 "description": v.get("description") or "", "settings": v.get("settings"), "samples": [], "sharing": None}
        sharing = v.get("sharing") or {}
        if v.get("category") in ("professional", "famous", "high_quality") or sharing.get("public_owner_id") or sharing.get("original_voice_id"):
            # A voice added from the library: record where it came from.
            entry["sharing"] = {"public_owner_id": sharing.get("public_owner_id"), "original_voice_id": sharing.get("original_voice_id"),
                                "status": sharing.get("status")}
        if entry["settings"] is None:
            try:
                entry["settings"] = call(key, f"/voices/{v['voice_id']}/settings")
            except Exception:  # noqa: BLE001
                pass
        for sample in v.get("samples") or []:
            dest = os.path.join(folder, sample.get("file_name") or (sample["sample_id"] + ".mp3"))
            try:
                audio = call(key, f"/voices/{v['voice_id']}/samples/{sample['sample_id']}/audio", raw=True)
                open(dest, "wb").write(audio)
                entry["samples"].append(dest)
            except urllib.error.HTTPError as exc:
                log(f"   {name}: sample {sample.get('file_name')} not downloadable (HTTP {exc.code})")
        kind = "library voice" if entry["sharing"] else f"{len(entry['samples'])} samples"
        log(f"{name}: {kind}")
        manifest.append(entry)
    json.dump(manifest, open(os.path.join(OUT, "voices.json"), "w", encoding="utf-8"), indent=1)
    log(f"exported {len(manifest)} voices to {OUT}")


def cmd_import(key, only=None):
    manifest = json.load(open(os.path.join(OUT, "voices.json"), encoding="utf-8"))
    existing = {v["name"].strip().lower(): v["voice_id"] for v in call(key, "/voices")["voices"]}
    created = 0
    for entry in manifest:
        name = entry["name"]
        if only and name.lower() not in [o.lower() for o in only]:
            continue
        if name.lower() in existing:
            log(f"{name}: already present, skipped")
            continue
        try:
            if entry.get("sharing") and entry["sharing"].get("public_owner_id"):
                s = entry["sharing"]
                r = call(key, f"/voices/add/{s['public_owner_id']}/{s['original_voice_id']}", "POST", {"new_name": name})
                voice_id = r.get("voice_id")
                log(f"{name}: added from the library")
            elif entry["samples"]:
                files = [p for p in entry["samples"] if os.path.exists(p)]
                body, ctype = multipart({"name": name, "description": entry.get("description") or "",
                                         "labels": json.dumps(entry.get("labels") or {}), "remove_background_noise": "false"}, files)
                r = call(key, "/voices/add", "POST", body, ctype)
                voice_id = r.get("voice_id")
                log(f"{name}: cloned from {len(files)} samples")
            else:
                log(f"{name}: no samples and not a library voice, cannot recreate")
                continue
            settings = entry.get("settings")
            if voice_id and settings:
                allowed = {k: settings[k] for k in ("stability", "similarity_boost", "style", "use_speaker_boost", "speed") if k in settings}
                call(key, f"/voices/{voice_id}/settings/edit", "POST", allowed)
            created += 1
        except urllib.error.HTTPError as exc:
            log(f"{name}: HTTP {exc.code}: {exc.read().decode('utf-8', 'replace')[:250]}")
    log(f"recreated {created} voices")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["export", "import"])
    ap.add_argument("--key-file", default=None, help="key of the destination workspace (import); default is the usual key file")
    ap.add_argument("--only", nargs="*", default=None, help="import only these voice names")
    args = ap.parse_args()
    key = read_key(args.key_file) if args.key_file else api_key()
    if args.command == "export":
        cmd_export(key)
    else:
        cmd_import(key, args.only)


if __name__ == "__main__":
    main()
