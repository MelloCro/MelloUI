#!/usr/bin/env python3
"""The voice sample addon (user, 2026-10-03): every voice of the voicegen library speaks one quest line at three
speeds -- 0.9x, 1.0x and 1.15x -- in a small addon of its own, MelloUI_VoiceSamples, shared on Discord as a zip.
Players play the three takes of each voice, tick the speed that sounds right, and paste the addon's feedback code
into #voiceover-feedback; `tally` reads those codes back. The speeds the user settles on go into
Tools/voice_v2/voice_speeds.json, which generate.py applies to every job of that voice when the pack is remade.

    python Tools/voice_samples/samples.py pick [--refresh]   choose each voice's line (writes picks.json)
    python Tools/voice_samples/samples.py manifest           the generation list (samples_manifest.json); the pack's
                                                             own 1.0x clips are copied, not made again
    python Tools/voice_v2/generate.py <OUT>/samples_manifest.json --clips <OUT>/clips --batches <OUT>/batches
           --max-total-minutes 200 --max-batch-minutes 30 --name melloui-voice-samples
    python Tools/voice_samples/samples.py addon              the addon folder and MelloUI_VoiceSamples.zip
           ... --complete-only                               only the voices with all three speeds made (a part
                                                             build while the service is down; a later full build
                                                             is an update: players keep their ratings)
    python Tools/voice_samples/samples.py tally FILE...      the feedback codes in the files (a Discord export or
                                                             pasted messages): per voice, how many picked each speed

The line of a voice (the user: "keep the voices speaking only their own voicelines or quest dialogues"; the ones
with none: "give them a random quest text from the game"), first that applies:
  pack     its own quest dialogue in the shipped pack (accept, complete or progress; 22-42 words, ~9-17 s), else
           its own other pack line (a greeting, gossip) -- the pack's clip is the 1.0x take
  npc      a quest dialogue of an NPC the live voice map gives this voice (the pack used an older map)
  name     a quest dialogue of the NPC the voice is named after (Tirion Fordring, Ahab Wheathoof ...)
  random   a quest's accept text from the game, drawn at random per voice (the same draw every run)
Only clean lines: one speaker, no flags but a stand-in's, no gendered variant. SKIP: voices left out
(pandacub, the user's call).

Output: MelloUI-BuildData/output/voice_samples (library.json and voice_map.json are cached from the service; the
token is read by voice_v2_voices.py and never shown). Standard library only.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import random
import re
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.join(TOOLS, "voice_v2"))
from paths import OUTPUT  # noqa: E402

OUT = os.path.join(OUTPUT, "voice_samples")
V2 = os.path.join(OUTPUT, "voice_v2")
ADDON = "MelloUI_VoiceSamples"
ADDON_SRC = os.path.join(HERE, "addon")
SPEEDS = (0.9, 1.0, 1.15)
SUFFIX = {0.9: "_090", 1.0: "_100", 1.15: "_115"}
WORDS = (22, 42)
IDEAL = 32
DIALOGUE = {"accept": 0, "complete": 1, "progress": 2}
# voices left out of the samples (each still takes its turn in the random deal, so the others keep their lines)
SKIP = {"pandacub": "the user, 2026-10-03: skip it (its takes of a quest line came out minutes long or not at all)"}
MANIFEST_FORMAT = "melloui-voice-lines/2"
# the feedback code: 3 picks per character (0 none, 1 = 0.9x, 2 = 1.0x, 3 = 1.15x), the addon's Core.lua the same
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+="
CODE_RE = re.compile(r"MVS1-([0-9a-f]{4})-([A-Za-z0-9+=]+)")


def say(*a):
    print(*a, flush=True)


def load_json(path, default=None):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


# ------------------------------------------------------------------------------------------------------------
# the service's lists (cached)
# ------------------------------------------------------------------------------------------------------------
def service_lists(refresh=False):
    lib_path, map_path = os.path.join(OUT, "library.json"), os.path.join(OUT, "voice_map.json")
    if refresh or not (os.path.exists(lib_path) and os.path.exists(map_path)):
        import voice_v2_voices as VV
        save_json(lib_path, VV.vg_voices())
        save_json(map_path, json.loads(VV._call("/v1/voice-map", timeout=300)))
    lib = load_json(lib_path)
    names = sorted({(i if isinstance(i, str) else i["name"]) for i in lib})
    return names, load_json(map_path)


# ------------------------------------------------------------------------------------------------------------
# pick
# ------------------------------------------------------------------------------------------------------------
# flags that say nothing about the text (a creature voice standing in, a line from the collector, a speaker the
# data does not name): such a line is still the voice's own and reads cleanly
TEXT_OK_FLAGS = {"voice-stand-in", "source-collector", "speaker-unknown"}


def clean(job: dict) -> bool:
    meta = job.get("meta") or {}
    return ("segments" not in job and set(meta.get("flags") or []) <= TEXT_OK_FLAGS
            and all(not ln.get("sex") for ln in meta.get("lines", [])))


def name_runs(name: str) -> set:
    """Every run of whole words of an NPC's name, joined: "Prophet Velen" -> prophet, velen, prophetvelen."""
    words = re.findall(r"[a-z0-9]+", (name or "").lower())
    return {"".join(words[i:j]) for i in range(len(words)) for j in range(i + 1, len(words) + 1)}


