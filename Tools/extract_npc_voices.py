#!/usr/bin/env python3
"""
Build Media/NPCVoiceData.lua for the MelloUI Voice Over module.

WoW: Forever reuses the vanilla NPC IDs, and the client exposes no race for an
NPC, so the module needs a lookup table NPC ID -> race + gender. This script
builds it from public data:

  1. cmangos classic-db  : creature_template (NPC entry -> display IDs)
  2. wago.tools DB2 CSVs : CreatureDisplayInfo, CreatureModelData,
                           CreatureDisplayInfoExtra (display -> model / race / sex)
  3. wowdev listfile     : model file data ID -> model path (race keywords)

Optionally it cross-checks the result against the Forever client's own
creaturecache.wdb (the NPCs you have actually seen in game).

Usage:
  python Tools/extract_npc_voices.py [--cache DIR] [--out Media/NPCVoiceData.lua]
                                     [--wdb "F:/World of Warcraft/_classic_beta_/Cache/WDB/enUS/creaturecache.wdb"]
                                     [--build 1.15.9.69722]

Only the Python standard library is needed.
"""

import argparse
import csv
import gzip
import io
import os
import re
import struct
import sys
import urllib.request
from collections import Counter, defaultdict
from paths import CACHE

CMANGOS_SQL = "https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
LISTFILE = "https://github.com/wowdev/wow-listfile/releases/latest/download/verified-listfile.csv"
WAGO_CSV = "https://wago.tools/db2/{table}/csv?build={build}"

# ChrRaces IDs used by CreatureDisplayInfoExtra.DisplayRaceID.
CHR_RACES = {
    1: "human", 2: "orc", 3: "dwarf", 4: "nightelf", 5: "undead", 6: "tauren",
    7: "gnome", 8: "troll", 9: "goblin", 10: "bloodelf", 11: "draenei",
    22: "worgen", 24: "pandaren", 25: "pandaren", 26: "pandaren",
    27: "nightborne", 28: "tauren", 29: "bloodelf", 30: "draenei", 31: "troll",
    32: "human", 34: "dwarf", 35: "vulpera", 36: "orc", 37: "human",
}

# Model path keywords -> race code. First match wins, so put specific ones first.
PATH_RACES = [
    ("goblin", "goblin"),
    ("ogre", "ogre"),
    ("gnome", "gnome"),
    ("leper", "gnome"),
    ("dwarf", "dwarf"),
    ("darkiron", "dwarf"),
    ("nightelf", "nightelf"),
    ("highelf", "highelf"),
    ("bloodelf", "highelf"),
    ("tauren", "tauren"),
    ("troll", "troll"),
    ("orc", "orc"),
    ("human", "human"),
    ("undead", "undead"),
    ("scourge", "undead"),
    ("skeleton", "undead"),
    ("ghoul", "undead"),
    ("zombie", "undead"),
    ("ghost", "undead"),
    ("banshee", "undead"),
    ("lich", "undead"),
    ("abomination", "undead"),
    ("murloc", "murloc"),
    ("kobold", "kobold"),
    ("gnoll", "gnoll"),
    ("trogg", "trogg"),
    ("furbolg", "furbolg"),
    ("naga", "naga"),
    ("satyr", "satyr"),
    ("harpy", "harpy"),
    ("centaur", "centaur"),
    ("quilboar", "quilboar"),
    ("wildkin", "beast"),
    ("giant", "giant"),
    ("golem", "giant"),
    ("infernal", "giant"),
    ("dragon", "dragon"),
    ("drake", "dragon"),
    ("whelp", "dragon"),
    ("dragonkin", "dragon"),
    ("demon", "demon"),
    ("felguard", "demon"),
    ("felhunter", "demon"),
    ("imp", "imp"),
    ("succubus", "succubus"),
    ("voidwalker", "demon"),
    ("doomguard", "demon"),
    ("dreadlord", "demon"),
    ("pitlord", "demon"),
    ("elemental", "elemental"),
    ("spirit", "spirit"),
    ("wisp", "spirit"),
    ("treant", "treant"),
    ("ancient", "treant"),
    ("keeper", "keeper"),
    ("dryad", "dryad"),
    ("silithid", "insect"),
    ("spider", "insect"),
    ("scorpid", "insect"),
    ("nerubian", "insect"),
    ("mechanical", "mechanical"),
    ("harvestgolem", "mechanical"),
    ("robot", "mechanical"),
    ("shredder", "mechanical"),
]

