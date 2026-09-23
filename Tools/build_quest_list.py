#!/usr/bin/env python3
"""
Build Media/QuestListData.lua for the MelloUI Quest List module: every quest
in WoW: Forever with its level, faction and class requirements, the zone it
belongs to, and where it is picked up (quest giver name, zone and map
coordinates).

Sources:
  Wowhead Forever listing (cached by import_wowhead_quests.py)   quest metadata + zone
  cmangos classic-db        vanilla quest givers (creature/gameobject relations) and spawn points
  wago.tools DB2 (1.15.9)   UiMapAssignment bounds (world -> map coordinates), AreaTable names
  Wowhead quest/NPC pages   Forever quest givers and turn-ins: zone, and map coordinates
                            where Wowhead has them (its NPC pages carry them since 2026-09)
  MelloUI-BuildData/cache/voice_lines.json   positions the Voice Over collector recorded in game

Usage:
  python Tools/build_quest_list.py [--fetch-npcs] [--refresh-npcs] [--out Media/QuestListData.lua]

A quest no NPC gives is placed at what begins it: an item (classic-db's
startquest and loot, or the Wowhead item page) or an object (the Forever
quest page's Start).

--fetch-npcs downloads the Wowhead NPC pages of Forever quest givers and
turn-ins not yet cached, one every 2.5 s, to learn their zone and place,
and the item / NPC / object pages that place the items and objects
quests begin from.
--refresh-npcs also re-downloads cached NPC pages that have no coordinates
(pages cached before Wowhead added them).
"""

import argparse
import glob
import gzip
import html
import json
import math
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from extract_npc_voices import parse_sql_values, load_creature_template, fetch as fetch_file, CMANGOS_SQL  # noqa: E402
from import_wowhead_quests import listing_data, parse_quest, fetch as fetch_page, BASE  # noqa: E402
from paths import CACHE

WOWHEAD = os.path.join(CACHE, "wowhead")
BUILD = "1.15.9.69722"          # Classic Era, from wago.tools (comma separated, vectors as Pos_0..)
FOREVER = "1.60.1.69913"        # Forever, exported with wow.export (semicolon separated, vectors as "x,y,z")
VECTOR_COLUMNS = {"Loc", "Pos", "Corpse", "Region", "GeoBox", "MapOffset", "FlightMapOffset"}


def db2(name):
    """Rows of a client table: the Forever export when it exists in the cache,
    else the Classic Era one. Both CSV dialects are normalised to wago's."""
    import csv
    for build in (FOREVER, BUILD):
        path = os.path.join(CACHE, f"{name}_{build}.csv")
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as fh:
            head = fh.readline()
            fh.seek(0)
            delim = ";" if head.count(";") > head.count(",") else ","
            rows = []
            for r in csv.DictReader(fh, delimiter=delim):
                out = {}
                for k, v in r.items():
                    if k in VECTOR_COLUMNS and v is not None and "," in v:
                        for i, part in enumerate(v.split(",")):
                            out[f"{k}_{i}"] = part
                    else:
                        out[k] = v
                rows.append(out)
        db2.used[name] = build
        return rows
    raise FileNotFoundError(f"{name}: no {FOREVER} or {BUILD} export in {CACHE}")


