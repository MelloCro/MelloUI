#!/usr/bin/env python3
"""
Build MelloUI_Companion/QuestObjectiveData.lua (in the route data companion,
which MelloUI loads on demand) for the Route module: where each quest's
objectives can be done, so the route goes to the nearest place still needed
for the tracked quest instead of the middle of the game's quest area (user,
2026-09-23: "now start on the route to quest objectives").

For every quest the Quest List knows that cmangos classic-db has:
  kill / talk / use   ReqCreatureOrGOId1-4: the creature (> 0) or object (< 0)
                      and its spawns
  collect             ReqItemId1-4: the creatures whose loot has the item
                      (creature_loot_template through creature_template.LootId)
                      and the chests / nodes whose loot has it
                      (gameobject_loot_template through gameobject_template.data1),
                      or, when nothing drops it, the vendors who sell it
                      (npc_vendor, and npc_vendor_template through
                      creature_template.VendorTemplateId), and their spawns
  explore             areatrigger_involvedrelation: the trigger's place
                      (AreaTrigger of the Classic Era client)
Forever's own quests (not in classic-db) come from their Wowhead pages
(cached by import_wowhead_quests.py): the objective list's creature, object
and item links. A creature is placed by its classic-db spawns, else by its
Wowhead NPC page's map; an item by what drops it (classic-db's loot for a
Classic item, else the item page's "dropped by" and "contained in" lists,
those creatures and objects placed as above); an object by its Wowhead page's
map. --fetch downloads the item, NPC and object pages not cached yet (one
every 2.5 s, in rounds until nothing new is needed).

Each objective keeps the names the game's objective line is matched by (the
creature, object or item name, and the quest's own objective text when it
has one) and its places, thinned to one per GRID yards, kept to the quest's
own zone when any lie there, at most CAP of them.

Output (world coordinates as the client tables give them, rounded to yards),
one packed string per quest; Route decodes a quest's when it is tracked
(memory audit, 2026-09-24: as tables the data held 1.7 MB in game, and
loading it made as much again in garbage):
  MelloUI_QuestObjectiveData = {
    [questID] = "<kind><map><name>|<alt>|<x1><y1><x2><y2>...~<kind><map>...~",
  }
  kind: 1 creature, 2 object, 3 item, 4 area; map: 0 Eastern Kingdoms,
  1 Kalimdor (one digit each); each coordinate is three characters, the value
  plus COORD_BIAS in base 64 with the digits "0" (chr 48) to "o" (chr 111).
  Decoded, an objective is { kind, "name", "alt", map, x1, y1, x2, y2, ... }.

    python Tools/build_quest_objectives.py [--fetch]
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_quest_list import (sql_rows, load_zone_maps, locate, load_listing, db2, fetch_file,  # noqa: E402
                              CMANGOS_SQL, CACHE, log, lua_str, WOWHEAD, place_on_map)
from import_wowhead_quests import fetch as fetch_page, BASE  # noqa: E402


# ---------------------------------------------------------------------------
# Wowhead pages (Forever quests)
# ---------------------------------------------------------------------------

def page_path(kind, i):
    return os.path.join(WOWHEAD, f"{kind}_{i}.html")


def read_page(kind, i):
    path = page_path(kind, i)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    return None


def quest_objectives(page):
    """The objective list of a quest page: [(kind, id, name)], kind npc / object / item."""
    i = page.find('class="icon-list"')
    if i < 0:
        return []
    block = page[i:page.find("</table>", i)]
    out = []
    for kind, oid, name in re.findall(r'href="/forever/(npc|object|item)=(\d+)[^"]*"[^>]*>([^<]*)<', block):
        entry = (kind, int(oid), name.strip())
        if entry not in out:
            out.append(entry)
    return out


def mapper_points(page):
    """Every point of a page's map (g_mapperData): [(areaID, uiMapID, x %, y %)]."""
    m = re.search(r"g_mapperData\s*=\s*(\{.*?\});", page or "", re.S)
    if not m:
        return []
    try:
        data = json.loads(m.group(1))
    except ValueError:
        return []
    out = []
    for area, spots in data.items():
        for spot in spots if isinstance(spots, list) else []:
            ui = spot.get("uiMapId")
            for c in spot.get("coords") or []:
                if ui and len(c) >= 2:
                    out.append((int(area), int(ui), float(c[0]), float(c[1])))
    return out


