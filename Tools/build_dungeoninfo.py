"""Build MelloUI_DungeonInfo/DungeonInfoData.lua: Dungeon Info's dungeons and raids, their bosses in order and what
each boss drops (docs/plans/dungeon-info.md; the user, 2026-10-22).

Sources (all local):
  the dungeons and raids   MelloUI's quest data (Media/QuestListData.lua: `dungeons`, `raids`, `dungeonLevel`; their
                           key is the client's AreaTable id, the same the quests and the map's door pins use)
  the instance             the client's AreaTable (ContinentID) and Map (AreaTableID, InstanceType, MaxPlayers):
                           WoWExport/db2
  the bosses               the client's DungeonEncounter, by the instance's map in its OrderIndex
  the drops                the cmangos classic-db dump the quest data is built from (MelloUI-BuildData/cache/
                           ClassicDB.sql.gz): a boss's creature (its name among the creatures the dump spawns on that
                           map), its creature_loot_template rows -- a group's 0 an equal share of what its explicit
                           ones leave; a reference the dump names a world drop ("NPC LOOT") or many tables use is the
                           world's drops (left out), the others the boss's own; uncommon and better, and anything that starts a quest
  the item                 the dump's item_template (the client's ItemSparse lacks most classic items: the game streams
                           them): its English name (shown until the game knows the item), quality, required level
  the emblem               the client's Interface/LFGFrame/LFGIcon-<name> (the listfile): the name's own, else the file
                           holding its longest word, else the plain dungeon or raid one

    python Tools/build_dungeoninfo.py [--check]
"""
import csv
import gzip  # noqa: F401  (the dump is read by build_quest_list's sql_rows)
import importlib.util
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BUILD = os.path.join(os.path.dirname(REPO), "MelloUI-BuildData", "cache")
DB2 = "F:/Download-Backup/WoWExport/db2"
OUT = os.path.join(REPO, "MelloUI_DungeonInfo", "DungeonInfoData.lua")
SQL = os.path.join(BUILD, "ClassicDB.sql.gz")
LISTFILE = os.path.join(BUILD, "verified-listfile.csv")

spec = importlib.util.spec_from_file_location("bql", os.path.join(HERE, "build_quest_list.py"))
bql = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bql)

WORLD_REF_USERS = 40    # a reference used by more loot tables than this: the world's drops (as one the dump calls
                        # a world drop, "NPC LOOT (...)", whatever few use it: the level bands' blue drops)
MIN_QUALITY = 2         # uncommon and better (and quest starters)
MIN_CHANCE = 0.1        # %: rarer than this left out


def log(msg):
    print(msg, file=sys.stderr)


