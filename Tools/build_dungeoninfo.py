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
  (1.2.2) the trash        the dump's other creatures on the instance's map: their rare drops (TRASH_*)
  (1.2.2) the picture      an instance with no LFG picture: its loading screen (LoadingScreens; picture_for)
  (1.2.2) Forever's loot   Everloot's open data (player-collected, CC BY-SA 4.0, credited in the data file): its
                           drop rates by boss and creature, fetched with --everloot into the build data's cache
  (1.2.2) seen in game     the players' /dungeoninfo exports in MelloUI-BuildData/dungeoninfo_seen (read_seen)

    python Tools/build_dungeoninfo.py [--check] [--everloot]
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
# (1.2.2, the user: "we also need to have information about the trash mobs loot since some of them drop valuable
# loot") the trash's drops: rare and better and quest starters (their pick "Blue and better"), what any of the
# instance's other creatures drops; a valuable trash drop is rare, so down to a hundredth of a percent
TRASH_QUALITY = 3
TRASH_MIN_CHANCE = 0.01
TRASH_MOBS = 3          # the creatures named with a trash drop (the likeliest first)

# (1.2.2, the user: "the pictures of wow forever specific dungeons are missing") an instance with no picture of its
# own in the client's LFG art gets its loading screen (Map.LoadingScreenID -> LoadingScreens): the file shown by its
# number in game, nothing of it shipped. Kind 1: Forever's own (its MainImageFileDataID, 2992 x 1684, the painting
# in rows 0.158 - 0.842, measured on the exports); kind 2: a classic one (NarrowScreenFileDataID, 2048 x 2048
# shown 4:3, the logo above and the frame below the painting, which fills 0.22 - 0.78). Files the Forever client does
# not have (Season of Discovery's: none exports) give way to the continent's own Forever loading screen.
FOREVER_SCREENS = {7950679, 7963775, 7963776, 7963777, 7963779, 7963781, 7963782, 8423398}
CLASSIC_SCREEN_MAX = 1000000   # a classic file number (the 131xxx loading screens): in every client
CONTINENT_SCREEN = {0: 7963776, 1: 7963779}   # Eastern Kingdoms, Kalimdor (LoadingScreens 4 and 3)
# (1.2.2, the user: "some are missing, some have their artwork streched") every instance's picture is a file and its
# kind, the page cutting the box's shape out of the kind's painted area: its own LFG background first (kind 3: 256 x
# 128, painted whole), else its loading screen (kinds 1 and 2), else the game's own pictures for a place it has none
# of: Random Dungeon's door for a dungeon, Heroic Scenario's skull crest for a raid (both 2:1, painted whole)
LFG_BACKGROUND = "interface/lfgframe/ui-lfg-background-"
GENERIC_PICTURE = {False: 337493, True: 851369}   # randomdungeon, heroicscenario


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
    """the dungeon keys the quest data's `entrances` (the map's door pins) use: {key: continent}"""
    text = open(os.path.join(REPO, "Media", "QuestListData.lua"), encoding="utf-8").read()
    i = text.index("\tentrances = {")
    j = text.index("\n\t},", i)
    return {int(k): int(c) for k, c in re.findall(r'\{(\d+),"(?:[^"\\]|\\.)*",(-?\d+),', text[i:j])}


SEEN_DIR = os.path.join(os.path.dirname(REPO), "MelloUI-BuildData", "dungeoninfo_seen")

# (1.2.2, the user: "the new dungeons still dont have their loot drops"; Forever's dungeon loot is in neither client
# nor hotfix: every list is collected from players. Their pick: Everloot, with its credit) Everloot's open data
# (https://everloot.app, CC BY-SA 4.0: player-collected, a fact only once 3 installs agree): its published drop
# rates (a share of the loot windows opened on a creature) and its bosses (an encounter's boss creatures). Fetched by
# `--everloot` into the build data's cache (checked against its manifest), read from the newest cached export by
# every build. Its rows stay CC BY-SA 4.0 in the data file, with EVERLOOT_CREDIT beside them.
EVERLOOT_URL = "https://data.everloot.app"
EVERLOOT_DIR = os.path.join(BUILD, "everloot")
EVERLOOT_CREDIT = "Data from Everloot (https://everloot.app), CC BY-SA 4.0."
EVERLOOT_FILES = ("observed/drop-rates.ndjson", "observed/bosses.ndjson", "observed/npcs.ndjson")