def listview(page, lv_id):
    """The data of one Listview of a page (dropped-by, contained-in-object ...)."""
    i = (page or "").find(f"id: '{lv_id}'")
    if i < 0:
        return []
    j = page.find("data:", i)
    end = page.find("new Listview(", i + 10)
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

GRID = 40          # yards: one place kept per cell
CAP = 30           # places kept per objective at most
MIN_CHANCE = 0.5   # a drop rarer than this (percent) is no place to farm the item


def thin(points, grid=GRID, cap=CAP):
    """One point per grid cell, then at most `cap`, evenly through the list."""
    cells = {}
    for m, x, y in points:
        cells.setdefault((m, int(x // grid), int(y // grid)), (m, round(x), round(y)))
    out = sorted(cells.values())
    if len(out) > cap:
        step = len(out) / cap
        out = [out[int(i * step)] for i in range(cap)]
    return out


# ---------------------------------------------------------------------------
# Packed output (decoded by ObjectivesOf in Modules/Route.lua)
# ---------------------------------------------------------------------------

COORD_BIAS = 131072   # a coordinate is stored as value + COORD_BIAS: -131072 .. 131071 yards
COORD_ZERO = 48       # base-64 digit 0 is "0"; the digits run to "o", clear of "|" and "~"


def pack_coord(v):
    """A world coordinate (whole yards) as three base-64 characters."""
    n = int(v) + COORD_BIAS
    if n != v + COORD_BIAS or not 0 <= n < 64 ** 3:
        raise ValueError(f"coordinate {v!r} cannot be packed")
    return chr(COORD_ZERO + n // 4096) + chr(COORD_ZERO + n // 64 % 64) + chr(COORD_ZERO + n % 64)


def pack_objectives(objs):
    """One quest's objectives [(kind, name, alt, [(map, x, y), ...])] as its
    packed string: <kind><map><name>|<alt>|<coordinates>~ per objective, with
    the places on the map of its first place."""
    parts = []
    for kind, name, alt, pts in objs:
        m = pts[0][0]
        if not (0 < kind < 10 and 0 <= m < 10):
            raise ValueError(f"kind {kind!r} and map {m!r} must be one digit each")
        for text in (name, alt):
            if "|" in text or "~" in text:
                raise ValueError(f"{text!r}: '|' and '~' separate the packed fields")
        coords = "".join(pack_coord(x) + pack_coord(y) for pm, x, y in pts if pm == m)
        parts.append(f"{kind}{m}{name}|{alt}|{coords}~")
    return "".join(parts)


def write_data(path, out):
    """MelloUI_Companion/QuestObjectiveData.lua from {questID: [(kind, name, alt, [(map, x, y), ...])]}."""
    with open(os.path.abspath(path), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by Tools/build_quest_objectives.py from cmangos classic-db and Wowhead's Forever pages. Do not edit by hand.\n")
        fh.write("-- [questID] = packed objectives, one string per quest; Route decodes the tracked quest's (ObjectivesOf).\n")
        fh.write("-- Each objective is <kind><map><name>|<alt>|<x1><y1><x2><y2>...~ : kind 1 creature, 2 object, 3 item,\n")
        fh.write("-- 4 area; map 0 Eastern Kingdoms, 1 Kalimdor; world coordinates in yards, three characters each: the\n")
        fh.write(f"-- value plus {COORD_BIAS} in base 64, digits \"0\" (chr 48) to \"o\" (chr 111).\n\n")
        fh.write("MelloUI_QuestObjectiveData = {\n")
        for qid in sorted(out):
            fh.write(f"\t[{qid}]={lua_str(pack_objectives(out[qid]))},\n")
        fh.write("}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(HERE, "..", "MelloUI_Companion", "QuestObjectiveData.lua"))
    ap.add_argument("--fetch", action="store_true", help="download the Wowhead item / NPC / object pages Forever quests need")
    args = ap.parse_args()

    sql = fetch_file(CMANGOS_SQL, os.path.join(CACHE, "ClassicDB.sql.gz"))
    zones, _ = load_zone_maps()
    listing = load_listing()

    log("reading cmangos creatures, objects, items and loot")
    cname, lootOf = {}, defaultdict(list)          # creature entry -> name; loot id -> creature entries
    vendorOf = defaultdict(list)                   # vendor template -> creature entries
    for r in sql_rows(sql, "creature_template"):
        e = int(r["Entry"])
        cname[e] = r["Name"]
        loot = int(r["LootId"] or 0)
        if loot:
            lootOf[loot].append(e)
        vt = int(r.get("VendorTemplateId") or 0)
        if vt:
            vendorOf[vt].append(e)
    oname, oLootOf = {}, defaultdict(list)         # object entry -> name; loot id -> object entries
    for r in sql_rows(sql, "gameobject_template"):
        e = int(r["entry"])
        oname[e] = r["name"]
        if int(r["type"]) in (3, 25) and int(r["data1"] or 0):   # chests, fishing holes
            oLootOf[int(r["data1"])].append(e)
    iname = {int(r["entry"]): r["name"] for r in sql_rows(sql, "item_template")}
    dropsC, dropsO = defaultdict(set), defaultdict(set)   # item -> creature / object entries
    for table, owners, drops in (("creature_loot_template", lootOf, dropsC), ("gameobject_loot_template", oLootOf, dropsO)):
        for r in sql_rows(sql, table):
            if int(r["mincountOrRef"] or 0) < 0:
                continue   # a reference to a shared table: world drops, not a place
            chance = abs(float(r["ChanceOrQuestChance"] or 0))
            if chance and chance < MIN_CHANCE:
                continue
            for owner in owners.get(int(r["entry"]), ()):
                drops[int(r["item"])].add(owner)
    sells = defaultdict(set)                       # item -> vendor creature entries
    for r in sql_rows(sql, "npc_vendor"):
        sells[int(r["item"])].add(int(r["entry"]))
    for r in sql_rows(sql, "npc_vendor_template"):
        for e in vendorOf.get(int(r["entry"]), ()):
            sells[int(r["item"])].add(e)
    spawnsC, spawnsO = defaultdict(list), defaultdict(list)
    for r in sql_rows(sql, "creature"):
        spawnsC[int(r["id"])].append((int(r["map"]), float(r["position_x"]), float(r["position_y"])))
    for r in sql_rows(sql, "gameobject"):
        spawnsO[int(r["id"])].append((int(r["map"]), float(r["position_x"]), float(r["position_y"])))
    triggers = {}
    for r in db2("AreaTrigger"):
        try:
            triggers[int(r["ID"])] = (int(r["ContinentID"]), float(r["Pos_0"]), float(r["Pos_1"]))
        except (KeyError, ValueError):
            pass
    explore = defaultdict(list)
    for r in sql_rows(sql, "areatrigger_involvedrelation"):
        explore[int(r["quest"])].append(int(r["id"]))

    zone_cache = {}

    def zone_of(p):
        if p not in zone_cache:
            loc = locate(zones, p[0], p[1], p[2])
            zone_cache[p] = loc[0]["areaID"] if loc else 0
        return zone_cache[p]

    def places(points, quest_zone):
        points = [p for p in points if p[0] in (0, 1)]   # the two continents: what Route can walk
        if quest_zone:
            here = [p for p in points if zone_of(p) == quest_zone]
            if here:
                points = here
        return thin(points)

    log("building objectives")
    out, stats = {}, defaultdict(int)
    for r in sql_rows(sql, "quest_template"):
        qid = int(r["entry"])
        if qid not in listing:
            continue
        qzone = listing[qid].get("category") or 0
        qzone = qzone if qzone > 0 else 0
        objs = []
        for i in range(1, 5):
            alt = (r.get(f"ObjectiveText{i}") or "").strip()
            target = int(r.get(f"ReqCreatureOrGOId{i}") or 0)
            if target > 0:
                pts = places(spawnsC.get(target, []), qzone)
                objs.append((1, cname.get(target, ""), alt, pts))
            elif target < 0:
                pts = places(spawnsO.get(-target, []), qzone)
                objs.append((2, oname.get(-target, ""), alt, pts))
            item = int(r.get(f"ReqItemId{i}") or 0)
            if item:
                pts = []
                for c in dropsC.get(item, ()):
                    pts += spawnsC.get(c, [])
                for o in dropsO.get(item, ()):
                    pts += spawnsO.get(o, [])
                if not pts:
                    for v in sells.get(item, ()):
                        pts += spawnsC.get(v, [])
                objs.append((3, iname.get(item, ""), "", places(pts, qzone)))
        for t in explore.get(qid, []):
            if t in triggers:
                objs.append((4, "", "", places([triggers[t]], 0)))
        objs = [o for o in objs if o[3]]
        if objs:
            out[qid] = objs
            for o in objs:
                stats[("creature", "object", "item", "area")[o[0] - 1]] += 1
    stats["classic quests"] = len(out)

    # ---- Forever's own quests, from their Wowhead pages
    classic = set(out) | {int(r["entry"]) for r in sql_rows(sql, "quest_template")}
    forever = []
    for qid in sorted(listing):
        if qid in classic:
            continue
        page = read_page("quest", qid)
        objs = quest_objectives(page) if page else []
        if objs:
            forever.append((qid, objs))

    def wh_points(kind, i):
        """(map, x, y) world points of an NPC / object from its Wowhead page's map."""
        pts = []
        for area, ui, px, py in mapper_points(read_page(kind, i)):
            placed = place_on_map(zones, [(area, ui, px, py)])
            if placed:
                pts.append((placed[3], placed[4], placed[5]))
        return pts

    def creature_points(i):
        return spawnsC.get(i) or wh_points("npc", i)

    def object_points(i):
        return spawnsO.get(i) or wh_points("object", i)

    def item_sources(i):
        """Creatures and objects an item comes from: ([npc ids], [object ids])."""
        if i in iname:   # a Classic item: classic-db's loot, then vendors
            npcs, objs = list(dropsC.get(i, ())), list(dropsO.get(i, ()))
            if not npcs and not objs:
                npcs = list(sells.get(i, ()))
            return npcs, objs
        page = read_page("item", i)
        npcs = [int(d["id"]) for d in listview(page, "dropped-by") if d.get("id")]
        objs = [int(d["id"]) for d in listview(page, "contained-in-object") if d.get("id")]
        return npcs, objs

    def missing_pages():
        need = set()
        for _, objs in forever:
            for kind, i, _ in objs:
                if kind == "npc" and i not in spawnsC and not read_page("npc", i):
                    need.add(("npc", i))
                elif kind == "object" and i not in spawnsO and not read_page("object", i):
                    need.add(("object", i))
                elif kind == "item":
                    if i not in iname and not read_page("item", i):
                        need.add(("item", i))
                    else:
                        npcs, objs2 = item_sources(i)
                        for n in npcs:
                            if n not in spawnsC and not read_page("npc", n):
                                need.add(("npc", n))
                        for o in objs2:
                            if o not in spawnsO and not read_page("object", o):
                                need.add(("object", o))
        return sorted(need)

    if args.fetch:
        for round_no in range(1, 4):
            need = missing_pages()
            if not need:
                break
            log(f"round {round_no}: fetching {len(need)} Wowhead pages")
            for n, (kind, i) in enumerate(need, 1):
                try:
                    fetch_page(f"{BASE}/{kind}={i}", page_path(kind, i))
                except Exception as exc:  # noqa: BLE001
                    log(f"   {kind} {i}: {exc}")
                if n % 50 == 0:
                    log(f"   {n}/{len(need)}")
    left = missing_pages()
    if left:
        log(f"  {len(left)} Wowhead pages not cached (run with --fetch)")

    for qid, objs in forever:
        qzone = listing[qid].get("category") or 0
        qzone = qzone if qzone > 0 else 0
        entries = []
        for kind, i, name in objs:
            if kind == "npc":
                entries.append((1, name, "", places(creature_points(i), qzone)))
            elif kind == "object":
                entries.append((2, name, "", places(object_points(i), qzone)))
            else:
                npcs, objs2 = item_sources(i)
                pts = []
                for n in npcs:
                    pts += creature_points(n)
                for o in objs2:
                    pts += object_points(o)
                entries.append((3, name, "", places(pts, qzone)))
        entries = [e for e in entries if e[3]]
        if entries:
            out[qid] = entries
            stats["forever quests"] += 1
            for e in entries:
                stats[("creature", "object", "item", "area")[e[0] - 1]] += 1
    stats["quests"] = len(out)

    write_data(args.out, out)
    log(f"wrote {args.out}: " + ", ".join(f"{k} {v}" for k, v in sorted(stats.items())))


if __name__ == "__main__":
    main()
