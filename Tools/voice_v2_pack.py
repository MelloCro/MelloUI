#!/usr/bin/env python3
"""Build the new voice pack, MelloUI_VoiceOverData_v2, from a line manifest and the clip library.

    python Tools/voice_v2_pack.py <manifest.json> [more.json ...]     build into MelloUI-BuildData/output/voice_v2/
                                                                      (several manifests make one pack, e.g.
                                                                      lines.json lines_readables.json)
    python Tools/voice_v2_pack.py <manifest.json> --check             every check and the counts, nothing written
    python Tools/voice_v2_pack.py <manifest.json> --install [ADDONS]  build, then copy the built addon into the
                                                                      game's AddOns folder (only when the user asks)
    ... --clips DIR    the clip library (default MelloUI-BuildData/output/voice_v2/clips)
    ... --out DIR      the built addon (default MelloUI-BuildData/output/voice_v2/MelloUI_VoiceOverData_v2)
    ... --build TEXT   the build text in the TOC and the index (default "<today> <manifest scope>")

The manifest is lines.json / lines_pilot.json / lines_readables.json (format "melloui-voice-lines/2", the voice
pack spec section 3.6); several are read as one (their keys must not repeat; a job in two of them is one clip).
Readable pages (books, letters, plaques ...) are keyed "r-<hash8>" and read by the narrator; their canonical texts
go into P.texts, and P.readNames maps the item / object name to its pages (the runtime's near-match).
Only its KEYED jobs go into the pack (A/B alternates have keys: []); a job's clip is <clips>/<id>.ogg, where
id = "<voiceKey>/<hash12>", kept exactly as the speech service returned it (Ogg Vorbis, mono).

The addon (spec section 1):
    MelloUI_VoiceOverData_v2.toc          no X-VoiceOver-* fields: only MelloUI's Voice Over reads this pack
    index.lua                             key -> clip and length, as flat arrays, each table in its own
                                          function block (Lua 5.1's constant limit), split past 100,000 constants
    SOURCES.txt                           where the texts and voices come from
    sounds/<voiceKey>/<hash12>.ogg        every clip a key uses, copied once however many keys share it

The build FAILS (exit 1, every problem listed) when a key is malformed or used twice, a key's clip is missing or
fails validation (OggS with a Vorbis identification header, mono, at least 0.3 s, at most 4 + words / 1.5 s,
whole pages to the end-of-stream page), a text key's hash is not the hash of its canonical text, or an NPC would
speak in two voices. It never writes to any folder but one named MelloUI_VoiceOverData_v2: the old pack
(MelloUI_VoiceOverData), built or installed, is never touched.

Standard library only. Tools never ship (.pkgmeta).
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from paths import OUTPUT  # noqa: E402

ADDON_NAME = "MelloUI_VoiceOverData_v2"
OLD_PACK = "MelloUI_VoiceOverData"
DEFAULT_ADDONS = r"F:\World of Warcraft\_classic_beta_\Interface\AddOns"
MANIFEST_FORMAT = "melloui-voice-lines/2"
MAX_CONSTANTS = 100_000          # per function block; Lua 5.1 allows 262,143
MIN_SECONDS = 0.3

KEY_RE = re.compile(r"^(?:(?:[mf]-)?\d+-(?:accept|objectives|progress|complete)(?:-\d+)?|g-\d+-[0-9a-f]{8}|r-[0-9a-f]{8})$")
ID_RE = re.compile(r"^([a-z0-9_]+)/([0-9a-f]{12})$")


class BuildError(Exception):
    pass


# ---------------------------------------------------------------------------
# The key rules the runtime shares (the spec's ref_vtext; Modules/VoiceOver.lua KeyCanon / Hash8)
# ---------------------------------------------------------------------------

def canon(text: str) -> str:
    """Lower case A-Z, every character but a-z and 0-9 a space, single spaces, trimmed."""
    out = []
    for ch in text:
        c = ch.lower() if "A" <= ch <= "Z" else ch
        out.append(c if ("a" <= c <= "z" or "0" <= c <= "9") else " ")
    return " ".join("".join(out).split())


def hash8(s: str) -> str:
    """32-bit polynomial hash over the UTF-8 bytes, 8 lowercase hex digits (Hash8 in VoiceOver.lua)."""
    h = 0
    for b in s.encode("utf-8"):
        h = (h * 31 + b) % 4294967296
    return "%04x%04x" % (h // 65536, h % 65536)


# ---------------------------------------------------------------------------
# Ogg Vorbis: the header and the length, read from the pages
# ---------------------------------------------------------------------------

def ogg_info(path: str) -> dict:
    """channels, rate, seconds (last granule position / rate) and bytes of an Ogg Vorbis file. Raises
    BuildError when it is not one, is cut short, or has no end-of-stream page."""
    with open(path, "rb") as f:
        data = f.read()
    pos, pages, first, last_granule, last_flags = 0, 0, None, None, 0
    while pos < len(data):
        if data[pos:pos + 4] != b"OggS":
            raise BuildError("no Ogg page at byte %d" % pos)
        if len(data) < pos + 27:
            raise BuildError("page header cut short at byte %d" % pos)
        version, flags = data[pos + 4], data[pos + 5]
        if version != 0:
            raise BuildError("Ogg version %d at byte %d" % (version, pos))
        granule = struct.unpack_from("<q", data, pos + 6)[0]
        nseg = data[pos + 26]
        lacing = data[pos + 27:pos + 27 + nseg]
        body = pos + 27 + nseg
        end = body + sum(lacing)
        if len(lacing) != nseg or end > len(data):
            raise BuildError("page cut short at byte %d" % pos)
        if first is None:
            if not flags & 0x02:
                raise BuildError("the first page is not a beginning of stream")
            first = data[body:end]
        if granule != -1:
            last_granule = granule
        last_flags = flags
        pages += 1
        pos = end
    if first is None:
        raise BuildError("empty file")
    if len(first) < 30 or first[:7] != b"\x01vorbis":
        raise BuildError("the first packet is not a Vorbis identification header")
    channels = first[11]
    rate = struct.unpack_from("<I", first, 12)[0]
    if rate <= 0:
        raise BuildError("sample rate %d" % rate)
    if not last_flags & 0x04:
        raise BuildError("no end-of-stream page (cut short?)")
    if last_granule is None or last_granule < 0:
        raise BuildError("no granule position")
    return {"channels": channels, "rate": rate, "seconds": last_granule / rate, "bytes": len(data), "pages": pages}


def words_of(job: dict) -> int:
    meta = job.get("meta") or {}
    if isinstance(meta.get("words"), int) and meta["words"] > 0:
        return meta["words"]
    if "segments" in job:
        text = " ".join(seg.get("text", "") for seg in job["segments"])
    else:
        text = job.get("text", "")
    return len(text.split())


def validate_clip(path: str, words: int) -> dict:
    info = ogg_info(path)
    if info["channels"] != 1:
        raise BuildError("%d channels, not mono" % info["channels"])
    if info["seconds"] < MIN_SECONDS:
        raise BuildError("%.2f s, shorter than %.1f s" % (info["seconds"], MIN_SECONDS))
    longest = 4 + words / 1.5
    if info["seconds"] > longest:
        raise BuildError("%.2f s, longer than 4 + %d words / 1.5 = %.1f s" % (info["seconds"], words, longest))
    return info


# ---------------------------------------------------------------------------
# The pack's content from the manifest
# ---------------------------------------------------------------------------

def plan(manifest: dict, clips: str) -> dict:
    """Everything the index needs, checked. Raises BuildError with every problem found."""
    problems = []
    if manifest.get("format") != MANIFEST_FORMAT:
        raise BuildError("manifest format %r, not %r" % (manifest.get("format"), MANIFEST_FORMAT))
    jobs = [j for j in manifest.get("jobs", []) if j.get("keys")]
    files = []                 # [(voiceKey, hash12, source path, words, jobIds)]
    file_index = {}            # job id -> index into files
    key_file = {}              # key -> file index (0-based)
    key_job = {}               # key -> job id (duplicate check)
    npc_voices = {}            # npc -> set(voiceKey)
    texts, text_index = [], {}
    npc_texts = {}             # npc (0 = objects) -> set(text index)
    read_names = {}            # canonical item / object name -> set(text index) of its readable pages
    titles = {}                # canonical title -> set(quest ID)
    for job in jobs:
        jid = job.get("id", "")
        m = ID_RE.match(jid)
        meta = job.get("meta") or {}
        if not m:
            problems.append("job id %r is not <voiceKey>/<hash12>" % jid)
            continue
        voice, h12 = m.group(1), m.group(2)
        if meta.get("voiceKey", voice) != voice:
            problems.append("job %s: meta.voiceKey %r is not the id's folder" % (jid, meta.get("voiceKey")))
        if ("text" in job) == ("segments" in job):
            problems.append("job %s: needs text or segments, never both" % jid)
        if jid not in file_index:
            file_index[jid] = len(files)
            files.append([voice, h12, os.path.join(clips, voice, h12 + ".ogg"), words_of(job), [jid]])
        fi = file_index[jid]
        for key in job["keys"]:
            if not isinstance(key, str) or not KEY_RE.match(key):
                problems.append("job %s: malformed key %r" % (jid, key))
                continue
            if key in key_job:
                problems.append("key %s is used by %s and %s" % (key, key_job[key], jid))
                continue
            key_job[key] = jid
            key_file[key] = fi
        keyset = set(job["keys"])
        for line in meta.get("lines") or []:
            key = line.get("key")
            if key not in keyset:
                problems.append("job %s: a meta line names key %r, not one of the job's keys" % (jid, key))
                continue
            npc = line.get("npc")
            if isinstance(npc, int) and npc > 0:
                npc_voices.setdefault(npc, set()).add(voice)
            if key.startswith("r-"):
                text = line.get("canon")
                if not isinstance(text, str) or not text or canon(text) != text:
                    problems.append("readable key %s has no canonical text (meta.lines[].canon)" % key)
                    continue
                if hash8(text) != key[2:]:
                    problems.append("readable key %s: the text's hash is %s" % (key, hash8(text)))
                    continue
                if npc not in (0, None):
                    problems.append("readable key %s: speaker %r; a page is read by the narrator (0)" % (key, npc))
                if text not in text_index:
                    text_index[text] = len(texts)
                    texts.append(text)
                for name in line.get("names") or []:
                    if isinstance(name, str) and canon(name):
                        read_names.setdefault(canon(name), set()).add(text_index[text])
                continue
            if key.startswith("g-"):
                _, key_npc, key_hash = key.split("-")
                text = line.get("canon")
                if not isinstance(text, str):
                    problems.append("text key %s has no canonical text (meta.lines[].canon)" % key)
                    continue
                if canon(text) != text:
                    problems.append("text key %s: its text is not canonical: %r" % (key, text[:60]))
                    continue
                if hash8(text) != key_hash:
                    problems.append("text key %s: the text's hash is %s" % (key, hash8(text)))
                    continue
                if int(key_npc) != (npc or 0):
                    problems.append("text key %s: speaker %r is not the key's NPC" % (key, npc))
                if text not in text_index:
                    text_index[text] = len(texts)
                    texts.append(text)
                npc_texts.setdefault(int(key_npc), set()).add(text_index[text])
            title = line.get("title")
            quest = line.get("quest")
            if isinstance(title, str) and isinstance(quest, int) and canon(title):
                titles.setdefault(canon(title), set()).add(quest)
    for npc, voices in sorted(npc_voices.items()):
        if len(voices) > 1:
            problems.append("NPC %d would speak in %d voices: %s" % (npc, len(voices), ", ".join(sorted(voices))))
    # the clips themselves
    seconds = []
    for voice, h12, src, words, jids in files:
        if not os.path.isfile(src):
            problems.append("missing clip %s/%s.ogg (job %s)" % (voice, h12, jids[0]))
            seconds.append(None)
            continue
        try:
            info = validate_clip(src, words)
        except BuildError as e:
            problems.append("clip %s/%s.ogg: %s" % (voice, h12, e))
            seconds.append(None)
            continue
        seconds.append((info["seconds"], info["bytes"]))
    if problems:
        raise BuildError("\n".join(problems))
    voices = sorted({f[0] for f in files})
    voice_index = {v: i + 1 for i, v in enumerate(voices)}
    return {
        "voices": voices,
        "files": [(f[0], f[1], f[2]) for f in files],
        "fileVoice": [voice_index[f[0]] for f in files],
        "seconds": [s[0] for s in seconds],
        "bytes": sum(s[1] for s in seconds),
        "lines": {k: i + 1 for k, i in key_file.items()},
        "npcs": {npc: voice_index[next(iter(v))] for npc, v in npc_voices.items()},
        "texts": texts,
        "npcTexts": {npc: sorted(i + 1 for i in idx) for npc, idx in npc_texts.items()},
        "titles": {t: next(iter(q)) for t, q in titles.items() if len(q) == 1},
        "readNames": {n: sorted(i + 1 for i in idx) for n, idx in read_names.items()},
        "readKeys": sum(1 for k in key_file if k.startswith("r-")),
        "titlesDropped": sorted(t for t, q in titles.items() if len(q) > 1),
    }


# ---------------------------------------------------------------------------
# Writing the addon
# ---------------------------------------------------------------------------

def lua_str(s: str) -> str:
    out = ['"']
    for b in s.encode("utf-8"):
        c = chr(b)
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif 32 <= b < 127:
            out.append(c)
        else:
            out.append("\\%d" % b)
    out.append('"')
    return "".join(out)


def lua_seconds(v: float) -> str:
    s = "%.2f" % v
    return s.rstrip("0").rstrip(".") if "." in s else s


def emit_blocks(name: str, items: list) -> list:
    """items: [(key literal or None for the next array slot, value literal, constants)]. The first block
    builds P.<name> with a constructor; a block that would pass MAX_CONSTANTS goes on in another block that
    fills the same table (explicit indices for array items)."""
    chunks, cur, consts = [], [], set()
    for slot, (k, v, c) in enumerate(items, 1):
        c = set(c)
        if k is None:
            c.add(slot)            # an array item written as t[slot] = v in a later block
        new = len(c - consts)
        if cur and len(consts) + new + 8 > MAX_CONSTANTS:
            chunks.append(cur)
            cur, consts = [], set()
        cur.append((slot, k, v))
        consts |= c
    if cur or not chunks:
        chunks.append(cur)
    blocks = []
    for n, chunk in enumerate(chunks):
        if n == 0:
            parts = [v if k is None else "[%s] = %s" % (k, v) for _, k, v in chunk]
            blocks.append(";(function() P.%s = { %s } end)()" % (name, ", ".join(parts)))
        else:
            parts = ["t[%s] = %s" % (slot if k is None else k, v) for slot, k, v in chunk]
            blocks.append(";(function() local t = P.%s %s end)()" % (name, " ".join(parts)))
    return blocks


def index_lua(p: dict, build: str) -> str:
    out = [
        "-- %s: generated by the pack builder. Do not edit." % ADDON_NAME,
        "local P = {}",
        "%s = P" % ADDON_NAME,
        "P.format = 2",
        "P.build = %s" % lua_str(build),
        'P.base = "Interface\\\\AddOns\\\\%s\\\\sounds\\\\"' % ADDON_NAME,
        "P.voices = { %s }" % ", ".join(lua_str(v) for v in p["voices"]),
    ]
    out += emit_blocks("file", [(None, lua_str(h), {h}) for _, h, _ in p["files"]])
    out += emit_blocks("fileVoice", [(None, str(v), {v}) for v in p["fileVoice"]])
    out += emit_blocks("seconds", [(None, lua_seconds(s), {lua_seconds(s)}) for s in p["seconds"]])
    out += emit_blocks("lines", [(lua_str(k), str(p["lines"][k]), {k, p["lines"][k]}) for k in sorted(p["lines"])])
    out += emit_blocks("npcs", [(str(n), str(p["npcs"][n]), {n, p["npcs"][n]}) for n in sorted(p["npcs"])])
    out += emit_blocks("texts", [(None, lua_str(t), {t}) for t in p["texts"]])
    out += emit_blocks("npcTexts", [(str(n), "{ %s }" % ", ".join(str(i) for i in p["npcTexts"][n]),
                                     {n, *p["npcTexts"][n]}) for n in sorted(p["npcTexts"])])
    out += emit_blocks("titles", [(lua_str(t), str(p["titles"][t]), {t, p["titles"][t]}) for t in sorted(p["titles"])])
    if p.get("readNames"):
        out += emit_blocks("readNames", [(lua_str(n), "{ %s }" % ", ".join(str(i) for i in p["readNames"][n]),
                                          {n, *p["readNames"][n]}) for n in sorted(p["readNames"])])
    return "\n".join(out) + "\n"


def interface_version() -> str:
    try:
        with open(os.path.join(os.path.dirname(HERE), "MelloUI.toc"), encoding="utf-8-sig") as f:
            for line in f:
                m = re.match(r"##\s*Interface:\s*(\d+)", line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return "16001"


def toc_text(build: str) -> str:
    return "\n".join([
        "## Interface: %s" % interface_version(),
        "## Title: MelloUI Voice Over Data v2",
        "## Notes: Recorded NPC and quest lines for MelloUI's Voice Over: one voice per NPC.",
        "## Version: 2.0.0",
        "## LoadOnDemand: 1",
        "## OptionalDeps: MelloUI",
        "## X-MelloUI-VoicePack: 2",
        "## X-MelloUI-VoicePack-Build: %s" % build.replace("\n", " "),
        "",
        "index.lua",
        "",
    ])


SOURCES = """MelloUI Voice Over Data v2
==========================