# (1.2.2, the user's pick) DungeonMaster's hand-curated boss loot (by MalkDev, CurseForge 1711748, GPL-3.0 like the
# classic-db our data is under): Forever's own dungeons' bosses and its corrected lists for the classic dungeons
# Forever changed. Its Curated.lua (ns.curatedDungeons: [instance map] = { order = { names in kill order },
# bosses = { [name] = { npcID, rare, loot = { items } } } }) is kept by hand in the build data's cache, a folder a
# version: download its zip from CurseForge, put Curated.lua, README.md and its TOC in DM_DIR/<version>/.
DM_DIR = os.path.join(BUILD, "dungeonmaster")
DM_CREDIT = "DungeonMaster by MalkDev (https://www.curseforge.com/wow/addons/dungeonmaster), GPL-3.0."


def read_dungeonmaster():
    """the newest cached DungeonMaster: (version or None, {instance map: {"order": [names], "bosses": {name: {"npc",
    "rare", "loot": [items]}}}})"""
    if not os.path.isdir(DM_DIR):
        return None, {}
    versions = sorted((d for d in os.listdir(DM_DIR) if os.path.isfile(os.path.join(DM_DIR, d, "Curated.lua"))),
                      key=lambda v: [int(x) if x.isdigit() else x for x in re.split(r"[.-]", v)])
    if not versions:
        return None, {}
    text = open(os.path.join(DM_DIR, versions[-1], "Curated.lua"), encoding="utf-8").read()
    i = text.index("ns.curatedDungeons = {")
    block = text[i:text.index("\n}", i)]
    out = {}
    for line in block.split("\n"):
        m = re.match(r"^\s*\[(\d+)\] = \{(.*)\},?\s*(?:--.*)?$", line)
        if not m:
            continue
        body = m.group(2)
        om = re.search(r"order = \{([^{}]*)\}", body)
        order = re.findall(r'"((?:[^"\\]|\\.)*)"', om.group(1)) if om else []
        bosses = {}
        for bm in re.finditer(r'\["((?:[^"\\]|\\.)*)"\] = \{([^{}]*?)loot = \{([\d,\s]*)\}', body):
            fields = bm.group(2)
            npc = re.search(r"npcID = (\d+)", fields)
            bosses[bm.group(1)] = {"npc": int(npc.group(1)) if npc else 0, "rare": "rare = true" in fields,
                                   "loot": [int(x) for x in re.findall(r"\d+", bm.group(3))]}
        if bosses:
            out[int(m.group(1))] = {"order": order, "bosses": bosses}
    return versions[-1], out


def norm_name(s):
    """a name compared: lower case, no leading "the", letters and digits only"""
    s = re.sub(r"^the\s+", "", (s or "").lower())
    return re.sub(r"[^a-z0-9]", "", s)


