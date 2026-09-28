#!/usr/bin/env python3
"""The pilot's listening folder (the voice pack spec, section 6.3 step 5), made from the clip library.

    python Tools/voice_v2/pilot_listen.py                   pilot/listen/, listen.csv, PILOT.md, pilot_all.ogg
    ... --asr                                               also transcribe every clip (/v1/asr) and score it
    ... --selection pilot_selection.json                    adds what each line is there to test
    ... --manifest / --clips / --out                        default lines_pilot.json, clips/, pilot/ under
                                                            MelloUI-BuildData/output/voice_v2

Writes (under --out):
  listen/P34_4607_Father-Lankester_79080-complete.ogg     a copy of every pilot clip; the narrator A/B pair is
  listen/P01_0_object_176-accept__narrator_neutral.ogg    ...__<voice>.ogg on both sides
  listen/listen.csv                                       pilot, key, NPC, voice, variant, spoken text, file
                                                          (+ heard, match with --asr)
  PILOT.md                                                the listening sheet: file, NPC, voice, seed, line type,
                                                          seconds, text, in sheet order
  asr.json                                                with --asr: clip sha1 -> what ASR heard (a re-run
                                                          only sends clips it has not heard)
  pilot_all.ogg                                           every clip chained in sheet order (Ogg chaining: the
                                                          clips byte for byte, one after another; a clip whose
                                                          stream serial repeats an earlier one gets a new serial
                                                          and page checksums, nothing else changes)

Network: only with --asr, only the voicegen box. Standard library only.
"""
from __future__ import annotations

import argparse
import csv
import difflib
import hashlib
import json
import os
import re
import shutil
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
from paths import OUTPUT  # noqa: E402
import voice_v2_pack as PACK  # noqa: E402

V2 = os.path.join(OUTPUT, "voice_v2")

LINE_TYPES = {"accept": "quest accept", "objectives": "quest objectives", "progress": "quest progress",
              "complete": "quest complete", "greeting": "greeting", "qgreet": "quest-giver greeting",
              "sub": "gossip sub-page", "holiday": "holiday greeting", "state": "state greeting",
              "trainer": "trainer greeting", "default": "default greeting"}


def load_json(path, default=None):
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return default


