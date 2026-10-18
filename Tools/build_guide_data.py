#!/usr/bin/env python3
"""
Build MelloUI_Guide/GuideOpenData.lua for the leveling guide (MelloUI_Guide):
the open tables its planner and XP estimates read, from open sources only.

Sources:
  wago.tools DB2 exports, build 1.60.1.70425 (WoW: Forever)
                            QuestLine, QuestLineXQuest   the client's quest lines and their order
                            QuestXP                      quest XP by quest level and difficulty
                            https://wago.tools/db2/<Table>/csv?build=1.60.1.70425
  cmangos classic-db        quest_template (the creatures quest objectives name: ReqCreatureOrGOId1-4)
  (GPL v3)                  creature_template (MinLevel, MaxLevel, Rank) -- vanilla 1.12 facts, so the
                            levels are vanilla's where Forever changed them
                            https://github.com/cmangos/classic-db

The game content in both (quest lines, XP values, creature levels) is
Blizzard Entertainment's. Nothing here comes from Wowhead, and nothing from
MelloUI's own quest tables (Media/QuestListData.lua, the Companion's
objective data): the guide reads those at runtime, in the client, and
derives what it needs there; this file holds only what the open sources say.

What is kept:
  questLines   [lineID] = { questIDs in OrderIndex order }; only the lines
               QuestLine lists (a QuestLineXQuest row of an unknown line is
               dropped); no names, the guide needs the order only
  questXP      [level] = { [difficulty] = xp }, difficulties 0 to 9
  creatures    [npcID] = { minLevel, maxLevel, elite }: every creature a
               classic-db quest objective names (a positive
               ReqCreatureOrGOId; negative ones are objects) whose MinLevel
               is 35 or below; elite is Rank 1 (elite), 2 (rare elite) or
               3 (boss). Creatures that only drop a quest's items are not
               in it (yet)

Usage:
  python -I Tools/build_guide_data.py [--cache DIR] [--out MelloUI_Guide/GuideOpenData.lua]

The downloads go into --cache (default: the MelloUI-BuildData cache, as the
other tools'), and a file already there is used as it is, so the tool
downloads once. Standard library only; it prints the row counts.
"""

import argparse
import csv
import gzip
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)

BUILD = "1.60.1.70425"          # WoW: Forever, the build the simulator's data pack is
WAGO_CSV = "https://wago.tools/db2/{table}/csv?build={build}"
CMANGOS_SQL = "https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
MAX_CREATURE_LEVEL = 35         # the demo's range (1 to 30) and a little beyond
ELITE_RANKS = {1, 2, 3}         # creature_template.Rank: 1 elite, 2 rare elite, 3 boss (4 rare is not elite)
LIMIT_BYTES = 300 * 1024        # the file must stay small: it loads with the addon


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def fetch(url, dest):
    """The file at dest, downloaded from url when it is not there yet."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    log(f"downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "MelloUI-guide-data/1.0"})
    tmp = dest + ".part"
    with urllib.request.urlopen(req) as resp, open(tmp, "wb") as fh:
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
    os.replace(tmp, dest)
    return dest


# ---------------------------------------------------------------------------
# wago.tools

def wago_rows(cache, table):
    path = fetch(WAGO_CSV.format(table=table, build=BUILD), os.path.join(cache, f"{table}_{BUILD}.csv"))
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def to_int(v, default=0):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def quest_lines(cache):
    """[lineID] = [questIDs] in OrderIndex order, for the lines QuestLine has."""
    known = {to_int(r["ID"]) for r in wago_rows(cache, "QuestLine")}
    members, dropped = {}, 0
    for r in wago_rows(cache, "QuestLineXQuest"):
        line, quest = to_int(r["QuestLineID"]), to_int(r["QuestID"])
        if line not in known or quest <= 0:
            dropped += 1
            continue
        members.setdefault(line, []).append((to_int(r["OrderIndex"]), quest))
    lines = {line: [q for _, q in sorted(rows)] for line, rows in members.items()}
    return lines, len(known), dropped


def quest_xp(cache):
    """[level] = [xp of difficulty 0 .. 9]."""
    table = {}
    for r in wago_rows(cache, "QuestXP"):
        level = to_int(r["ID"])
        if level > 0:
            table[level] = [to_int(r.get(f"Difficulty_{d}")) for d in range(10)]
    return table


# ---------------------------------------------------------------------------
# cmangos classic-db: a MySQL dump, read as text (never run)

def sql_values(body):
    """The rows of an INSERT's VALUES body as lists of str / None."""
    i, n = 0, len(body)
    while i < n:
        if body[i] != "(":
            i += 1
            continue
        i += 1
        row, cur, quoted = [], [], False
        while i < n:
            c = body[i]
            if c == "'":
                i += 1
                while i < n:
                    c = body[i]
                    if c == "\\" and i + 1 < n:
                        cur.append(body[i + 1])
                        i += 2
                        continue
                    if c == "'":
                        if i + 1 < n and body[i + 1] == "'":
                            cur.append("'")
                            i += 2
                            continue
                        break
                    cur.append(c)
                    i += 1
                quoted = True
                i += 1
                continue
            if c == "," or c == ")":
                text = "".join(cur)
                row.append(text if quoted else (None if text.strip().upper() == "NULL" else text.strip()))
                cur, quoted = [], False
                i += 1
                if c == ")":
                    break
                continue
            cur.append(c)
            i += 1
        yield row