def fetch_everloot():
    """Everloot's newest open-data export into EVERLOOT_DIR/<stamp>/ (each file checked against the manifest's
    byte count and sha256); False when there is none yet (the cache kept as it is)"""
    import hashlib
    import json
    import urllib.error
    import urllib.request

    def get(path):
        req = urllib.request.Request(EVERLOOT_URL + "/" + path, headers={"User-Agent": "MelloUI build_dungeoninfo"})
        with urllib.request.urlopen(req, timeout=60) as res:
            return res.read()
    try:
        latest = json.loads(get("open-data/latest.json"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            log("Everloot has published no open-data export yet: the cached one (if any) is kept")
            return False
        raise
    stamp, manifest_path = latest["stamp"], latest["manifest"]
    if not re.match(r"^[\w.-]+$", stamp) or not manifest_path.startswith("open-data/"):
        sys.exit("Everloot's latest.json looks wrong: %r" % latest)
    manifest = json.loads(get(manifest_path))
    folder = os.path.join(EVERLOOT_DIR, stamp)
    os.makedirs(os.path.join(folder, "observed"), exist_ok=True)
    base = manifest_path.rsplit("/", 1)[0]
    by_path = {f["path"]: f for f in manifest["files"]}
    for path in EVERLOOT_FILES:
        f = by_path.get(path)
        if not f:
            log("Everloot's export has no %s" % path)
            continue
        body = get(base + "/" + path)
        if len(body) != f["bytes"] or hashlib.sha256(body).hexdigest() != f["sha256"]:
            sys.exit("Everloot's %s does not match its manifest: nothing kept" % path)
        with open(os.path.join(folder, path), "wb") as fh:
            fh.write(body)
    with open(os.path.join(folder, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1)
    log("Everloot export %s cached (%s)" % (stamp, ", ".join("%s %s rows" % (p, by_path[p]["rows"]) for p in EVERLOOT_FILES if p in by_path)))
    return True


def read_everloot():
    """the newest cached Everloot export: (stamp or None, boss npc -> (instance map, encounter), drop rows by npc
    {npc: [(item, rate, windows)]}, npc names {npc: name})"""
    import json
    if not os.path.isdir(EVERLOOT_DIR):
        return None, {}, {}, {}
    stamps = sorted(d for d in os.listdir(EVERLOOT_DIR) if os.path.isfile(os.path.join(EVERLOOT_DIR, d, "manifest.json")))
    if not stamps:
        return None, {}, {}, {}
    folder = os.path.join(EVERLOOT_DIR, stamps[-1])

    def rows(path):
        p = os.path.join(folder, path)
        if not os.path.exists(p):
            return []
        return [json.loads(line) for line in open(p, encoding="utf-8") if line.strip()]
    bosses = {}
    for r in rows("observed/bosses.ndjson"):
        for n in r.get("npcIds") or []:
            if isinstance(n, dict) and isinstance(n.get("npcId"), int):
                bosses[n["npcId"]] = (int(r["instanceMapId"]), int(r["encounterId"]))
    drops = defaultdict(list)
    for r in rows("observed/drop-rates.ndjson"):
        npc = r.get("sourceNpcId")
        if isinstance(npc, int) and isinstance(r.get("itemId"), int) and isinstance(r.get("rate"), (int, float)):
            drops[npc].append((r["itemId"], float(r["rate"]), int(r.get("lootWindows") or 0)))
    names = {r["npcId"]: r["name"] for r in rows("observed/npcs.ndjson") if isinstance(r.get("npcId"), int) and r.get("name")}
    return stamps[-1], bosses, drops, names


def read_seen():
    """(1.2.2) the drops players have seen and sent in (`/dungeoninfo export`, pasted into text files in
    MelloUI-BuildData/dungeoninfo_seen): each player's newest export (by its id; the files read in name order, an
    export later in them replacing an earlier one of the same id), all players' counts added up.
    -> boss {enc: [kills, {item: [times, q]}]}, mob {npc: [key, name, corpses, {item: [times, q]}]}, roll {key: {item: [times, q]}}"""
    exports = {}
    if os.path.isdir(SEEN_DIR):
        for name in sorted(os.listdir(SEEN_DIR)):
            if not name.lower().endswith(".txt"):
                continue
            cur = None
            for line in open(os.path.join(SEEN_DIR, name), encoding="utf-8", errors="replace"):
                line = line.strip()
                m = re.match(r"^MDI1 ([0-9a-f]{6,16}) ", line)
                if m:
                    cur = {"B": [], "M": [], "R": []}
                    exports[m.group(1)] = cur
                elif line == "END":
                    cur = None
                elif cur is not None and line[:2] in ("B ", "M ", "R "):
                    cur[line[0]].append(line[2:])

    def items(text):
        out = {}
        for part in text.split():
            m = re.match(r"^(\d+):(\d+):(\d+)$", part)
            if m:
                out[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
        return out
    boss, mob, roll = {}, {}, {}
    for ex in exports.values():
        for line in ex["B"]:
            m = re.match(r"^(\d+) (\d+)\s*(.*)$", line)
            if not m:
                continue
            b = boss.setdefault(int(m.group(1)), [0, {}])
            b[0] += int(m.group(2))
            for item, (t, q) in items(m.group(3)).items():
                b[1][item] = [b[1].get(item, [0, q])[0] + t, q]
        for line in ex["M"]:
            m = re.match(r"^(\d+) (\d+) (\d+)\s*([^|]*)\|(.*)$", line)
            if not m:
                continue
            o = mob.setdefault(int(m.group(2)), [int(m.group(1)), "", 0, {}])
            o[1] = o[1] or m.group(5).strip()
            o[2] += int(m.group(3))
            for item, (t, q) in items(m.group(4)).items():
                o[3][item] = [o[3].get(item, [0, q])[0] + t, q]
        for line in ex["R"]:
            m = re.match(r"^(\d+)\s*(.*)$", line)
            if not m:
                continue
            r = roll.setdefault(int(m.group(1)), {})
            for item, (t, q) in items(m.group(2)).items():
                r[item] = [r.get(item, [0, q])[0] + t, q]
    return boss, mob, roll, len(exports)


def picture_for(m, keys, doors, screens):
    """an instance's loading screen when it has no LFG picture: (file number, kind) or (0, 0)"""
    ls = screens.get(int(m["LoadingScreenID"] or 0))
    if ls:
        main, narrow = int(ls["MainImageFileDataID"] or 0), int(ls["NarrowScreenFileDataID"] or 0)
        if main in FOREVER_SCREENS:
            return main, 1
        if 0 < narrow < CLASSIC_SCREEN_MAX:
            return narrow, 2
    for k in keys:
        if doors.get(k) in CONTINENT_SCREEN:
            return CONTINENT_SCREEN[doors[k]], 1
    return 0, 0


def emblems():
    """the client's lfgicon file names (without the prefix and extension)"""
    names = []
    for line in open(LISTFILE, encoding="utf-8", errors="replace"):
        _, _, path = line.strip().partition(";")
        m = re.match(r"interface/lfgframe/lfgicon-([a-z0-9]+)\.blp$", path)
        if m:
            names.append(m.group(1))
    return names


def backgrounds():
    """the client's LFG backgrounds: {name (without the prefix and extension): file number}"""
    out = {}
    for line in open(LISTFILE, encoding="utf-8", errors="replace"):
        fid, _, path = line.strip().partition(";")
        if path.startswith(LFG_BACKGROUND) and path.endswith(".blp"):
            out[path[len(LFG_BACKGROUND):-4]] = int(fid)
    return out


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
    screens = {int(r["ID"]): r for r in read_csv("LoadingScreens.csv")}
    lfg_bg = backgrounds()
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
        emblem = emblem_for([name, m["MapName_lang"], dungeons[key]], raid, files)
        if emblem in lfg_bg:
            pic, pic_kind = lfg_bg[emblem], 3
        else:
            pic, pic_kind = picture_for(m, keys, doors, screens)
            if not pic:
                pic, pic_kind = GENERIC_PICTURE[raid], 3
        instances.append({"key": key, "keys": sorted(keys), "map": mid, "raid": raid, "name": name, "lo": lo, "hi": hi,
                          "players": int(m["MaxPlayers"] or 0), "emblem": emblem, "pic": pic, "picKind": pic_kind,
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
    trash_of = {}   # instance key -> [(creature entry, its loot id)]: every creature on its map that is no boss's
    for inst in instances:
        bossy = set()
        for enc_id, bname in inst["bosses"]:
            ents = list(by_name[inst["map"]].get(bname, []))
            if not ents and len(every.get(bname, [])) <= 3:
                ents = list(every.get(bname, []))
            # (what he brings to his fight: "Sneed's Shredder", on the same map)
            for n, es in by_name[inst["map"]].items():
                if n.startswith(bname + "'s "):
                    ents += es
            bossy.update(ents)
            lids = sorted({loot_ids[e] for e in ents if loot_ids.get(e)})
            boss_loot[enc_id] = lids
            want_loot.update(lids)
        trash_of[inst["key"]] = sorted((e, loot_ids[e]) for e in spawned[inst["map"]] - bossy if loot_ids.get(e))
        want_loot.update(lid for _, lid in trash_of[inst["key"]])
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
                drops.append((item, c, quality, iname, req, starts, 0))
            drops.sort(key=lambda d: (-d[2], -d[1], d[3]))
            full.append((enc_id, bname, drops))
        inst["bosses"] = full
        # the trash's: each item at its likeliest creature's chance, with the creatures that drop it
        best, mobs = {}, defaultdict(dict)
        for e, lid in trash_of[inst["key"]]:
            for item, c in drops_of(lid).items():
                it = items.get(item)
                if not it or c < TRASH_MIN_CHANCE or (it[1] < TRASH_QUALITY and not it[3]):
                    continue
                best[item] = max(best.get(item, 0), c)
                n = names.get(e, "")
                if n:
                    mobs[item][n] = max(mobs[item].get(n, 0), c)
        trash = []
        for item, c in best.items():
            iname, quality, req, starts = items[item]
            who = [n for n, _ in sorted(mobs[item].items(), key=lambda kv: (-kv[1], kv[0]))][:TRASH_MOBS]
            trash.append((item, c, quality, iname, req, starts, ", ".join(who), 0))
        trash.sort(key=lambda d: (-d[2], -d[1], d[3]))
        inst["trash"] = trash

    # an item's name, quality and level: the database's, else the client's (ItemSparse); a Forever item neither
    # knows yet: quality 0, the game's own read in game
    sparse = {}
    sparse_path = os.path.join(DB2, "ItemSparse.csv")
    if os.path.exists(sparse_path):
        for r in read_csv("ItemSparse.csv"):
            sparse[int(r["ID"])] = (r["Display_lang"], int(r["OverallQualityID"] or 0), int(r["RequiredLevel"] or 0))

    def item_info(item):
        if item in items:
            return items[item][0], items[item][1], items[item][2]
        return sparse.get(item, ("", 0, 0))

    # DungeonMaster's curated lists (read_dungeonmaster): a boss's list is its, in its order -- an item the database
    # has keeps its chance and quest, one it has not no chance (flag 1); the database's quest starters it leaves out
    # stay. Its boss by name, else by its place in its kill order where the client's boss there is not named in
    # it (its Magmatus is the client's Infurnus); a rare spawn, or a creature the client has no encounter for, to the
    # trash under its own name
    dm_version, dm = read_dungeonmaster()
    dm_bosses = dm_items = 0
    for inst in instances:
        cur = dm.get(inst["map"])
        if not cur:
            continue
        ours = [(enc, bname) for enc, bname, _ in inst["bosses"]]
        by_norm = {norm_name(b): enc for enc, b in ours}
        match = {}
        for name, b in cur["bosses"].items():
            if not b["rare"] and norm_name(name) in by_norm:
                match[name] = by_norm[norm_name(name)]
        named = set(match.values())
        if len(cur["order"]) == len(ours):
            for (enc, _), name in zip(ours, cur["order"]):
                b = cur["bosses"].get(name)
                if b and not b["rare"] and name not in match and enc not in named:
                    match[name] = enc
                    named.add(enc)
        full = []
        for enc, bname, drops in inst["bosses"]:
            name = next((n for n, e in match.items() if e == enc), None)
            if name is None:
                full.append((enc, bname, drops))
                continue
            have = {d[0]: d for d in drops}
            new = []
            for item in cur["bosses"][name]["loot"]:
                if item in have:
                    new.append(have.pop(item))
                else:
                    iname, quality, req = item_info(item)
                    new.append((item, None, quality, iname, req, 0, 1))
            new += [d for d in have.values() if d[5]]   # (the database's quest starters)
            full.append((enc, bname, new))
            dm_bosses += 1
            dm_items += len(cur["bosses"][name]["loot"])
        inst["bosses"] = full
        trash = list(inst["trash"])
        in_trash = {d[0] for d in trash}
        for name, b in cur["bosses"].items():
            if name in match:
                continue
            for item in b["loot"]:
                if item not in in_trash:
                    iname, quality, req = item_info(item)
                    trash.append((item, None, quality, iname, req, 0, name, 1))
                    in_trash.add(item)
                    dm_items += 1
        inst["trash"] = trash
    if dm_version:
        log("DungeonMaster %s: %d bosses' lists, %d items" % (dm_version, dm_bosses, dm_items))

    # Everloot's drop rates (read_everloot): a boss's by his encounter's creatures, the trash's by the creatures
    # spawned on the instance's map (the database's: Forever's own creatures are on no map the data places)
    e_stamp, e_bosses, e_drops, e_names = read_everloot()
    for inst in instances:
        e_boss, e_trash = {}, {}
        enc_ids = {enc for enc, _, _ in inst["bosses"]}
        for npc, (imap, enc) in e_bosses.items():
            if imap != inst["map"] or enc not in enc_ids:
                continue
            for item, rate, _ in e_drops.get(npc, []):
                iname, quality, req = item_info(item)
                if quality and quality < MIN_QUALITY:
                    continue
                key = (enc, item)
                if rate > e_boss.get(key, (0,))[0]:
                    e_boss[key] = (rate, quality, iname, req)
        for npc in spawned[inst["map"]]:
            if npc in e_bosses or npc not in e_drops:
                continue
            for item, rate, _ in e_drops[npc]:
                iname, quality, req = item_info(item)
                if quality and quality < TRASH_QUALITY:
                    continue
                cur = e_trash.get(item)
                who = names.get(npc) or e_names.get(npc) or ""
                if not cur:
                    e_trash[item] = [rate, quality, iname, req, [(rate, who)]]
                else:
                    cur[0] = max(cur[0], rate)
                    cur[4].append((rate, who))
        inst["everBoss"] = sorted(((enc, item) + v for (enc, item), v in e_boss.items()), key=lambda d: (d[0], -d[2]))
        inst["everTrash"] = sorted(((item, v[0], v[1], v[2], v[3], ", ".join(w for _, w in sorted(v[4], key=lambda x: -x[0])[:TRASH_MOBS] if w))
                                    for item, v in e_trash.items()), key=lambda d: -d[1])

    lines = ["-- Generated by Tools/build_dungeoninfo.py. Do not edit by hand.",
             "-- Sources: MelloUI's quest data (the dungeons, their levels), the client's AreaTable, Map and DungeonEncounter",
             "-- (the instances, the bosses in order), the cmangos classic-db (the drops, the items).",
             bql.GPL_NOTICE,
             "-- luacheck: globals MelloUI_DungeonInfoData",
             "MelloUI_DungeonInfoData = {",
             "\t-- [key] = { map, kind (1 dungeon, 2 raid), name, level from, level to, players, emblem (LFGIcon-<it>),",
             "\t--   every quest key of it (the quest data's dungeon keys: its quests), bosses: { { encounter id, name,",
             "\t--   drops: { item, chance (tenths of a percent; -1 not known), quality (0 not known yet), name, required",
             "\t--   level, quest it starts (0 none), source (0 the database, 1 DungeonMaster), ... } }, ... }, the trash's",
             "\t--   drops: { item, chance (hundredths of a percent; -1 not known), quality, name, required level, quest",
             "\t--   it starts, the creatures that drop it, source, ... }, its picture's file, its kind (1 a Forever loading",
             "\t--   screen, 2 a classic one, 3 an LFG background), Everloot's boss drops: { encounter,",
             "\t--   item, rate (tenths of a percent), quality (0: not known yet), name, required level, ... }, Everloot's",
             "\t--   trash drops: { item, rate (hundredths of a percent), quality, name, required level, creatures, ... } };",
             "\t--   key: the quest data's dungeon key (AreaTable id) its door pins use",
             "\t-- Everloot's rows: %s (export %s)" % (EVERLOOT_CREDIT, e_stamp or "none yet"),
             "\t-- Source 1 rows: %s (version %s)" % (DM_CREDIT, dm_version or "none"),
             "\tinstances = {"]

    def q(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    for inst in instances:
        lines.append("\t\t[%d] = { %d, %d, %s, %d, %d, %d, %s, { %s }, {" % (
            inst["key"], inst["map"], 2 if inst["raid"] else 1, q(inst["name"]), inst["lo"], inst["hi"],
            inst["players"], q(inst["emblem"]), ", ".join(str(k) for k in inst["keys"])))
        for enc_id, bname, drops in inst["bosses"]:
            flat = ", ".join("%d,%d,%d,%s,%d,%d,%d" % (d[0], -1 if d[1] is None else int(round(d[1] * 10)), d[2],
                                                        q(d[3]), d[4], d[5], d[6]) for d in drops)
            lines.append("\t\t\t{ %d, %s, { %s } }," % (enc_id, q(bname), flat))
        trash = ", ".join("%d,%d,%d,%s,%d,%d,%s,%d" % (d[0], -1 if d[1] is None else int(round(d[1] * 100)), d[2],
                                                       q(d[3]), d[4], d[5], q(d[6]), d[7]) for d in inst["trash"])
        ever_boss = ", ".join("%d,%d,%d,%d,%s,%d" % (d[0], d[1], int(round(d[2] * 1000)), d[3], q(d[4]), d[5])
                              for d in inst["everBoss"])
        ever_trash = ", ".join("%d,%d,%d,%s,%d,%s" % (d[0], int(round(d[1] * 10000)), d[2], q(d[3]), d[4], q(d[5]))
                               for d in inst["everTrash"])
        lines.append("\t\t}, { %s }, %d, %d, { %s }, { %s } }," % (trash, inst["pic"], inst["picKind"], ever_boss, ever_trash))
    lines.append("\t},")
    # (1.2.2) what players have seen fall and sent in, added up (read_seen): counted in game with your own
    s_boss, s_mob, s_roll, n_exports = read_seen()

    def flat(d):
        return ", ".join("%d,%d,%d" % (item, t, q) for item, (t, q) in sorted(d.items()))
    lines += ["\t-- the drops players have seen and sent in (%d exports): boss = { [encounter] = { kills, item, times," % n_exports,
              "\t--   quality, ... } }, mob = { [npc] = { instance key, name, corpses looted, item, times, quality, ... } },",
              "\t--   roll = { [instance key] = { item, times, quality, ... } } (rolls whose creature is not known)",
              "\tseen = {", "\t\tboss = {"]
    lines += ["\t\t\t[%d] = { %d, %s }," % (enc, b[0], flat(b[1])) for enc, b in sorted(s_boss.items())]
    lines += ["\t\t},", "\t\tmob = {"]
    lines += ["\t\t\t[%d] = { %d, %s, %d, %s }," % (npc, o[0], q(o[1]), o[2], flat(o[3])) for npc, o in sorted(s_mob.items())]
    lines += ["\t\t},", "\t\troll = {"]
    lines += ["\t\t\t[%d] = { %s }," % (key, flat(r)) for key, r in sorted(s_roll.items())]
    lines += ["\t\t},", "\t},", "}", ""]
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
    same_drive = os.path.splitdrive(OUT)[0].lower() == os.path.splitdrive(REPO)[0].lower()
    print("wrote %s: %d instances, %d bosses, %d drops, %d trash drops, %d pictures, %d KB" % (
        os.path.relpath(OUT, REPO) if same_drive else OUT, len(instances), sum(len(i["bosses"]) for i in instances), n_drops,
        sum(len(i["trash"]) for i in instances), sum(1 for i in instances if i["pic"]), len(text) // 1024))


if __name__ == "__main__":
    if "--everloot" in sys.argv:
        fetch_everloot()
    main("--check" in sys.argv)