def npc_names() -> dict:
    names = {}
    path = os.path.join(HERE, "npc_voices.csv")
    with open(path, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            try:
                names[int(row["npc"])] = row["name"]
            except (KeyError, ValueError):
                pass
    return names


def slug(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-")
    return s or "x"


def pilot_order(p: str) -> tuple:
    m = re.match(r"P(\d+)([mf]?)$", p or "")
    if not m:
        return (999, 9)
    return (int(m.group(1)), {"": 0, "m": 1, "f": 2}[m.group(2)])


def spoken_parts(job: dict) -> list:
    """[(role, voice, text)] of a job: role is 'npc' for the speaker's voice, 'narrator' otherwise."""
    vk = job["meta"]["voiceKey"]
    if "segments" in job:
        segs = job["segments"]
    else:
        segs = [{"voice": job["voice"], "text": job["text"], "seed": job.get("seed")}]
    out = []
    for s in segs:
        narr = s["voice"].startswith("narrator") and not vk.startswith("narrator")
        out.append(("narrator" if narr else "npc", s["voice"], s["text"], s.get("seed")))
    return out


# ------------------------------------------------------------------------------------------------------------
# Ogg chaining
# ------------------------------------------------------------------------------------------------------------
def _crc_table():
    t = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else (r << 1)
        t.append(r & 0xFFFFFFFF)
    return t


_CRC = _crc_table()


def ogg_crc(data: bytes) -> int:
    crc = 0
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _CRC[((crc >> 24) & 0xFF) ^ b]
    return crc


def pages(data: bytes):
    pos = 0
    while pos < len(data):
        if data[pos:pos + 4] != b"OggS":
            raise ValueError("no Ogg page at byte %d" % pos)
        nseg = data[pos + 26]
        end = pos + 27 + nseg + sum(data[pos + 27:pos + 27 + nseg])
        yield pos, end
        pos = end


def serial_of(data: bytes) -> int:
    return struct.unpack_from("<I", data, 14)[0]


def reserial(data: bytes, serial: int) -> bytes:
    out = bytearray()
    for a, b in pages(data):
        page = bytearray(data[a:b])
        struct.pack_into("<I", page, 14, serial)
        struct.pack_into("<I", page, 22, 0)
        struct.pack_into("<I", page, 22, ogg_crc(bytes(page)))
        out += page
    return bytes(out)


def chain(paths: list, dest: str) -> dict:
    used, renumbered = set(), 0
    next_serial = 0x4D454C00          # "MEL\0": a fresh serial for a clip that repeats one
    with open(dest + ".tmp", "wb") as out:
        for p in paths:
            with open(p, "rb") as f:
                data = f.read()
            s = serial_of(data)
            if s in used:
                while next_serial in used:
                    next_serial += 1
                data = reserial(data, next_serial)
                s = next_serial
                renumbered += 1
            used.add(s)
            out.write(data)
    os.replace(dest + ".tmp", dest)
    return {"clips": len(paths), "renumbered": renumbered, "bytes": os.path.getsize(dest)}


# ------------------------------------------------------------------------------------------------------------
def file_sha1(path: str) -> str:
    with open(path, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def asr_all(files: list, cache_path: str) -> dict:
    """{basename: heard text} from /v1/asr, a few clips per call. Clips heard before (same bytes) come from
    the cache (asr.json next to PILOT.md), so a re-run does not ask the box again."""
    cache = load_json(cache_path, {}) or {}
    heard, todo = {}, []
    for p in files:
        name, digest = os.path.basename(p), file_sha1(p)
        hit = cache.get(digest)
        if hit is not None:
            heard[name] = hit
        else:
            todo.append((p, digest))
    if todo:
        import voice_v2_voices as VV
        by_name = {os.path.basename(p): d for p, d in todo}
        for i in range(0, len(todo), 12):
            for r in VV.vg_asr([p for p, _ in todo[i:i + 12]]) or []:
                if isinstance(r, dict):
                    name = os.path.basename(str(r.get("file", "")))
                    heard[name] = r.get("text", "")
                    if name in by_name:
                        cache[by_name[name]] = heard[name]
        with open(cache_path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(cache, f, indent=1, ensure_ascii=False, sort_keys=True)
    return heard


def _words(s: str) -> list:
    return re.sub(r"[^a-z0-9 ]", " ", s.lower().replace("-", " ")).split()


def match_score(expected: str, heard: str) -> float:
    """Share of the expected words heard, in order (the longest common word sequence), less a penalty for
    extra words heard beyond the text's length."""
    e, g = _words(expected), _words(heard)
    if not e:
        return 1.0
    same = sum(b.size for b in difflib.SequenceMatcher(None, e, g, autojunk=False).get_matching_blocks())
    extra = max(0, len(g) - len(e))
    return round(max(0.0, (same - extra) / len(e)), 3)


def md_cell(s: str) -> str:
    return str(s).replace("|", "\\|").replace("\n", " ")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=os.path.join(V2, "lines_pilot.json"))
    ap.add_argument("--clips", default=os.path.join(V2, "clips"))
    ap.add_argument("--out", default=os.path.join(V2, "pilot"))
    ap.add_argument("--selection", default=None, help="pilot_selection.json: adds what each line tests")
    ap.add_argument("--asr", action="store_true", help="transcribe every clip on voicegen and score it")
    ap.add_argument("--pack", default=None, help="the built test pack folder, named in PILOT.md")
    args = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    manifest = load_json(args.manifest)
    index = load_json(os.path.join(args.clips, "index.json"), {})
    selection = {l["pilot"]: l for l in (load_json(args.selection, {}) or {}).get("lines", [])}
    voices = (load_json(os.path.join(V2, "voices.json"), {}) or {}).get("voices", {})
    batches = {}
    for name in os.listdir(os.path.join(V2, "batches")) if os.path.isdir(os.path.join(V2, "batches")) else []:
        if name.endswith(".json") and not name.endswith(".tmp"):
            rec = load_json(os.path.join(V2, "batches", name), {})
            if isinstance(rec, dict) and rec.get("batch"):
                batches[rec["batch"]] = rec
    names = npc_names()
    jobs = sorted(manifest["jobs"], key=lambda j: (pilot_order(j["meta"].get("pilot")),
                                                   1 if not j.get("keys") else 0))
    listen = os.path.join(args.out, "listen")
    os.makedirs(listen, exist_ok=True)
    for old in os.listdir(listen):
        if old.endswith(".ogg"):
            os.remove(os.path.join(listen, old))

    rows, missing = [], []
    for job in jobs:
        meta = job["meta"]
        pilot = meta.get("pilot") or "?"
        line = meta["lines"][0]
        key = line["key"]
        npc = line.get("npc") or 0
        if npc:
            who = names.get(npc, "NPC %d" % npc)
        else:
            who = "%s (quest %s)" % (line.get("speakerKind") or "object", line.get("quest"))
        ab = meta.get("ab")
        sel = selection.get(pilot, {})
        variant = ""
        if ab:
            variant = ab.get("variant", "")
        elif sel.get("ab"):
            variant = sel["ab"].get("keysGoTo") or meta["voiceKey"]
        fname = "%s_%d_%s_%s%s.ogg" % (pilot, npc, slug(who if npc else line.get("speakerKind") or "object"), key,
                                       "__" + variant if variant else "")
        src = os.path.join(args.clips, *job["id"].split("/")) + ".ogg"
        info = index.get(job["id"], {})
        if not os.path.isfile(src):
            missing.append((pilot, job["id"]))
            continue
        try:
            secs = PACK.ogg_info(src)["seconds"]
        except PACK.BuildError as e:
            missing.append((pilot, "%s: %s" % (job["id"], e)))
            continue
        shutil.copyfile(src, os.path.join(listen, fname))
        parts = spoken_parts(job)
        vk = meta["voiceKey"]
        service = voices.get(vk, {}).get("service", vk)
        voice_cell = vk if service == vk else "%s (%s)" % (vk, service)
        narr = sorted({v for r, v, _, _ in parts if r == "narrator"})
        if narr:
            voice_cell += " + narrator " + ", ".join(narr)
        if all(r == "narrator" for r, _, _, _ in parts) and not vk.startswith("narrator"):
            voice_cell = "%s (narrator only: %s)" % (vk, ", ".join(sorted({v for _, v, _, _ in parts})))
        if ab:
            voice_cell = "%s (A/B alternate of %s)" % (job.get("voice"), vk)
        asked = sorted({str(s) for _, _, _, s in parts})
        used = info.get("seedUsed")
        seed_cell = "/".join(asked)
        if used is not None:
            u = used if isinstance(used, list) else [used]
            if sorted({str(x) for x in u}) != asked:
                seed_cell += " (re-rolled: %s)" % "/".join(str(x) for x in u)
        kind = line.get("kind")
        ltype = LINE_TYPES.get(kind, kind or "")
        if line.get("sex"):
            ltype += " (%s player)" % {"m": "male", "f": "female"}[line["sex"]]
        if len(meta["lines"]) > 1 or line.get("kinds"):
            extra = line.get("kinds") or []
            if extra:
                ltype += " + " + ", ".join(LINE_TYPES.get(k, k) for k in extra if k != kind)
        text_md = " ".join(("*[narrator]* " + t) if r == "narrator" else t for r, _, t, _ in parts)
        text_csv = " | ".join(("[narrator] " + t) if r == "narrator" else t for r, _, t, _ in parts)
        rows.append({"pilot": pilot, "key": key if not ab else key + " (alternate, no key)", "npc": npc, "who": who,
                     "voice": voice_cell, "variant": variant, "seed": seed_cell, "type": ltype,
                     "seconds": secs, "text_md": text_md, "text": text_csv, "file": fname,
                     "expected": " ".join(t for _, _, t, _ in parts), "tests": sel.get("why", ""),
                     "flags": ", ".join(meta.get("flags") or []), "batch": info.get("batch", ""),
                     "path": os.path.join(listen, fname)})

    if args.asr and rows:
        heard = asr_all([r["path"] for r in rows], os.path.join(args.out, "asr.json"))
        for r in rows:
            r["heard"] = heard.get(r["file"], "")
            r["match"] = match_score(r["expected"], r["heard"]) if r["heard"] else None

    with open(os.path.join(listen, "listen.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        head = ["pilot", "key", "NPC", "voice", "variant", "seed", "line type", "seconds", "spoken text", "file"]
        if args.asr:
            head += ["heard (ASR)", "match"]
        w.writerow(head)
        for r in rows:
            row = [r["pilot"], r["key"], "%d %s" % (r["npc"], r["who"]) if r["npc"] else r["who"], r["voice"],
                   r["variant"], r["seed"], r["type"], "%.2f" % r["seconds"], r["text"], r["file"]]
            if args.asr:
                row += [r.get("heard", ""), "" if r.get("match") is None else "%.2f" % r["match"]]
            w.writerow(row)

    chained = chain([r["path"] for r in rows], os.path.join(args.out, "pilot_all.ogg")) if rows else None
    total = sum(r["seconds"] for r in rows)
    keyed = [r for r in rows if "(alternate" not in r["key"]]

    md = []
    md.append("# Voice pack v2: pilot listening sheet")
    md.append("")
    md.append("%d clips, %.1f s (%d min %02d s) of audio: %d keyed lines and %d A/B alternate."
              % (len(rows), total, int(total) // 60, int(round(total)) % 60, len(keyed), len(rows) - len(keyed)))
    recs = [batches[b] for b in sorted({r["batch"] for r in rows if r["batch"]}) if b in batches]
    if recs:
        md.append("Made on voicegen (%s) in %d batches of under 3 speech minutes each, one after another: %s."
                  % (recs[0].get("box") or "?", len(recs), ", ".join("`%s`" % x["name"] for x in recs)))
    md.append("")
    md.append("- **Everything in one file:** `pilot_all.ogg` plays every clip below in this order (VLC plays it).")
    md.append("- **One clip at a time:** `listen/` (file names start with the pilot number); `listen/listen.csv` "
              "is this sheet as a table.")
    if args.pack:
        md.append("- **In game:** the test pack of just these lines is `%s`. Copy that folder into "
                  "`Interface\\AddOns` (or run `python Tools/voice_v2_pack.py <lines_pilot.json> --out <that folder> "
                  "--install`) only when you want to try it; the old pack stays as it is." % args.pack)
    md.append("")
    md.append("What to decide by ear (spec 6.3): the narrator (P01, neutral against alliance), the creature voices "
              "(P42-P47, P53-P57), the pacing, the placeholder results (P04, P23, P25, P30, P45, P46), and Tirion "
              "(P52: his retail voice).")
    md.append("")
    if missing:
        md.append("**Missing clips:** " + ", ".join("%s %s" % m for m in missing))
        md.append("")
    has_asr = args.asr
    head = "| # | file | NPC | voice | seed | line type | s | text |"
    sep = "|---|---|---|---|---|---|---|---|"
    if has_asr:
        head += " ASR |"
        sep += "---|"
    md += [head, sep]
    for r in rows:
        who = ("%d %s" % (r["npc"], r["who"])) if r["npc"] else r["who"]
        cells = [r["pilot"], "[%s](listen/%s)" % (r["file"], r["file"].replace(" ", "%20")), who, r["voice"],
                 r["seed"], r["type"], "%.1f" % r["seconds"], r["text_md"]]
        if has_asr:
            cells.append("" if r.get("match") is None else "%.2f" % r["match"])
        md.append("| " + " | ".join(md_cell(c) for c in cells) + " |")
    md.append("")
    if any(r["tests"] or r["flags"] for r in rows):
        md.append("## What each line tests")
        md.append("")
        for r in rows:
            if r["tests"] or r["flags"]:
                bits = [r["tests"]] if r["tests"] else []
                if r["flags"]:
                    bits.append("flags: " + r["flags"])
                md.append("- **%s** `%s`: %s" % (r["pilot"], r["key"], "; ".join(bits)))
        md.append("")
    if has_asr:
        low = [r for r in rows if r.get("match") is not None and r["match"] < 0.85]
        md.append("## Speech check (ASR read-back)")
        md.append("")
        md.append("Each clip was transcribed on voicegen and compared with the text it should say (share of the "
                  "words heard in order; names in fantasy languages are the usual misses).")
        md.append("")
        if low:
            md.append("| # | match | heard |")
            md.append("|---|---|---|")
            for r in low:
                md.append("| %s | %.2f | %s |" % (r["pilot"] + (" (alternate)" if "(alternate" in r["key"] else ""),
                                                  r["match"], md_cell(r["heard"])))
        else:
            md.append("Every clip matched its text at 0.85 or more.")
        md.append("")
    if chained:
        md.append("`pilot_all.ogg`: %d clips chained, %.1f MB%s." % (
            chained["clips"], chained["bytes"] / 1e6,
            "" if not chained["renumbered"] else "; %d clips got a new stream serial so players keep them apart"
            % chained["renumbered"]))
        md.append("")
    with open(os.path.join(args.out, "PILOT.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(md))
    print("pilot: %d clips, %.1f s, %d missing -> %s" % (len(rows), total, len(missing), args.out))
    if chained:
        print("pilot_all.ogg: %d clips, %d renumbered, %d bytes" % (chained["clips"], chained["renumbered"],
                                                                      chained["bytes"]))
    for m in missing:
        print("  missing %s %s" % m)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