Recorded NPC and quest lines for MelloUI's Voice Over. Every NPC speaks all of its lines in one voice.

Texts
  The game's quest and NPC texts, and the pages of its books, letters, notes, plaques and signs: taken from the
  classic-db dump of the game's data, from cached quest and item pages of World of Warcraft: Forever, from the
  game's own text cache, and from lines collected in the game.
  The player's name, class and race are left out of the spoken words; lines whose words depend on the
  player's sex are recorded twice.

Voices
  Generated by a text-to-speech model on a private server.
  The reference voices were cut from the game's own NPC greeting recordings.

Build: {build}
Lines: {keys}   Recordings: {files}   Audio: {hours:.2f} h
"""


def sync_tree(src_files: dict, out: str, prune_sounds: bool = True) -> tuple:
    """Write {relative path: bytes | source file path} into out; copy a clip only when it changed; take out
    the .ogg files under sounds/ that no key uses any more. Returns (written, removed)."""
    guard(out)
    written = removed = 0
    for rel, src in src_files.items():
        dst = os.path.join(out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if isinstance(src, bytes):
            if os.path.isfile(dst):
                with open(dst, "rb") as f:
                    if f.read() == src:
                        continue
            with open(dst, "wb") as f:
                f.write(src)
            written += 1
        else:
            if os.path.isfile(dst) and os.path.getsize(dst) == os.path.getsize(src) and sha1(dst) == sha1(src):
                continue
            shutil.copyfile(src, dst)
            written += 1
    if prune_sounds:
        sounds = os.path.join(out, "sounds")
        keep = {os.path.normcase(os.path.join(out, r)) for r in src_files}
        for root, dirs, names in os.walk(sounds, topdown=False):
            for name in names:
                path = os.path.join(root, name)
                if name.endswith(".ogg") and os.path.normcase(path) not in keep:
                    os.remove(path)
                    removed += 1
            if root != sounds and not os.listdir(root):
                os.rmdir(root)
    return written, removed


def sha1(path: str) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def guard(folder: str) -> None:
    """Only ever a folder named MelloUI_VoiceOverData_v2: never the old pack, built or installed."""
    name = os.path.basename(os.path.normpath(folder))
    if name != ADDON_NAME:
        raise BuildError("refusing to write %s: the pack's folder must be named %s" % (folder, ADDON_NAME))


def load_manifests(paths) -> dict:
    """One manifest from one or several (lines.json + lines_readables.json): the jobs in order, the scopes joined.
    A job that is in two of them (the same words in the same voice) stays one clip for all of its keys."""
    if isinstance(paths, str):
        paths = [paths]
    merged = None
    for path in paths:
        with open(path, encoding="utf-8") as f:
            m = json.load(f)
        if m.get("format") != MANIFEST_FORMAT:
            raise BuildError("%s: manifest format %r, not %r" % (path, m.get("format"), MANIFEST_FORMAT))
        if merged is None:
            merged = dict(m, jobs=list(m.get("jobs", [])))
        else:
            merged["jobs"].extend(m.get("jobs", []))
            merged["scope"] = "%s+%s" % (merged.get("scope") or "full", m.get("scope") or "full")
    return merged


def build(manifest_path, clips: str, out: str, build_text: str | None, check_only: bool = False) -> dict:
    manifest = load_manifests(manifest_path)
    guard(out)
    p = plan(manifest, clips)
    if not build_text:
        build_text = "%s %s" % (datetime.date.today().isoformat(), manifest.get("scope") or "full")
    seconds = sum(p["seconds"])
    stats = {"keys": len(p["lines"]), "files": len(p["files"]), "npcs": len(p["npcs"]), "texts": len(p["texts"]),
             "readKeys": p["readKeys"], "readNames": len(p["readNames"]),
             "titles": len(p["titles"]), "titlesDropped": len(p["titlesDropped"]), "voices": len(p["voices"]),
             "mb": p["bytes"] / 1e6, "hours": seconds / 3600, "build": build_text}
    if check_only:
        return stats
    tree = {
        ADDON_NAME + ".toc": toc_text(build_text).encode("utf-8"),
        "index.lua": index_lua(p, build_text).encode("utf-8"),
        "SOURCES.txt": SOURCES.format(build=build_text, keys=stats["keys"], files=stats["files"],
                                      hours=stats["hours"]).encode("utf-8"),
    }
    for voice, h12, src in p["files"]:
        tree[os.path.join("sounds", voice, h12 + ".ogg")] = src
    stats["written"], stats["removed"] = sync_tree(tree, out)
    return stats


def install(out: str, addons: str) -> tuple:
    """Copy the built addon into the game's AddOns folder, as MelloUI_VoiceOverData_v2 only."""
    guard(out)
    target = os.path.join(addons, ADDON_NAME)
    guard(target)
    if os.path.normcase(os.path.normpath(target)) == os.path.normcase(os.path.normpath(os.path.join(addons, OLD_PACK))):
        raise BuildError("refusing to write the old pack")
    tree = {}
    for root, _, names in os.walk(out):
        for name in names:
            src = os.path.join(root, name)
            tree[os.path.relpath(src, out)] = src
    return target, sync_tree(tree, target)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest", nargs="+", help="lines.json (and lines_readables.json ...): one pack")
    ap.add_argument("--clips", default=os.path.join(OUTPUT, "voice_v2", "clips"))
    ap.add_argument("--out", default=os.path.join(OUTPUT, "voice_v2", ADDON_NAME))
    ap.add_argument("--build", default=None)
    ap.add_argument("--check", action="store_true", help="run every check and print the counts; write nothing")
    ap.add_argument("--install", nargs="?", const=DEFAULT_ADDONS, default=None, metavar="ADDONS",
                    help="also copy the built addon into ADDONS\\%s (only when the user asks)" % ADDON_NAME)
    args = ap.parse_args(argv)
    try:
        stats = build(args.manifest, args.clips, args.out, args.build, check_only=args.check)
    except BuildError as e:
        lines = str(e).splitlines()
        print("voice pack: build FAILED, %d problem%s" % (len(lines), "" if len(lines) == 1 else "s"))
        for line in lines:
            print("  " + line)
        return 1
    print("voice pack %s: %d keys, %d files, %d NPCs, %d texts, %d titles (%d shared titles left out), %d voices, "
          "%.1f MB, %.2f h" % (stats["build"], stats["keys"], stats["files"], stats["npcs"], stats["texts"],
                               stats["titles"], stats["titlesDropped"], stats["voices"], stats["mb"], stats["hours"]))
    if stats["readKeys"]:
        print("  readable pages: %d keys, %d item / object names" % (stats["readKeys"], stats["readNames"]))
    if args.check:
        print("checked only: nothing written")
        return 0
    print("built %s (%d files written, %d stale clips removed)" % (args.out, stats["written"], stats["removed"]))
    if args.install:
        try:
            target, (written, removed) = install(args.out, args.install)
        except BuildError as e:
            print("install FAILED: %s" % e)
            return 1
        print("installed %s (%d files written, %d stale clips removed)" % (target, written, removed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