GENDER_NAMES = {0: "m", 1: "f", 2: "n"}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def fetch(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    log(f"downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "MelloUI-extract/1.0"})
    with urllib.request.urlopen(req) as resp, open(dest, "wb") as fh:
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
    return dest


# --------------------------------------------------------------------------
# creature_template from the cmangos SQL dump
# --------------------------------------------------------------------------

def parse_sql_values(body):
    """Yield tuples of values from a MySQL VALUES body (handles quoted strings)."""
    i, n = 0, len(body)
    while i < n:
        if body[i] != "(":
            i += 1
            continue
        i += 1
        row = []
        cur = []
        while i < n:
            c = body[i]
            if c == "'":
                i += 1
                s = []
                while i < n:
                    c = body[i]
                    if c == "\\":
                        s.append(body[i + 1])
                        i += 2
                        continue
                    if c == "'":
                        i += 1
                        break
                    s.append(c)
                    i += 1
                row.append("".join(s))
                cur = None
            elif c == ",":
                if cur is not None:
                    row.append("".join(cur).strip())
                cur = []
                i += 1
            elif c == ")":
                if cur is not None:
                    row.append("".join(cur).strip())
                i += 1
                yield row
                break
            else:
                if cur is not None:
                    cur.append(c)
                i += 1


def load_creature_template(path):
    log("parsing creature_template")
    columns = None
    npcs = {}
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        in_create = False
        for line in fh:
            if line.startswith("CREATE TABLE `creature_template`"):
                in_create = True
                columns = []
                continue
            if in_create:
                m = re.match(r"\s*`(\w+)`", line)
                if m:
                    columns.append(m.group(1))
                elif line.startswith(")"):
                    in_create = False
                continue
            if line.startswith("INSERT INTO `creature_template`"):
                body = line[line.index("VALUES") + 6:]
                for row in parse_sql_values(body):
                    rec = dict(zip(columns, row))
                    entry = int(rec["Entry"])
                    models = [int(rec.get(f"ModelId{i}", "0") or 0) for i in range(1, 5)]
                    npcs[entry] = {
                        "name": rec.get("Name", ""),
                        "models": [m for m in models if m],
                        "type": int(rec.get("CreatureType", "0") or 0),
                    }
    log(f"  {len(npcs)} creature templates")
    return npcs


# --------------------------------------------------------------------------
# DB2 tables from wago.tools
# --------------------------------------------------------------------------

def load_csv(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def load_db2(cache, build):
    log(f"loading DB2 exports for build {build}")
    tables = {}
    for table in ("CreatureDisplayInfo", "CreatureModelData", "CreatureDisplayInfoExtra"):
        dest = os.path.join(cache, f"{table}_{build}.csv")
        fetch(WAGO_CSV.format(table=table, build=build), dest)
        tables[table] = load_csv(dest)
        log(f"  {table}: {len(tables[table])} rows")
    display = {}
    for row in tables["CreatureDisplayInfo"]:
        display[int(row["ID"])] = {
            "model": int(row["ModelID"] or 0),
            "extra": int(row["ExtendedDisplayInfoID"] or 0),
            "gender": int(row["Gender"] or 2),
        }
    model_fdid = {int(r["ID"]): int(r["FileDataID"] or 0) for r in tables["CreatureModelData"]}
    extra = {}
    for row in tables["CreatureDisplayInfoExtra"]:
        extra[int(row["ID"])] = {
            "race": int(row["DisplayRaceID"] or 0),
            "sex": int(row["DisplaySexID"] or 0),
        }
    return display, model_fdid, extra


def load_listfile(path):
    log("reading listfile")
    paths = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.endswith(".m2\n"):
                continue
            fdid, _, p = line.partition(";")
            p = p.strip().lower()
            if p.startswith("creature/") or p.startswith("character/"):
                paths[int(fdid)] = p
    log(f"  {len(paths)} creature/character models")
    return paths


# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------

def race_from_path(path):
    for key, race in PATH_RACES:
        if key in path:
            return race
    return None


def gender_from_path(path):
    if "female" in path:
        return "f"
    if "male" in path:
        return "m"
    return None


def classify(npc, display, model_fdid, extra, paths):
    for display_id in npc["models"]:
        info = display.get(display_id)
        if not info:
            continue
        fdid = model_fdid.get(info["model"], 0)
        path = paths.get(fdid, "")
        race = None
        gender = None
        if info["extra"] and info["extra"] in extra:
            e = extra[info["extra"]]
            race = CHR_RACES.get(e["race"])
            gender = "f" if e["sex"] == 1 else "m"
        if race is None and path:
            race = race_from_path(path)
        if gender is None:
            gender = GENDER_NAMES.get(info["gender"]) or gender_from_path(path)
            if gender == "n" and path:
                gender = gender_from_path(path) or "n"
        if race:
            return race, gender or "n", path
        if path:
            return "other", gender or "n", path
    return None, None, ""


# --------------------------------------------------------------------------
# Client creature cache (validation only)
# --------------------------------------------------------------------------

def read_wdb(path):
    """Return {entry: (name, [displayIDs])} from a modern creaturecache.wdb.

    The record payload layout is not documented, so the display IDs are found
    heuristically: a count (1..4) followed by a 1.0 float and then
    (displayID, scale, probability) triples.
    """
    data = open(path, "rb").read()
    if data[:4] != b"BOMW":
        raise ValueError("not a creaturecache.wdb")
    pos = 0x18  # header: magic, build, locale, 3 x uint32
    out = {}
    while pos + 8 <= len(data):
        entry, size = struct.unpack_from("<II", data, pos)
        pos += 8
        if entry == 0 and size == 0:
            break
        payload = data[pos:pos + size]
        pos += size
        m = re.search(rb"[\x20-\x7e]{2,}\x00", payload)
        name = m.group(0)[:-1].decode("ascii", "replace") if m else "?"
        displays = []
        # Payloads are not 4-byte aligned after the variable length strings.
        for off in range(0, len(payload) - 20):
            count = struct.unpack_from("<I", payload, off)[0]
            if not 1 <= count <= 4:
                continue
            if struct.unpack_from("<f", payload, off + 4)[0] != 1.0:
                continue
            ids = []
            ok = True
            for k in range(count):
                base = off + 8 + k * 12
                if base + 12 > len(payload):
                    ok = False
                    break
                did, scale, prob = struct.unpack_from("<Iff", payload, base)
                if did == 0 or did > 200000 or not (0 < scale < 20) or not (0 <= prob <= 1):
                    ok = False
                    break
                ids.append(did)
            if ok and ids:
                displays = ids
                break
        out[entry] = (name, displays)
    return out


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def write_lua(out_path, table):
    groups = defaultdict(list)
    for entry, (race, gender) in table.items():
        groups[f"{race}_{gender}"].append(entry)
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by Tools/extract_npc_voices.py. Do not edit by hand.\n")
        fh.write("-- NPC ID lists per race and gender for the Voice Over module.\n")
        fh.write("-- Sources: cmangos classic-db, wago.tools DB2 exports, wowdev listfile.\n\n")
        fh.write("MelloUI_NPCVoiceData = {\n")
        for key in sorted(groups):
            ids = sorted(groups[key])
            fh.write(f'\t["{key}"] = "')
            line_len = 0
            for i, entry in enumerate(ids):
                s = f"{entry} "
                fh.write(s)
                line_len += len(s)
                if line_len > 110 and i < len(ids) - 1:
                    fh.write('"\n\t\t.. "')
                    line_len = 0
            fh.write('",\n')
        fh.write("}\n")
    log(f"wrote {out_path}: {len(table)} NPCs in {len(groups)} groups")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=CACHE)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "Media", "NPCVoiceData.lua"))
    ap.add_argument("--build", default="1.15.9.69722", help="Classic Era build for the wago.tools DB2 exports")
    ap.add_argument("--retail-build", default="12.1.0.69814",
                    help="retail build used as a fallback for display IDs missing from Classic Era (\"none\" to skip)")
    ap.add_argument("--wdb", default="F:/World of Warcraft/_classic_beta_/Cache/WDB/enUS/creaturecache.wdb",
                    help="creaturecache.wdb from the Forever client; NPCs seen in game that are not in the vanilla DB are added from it")
    ap.add_argument("--report", default=None, help="write a CSV with every NPC, its model path and classification")
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)

    sql = fetch(CMANGOS_SQL, os.path.join(args.cache, "ClassicDB.sql.gz"))
    listfile = fetch(LISTFILE, os.path.join(args.cache, "verified-listfile.csv"))
    npcs = load_creature_template(sql)
    display, model_fdid, extra = load_db2(args.cache, args.build)
    if args.retail_build and args.retail_build.lower() != "none":
        r_display, r_model_fdid, r_extra = load_db2(args.cache, args.retail_build)
        # Classic Era rows win; retail only fills in IDs it does not have.
        for k, v in r_display.items():
            display.setdefault(k, v)
        for k, v in r_model_fdid.items():
            model_fdid.setdefault(k, v)
        for k, v in r_extra.items():
            extra.setdefault(k, v)
    paths = load_listfile(listfile)

    table = {}
    stats = Counter()
    report = []
    for entry, npc in sorted(npcs.items()):
        race, gender, path = classify(npc, display, model_fdid, extra, paths)
        if race:
            table[entry] = (race, gender)
            stats[race] += 1
        else:
            stats["<unresolved>"] += 1
        report.append((entry, npc["name"], npc["models"][:1], path, race or "", gender or ""))

    log("classification:")
    for race, n in stats.most_common():
        log(f"  {race:14s} {n}")

    if args.report:
        with open(args.report, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["entry", "name", "display", "model", "race", "gender"])
            for row in report:
                w.writerow([row[0], row[1], row[2][0] if row[2] else "", row[3], row[4], row[5]])
        log(f"wrote report {args.report}")

    if args.wdb and os.path.exists(args.wdb):
        seen = read_wdb(args.wdb)
        same = missing = differ = added = 0
        for entry, (name, displays) in seen.items():
            npc = npcs.get(entry)
            if not npc:
                missing += 1
                race, gender, path = classify({"models": displays}, display, model_fdid, extra, paths)
                if race:
                    added += 1
                    table[entry] = (race, gender)
                    log(f"  added from client cache: {entry} {name} -> {race} {gender} ({path})")
                else:
                    log(f"  unresolved (new Forever NPC): {entry} {name} displays={displays}")
            elif displays and npc["models"] and displays[0] in npc["models"]:
                same += 1
            elif displays:
                differ += 1
                log(f"  display differs: {entry} {name} client={displays} vanilla={npc['models']}")
            else:
                same += 1
        log(f"client cache: {len(seen)} NPCs seen, {same} match vanilla, {differ} differ, "
            f"{missing} not in vanilla DB of which {added} resolved from display tables")

    write_lua(os.path.abspath(args.out), table)


if __name__ == "__main__":
    main()