db2.used = {}
# Wowhead category -> holiday / world event name. Category2 9 holds the
# holidays, 7 the world events (minus the legendary chains), -22 is Wowhead's
# "special" bucket that only has Winter Veil quests in it.
EVENTS = {
    -1001: "Feast of Winter Veil", -22: "Feast of Winter Veil", -1002: "Children's Week", -1003: "Hallow's End",
    -1004: "Love is in the Air", -1005: "Harvest Festival", -1006: "New Year", -364: "Darkmoon Faire",
    -366: "Lunar Festival", -369: "Midsummer Fire Festival", -365: "Ahn'Qiraj War Effort",
    -367: "Scourge Invasion", -368: "Scourge Invasion", -641: "Nightmare Incursions", -644: "Grand Tournament of Gnomeregan",
}
CLASSES = {1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST", 64: "SHAMAN", 128: "MAGE", 256: "WARLOCK", 1024: "DRUID"}
JUNK = re.compile(r"^\s*[<\[]|UNUSED|\bTEST\b|\bNYI\b|DEPRECATED|\bDND\b|\bTXT\b|^zz|\(123\)|REUSE|Never used", re.I)


def log(msg):
    print(msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# cmangos
# ---------------------------------------------------------------------------

def sql_rows(path, table):
    """Yield dict rows of one table from the cmangos dump."""
    columns = None
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        in_create = False
        for line in fh:
            if line.startswith(f"CREATE TABLE `{table}`"):
                in_create, columns = True, []
                continue
            if in_create:
                m = re.match(r"\s*`(\w+)`", line)
                if m:
                    columns.append(m.group(1))
                elif line.startswith(")"):
                    in_create = False
                continue
            if line.startswith(f"INSERT INTO `{table}`"):
                for row in parse_sql_values(line[line.index("VALUES") + 6:]):
                    yield dict(zip(columns, row))


def load_vanilla(sql):
    log("reading cmangos quest givers and spawns")
    givers = defaultdict(list)   # quest -> [("npc"|"object", entry)]
    for r in sql_rows(sql, "creature_questrelation"):
        givers[int(r["quest"])].append(("npc", int(r["id"])))
    for r in sql_rows(sql, "gameobject_questrelation"):
        givers[int(r["quest"])].append(("object", int(r["id"])))
    enders = defaultdict(list)   # quest -> [("npc"|"object", entry)] that take it back
    for r in sql_rows(sql, "creature_involvedrelation"):
        enders[int(r["quest"])].append(("npc", int(r["id"])))
    for r in sql_rows(sql, "gameobject_involvedrelation"):
        enders[int(r["quest"])].append(("object", int(r["id"])))
    spawns = defaultdict(list)   # ("npc"|"object", entry) -> [(map, x, y)]
    for r in sql_rows(sql, "creature"):
        spawns[("npc", int(r["id"]))].append((int(r["map"]), float(r["position_x"]), float(r["position_y"])))
    for r in sql_rows(sql, "gameobject"):
        spawns[("object", int(r["id"]))].append((int(r["map"]), float(r["position_x"]), float(r["position_y"])))
    names = {("npc", e): n["name"] for e, n in load_creature_template(sql).items()}
    for r in sql_rows(sql, "gameobject_template"):
        names[("object", int(r["entry"]))] = r["name"]
    log(f"  {len(givers)} quests with givers, {len(enders)} with turn-ins, {len(spawns)} spawned entries")
    return givers, spawns, names, enders


# ---------------------------------------------------------------------------
# Map geometry
# ---------------------------------------------------------------------------

def load_wowhead_zones():
    """Wowhead's Forever zone list: {id: (name, instance)} with instance 0 zone,
    2 dungeon, 3 raid, 4 battleground. Knows Forever's new dungeons, which the
    Classic Era area table does not."""
    page = fetch_page(f"{BASE}/zones", os.path.join(WOWHEAD, "zones.html"))
    i = page.find('"template":"zone","data":[')
    if i < 0:
        log("  zones: listing not found on the Wowhead page")
        return {}
    start = page.index("[", i + len('"template":"zone","data":') - 1)
    depth = 0
    for k in range(start, len(page)):
        if page[k] == "[":
            depth += 1
        elif page[k] == "]":
            depth -= 1
            if depth == 0:
                rows = json.loads(page[start:k + 1])
                break
    # category 0 = Eastern Kingdoms, 1 = Kalimdor, -1 = elsewhere
    zones = {r["id"]: (r["name"], r.get("instance") or 0, r.get("category", -1)) for r in rows if "Test" not in r["name"]}
    load_wowhead_zones.levels = {r["id"]: (r.get("minlevel") or r.get("reqlevel") or 0, r.get("maxlevel") or 0) for r in rows}
    log(f"  {len(zones)} Wowhead zones, {sum(1 for _, t, _ in zones.values() if t in (2, 3))} dungeons and raids")
    return zones


# Quests that grant access to an instance; their whole chain is flagged.
ATTUNEMENT_TITLES = {
    "attunement to the core", "blackhand's command", "the dread citadel - naxxramas", "drakefire amulet",
    "seal of ascension", "the key to scholomance", "the scarlet enclave",
}


def load_zone_maps():
    import csv
    areas = {int(r["ID"]): r["AreaName_lang"] for r in db2("AreaTable")}
    uimaps = {int(r["ID"]): r for r in db2("UiMap")}
    zones = []
    for r in db2("UiMapAssignment"):
        ui = uimaps.get(int(r["UiMapID"]))
        if not ui or ui["Type"] not in ("3", "4"):   # zones and cities / dungeons only, not continents
            continue
        x0, y0, x1, y1 = float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"])
        zones.append({
            "uiMapID": int(r["UiMapID"]), "name": ui["Name_lang"], "areaID": int(r["AreaID"] or 0), "mapID": int(r["MapID"]),
            "x0": x0, "y0": y0, "x1": x1, "y1": y1, "area": abs((x1 - x0) * (y1 - y0)),
        })
    log(f"  {len(zones)} zone maps with bounds, {len(areas)} areas")
    return zones, areas


def locate(zones, map_id, wx, wy):
    """Zone containing a world point, smallest first (cities inside their zone), with map percent coords."""
    best = None
    for z in zones:
        if z["mapID"] != map_id:
            continue
        if z["x0"] <= wx <= z["x1"] and z["y0"] <= wy <= z["y1"]:
            if best is None or z["area"] < best["area"]:
                best = z
    if not best:
        return None
    px = (best["y1"] - wy) / (best["y1"] - best["y0"]) * 100
    py = (best["x1"] - wx) / (best["x1"] - best["x0"]) * 100
    return best, round(px, 1), round(py, 1)


# ---------------------------------------------------------------------------
# Wowhead
# ---------------------------------------------------------------------------

def load_listing():
    quests = {}
    for f in glob.glob(os.path.join(WOWHEAD, "listing_*.html")):
        for row in listing_data(open(f, encoding="utf-8").read()):
            quests[row["id"]] = row
    log(f"  {len(quests)} quests in the Wowhead listing")
    return quests


MAPPER = re.compile(r"g_mapperData\s*=\s*(\{.*?\});", re.S)


def npc_places(page):
    """Where Wowhead's map puts an NPC: [(areaID, uiMapID, x, y)] in map
    percent, first point of each zone it stands in."""
    m = MAPPER.search(page)
    if not m:
        return []
    try:
        data = json.loads(m.group(1))
    except ValueError:
        return []
    out = []
    for area, spots in data.items():
        for spot in spots if isinstance(spots, list) else []:
            coords = spot.get("coords") or []
            if coords and spot.get("uiMapId"):
                out.append((int(area), int(spot["uiMapId"]), float(coords[0][0]), float(coords[0][1])))
                break
    return out


def forever_givers(quest_ids, fetch_npcs, refresh_npcs=False):
    """Start / end NPC (id, name) for Forever quests from cached pages, with
    each NPC's zone (areaID) and Wowhead map places."""
    givers = {}
    enders = {}
    npc_zone = {}
    npc_pos = {}
    for qid in quest_ids:
        path = os.path.join(WOWHEAD, f"quest_{qid}.html")
        if not os.path.exists(path):
            continue
        info = parse_quest(open(path, encoding="utf-8").read(), qid)
        if info["start"]:
            givers[qid] = info["start"]
        if info.get("end"):
            enders[qid] = info["end"]
    npc_ids = sorted({g["npcID"] for g in givers.values()} | {e["npcID"] for e in enders.values()})
    def cached(n):
        return os.path.join(WOWHEAD, f"npc_{n}.html")
    missing = [n for n in npc_ids if not os.path.exists(cached(n))]
    if refresh_npcs:
        stale = [n for n in npc_ids if os.path.exists(cached(n)) and not npc_places(open(cached(n), encoding="utf-8").read())]
        log(f"  {len(stale)} cached NPC pages without coordinates, fetched again")
        for n in stale:
            os.replace(cached(n), cached(n) + ".old")
        missing += stale
    if fetch_npcs and missing:
        log(f"fetching {len(missing)} NPC pages from Wowhead for their zone")
        for n, npc_id in enumerate(missing, 1):
            try:
                fetch_page(f"{BASE}/npc={npc_id}", os.path.join(WOWHEAD, f"npc_{npc_id}.html"))
            except Exception as exc:  # noqa: BLE001
                log(f"   npc {npc_id}: {exc}")
            if n % 25 == 0:
                log(f"   {n}/{len(missing)}")
    for npc_id in npc_ids:
        path = os.path.join(WOWHEAD, f"npc_{npc_id}.html")
        if os.path.exists(path):
            page = open(path, encoding="utf-8").read()
            m = re.search(r'"location":\[(\d+)', page)
            if m:
                npc_zone[npc_id] = int(m.group(1))
            places = npc_places(page)
            if places:
                npc_pos[npc_id] = places
        elif os.path.exists(path + ".old"):
            os.replace(path + ".old", path)   # the re-fetch failed: keep the old page
    log(f"  {len(givers)} Forever quest givers, {len(enders)} turn-ins, zone known for {len(npc_zone)} NPCs, "
        f"placed on the map for {len(npc_pos)}")
    return givers, npc_zone, enders, npc_pos


def place_on_map(zones, places, prefer_area=0):
    """A Wowhead map place -> (areaID, map x %, map y %, continent, world x, world y):
    the inverse of locate(), on the zone map's full bounds. The place in the
    quest's own zone when the NPC stands in several."""
    if not places:
        return None
    pick = next((p for p in places if prefer_area and p[0] == prefer_area), places[0])
    area, ui_map, px, py = pick
    bounds = [z for z in zones if z["uiMapID"] == ui_map]
    if not bounds:
        return None
    z = max(bounds, key=lambda b: b["area"])
    wy = z["y1"] - px / 100 * (z["y1"] - z["y0"])
    wx = z["x1"] - py / 100 * (z["x1"] - z["x0"])
    return area, round(px, 1), round(py, 1), z["mapID"], round(wx, 1), round(wy, 1)


# ---------------------------------------------------------------------------
# Quests begun by an item or an object (no NPC gives them)
# ---------------------------------------------------------------------------

MIN_DROP = 0.5       # percent: a rarer drop is no place to find the item


def wh_places(page):
    """Every point of a Wowhead page's map: [(areaID, uiMapID, x %, y %)]."""
    m = MAPPER.search(page or "")
    if not m:
        return []
    try:
        data = json.loads(m.group(1))
    except ValueError:
        return []
    out = []
    for area, spots in data.items():
        for spot in spots if isinstance(spots, list) else []:
            for c in spot.get("coords") or []:
                if spot.get("uiMapId") and len(c) >= 2:
                    out.append((int(area), int(spot["uiMapId"]), float(c[0]), float(c[1])))
    return out


def wh_listview(page, lv_id):
    """The data of one Listview of a Wowhead page (dropped-by, contained-in-object ...)."""
    i = (page or "").find(f"id: '{lv_id}'")
    j = page.find("data:", i) if i >= 0 else -1
    end = page.find("new Listview(", i + 10) if i >= 0 else -1
    if j < 0 or (0 <= end < j):
        return []
    seg = page[j + 5:].lstrip()
    depth = 0
    for n, ch in enumerate(seg):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(seg[:n + 1])
                except ValueError:
                    return []
    return []


def read_cached(kind, i):
    path = os.path.join(WOWHEAD, f"{kind}_{i}.html")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    return None


def load_starters(sql, spawns, zones, quest_ids, fetch=False):
    """Quests begun by an item or an object rather than an NPC (user,
    2026-09-23: "quest giver unknown" on Furlbrow's Deed, which starts from
    the Westfall Deed drop).

    Items: classic-db's item_template.startquest, and the Wowhead item pages
    cached for Forever ("This Item Begins a Quest"); where they come from is
    classic-db's creature / chest loot for a Classic item, else the item
    page's "dropped by" and "contained in" lists. Objects: the Start of a
    Forever quest page, placed by classic-db's spawns or the object's Wowhead
    map. Returns quest -> (kind 2 object, 3 item dropped by creatures, 4 item
    picked up from an object, name, [(map, x, y)])."""
    wanted = set(quest_ids)
    out = {}
    items = {}                                     # item -> (name, [quests])
    for r in sql_rows(sql, "item_template"):
        q = int(r.get("startquest") or 0)
        if q in wanted:
            items.setdefault(int(r["entry"]), (r["name"], []))[1].append(q)
    classic_items = set(items)
    for f in glob.glob(os.path.join(WOWHEAD, "item_*.html")):
        page = open(f, encoding="utf-8").read()
        m = re.search(r'/quest=(\d+)[^"]*" class="q1">This Item Begins a Quest', page)
        if not m or int(m.group(1)) not in wanted:
            continue
        iid = int(os.path.basename(f)[5:-5])
        if iid in items:
            continue
        n = re.search(r"<title>(.*?) - Item", page)
        items[iid] = (html.unescape(n.group(1)) if n else "", [int(m.group(1))])
    # Forever quest pages naming an object (or an item) as their start
    objects = {}
    for qid in quest_ids:
        page = read_cached("quest", qid)
        if not page:
            continue
        m = re.search(r"Start: (?:\[span[^\]]*\])?\[url=/forever/(object|item)=(\d+)/[^\]]*\]([^\[]*)\[/url\]",
                      page.replace("\\/", "/"))
        if m and m.group(1) == "object":
            objects[qid] = (int(m.group(2)), html.unescape(m.group(3)))
        elif m and int(m.group(2)) not in items:
            items[int(m.group(2))] = (html.unescape(m.group(3)), [qid])

    # classic-db loot of the Classic items
    need = {i for i in items if i in classic_items}
    loot_c, loot_o = defaultdict(list), defaultdict(list)
    for r in sql_rows(sql, "creature_template"):
        if int(r["LootId"] or 0):
            loot_c[int(r["LootId"])].append(int(r["Entry"]))
    for r in sql_rows(sql, "gameobject_template"):
        if int(r["type"]) in (3, 25) and int(r["data1"] or 0):
            loot_o[int(r["data1"])].append(int(r["entry"]))
    # one step back: the container an item comes out of (a crate, a clam),
    # and the shared loot tables ("references") a boss's loot points to
    container_of = defaultdict(list)
    for r in sql_rows(sql, "item_loot_template"):
        if int(r["item"]) in need:
            container_of[int(r["item"])].append(int(r["entry"]))
    targets = need | {c for cs in container_of.values() for c in cs}
    refs_of = defaultdict(list)
    for r in sql_rows(sql, "reference_loot_template"):
        if int(r["item"]) in targets:
            refs_of[int(r["item"])].append(int(r["entry"]))
    wanted_refs = {ref for rs in refs_of.values() for ref in rs}
    direct = defaultdict(list)                     # item -> [("npc"|"object"|"vendor", entry)]
    rare = defaultdict(list)                       # the same, from drops rarer than MIN_DROP
    ref_users = defaultdict(list)                  # reference -> owners whose loot uses it
    for table, owners, kind in (("creature_loot_template", loot_c, "npc"), ("gameobject_loot_template", loot_o, "object")):
        for r in sql_rows(sql, table):
            item, ref = int(r["item"]), int(r["mincountOrRef"] or 0)
            if ref < 0:
                if -ref in wanted_refs:
                    ref_users[-ref] += [(kind, o) for o in owners.get(int(r["entry"]), ())]
                continue
            if item not in targets:
                continue
            chance = abs(float(r["ChanceOrQuestChance"] or 0))
            for owner in owners.get(int(r["entry"]), ()):
                (rare if chance and chance < MIN_DROP else direct)[item].append((kind, owner))

    def found(item):
        """Where an item comes from: its drops, else its rare drops (still the
        only way to get it), else a boss's shared loot table (not a world drop
        table used by many), else the creatures and objects of its container."""
        if direct.get(item):
            return direct[item]
        if rare.get(item):
            return rare[item]
        users = [u for ref in refs_of.get(item, ()) for u in ref_users.get(ref, ()) if len(ref_users[ref]) <= 20]
        if users:
            return users
        return [s for c in container_of.get(item, ()) for s in (direct.get(c) or rare.get(c) or [])]

    sources = defaultdict(list)
    for iid in need:
        sources[iid] = found(iid)
    vendor_of = defaultdict(list)                  # vendor template -> creature entries
    for r in sql_rows(sql, "creature_template"):
        if int(r.get("VendorTemplateId") or 0):
            vendor_of[int(r["VendorTemplateId"])].append(int(r["Entry"]))
    sold = defaultdict(list)
    for r in sql_rows(sql, "npc_vendor"):
        sold[int(r["item"])].append(("vendor", int(r["entry"])))
    for r in sql_rows(sql, "npc_vendor_template"):
        sold[int(r["item"])] += [("vendor", e) for e in vendor_of.get(int(r["entry"]), ())]
    for iid in items:
        if iid not in classic_items:
            page = read_cached("item", iid)
            sources[iid] += [("npc", int(d["id"])) for d in wh_listview(page, "dropped-by") if d.get("id")]
            sources[iid] += [("object", int(d["id"])) for d in wh_listview(page, "contained-in-object") if d.get("id")]
            if not sources[iid]:
                sources[iid] = [("vendor", int(d["id"])) for d in wh_listview(page, "sold-by") if d.get("id")]
        elif not sources.get(iid):
            sources[iid] = sold.get(iid, [])

    def missing():
        miss = {("object", oid) for oid, _ in objects.values() if ("object", oid) not in spawns}
        for iid in items:
            if iid not in classic_items and read_cached("item", iid) is None:
                miss.add(("item", iid))
            for kind, e in sources.get(iid, ()):
                kind = "npc" if kind == "vendor" else kind
                if (kind, e) not in spawns:
                    miss.add((kind, e))
        return sorted(m for m in miss if read_cached(*m) is None)

    if fetch:
        todo = missing()
        if todo:
            log(f"fetching {len(todo)} Wowhead pages for quests begun by an item or object")
        for n, (kind, i) in enumerate(todo, 1):
            try:
                fetch_page(f"{BASE}/{kind}={i}", os.path.join(WOWHEAD, f"{kind}_{i}.html"))
            except Exception as exc:  # noqa: BLE001
                log(f"   {kind} {i}: {exc}")
            if n % 25 == 0:
                log(f"   {n}/{len(todo)}")

    def points(kind, e):
        kind = "npc" if kind == "vendor" else kind
        pts = spawns.get((kind, e))
        if pts:
            return pts
        out_pts = []
        for place in wh_places(read_cached(kind, e)):
            p = place_on_map(zones, [place])
            if p:
                out_pts.append((p[3], p[4], p[5]))
        return out_pts

    for iid, (name, quests) in items.items():
        dropped, picked = [], []
        for kind, e in sources.get(iid, ()):
            (dropped if kind == "npc" else picked).extend(points(kind, e))
        # dropped by creatures (3) or picked up from an object or bought (4), by where most of it comes from
        kind = 4 if len(picked) > len(dropped) else 3
        for q in quests:
            out.setdefault(q, (kind, name, dropped + picked))
    for qid, (oid, name) in objects.items():
        out.setdefault(qid, (2, name, points("object", oid)))
    log(f"  {sum(1 for v in out.values() if v[0] == 3)} quests begun by a dropped item, "
        f"{sum(1 for v in out.values() if v[0] == 4)} by an item picked up, "
        f"{sum(1 for v in out.values() if v[0] == 2)} by an object")
    return out


CLUSTER = 150        # yards: the neighbourhood counted when looking for the densest spot
QUEST_ZONE_SHARE = 0.25   # the quest's own zone wins when at least this share of the sources lie there


def starter_place(zones, pts, quest_zone, map_area=None):
    """Where a quest-starting item or object is found: (areaID, x %, y %, world).
    The zone most sources lie in (the quest's own zone when a fair share do),
    and in it the densest spot (user, 2026-09-23: the area where the mobs are,
    not just the zone): the source with the most others within CLUSTER yards,
    moved to the source nearest the middle of that group."""
    located = []
    for m, x, y in pts:
        loc = locate(zones, m, x, y)
        if loc:
            located.append((loc, m, x, y))
    if not located:
        # found only inside an instance: no spot on the world map, but the
        # instance as its zone (the quest is then filed under that dungeon)
        maps = defaultdict(int)
        for m, _, _ in pts:
            maps[m] += 1
        area = (map_area or {}).get(max(maps, key=maps.get), 0) if maps else 0
        return area, 0, 0, (-1, 0, 0)
    count = defaultdict(int)
    for p in located:
        count[p[0][0]["areaID"]] += 1
    zone = max(count, key=count.get)
    if quest_zone and count.get(quest_zone, 0) >= QUEST_ZONE_SHARE * len(located):
        zone = quest_zone
    pool = [p for p in located if p[0][0]["areaID"] == zone]
    pool = list({(p[1], round(p[2]), round(p[3])): p for p in pool}.values())   # one per spawn spot

    def near(a):
        return [b for b in pool if b[1] == a[1] and math.hypot(b[2] - a[2], b[3] - a[3]) <= CLUSTER]
    group = max((near(a) for a in pool), key=len)
    cx = sum(p[2] for p in group) / len(group)
    cy = sum(p[3] for p in group) / len(group)
    best = min(group, key=lambda p: math.hypot(p[2] - cx, p[3] - cy))
    (z, px, py), m0, x0, y0 = best
    return zone, px, py, (m0, round(x0, 1), round(y0, 1))


# ---------------------------------------------------------------------------
# Quest chains
# ---------------------------------------------------------------------------

def build_chains(sql, listing):
    """Group quests into chains: cmangos previous / next links for vanilla,
    Wowhead series tables for Forever. Returns {questID: chainID}, {chainID: name}."""
    parent = {}

    def find(a):
        while parent.get(a, a) != a:
            parent[a] = parent.get(parent[a], parent[a])
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    prev_of = {}
    # Only hard prerequisites link vanilla quests: PrevQuestId means the
    # quest cannot be taken before the other one is done. NextQuestId is just
    # the follow-up offered afterwards and would merge whole zones into one.
    for r in sql_rows(sql, "quest_template"):
        qid = int(r["entry"])
        other = abs(int(r.get("PrevQuestId") or 0))
        if other and other != qid and other in listing and qid in listing:
            union(qid, other)
            prev_of[qid] = other
    for f in glob.glob(os.path.join(WOWHEAD, "quest_*.html")):
        page = open(f, encoding="utf-8").read()
        m = re.search(r'<table class="series">(.*?)</table>', page, re.S)
        if not m:
            continue
        ids = [int(x) for x in re.findall(r"quest=(\d+)", m.group(1))]
        ids = [i for i in ids if i in listing]
        for a, b in zip(ids, ids[1:]):
            union(a, b)
            prev_of.setdefault(b, a)
    groups = defaultdict(list)
    for qid in list(parent) + [q for q in prev_of]:
        groups[find(qid)].append(qid)
    chain_of, names = {}, {}
    next_id = 1
    for root, members in groups.items():
        members = sorted(set(members))
        if len(members) < 2:
            continue
        starts = [q for q in members if q not in prev_of or prev_of[q] not in members]
        first = min(starts or members, key=lambda q: ((listing[q].get("level") or 0), q))
        names[next_id] = listing[first]["name"]
        for q in members:
            chain_of[q] = next_id
        next_id += 1
    log(f"  {len(names)} quest chains covering {len(chain_of)} quests")
    # Previous quest inside the chain, for step numbers and "next step" hints.
    prev_in_chain = {q: p for q, p in prev_of.items() if chain_of.get(q) and chain_of.get(p) == chain_of[q]}
    return chain_of, names, prev_in_chain


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Instance entrances and transports (map pins)
# ---------------------------------------------------------------------------

# areatrigger_teleport rows whose target is the outside world are the exits of
# an instance: their target position IS the entrance. Skip the odd ones.
SKIP_ENTRANCE = ("back door", "after ", "fall", "instance end")

# Zeppelin towers stand outside the city bounds; name them by hand.
DOCK_LABELS = [(1, 1340.0, -4645.0, "Orgrimmar", 250.0), (0, 2062.0, 260.0, "Undercity", 250.0),
               (1, 8533.7, 1025.1, "Rut'theran Village", 300.0), (1, -4347.8, 2444.4, "the Forgotten Coast", 300.0),
               # Forever's routes (positions from the 1.60 path table)
               (0, -1103.0, -555.0, "Southshore", 300.0), (1, -6933.0, -4951.0, "Steamwheedle Port", 300.0),
               (0, -8232.0, -5801.0, "Powderfuse Port", 300.0), (2991, 1848.0, 569.0, "Zephras Isle", 400.0),
               (2991, 1953.0, 1019.0, "Zephras Isle", 400.0)]
ZEPPELIN_TOWERS = {"Orgrimmar", "Undercity", "Grom'gol Base Camp"}


def build_map_points(sql, zones, used_dungeons, raids):
    """Entrances of dungeons / raids and boat / zeppelin docks, with world
    coordinates (resolved on the client) and a build-time zone guess."""
    import csv
    maps = {int(r["ID"]): r for r in db2("Map")}
    trig = {int(r["ID"]): r for r in db2("AreaTrigger")}
    area_of_map = {}
    for mid, m in maps.items():
        if int(m.get("AreaTableID") or 0):
            area_of_map[mid] = int(m["AreaTableID"])
    for r in db2("AreaTable"):
        cont, parent = int(r.get("ContinentID") or -1), int(r.get("ParentAreaID") or 0)
        if cont in maps and parent == 0 and cont not in area_of_map:
            area_of_map[cont] = int(r["ID"])
    dungeon_by_name = {re.sub(r"^the ", "", name.lower()): did for did, name in used_dungeons.items()}

    entrances, seen = [], set()
    for r in sql_rows(sql, "areatrigger_teleport"):
        t = trig.get(int(r["id"]))
        if not t:
            continue
        low = r["name"].lower()
        if any(k in low for k in SKIP_ENTRANCE):
            continue
        if r["target_map"] in ("0", "1"):
            # An exit: its target stands outside, at the entrance.
            inst = int(t["ContinentID"])
            cont, wx, wy = int(r["target_map"]), float(r["target_position_x"]), float(r["target_position_y"])
        elif t["ContinentID"] in ("0", "1"):
            # An entering trigger: the trigger itself stands outside.
            inst = int(r["target_map"])
            cont, wx, wy = int(t["ContinentID"]), float(t["Pos_0"]), float(t["Pos_1"])
        else:
            continue
        m = maps.get(inst)
        if not m or m["InstanceType"] not in ("1", "2") or m["MapName_lang"].startswith("<"):
            continue
        key = (inst, round(wx / 60), round(wy / 60))
        if key in seen:
            continue
        seen.add(key)
        name = m["MapName_lang"]
        did = area_of_map.get(inst, 0)
        if did not in used_dungeons:
            did = dungeon_by_name.get(re.sub(r"^the ", "", name.lower()), 0)
        loc = locate(zones, cont, wx, wy)
        entrances.append((did, name, cont, round(wx, 1), round(wy, 1),
                          loc[0]["areaID"] if loc else 0, loc[1] if loc else 0, loc[2] if loc else 0,
                          2 if m["InstanceType"] == "2" else 1))
    entrances.sort(key=lambda e: (e[1], e[2], e[3]))
    log(f"  {len(entrances)} instance entrances ({sum(1 for e in entrances if e[0] == 0)} without a Wowhead instance id)")

    nodes = defaultdict(list)
    for r in db2("TaxiPathNode"):
        nodes[int(r["PathID"])].append(r)
    pois = []
    for r in db2("AreaPOI"):
        if r["ContinentID"] in ("0", "1"):
            pois.append((r["Name_lang"], int(r["ContinentID"]), float(r["Pos_0"]), float(r["Pos_1"])))

    def dock_name(cont, x, y, loc):
        for c, px, py, name, radius in DOCK_LABELS:
            if c == cont and math.hypot(px - x, py - y) < radius:
                return name
        best, bd = None, 900.0
        for name, c, px, py in pois:
            if c == cont:
                d = math.hypot(px - x, py - y)
                if d < bd:
                    best, bd = name, d
        return best or (loc[0]["name"] if loc else "the other shore")

    def stops_of(path_id):
        """Docks of a transport path: its nodes with a wait, in order, merged when repeated."""
        out = []
        for n in sorted(nodes.get(path_id, []), key=lambda n: int(n["NodeIndex"])):
            if int(n["Delay"]) <= 0:
                continue
            cont, x, y = int(n["ContinentID"]), float(n["Loc_0"]), float(n["Loc_1"])
            if any(d[0] == cont and math.hypot(d[1] - x, d[2] - y) < 100 for d in out):
                continue
            out.append((cont, x, y))
        return out

    # Stop sequences, with a hint whether the vehicle is a zeppelin.
    routes = []
    forever_paths = db2.used.get("TaxiPathNode") == FOREVER
    if forever_paths:
        node_names = {int(r["ID"]): r["Name_lang"] for r in db2("TaxiNodes")}
        for r in db2("TaxiPath"):
            stops = stops_of(int(r["ID"]))
            if len(stops) >= 2:
                hint = (node_names.get(int(r["FromTaxiNode"]), "") + " " + node_names.get(int(r["ToTaxiNode"]), "")).lower()
                routes.append((stops, "zepp" in hint))
    else:
        for r in sql_rows(sql, "gameobject_template"):
            if str(r.get("type")) != "15" or "naxx" in r["name"].lower():
                continue
            stops = stops_of(int(r["data0"]))
            if len(stops) != 2:
                log(f"  transport {r['name']}: {len(stops)} docks, skipped")
                continue
            routes.append((stops, "zeppelin" in r["name"].lower()))

    def same_dock(a, b):
        return a[0] == b[0] and math.hypot(a[1] - b[1], a[2] - b[2]) < 100

    longer = [stops for stops, _ in routes if len(stops) >= 3]
    routes = [(stops, hint) for stops, hint in routes
              if not (len(stops) == 2 and any(all(any(same_dock(st, d) for d in big) for st in stops) for big in longer))]

    transports = []
    for stops, zeppelin_hint in routes:
        labels = []
        for cont, x, y in stops:
            loc = locate(zones, cont, x, y)
            labels.append((dock_name(cont, x, y, loc), loc))
        kind = 2 if any(l[0] in ZEPPELIN_TOWERS for l in labels) else 1
        if kind == 2:
            faction = 2
        elif forever_paths or any(l[0] in ("Booty Bay", "Ratchet") for l in labels):
            faction = 0   # Forever opened the boats to both factions
        else:
            faction = 1
        count = len(stops)
        for i, (cont, x, y) in enumerate(stops):
            # A boat on a loop goes on to the next stop; with three stops say so.
            if count == 2:
                nxt = 1 - i
            else:
                nxt = (i + 1) % count
            here, loc = labels[i]
            dest = labels[nxt][0]
            label = ("Zeppelin to " if kind == 2 else "Boat to ") + dest
            if count >= 3:
                label += ", then " + labels[(nxt + 1) % count][0]
            other = stops[nxt]
            transports.append((kind, faction, label, here,
                               cont, round(x, 1), round(y, 1),
                               loc[0]["areaID"] if loc else 0, loc[1] if loc else 0, loc[2] if loc else 0,
                               other[0], round(other[1], 1), round(other[2], 1)))
    log(f"  {len(transports)} boat / zeppelin docks")
    return entrances, transports


def build_taxi():
    """Vanilla flight network: {id: (name, continent, x, y, faction)} and
    [(from, to, seconds)] with the flight time from the path geometry."""
    import csv
    FLIGHT_SPEED = 32.0   # yards per second on a vanilla gryphon
    nodes = {}
    all_names = {}   # every node the node table knows, whatever its flags (Forever re-enabled some)
    for r in db2("TaxiNodes"):
        if r["ContinentID"] in ("0", "1"):
            all_names[int(r["ID"])] = r["Name_lang"]
        flags = int(r["Flags"] or 0) & 3
        if r["ContinentID"] in ("0", "1") and flags:
            faction = 0 if flags == 3 else flags   # 1 Alliance, 2 Horde, 0 both
            nodes[int(r["ID"])] = (r["Name_lang"], int(r["ContinentID"]), round(float(r["Pos_0"]), 1), round(float(r["Pos_1"]), 1), faction)
    lengths = defaultdict(float)
    last = {}
    path_nodes = defaultdict(list)
    for r in sorted(db2("TaxiPathNode"),
                    key=lambda n: (int(n["PathID"]), int(n["NodeIndex"]))):
        pid = int(r["PathID"])
        path_nodes[pid].append(r)
        x, y = float(r["Loc_0"]), float(r["Loc_1"])
        if pid in last and last[pid][0] == r["ContinentID"]:
            lengths[pid] += math.hypot(x - last[pid][1], y - last[pid][2])
        last[pid] = (r["ContinentID"], x, y)
    # Flight points the node table does not know (Forever's new ones when only
    # the path tables were exported): their position is the path's first or
    # last node; the name comes from a known point within 60 yards, else a
    # placeholder. The client matches them by id anyway.
    ends = {}
    for pid, ns in path_nodes.items():
        ns = sorted(ns, key=lambda n: int(n["NodeIndex"]))
        ends[pid] = (ns[0], ns[-1])
    synthesized = 0
    for r in db2("TaxiPath"):
        pid, a, b = int(r["ID"]), int(r["FromTaxiNode"]), int(r["ToTaxiNode"])
        if pid not in ends:
            continue
        for nid, node in ((a, ends[pid][0]), (b, ends[pid][1])):
            if nid == 0 or nid in nodes or node["ContinentID"] not in ("0", "1"):
                continue
            hint = (all_names.get(nid) or "").lower()
            if "transport" in hint or "generic" in hint or "ferry" in hint or "naxxramas" in hint:
                continue
            cont, x, y = int(node["ContinentID"]), float(node["Loc_0"]), float(node["Loc_1"])
            name = all_names.get(nid)
            for known in nodes.values():
                if name is None and known[1] == cont and math.hypot(known[2] - x, known[3] - y) < 60:
                    name = known[0]
                    break
            nodes[nid] = (name or f"Flight point {nid}", cont, round(x, 1), round(y, 1), 0)
            synthesized += 1
    if synthesized:
        log(f"  {synthesized} flight points placed from path geometry (no TaxiNodes export for {FOREVER})")
    paths, used = [], set()
    for r in db2("TaxiPath"):
        a, b = int(r["FromTaxiNode"]), int(r["ToTaxiNode"])
        stops = sum(1 for n in path_nodes.get(int(r["ID"]), []) if int(n["Delay"]) > 0)
        if a != b and stops < 2 and a in nodes and b in nodes and lengths.get(int(r["ID"]), 0) > 0:
            paths.append((a, b, int(lengths[int(r["ID"])] / FLIGHT_SPEED) + 5))
            used.add(a)
            used.add(b)
    nodes = {i: n for i, n in nodes.items() if i in used}
    log(f"  {len(nodes)} flight points, {len(paths)} flight links")
    return nodes, paths


# ---------------------------------------------------------------------------
# Service NPCs and mailboxes (the Services module's "nearest ..." routing)
# ---------------------------------------------------------------------------

# Vanilla NpcFlags bits.
NPC_FLAGS = {"innkeeper": 128, "banker": 256, "auction": 4096, "repair": 16384, "trainer": 16}


def build_services(sql, spawns):
    """[(kind, name, subname, side, continent, world x, world y)] for every
    spawned repairer, innkeeper, auctioneer, banker and trainer, plus every
    mailbox. side: 0 both factions, 1 Alliance only, 2 Horde only."""
    import csv
    side_of = {}
    for r in db2("FactionTemplate"):
        enemies = int(r["EnemyGroup"] or 0)
        side_of[int(r["ID"])] = 1 if enemies & 4 else (2 if enemies & 2 else 0)
    rows, stats = [], defaultdict(int)
    for r in sql_rows(sql, "creature_template"):
        flags = int(r.get("NpcFlags") or 0)
        kinds = [k for k, bit in NPC_FLAGS.items() if flags & bit]
        if not kinds or JUNK.search(r["Name"] or ""):
            continue
        side = side_of.get(int(r.get("Faction") or 0), 0)
        placed = []
        for map_id, wx, wy in spawns.get(("npc", int(r["Entry"])), []):
            if map_id not in (0, 1) or any(p[0] == map_id and math.hypot(p[1] - wx, p[2] - wy) < 50 for p in placed):
                continue
            placed.append((map_id, wx, wy))
            for kind in kinds:
                sub = r.get("SubName") or ""
                if sub.upper() == "NULL":
                    sub = ""
                rows.append((kind, r["Name"], sub, side, map_id, round(wx, 1), round(wy, 1)))
                stats[kind] += 1
    mailboxes = {int(r["entry"]) for r in sql_rows(sql, "gameobject_template") if str(r.get("type")) == "19"}
    for entry in mailboxes:
        for map_id, wx, wy in spawns.get(("object", entry), []):
            if map_id in (0, 1):
                rows.append(("mailbox", "Mailbox", "", 0, map_id, round(wx, 1), round(wy, 1)))
                stats["mailbox"] += 1
    log("  services: " + ", ".join(f"{k} {v}" for k, v in sorted(stats.items())))
    return rows


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(HERE, "..", "Media", "QuestListData.lua"))
    ap.add_argument("--fetch-npcs", action="store_true")
    ap.add_argument("--refresh-npcs", action="store_true")
    ap.add_argument("--store", default=os.path.join(CACHE, "voice_lines.json"))
    args = ap.parse_args()

    sql = fetch_file(CMANGOS_SQL, os.path.join(CACHE, "ClassicDB.sql.gz"))
    zones, areas = load_zone_maps()
    area_by_name = {name.lower(): aid for aid, name in areas.items()}
    listing = load_listing()
    givers, spawns, names, venders = load_vanilla(sql)
    # a quest classic-db has is Classic; the rest are Forever's own (user,
    # 2026-09-23: "Classic" / "Forever" on each quest, to tell new from old)
    classic_ids = {int(r["entry"]) for r in sql_rows(sql, "quest_template")}
    store = json.load(open(args.store, encoding="utf-8")) if os.path.exists(args.store) else {}
    learned = {int(k): v for k, v in store.get("npcs", {}).items() if v.get("x") is not None}
    forever_ids = [q for q in listing if q >= 60000]
    fgivers, npc_zone, fenders, npc_pos = forever_givers(forever_ids, args.fetch_npcs or args.refresh_npcs, args.refresh_npcs)

    # Quests met in game that Wowhead does not list: title and giver from the
    # collector, level unknown (0), zone and position from where you stood.
    for qid, kinds in store.get("quests", {}).items():
        if not qid.isdigit() or int(qid) in listing:
            continue
        rec = kinds.get("accept") or kinds.get("progress") or kinds.get("complete")
        if not isinstance(rec, dict):
            continue
        npc = learned.get(rec.get("npcID") or -1, {})
        listing[int(qid)] = {"id": int(qid), "name": rec.get("title") or "", "level": kinds.get("_level") or 0, "reqlevel": 0,
                             "side": 0, "reqclass": 0, "category": area_by_name.get((npc.get("mapName") or "").lower(), 0)}
        if rec.get("npcID"):
            fgivers[int(qid)] = {"npcID": rec["npcID"], "name": rec.get("npc") or ""}

    starters = load_starters(sql, spawns, zones, list(listing), args.fetch_npcs)

    chain_of, chain_names, prev_of = build_chains(sql, listing)
    wh_zones = load_wowhead_zones()
    for zid, (name, _, _) in wh_zones.items():
        areas.setdefault(zid, name)   # Forever's new zones and instances
    instances = {zid for zid, (_, kind, _) in wh_zones.items() if kind in (2, 3)}
    raids = {zid for zid, (_, kind, _) in wh_zones.items() if kind == 3}
    # Instance map -> the instance's zone, for items found only inside one.
    # Wowhead files some instances under another ID than the client's area
    # (Blackrock Spire: the dungeon is 17804, 1583 the zone), matched by name;
    # one it lists only as a zone (Onyxia's Lair) is an instance by the client's
    # own map type.
    instance_by_name = {wh_zones[z][0].lower(): z for z in instances}
    map_area, unlisted = {}, {}                    # unlisted: area -> (name, raid), added when a starter is there
    for r in db2("Map"):
        itype, area = int(r.get("InstanceType") or 0), int(r.get("AreaTableID") or 0)
        if itype not in (1, 2) or not area:
            continue
        if area not in instances:
            area = instance_by_name.get((r.get("MapName_lang") or "").lower(), area)
        if area not in instances:
            unlisted[area] = (r.get("MapName_lang") or str(area), itype == 2)
        map_area[int(r["ID"])] = area
    # Wowhead's instance pages list only quests already filed under the
    # instance, and Forever's new instances have no quest data there at all,
    # so there is nothing extra to learn from them; quests picked up inside an
    # instance are caught through the giver zone below.
    instance_quests = {}
    import csv as _csv
    continent_of = {int(r["ID"]): int(r["ContinentID"] or 0) for r in db2("AreaTable")}
    for zid, (_, _, cat) in wh_zones.items():
        if continent_of.get(zid) not in (0, 1):
            continent_of[zid] = cat if cat in (0, 1) else -1
    # Attunement chains: any chain holding an attunement quest, plus lone ones.
    attune_chains = set()
    attune_quests = set()
    for qid, q in listing.items():
        title = (q.get("name") or "").lower()
        if title in ATTUNEMENT_TITLES or "attune" in title:
            attune_quests.add(qid)
            if chain_of.get(qid):
                attune_chains.add(chain_of[qid])

    rows = []
    used_zones = set()
    used_dungeons = {}
    stats = defaultdict(int)
    for qid, q in sorted(listing.items()):
        if JUNK.search(q.get("name") or ""):
            continue
        quest_zone = q["category"] if q["category"] > 0 else 0
        giver_name, giver_zone, gx, gy, kind = "", 0, 0, 0, 0
        world = (-1, 0, 0)   # continent, world x, world y of a vanilla spawn (placed by the client)
        giver_id = 0         # creature entry of an NPC giver, for the Voice Over race / gender lookup
        candidates = givers.get(qid, [])
        placed = None
        # Vanilla giver with spawn: prefer a spawn inside the quest's own zone.
        for gkind, entry in candidates:
            for map_id, wx, wy in spawns.get((gkind, entry), []):
                loc = locate(zones, map_id, wx, wy)
                if loc and (placed is None or (quest_zone and loc[0]["areaID"] == quest_zone and placed[0][0]["areaID"] != quest_zone)):
                    placed = (loc, gkind, entry, map_id, wx, wy)
        if placed:
            (z, px, py), gkind, entry, map_id, wx, wy = placed
            giver_name, giver_zone, gx, gy = names.get((gkind, entry), ""), z["areaID"], px, py
            world = (map_id, round(wx, 1), round(wy, 1))
            giver_id = entry if gkind == "npc" else 0
            kind = 1 if gkind == "npc" else 2
            stats["vanilla giver placed"] += 1
        elif candidates:
            gkind, entry = candidates[0]
            giver_name, kind = names.get((gkind, entry), ""), 1 if gkind == "npc" else 2
            giver_id = entry if gkind == "npc" else 0
            stats["vanilla giver without spawn"] += 1
        elif qid in fgivers:
            g = fgivers[qid]
            giver_name, kind = g["name"], 1
            giver_id = int(g.get("npcID") or 0)
            npc = learned.get(g["npcID"])
            wh = place_on_map(zones, npc_pos.get(g["npcID"]), quest_zone)
            if npc and npc.get("mapName"):
                giver_zone = area_by_name.get(npc["mapName"].lower(), 0)
                gx, gy = npc["x"], npc["y"]
                stats["forever giver placed from in-game position"] += 1
            elif wh:
                giver_zone, gx, gy = wh[0], wh[1], wh[2]
                world = (wh[3], wh[4], wh[5])
                stats["forever giver placed from Wowhead"] += 1
            else:
                giver_zone = npc_zone.get(g["npcID"], 0)
                stats["forever giver, zone only" if giver_zone else "forever giver, no zone"] += 1
        elif qid in starters:
            kind, giver_name, pts = starters[qid]
            giver_zone, gx, gy, world = starter_place(zones, pts, quest_zone, map_area)
            if giver_zone in unlisted and world[0] < 0:
                name, is_raid = unlisted.pop(giver_zone)
                instances.add(giver_zone)
                areas.setdefault(giver_zone, name)
                if is_raid:
                    raids.add(giver_zone)
            what = {2: "an object", 3: "a dropped item", 4: "an item picked up"}[kind]
            stats[f"begun by {what}, " + ("placed" if world[0] >= 0 else "in an instance" if giver_zone else "no place")] += 1
        else:
            stats["no giver known"] += 1
        # Who takes the quest back, placed like the giver.
        ender_name, ender_zone, ender_id, ender_world = "", 0, 0, (-1, 0, 0)
        ecands = venders.get(qid, [])
        eplaced = None
        for gkind, entry in ecands:
            for map_id, wx, wy in spawns.get((gkind, entry), []):
                loc = locate(zones, map_id, wx, wy)
                if loc and (eplaced is None or (quest_zone and loc[0]["areaID"] == quest_zone and eplaced[0][0]["areaID"] != quest_zone)):
                    eplaced = (loc, gkind, entry, map_id, wx, wy)
        if eplaced:
            (z, _, _), gkind, entry, map_id, wx, wy = eplaced
            ender_name, ender_zone = names.get((gkind, entry), ""), z["areaID"]
            ender_world = (map_id, round(wx, 1), round(wy, 1))
            ender_id = entry if gkind == "npc" else 0
            stats["turn-in placed"] += 1
        elif ecands:
            gkind, entry = ecands[0]
            ender_name = names.get((gkind, entry), "")
            ender_id = entry if gkind == "npc" else 0
            stats["turn-in without spawn"] += 1
        elif qid in fenders:
            e = fenders[qid]
            ender_name, ender_id = e["name"], int(e.get("npcID") or 0)
            wh = place_on_map(zones, npc_pos.get(ender_id), quest_zone)
            if wh:
                ender_zone = wh[0]
                ender_world = (wh[3], wh[4], wh[5])
                stats["forever turn-in placed from Wowhead"] += 1
            else:
                ender_zone = npc_zone.get(ender_id, 0)
                stats["forever turn-in (zone %s)" % ("known" if ender_zone else "unknown")] += 1
        for aid in (quest_zone, giver_zone, ender_zone):
            if aid:
                used_zones.add(aid)
        event = q["category"] if q["category"] in EVENTS else 0
        if event:
            stats["event / holiday quests"] += 1
        # Dungeon and raid quests: filed under an instance in Wowhead's zone
        # list, listed on the instance's Wowhead page, or picked up inside one
        # (the collector records the instance map as the giver's zone).
        dungeon = 0
        if q["category"] in instances:
            dungeon = q["category"]
        elif qid in instance_quests:
            dungeon = instance_quests[qid]
        elif giver_zone in instances:
            dungeon = giver_zone
        if dungeon:
            used_dungeons[dungeon] = areas.get(dungeon, str(dungeon))
            stats["dungeon / raid quests"] += 1
        attunement = 1 if (qid in attune_quests or chain_of.get(qid, 0) in attune_chains) else 0
        if attunement:
            stats["attunement quests"] += 1
        rows.append((qid, q["name"], q.get("level") or 0, q.get("reqlevel") or 0, q.get("side") or 0, q.get("reqclass") or 0,
                     quest_zone, giver_zone, giver_name, gx, gy, kind, event, chain_of.get(qid, 0), dungeon, attunement,
                     prev_of.get(qid, 0), world[0], world[1], world[2], giver_id,
                     ender_name, ender_id, ender_zone, ender_world[0], ender_world[1], ender_world[2],
                     1 if qid in classic_ids else 2))

    # Every instance Wowhead lists, so the panel can show the ones without quests too.
    for zid in instances:
        used_dungeons.setdefault(zid, areas.get(zid, str(zid)))
    entrances, transports = build_map_points(sql, zones, used_dungeons, raids)
    taxi_nodes, taxi_paths = build_taxi()
    services = build_services(sql, spawns)

    with open(os.path.abspath(args.out), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by Tools/build_quest_list.py. Do not edit by hand.\n")
        fh.write("-- Sources: Wowhead Forever listing, cmangos classic-db, wago.tools DB2 exports, in-game positions.\n\n")
        fh.write("MelloUI_QuestListData = {\n")
        fh.write("\t-- quest fields: id, title, level, required level, side (1 Alliance, 2 Horde, 3 both), class mask,\n")
        fh.write("\t-- quest zone (area id), pick-up zone (area id), giver name, giver x, giver y,\n")
        fh.write("\t-- giver kind (1 NPC, 2 object, 3 item dropped by creatures, 4 item picked up; 3 and 4 at their densest spot),\n")
        fh.write("\t-- event (key into events, 0 for none), chain (key into chains, 0 for none), dungeon (key into dungeons, 0 for none),\n")
        fh.write("\t-- attunement (1 when the quest or its chain grants access to an instance),\n")
        fh.write("\t-- previous quest in the chain, giver continent, giver world x, giver world y, giver NPC entry,\n")
        fh.write("\t-- turn-in name, turn-in NPC entry, turn-in zone (area id), turn-in continent, turn-in world x, turn-in world y,\n")
        fh.write("\t-- origin (1 Classic: in classic-db, 2 Forever: Forever's own)\n")
        fh.write("\tzones = {\n")
        for aid in sorted(used_zones):
            fh.write(f"\t\t[{aid}] = {lua_str(areas.get(aid, str(aid)))},\n")
        fh.write("\t},\n\t-- zone -> continent: 0 Eastern Kingdoms, 1 Kalimdor, -1 elsewhere\n\tzoneContinent = {\n")
        for aid in sorted(used_zones):
            fh.write(f"\t\t[{aid}] = {continent_of.get(aid, -1)},\n")
        fh.write("\t},\n\tcontinentNames = { [0] = \"Eastern Kingdoms\", [1] = \"Kalimdor\" },\n")
        fh.write("\t-- instance -> { min level, max level } from Wowhead's zone list, for sorting dungeons by their level\n\tdungeonLevel = {\n")
        for did in sorted(used_dungeons):
            lo, hi = load_wowhead_zones.levels.get(did, (0, 0))
            fh.write(f"\t\t[{did}] = {{ {lo}, {hi} }},\n")
        fh.write("\t},\n\traids = {\n")
        for did in sorted(used_dungeons):
            if did in raids:
                fh.write(f"\t\t[{did}] = true,\n")
        fh.write("\t},\n\tevents = {\n")
        for cat in sorted(set(EVENTS)):
            fh.write(f"\t\t[{cat}] = {lua_str(EVENTS[cat])},\n")
        fh.write("\t},\n\tdungeons = {\n")
        for did in sorted(used_dungeons):
            fh.write(f"\t\t[{did}] = {lua_str(used_dungeons[did])},\n")
        fh.write("\t},\n")
        fh.write("\t-- instance entrances: dungeon (key into dungeons, 0 unknown), name, continent, world x, world y,\n")
        fh.write("\t-- zone (area id, build-time guess), map x, map y, kind (1 dungeon, 2 raid)\n\tentrances = {\n")
        for e in entrances:
            did, name, cont, wx, wy, zone, px, py, kind = e
            fh.write(f"\t\t{{{did},{lua_str(name)},{cont},{wx},{wy},{zone},{px},{py},{kind}}},\n")
        fh.write("\t},\n")
        fh.write("\t-- transports: kind (1 boat, 2 zeppelin), faction (0 neutral, 1 Alliance, 2 Horde), label, dock name,\n")
        fh.write("\t-- continent, world x, world y, zone (build-time guess), map x, map y, destination continent, world x, world y\n\ttransports = {\n")
        for t in transports:
            kind, faction, label, here, cont, wx, wy, zone, px, py, dcont, dx, dy = t
            fh.write(f"\t\t{{{kind},{faction},{lua_str(label)},{lua_str(here)},{cont},{wx},{wy},{zone},{px},{py},{dcont},{dx},{dy}}},\n")
        fh.write("\t},\n")
        fh.write("\t-- flight points: [id] = { name, continent, world x, world y, faction (0 both, 1 Alliance, 2 Horde) }\n\ttaxiNodes = {\n")
        for nid in sorted(taxi_nodes):
            name, cont, wx, wy, faction = taxi_nodes[nid]
            fh.write(f"\t\t[{nid}] = {{{lua_str(name)},{cont},{wx},{wy},{faction}}},\n")
        fh.write("\t},\n\t-- services: kind (repair, mailbox, innkeeper, auction, banker, trainer), name, subname,\n")
        fh.write("\t-- side (0 both, 1 Alliance, 2 Horde), continent, world x, world y\n\tservices = {\n")
        for kind, name, sub, side, cont, wx, wy in services:
            fh.write(f"\t\t{{{lua_str(kind)},{lua_str(name)},{lua_str(sub)},{side},{cont},{wx},{wy}}},\n")
        fh.write("\t},\n\t-- flight links: from id, to id, seconds in the air\n\ttaxiPaths = {\n")
        for a, b, secs in taxi_paths:
            fh.write(f"\t\t{{{a},{b},{secs}}},\n")
        fh.write("\t},\n\tchains = {\n")
        for cid in sorted(chain_names):
            fh.write(f"\t\t[{cid}] = {lua_str(chain_names[cid])},\n")
        fh.write("\t},\n\tclasses = {\n")
        for mask, cls in sorted(CLASSES.items()):
            fh.write(f"\t\t[{mask}] = {lua_str(cls)},\n")
        fh.write("\t},\n\tquests = {\n")
        for r in rows:
            qid, title, level, req, side, cls, qz, gz, gname, gx, gy, kind, event, chain, dungeon, attunement, prev, wc, wx, wy, npc, ename, enpc, ezone, ec, ex, ey, origin = r
            fh.write(f"\t\t{{{qid},{lua_str(title)},{level},{req},{side},{cls},{qz},{gz},{lua_str(gname)},{gx},{gy},{kind},{event},{chain},{dungeon},{attunement},{prev},{wc},{wx},{wy},{npc},{lua_str(ename)},{enpc},{ezone},{ec},{ex},{ey},{origin}}},\n")
        fh.write("\t},\n}\n")
    log("client tables: " + ", ".join(f"{name} {build}" for name, build in sorted(db2.used.items())))
    log(f"wrote {args.out}: {len(rows)} quests, {len(used_zones)} zones")
    for k, v in sorted(stats.items()):
        log(f"  {k}: {v}")


if __name__ == "__main__":
    main()