def cmangos_tables(path, wanted):
    """{table: [row dicts]} for the wanted tables, in one pass over the dump."""
    columns = {t: [] for t in wanted}
    rows = {t: [] for t in wanted}
    creating = None
    insert = re.compile(r"INSERT INTO `(\w+)` VALUES ")
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if creating:
                m = re.match(r"\s*`(\w+)`", line)
                if m:
                    columns[creating].append(m.group(1).lower())
                elif line.startswith(")"):
                    creating = None
                continue
            m = re.match(r"CREATE TABLE `(\w+)`", line)
            if m and m.group(1) in wanted:
                creating = m.group(1)
                columns[creating] = []
                continue
            m = insert.match(line)
            if m and m.group(1) in wanted:
                cols = columns[m.group(1)]
                for values in sql_values(line[m.end():]):
                    rows[m.group(1)].append(dict(zip(cols, values)))
    return rows


def creatures(cache):
    """[npcID] = (minLevel, maxLevel, elite) for the creatures quest objectives name."""
    path = fetch(CMANGOS_SQL, os.path.join(cache, "ClassicDB.sql.gz"))
    log("reading cmangos quest_template and creature_template")
    t = cmangos_tables(path, {"quest_template", "creature_template"})
    named = set()
    for q in t["quest_template"]:
        for k in range(1, 5):
            npc = to_int(q.get(f"reqcreatureorgoid{k}"))
            if npc > 0:
                named.add(npc)
    out, high, unknown = {}, 0, 0
    template = {to_int(c.get("entry")): c for c in t["creature_template"]}
    for npc in named:
        c = template.get(npc)
        if not c:
            unknown += 1
            continue
        lo, hi = to_int(c.get("minlevel")), to_int(c.get("maxlevel"))
        if lo > MAX_CREATURE_LEVEL:
            high += 1
            continue
        out[npc] = (lo, max(lo, hi), to_int(c.get("rank")) in ELITE_RANKS)
    stats = {"quests": len(t["quest_template"]), "templates": len(t["creature_template"]),
             "named": len(named), "above": high, "unknown": unknown}
    return out, stats


# ---------------------------------------------------------------------------
# GuideOpenData.lua

def write_lua(path, lines, xp, mobs):
    out = [
        "-- Generated by Tools/build_guide_data.py. Do not edit by hand.",
        f"-- Sources: wago.tools DB2 exports of WoW: Forever {BUILD} (QuestLine, QuestLineXQuest, QuestXP) and",
        "-- cmangos classic-db (GPL v3: quest_template objectives, creature_template levels and rank). The game",
        "-- content is Blizzard Entertainment's. Nothing from Wowhead, nothing from MelloUI's quest tables.",
        "-- questLines: [lineID] = { questIDs in order }",
        "-- questXP: [level] = { [difficulty] = xp }, difficulties 0 to 9",
        f"-- creatures: [npcID] = {{ minLevel, maxLevel, elite }}, the creatures quest objectives name, level {MAX_CREATURE_LEVEL} and below",
        "",
        "local _, ns = ...",
        "",
        "MelloUI_GuideOpenData = {",
        "\tquestLines = {",
    ]
    for line in sorted(lines):
        out.append(f"\t\t[{line}] = {{ {', '.join(str(q) for q in lines[line])} }},")
    out.append("\t},")
    out.append("\tquestXP = {")
    for level in sorted(xp):
        v = xp[level]
        out.append(f"\t\t[{level}] = {{ [0] = {v[0]}, {', '.join(str(x) for x in v[1:])} }},")
    out.append("\t},")
    out.append("\tcreatures = {")
    for npc in sorted(mobs):
        lo, hi, elite = mobs[npc]
        out.append(f"\t\t[{npc}] = {{ minLevel = {lo}, maxLevel = {hi}, elite = {'true' if elite else 'false'} }},")
    out.append("\t},")
    out.append("}")
    out.append("")
    out.append("if ns then ns.OpenData = MelloUI_GuideOpenData end")
    out.append("")
    text = "\n".join(out)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return len(text.encode("utf-8"))


def default_cache():
    sys.path.insert(0, HERE)
    from paths import CACHE  # Mello's own tool module: the MelloUI-BuildData cache
    return CACHE


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--cache", help="where the downloads are kept (default: the MelloUI-BuildData cache)")
    ap.add_argument("--out", default=os.path.join(ADDON, "MelloUI_Guide", "GuideOpenData.lua"))
    args = ap.parse_args()
    cache = args.cache or default_cache()
    os.makedirs(cache, exist_ok=True)

    lines, known, dropped = quest_lines(cache)
    xp = quest_xp(cache)
    mobs, st = creatures(cache)
    size = write_lua(args.out, lines, xp, mobs)

    print(f"QuestLine: {known} lines; QuestLineXQuest: {sum(len(v) for v in lines.values())} quests kept in "
          f"{len(lines)} lines, {dropped} rows dropped")
    print(f"QuestXP: {len(xp)} levels x 10 difficulties")
    print(f"cmangos: {st['quests']} quests, {st['templates']} creature templates; {st['named']} creatures named by "
          f"objectives, {len(mobs)} kept (level {MAX_CREATURE_LEVEL} and below), {st['above']} above, "
          f"{st['unknown']} without a template; {sum(1 for m in mobs.values() if m[2])} elite")
    print(f"wrote {args.out}: {size} bytes")
    if size > LIMIT_BYTES:
        print(f"too big: over {LIMIT_BYTES} bytes", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