def kinds(job: dict) -> set:
    return {ln["kind"] for ln in job["meta"]["lines"]}


def dialogue_rank(job: dict):
    """Sort key of a quest dialogue: accept first, then the length nearest IDEAL, then the id."""
    k = min((DIALOGUE[x] for x in kinds(job) if x in DIALOGUE), default=9)
    return (k, abs(job["meta"]["words"] - IDEAL), job["id"])


def in_range(job: dict) -> bool:
    return WORDS[0] <= job["meta"]["words"] <= WORDS[1]


def is_dialogue(job: dict) -> bool:
    return bool(kinds(job) & set(DIALOGUE))


def line_of(job: dict) -> dict:
    """The meta line that names the speaker: a dialogue one first."""
    lines = job["meta"]["lines"]
    for ln in lines:
        if ln["kind"] in DIALOGUE:
            return ln
    return lines[0]


def pick_all(names, vmap, jobs, index, quests):
    by_voice = collections.defaultdict(list)
    by_npc = collections.defaultdict(list)
    pool = []
    pack_count = collections.Counter()
    for j in jobs:
        if "voice" in j:
            pack_count[j["voice"]] += 1
        for seg in j.get("segments") or []:
            pack_count[seg.get("voice")] += 1
        if not clean(j):
            continue
        by_voice[j["voice"]].append(j)
        for ln in j["meta"]["lines"]:
            if ln.get("npc") and ln["kind"] in DIALOGUE:
                by_npc[int(ln["npc"])].append(j)
        if "accept" in kinds(j) and in_range(j):
            pool.append(j)
    pool.sort(key=lambda j: j["id"])
    npcs = vmap.get("npcs", {})
    map_voice = collections.defaultdict(list)
    for entry, rec in npcs.items():
        if rec.get("voice"):
            map_voice[rec["voice"]].append(int(entry))
    by_name = collections.defaultdict(list)
    for entry, rec in npcs.items():
        if by_npc.get(int(entry)):
            for run in name_runs(rec.get("name")):
                if len(run) >= 5:
                    by_name[run].append(int(entry))
    # the quests drawn for the voices with no line of their own: one fixed shuffle, dealt in voice order, so no
    # two voices read the same quest and a re-run draws the same
    random.Random(20261003).shuffle(pool)
    dealt = iter(pool)

    def best_of(cands):
        cands = [j for j in cands if is_dialogue(j) and in_range(j)]
        return min(cands, key=dialogue_rank) if cands else None

    picks = []
    for v in names:
        src, job = None, None
        own = by_voice.get(v, [])
        job = best_of([j for j in own if j["id"] in index])
        if job:
            src = "pack"
        if not job:
            # its own other pack lines: a quest dialogue of another length first, then a greeting or gossip of 12
            # words or more, then any line of 8 or more
            others = [j for j in own if j["id"] in index and j["meta"]["words"] >= 8]
            if others:
                job, src = min(others, key=lambda j: (0 if is_dialogue(j) and j["meta"]["words"] >= 12 else
                                                      1 if j["meta"]["words"] >= 12 else 2,
                                                      abs(j["meta"]["words"] - IDEAL), j["id"])), "pack"
        if not job:
            job = best_of([j for e in map_voice.get(v, []) for j in by_npc.get(e, [])])
            src = "npc" if job else None
        if not job:
            key = norm(v[len("retail_"):] if v.startswith("retail_") else v)
            hits = by_name.get(key, []) if len(key) >= 5 else []
            job = best_of([j for e in hits for j in by_npc.get(e, [])])
            src = "name" if job else None
        if not job:
            job, src = next(dealt), "random"
        ln = line_of(job)
        q = quests.get(ln.get("quest")) or {}
        npc = ln.get("npc")
        who = (npcs.get(str(npc)) or {}).get("name") if npc else None
        if not who and q:
            who = q.get("giverName") if ln["kind"] == "accept" else q.get("turninName")
        info = (vmap.get("voices") or {}).get(v) or {}
        picks.append({
            "voice": v, "source": src, "text": job["text"], "words": job["meta"]["words"],
            "seed": job.get("seed", 42) if src == "pack" else 42,
            "packId": job["id"] if src == "pack" else None,
            "kind": ln["kind"], "quest": ln.get("quest"), "questTitle": q.get("title"), "npc": npc, "who": who,
            "packLines": pack_count.get(v, 0), "mapNpcs": info.get("npcs", 0), "mapKind": info.get("kind"),
        })
    return picks