def read_csv(name):
    with open(os.path.join(DB2, name), encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def quest_data():
    """the quest data's dungeons and raids: {key: name}, {key: True}, {key: (lo, hi)}"""
    text = open(os.path.join(REPO, "Media", "QuestListData.lua"), encoding="utf-8").read()

    def block(name):
        i = text.index("\t%s = {" % name)
        j = text.index("\n\t},", i)
        return text[i:j]
    dungeons = {int(k): v for k, v in re.findall(r'\[(\d+)\] = "((?:[^"\\]|\\.)*)"', block("dungeons"))}
    raids = {int(k) for k in re.findall(r"\[(\d+)\] = true", block("raids"))}
    levels = {int(k): (int(a), int(b)) for k, a, b in re.findall(r"\[(\d+)\] = \{ (\d+), (\d+) \}", block("dungeonLevel"))}
    return dungeons, raids, levels


def door_keys():
    """the dungeon keys the quest data's `entrances` (the map's door pins) use"""
    text = open(os.path.join(REPO, "Media", "QuestListData.lua"), encoding="utf-8").read()
    i = text.index("\tentrances = {")
    j = text.index("\n\t},", i)
    return {int(k) for k in re.findall(r"\{(\d+),", text[i:j])}


def emblems():
    """the client's lfgicon file names (without the prefix and extension)"""
    names = []
    for line in open(LISTFILE, encoding="utf-8", errors="replace"):
        _, _, path = line.strip().partition(";")
        m = re.match(r"interface/lfgframe/lfgicon-([a-z0-9]+)\.blp$", path)
        if m:
            names.append(m.group(1))
    return names


def emblem_for(names, raid, files):
    """the client's emblem for the instance: one named as it is (exactly, or all but a letter: Zul'Farrak's is
    "zulfarak"), else the plain dungeon or raid one -- never a later instance's that shares a word with it"""
    import difflib
    for name in names:
        norm = re.sub(r"[^a-z]", "", re.sub(r"^the\s+", "", name.lower()))
        if norm in files:
            return norm
        close = difflib.get_close_matches(norm, files, n=1, cutoff=0.88)
        if close:
            return close[0]
    return "raid" if raid else "dungeon"


def main(check):
    dungeons, raids, levels = quest_data()
    files = set(emblems())
    areas = {int(r["ID"]): r for r in read_csv("AreaTable.csv")}
    maps = {int(r["ID"]): r for r in read_csv("Map.csv")}
    by_area = {}
    for mid, r in maps.items():
        if int(r["InstanceType"] or 0) in (1, 2) and int(r["AreaTableID"] or 0):
            by_area.setdefault(int(r["AreaTableID"]), mid)
    encounters = defaultdict(list)
    for r in read_csv("DungeonEncounter.csv"):
        encounters[int(r["MapID"])].append(r)

    # the quest keys by instance map: one instance a map, every key of it kept (the quests of each are its quests;
    # Nightmare Grove's keys are the four dragons' zones, Blackrock Depths has two)
    keys_of = defaultdict(list)
    for key, name in sorted(dungeons.items()):
        a = areas.get(key)
        mid = int(a["ContinentID"]) if a else 0
        if not (mid in maps and int(maps[mid]["InstanceType"] or 0) in (1, 2)):
            mid = by_area.get(key, 0)
        if not mid:
            log("no instance map for %d %s" % (key, name))
            continue
        keys_of[mid].append(key)
    doors = door_keys()
    instances = []
    for mid, keys in sorted(keys_of.items(), key=lambda kv: min(kv[1])):
        m = maps[mid]
        # its key: the one the map's door pins use, else the map's own area, else the first
        key = next((k for k in keys if k in doors), None) or (int(m["AreaTableID"] or 0) if int(m["AreaTableID"] or 0) in keys else keys[0])
        # its name: the quest data's for its door's key (or its only key); the map's own when several share it and
        # none is a door's (Nightmare Grove: its keys are the dragons' zones)
        name = dungeons[key] if (key in doors or len(keys) == 1) else m["MapName_lang"]
        raid = key in raids or int(m["InstanceType"]) == 2
        lo, hi = levels.get(key, (0, 0))
        if not lo:
            for k in keys:
                klo, khi = levels.get(k, (0, 0))
                if klo and (not lo or klo < lo):
                    lo = klo
                hi = max(hi, khi)
        bosses = sorted(encounters.get(mid, []), key=lambda r: int(r["OrderIndex"]))
        instances.append({"key": key, "keys": sorted(keys), "map": mid, "raid": raid, "name": name, "lo": lo, "hi": hi,
                          "players": int(m["MaxPlayers"] or 0),
                          "emblem": emblem_for([name, m["MapName_lang"], dungeons[key]], raid, files),
                          "bosses": [(int(b["ID"]), b["Name_lang"]) for b in bosses]})
    log("%d instances, %d bosses" % (len(instances), sum(len(i["bosses"]) for i in instances)))

    # the bosses' creatures: by name among the creatures spawned on the instance's map
    want_maps = {i["map"] for i in instances}
    spawned = defaultdict(set)   # map -> creature entries
    for r in bql.sql_rows(SQL, "creature"):
        if int(r["map"]) in want_maps:
            spawned[int(r["map"])].add(int(r["id"]))
    names = {}
    loot_ids = {}
    for r in bql.sql_rows(SQL, "creature_template"):
        e = int(r["Entry"])
        names[e] = r["Name"]
        loot_ids[e] = int(r["LootId"] or 0)
    by_name = defaultdict(dict)   # map -> name -> [entries]
    for mid, ents in spawned.items():
        for e in ents:
            by_name[mid].setdefault(names.get(e, ""), []).append(e)
    every = defaultdict(list)   # name -> entries, the whole dump (a boss that is not spawned: summoned in his fight)
    for e, n in names.items():
        every[n].append(e)
    want_loot = set()
    boss_loot = {}
    for inst in instances:
        for enc_id, bname in inst["bosses"]:
            ents = list(by_name[inst["map"]].get(bname, []))
            if not ents and len(every.get(bname, [])) <= 3:
                ents = list(every.get(bname, []))
            # (what he brings to his fight: "Sneed's Shredder", on the same map)
            for n, es in by_name[inst["map"]].items():
                if n.startswith(bname + "'s "):
                    ents += es
            lids = sorted({loot_ids[e] for e in ents if loot_ids.get(e)})
            boss_loot[enc_id] = lids
            want_loot.update(lids)
    loot = defaultdict(list)
    ref_users = defaultdict(int)
    world = set()   # the references the dump names a world drop (its NPC LOOT tables)
    for r in bql.sql_rows(SQL, "creature_loot_template"):
        ref = int(r["mincountOrRef"])
        if ref < 0:
            ref_users[-ref] += 1
            if "NPC LOOT" in (r.get("comments") or "") or "World Drop" in (r.get("comments") or ""):
                world.add(-ref)
        if int(r["entry"]) in want_loot:
            loot[int(r["entry"])].append(r)
    refs = {-int(r["mincountOrRef"]) for rows in loot.values() for r in rows if int(r["mincountOrRef"]) < 0}
    ref_rows = defaultdict(list)
    for r in bql.sql_rows(SQL, "reference_loot_template"):
        if int(r["entry"]) in refs:
            ref_rows[int(r["entry"])].append(r)
    items = {}
    for r in bql.sql_rows(SQL, "item_template"):
        items[int(r["entry"])] = (r["name"], int(r["Quality"] or 0), int(r["RequiredLevel"] or 0),
                                  int(r["startquest"] or 0))

    def shares(rows):
        explicit, zeros = defaultdict(float), defaultdict(int)
        for r in rows:
            g, c = int(r["groupid"]), float(r["ChanceOrQuestChance"])
            if c > 0:
                explicit[g] += c
            elif g > 0:
                zeros[g] += 1
        for r in rows:
            g, c = int(r["groupid"]), float(r["ChanceOrQuestChance"])
            if c == 0 and g > 0:
                c = max(0.0, 100.0 - explicit[g]) / zeros[g]
            yield r, c

    def drops_of(lid):
        out = {}
        for r, c in shares(loot[lid]):
            ref = int(r["mincountOrRef"])
            if ref < 0:
                if -ref in world or ref_users[-ref] > WORLD_REF_USERS:
                    continue
                for rr, cc in shares(ref_rows[-ref]):
                    out[int(rr["item"])] = out.get(int(rr["item"]), 0) + cc * (c or 100) / 100
            elif c > 0:
                out[int(r["item"])] = out.get(int(r["item"]), 0) + c
        return out

    for inst in instances:
        full = []
        for enc_id, bname in inst["bosses"]:
            got = {}
            for lid in boss_loot.get(enc_id, []):
                for item, c in drops_of(lid).items():
                    got[item] = max(got.get(item, 0), c)
            drops = []
            for item, c in got.items():
                it = items.get(item)
                if not it or c < MIN_CHANCE:
                    continue
                iname, quality, req, starts = it
                if quality < MIN_QUALITY and not starts:
                    continue
                drops.append((item, c, quality, iname, req, starts))
            drops.sort(key=lambda d: (-d[2], -d[1], d[3]))
            full.append((enc_id, bname, drops))
        inst["bosses"] = full

    lines = ["-- Generated by Tools/build_dungeoninfo.py. Do not edit by hand.",
             "-- Sources: MelloUI's quest data (the dungeons, their levels), the client's AreaTable, Map and DungeonEncounter",
             "-- (the instances, the bosses in order), the cmangos classic-db (the drops, the items).",
             "-- luacheck: globals MelloUI_DungeonInfoData",
             "MelloUI_DungeonInfoData = {",
             "\t-- [key] = { map, kind (1 dungeon, 2 raid), name, level from, level to, players, emblem (LFGIcon-<it>),",
             "\t--   every quest key of it (the quest data's dungeon keys: its quests), bosses: { { encounter id, name,",
             "\t--   drops: { item, chance (tenths of a percent), quality, name, required level, quest it starts (0 none),",
             "\t--   ... } }, ... } }; key: the quest data's dungeon key (AreaTable id) its door pins use",
             "\tinstances = {"]

    def q(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    for inst in instances:
        lines.append("\t\t[%d] = { %d, %d, %s, %d, %d, %d, %s, { %s }, {" % (
            inst["key"], inst["map"], 2 if inst["raid"] else 1, q(inst["name"]), inst["lo"], inst["hi"],
            inst["players"], q(inst["emblem"]), ", ".join(str(k) for k in inst["keys"])))
        for enc_id, bname, drops in inst["bosses"]:
            flat = ", ".join("%d,%d,%d,%s,%d,%d" % (d[0], int(round(d[1] * 10)), d[2], q(d[3]), d[4], d[5])
                             for d in drops)
            lines.append("\t\t\t{ %d, %s, { %s } }," % (enc_id, q(bname), flat))
        lines.append("\t\t} },")
    lines += ["\t},", "}", ""]
    text = "\n".join(lines)
    if check:
        old = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if old != text:
            sys.exit("DungeonInfoData.lua is out of date: run python Tools/build_dungeoninfo.py")
        print("DungeonInfoData.lua is up to date")
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    n_drops = sum(len(b[2]) for i in instances for b in i["bosses"])
    print("wrote %s: %d instances, %d bosses, %d drops, %d KB" % (
        os.path.relpath(OUT, REPO), len(instances), sum(len(i["bosses"]) for i in instances), n_drops, len(text) // 1024))


if __name__ == "__main__":
    main("--check" in sys.argv)