def cmd_pick(args):
    import sources
    names, vmap = service_lists(args.refresh)
    jobs = load_json(os.path.join(V2, "lines.json"))["jobs"] + load_json(os.path.join(V2, "lines_readables.json"))["jobs"]
    index = load_json(os.path.join(V2, "clips", "index.json"), {})
    quests = sources.quest_list()
    picks = [p for p in pick_all(names, vmap, jobs, index, quests) if p["voice"] not in SKIP]
    save_json(os.path.join(OUT, "picks.json"), {"voices": len(picks), "skipped": SKIP, "picks": picks})
    c = collections.Counter(p["source"] for p in picks)
    say("picks.json: %d voices (%s)" % (len(picks), ", ".join("%s %d" % kv for kv in sorted(c.items()))))
    return 0


# ------------------------------------------------------------------------------------------------------------
# manifest
# ------------------------------------------------------------------------------------------------------------
def sample_id(p: dict, speed: float) -> str:
    if speed == 1.0 and p.get("packId"):
        return p["packId"]
    h = hashlib.sha1(("%s|%s|%s|%s" % (p["voice"], p["seed"], speed, p["text"])).encode("utf-8")).hexdigest()
    return "%s/%s" % (p["voice"], h[:12])


def manifest_jobs(picks: list) -> list:
    jobs = []
    for p in picks:
        for s in SPEEDS:
            # (every job states its speed, 1.0 too: voice_speeds.json never changes a sample)
            job = {"voice": p["voice"], "text": p["text"], "seed": p["seed"], "id": sample_id(p, s),
                   "keys": ["%s@%s" % (p["voice"], s)], "speed": s,
                   "meta": {"voiceKey": p["voice"], "words": p["words"], "flags": [], "lines": [],
                            "sample": {"speed": s, "source": p["source"]}}}
            jobs.append(job)
    return jobs


def cmd_manifest(args):
    picks = load_json(os.path.join(OUT, "picks.json"))["picks"]
    jobs = manifest_jobs(picks)
    clips = os.path.join(OUT, "clips")
    index = load_json(os.path.join(clips, "index.json"), {})
    pack_index = load_json(os.path.join(V2, "clips", "index.json"), {})
    copied = 0
    for p in picks:
        pid = p.get("packId")
        if not pid:
            continue
        voice, h = pid.split("/")
        src = os.path.join(V2, "clips", voice, h + ".ogg")
        dst = os.path.join(clips, voice, h + ".ogg")
        if not os.path.exists(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            copied += 1
        index[pid] = dict(pack_index[pid], copiedFromPack=True)
    # each sample clip made before generate.py recorded speeds: made at its job's speed (they were sent with it)
    for j in jobs:
        if j["id"] in index and "speed" not in index[j["id"]]:
            index[j["id"]]["speed"] = j["speed"]
    save_json(os.path.join(clips, "index.json"), index)
    save_json(os.path.join(OUT, "samples_manifest.json"),
              {"format": MANIFEST_FORMAT, "scope": "samples", "jobs": jobs})
    todo = [j for j in jobs if j["id"] not in index]
    say("samples_manifest.json: %d jobs (%d voices x %d speeds); %d pack clips copied (%d in all); %d to make, "
        "about %.0f speech minutes" % (len(jobs), len(picks), len(SPEEDS), copied, len(jobs) - len(todo), len(todo),
                                       sum(j["meta"]["words"] / 2.5 for j in todo) / 60))
    return 0


# ------------------------------------------------------------------------------------------------------------
# addon
# ------------------------------------------------------------------------------------------------------------
GROUPS = [("narrator", "Narrators"), ("creature_", "Creatures"), ("skyborne", "Skyborne"),
          ("npcdeathknight", "Death knights"), ("npcbloodelf", "Blood elves"), ("npcdraenei", "Draenei"),
          ("npctuskarr", "Tuskarr"), ("npcvrykul", "Vrykul"), ("retail_", "Retail voices")]


def group_of(p: dict) -> str:
    for prefix, label in GROUPS:
        if p["voice"].startswith(prefix):
            return label
    return "Game voices"


def lua_str(s) -> str:
    s = "" if s is None else str(s)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'


def data_version(keys: list) -> str:
    return hashlib.sha1("\n".join(keys).encode("utf-8")).hexdigest()[:4]


def data_lua(picks: list, secs: dict) -> str:
    keys = [p["voice"] for p in picks]
    out = ["-- MelloUI Voice Samples: the voices and their lines (made by Tools/voice_samples/samples.py addon).",
           "local _, ns = ...",
           "ns.data = {",
           "\tversion = %s," % lua_str(data_version(keys)),
           "\tvoices = {"]
    for p in picks:
        s = secs[p["voice"]]
        out.append("\t\t{ key = %s, group = %s, who = %s, quest = %s, text = %s, packLines = %d, source = %s, "
                   "secs = { %.2f, %.2f, %.2f } }," % (
                       lua_str(p["voice"]), lua_str(group_of(p)), lua_str(p.get("who") or ""),
                       lua_str(p.get("questTitle") or ""), lua_str(p["text"]), p.get("packLines", 0),
                       lua_str(p["source"]), s[0], s[1], s[2]))
    out += ["\t},", "}", ""]
    return "\n".join(out)


def cmd_addon(args):
    picks = load_json(os.path.join(OUT, "picks.json"))["picks"]
    clips = os.path.join(OUT, "clips")
    index = load_json(os.path.join(clips, "index.json"), {})
    missing = [(p["voice"], s) for p in picks for s in SPEEDS if sample_id(p, s) not in index]
    if missing and args.complete_only:
        short = {v for v, _ in missing}
        picks = [p for p in picks if p["voice"] not in short]
        say("--complete-only: %d voices with every speed made, %d left out for now" % (len(picks), len(short)))
    elif missing:
        say("not every clip is made: %d missing, e.g. %s (--complete-only builds the voices that are)"
            % (len(missing), missing[:5]))
        return 1
    root = os.path.join(OUT, "addon")
    folder = os.path.join(root, ADDON)
    if os.path.exists(folder):
        shutil.rmtree(folder)
    os.makedirs(os.path.join(folder, "Sounds"))
    secs = {}
    for p in picks:
        secs[p["voice"]] = []
        for s in SPEEDS:
            jid = sample_id(p, s)
            voice, h = jid.split("/")
            shutil.copyfile(os.path.join(clips, voice, h + ".ogg"),
                            os.path.join(folder, "Sounds", p["voice"] + SUFFIX[s] + ".ogg"))
            secs[p["voice"]].append(index[jid]["seconds"])
    for name in os.listdir(ADDON_SRC):
        shutil.copyfile(os.path.join(ADDON_SRC, name), os.path.join(folder, name))
    with open(os.path.join(folder, "Data.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(data_lua(picks, secs))
    keys = [p["voice"] for p in picks]
    data = load_json(os.path.join(OUT, "data.json"), {}) or {}
    versions = data.get("versions") or ({data["version"]: data["keys"]} if data.get("version") else {})
    versions[data_version(keys)] = keys
    save_json(os.path.join(OUT, "data.json"), {"current": data_version(keys), "versions": versions})
    zpath = os.path.join(OUT, ADDON + ".zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, _, files in os.walk(folder):
            for fn in sorted(files):
                full = os.path.join(dirpath, fn)
                arc = os.path.relpath(full, root).replace("\\", "/")
                z.write(full, arc, compress_type=zipfile.ZIP_STORED if fn.endswith(".ogg") else zipfile.ZIP_DEFLATED)
    say("%s: %d voices, %d clips, %.1f MB" % (zpath, len(picks), len(picks) * len(SPEEDS), os.path.getsize(zpath) / 1e6))
    return 0


# ------------------------------------------------------------------------------------------------------------
# the feedback code and the tally
# ------------------------------------------------------------------------------------------------------------
def encode(picks_by_index: list) -> str:
    """picks_by_index: 0 none, 1 = 0.9x, 2 = 1.0x, 3 = 1.15x per voice in the data's order."""
    chars = []
    for i in range(0, len(picks_by_index), 3):
        a = picks_by_index[i:i + 3] + [0, 0]
        chars.append(ALPHABET[a[0] + 4 * a[1] + 16 * a[2]])
    return "".join(chars)


def decode(payload: str, count: int) -> list:
    out = []
    for ch in payload:
        n = ALPHABET.index(ch)
        out += [n % 4, (n // 4) % 4, n // 16]
    return out[:count]


def cmd_tally(args):
    versions = (load_json(os.path.join(OUT, "data.json")) or {}).get("versions", {})
    keys = sorted({k for ks in versions.values() for k in ks})
    counts = {k: [0, 0, 0] for k in keys}
    seen, people, wrong, twice = set(), 0, 0, 0
    for path in args.files:
        text = open(path, encoding="utf-8", errors="replace").read()
        for ver, payload in CODE_RE.findall(text):
            if ver not in versions:
                wrong += 1
                continue
            if (ver, payload) in seen:
                twice += 1
                continue
            seen.add((ver, payload))
            people += 1
            order = versions[ver]
            for k, v in zip(order, decode(payload, len(order))):
                if v:
                    counts[k][v - 1] += 1
    rows = []
    for k in keys:
        n = sum(counts[k])
        mean = (0.9 * counts[k][0] + 1.0 * counts[k][1] + 1.15 * counts[k][2]) / n if n else None
        rows.append((k, counts[k][0], counts[k][1], counts[k][2], n, mean))
    csv_path = os.path.join(OUT, "feedback_tally.csv")
    with open(csv_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("voice,picked_0.9x,picked_1.0x,picked_1.15x,votes,mean_speed\n")
        for k, a, b, c, n, mean in rows:
            f.write("%s,%d,%d,%d,%d,%s\n" % (k, a, b, c, n, "" if mean is None else "%.3f" % mean))
    say("%d feedback codes (%d posted twice, %d of another sample set skipped): %s" % (people, twice, wrong, csv_path))
    for k, a, b, c, n, mean in sorted(rows, key=lambda r: -(r[4])):
        if n:
            say("  %-36s 0.9x %3d   1.0x %3d   1.15x %3d   mean %.2f" % (k, a, b, c, mean))
    return 0


# ------------------------------------------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pick")
    p.add_argument("--refresh", action="store_true", help="fetch the voice list and the voice map again")
    sub.add_parser("manifest")
    a = sub.add_parser("addon")
    a.add_argument("--complete-only", action="store_true", help="only the voices with all three speeds made")
    t = sub.add_parser("tally")
    t.add_argument("files", nargs="+")
    args = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    return {"pick": cmd_pick, "manifest": cmd_manifest, "addon": cmd_addon, "tally": cmd_tally}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
