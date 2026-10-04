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
  needed items        ReqSourceId1-4 / ReqSourceCount1-4: an item the quest
                      needs in the bags that is not itself an objective
                      (Marla's Last Wish: Samuel's Remains, dropped by
                      Samuel Fipps, before Marla's Grave can be used; user,
                      2026-09-28: "get the item first"). Linked to the
                      objective of the same number, else to the quest's only
                      objective, else to every one of them; placed where it
                      comes from: the creatures that drop it, then the
                      objects that hold it, or, when nothing drops it, the
                      vendors who sell it. ReqSourceCount is the most of it
                      that drops for the quest (cmangos' HasQuestForItem;
                      0: up to a stack, the count kept then): Route asks for
                      that many at once only where the objective takes them
                      together (1016's five bracers for one scroll), else for
                      as many as the objective still lacks, at most that
                      (746: a pick for each tool still missing). Left out:
                      the item the quest giver hands over (SrcItemId), one
                      that is also a collect objective, one that comes only
                      from the objective's own creature or object (nothing
                      to do first), one whose creatures or objects drop the
                      collect objective's item as well (6142 Clam Bait: the
                      clam meat drops as it is, the clams are a rare extra),
                      one of NOT_NEEDED, and one with no place in the open
                      world.
                      An objective that needs one is kept even when it has
                      no place of its own (1195 The Sacred Flame's filled
                      phial), so the item's sources can stand in for it.
Forever's own quests (not in classic-db) come from their Wowhead pages
(cached by import_wowhead_quests.py): the objective list's creature, object
and item links. A creature is placed by its classic-db spawns, else by its
Wowhead NPC page's map; an item by what drops it (classic-db's loot for a
Classic item, else the item page's "dropped by" and "contained in" lists,
those creatures and objects placed as above); an object by its Wowhead page's
map. --fetch downloads the item, NPC and object pages not cached yet (one
every 2.5 s, in rounds until nothing new is needed). Their pages list no
needed items (Wowhead shows only the item the quest giver hands over,
"Provided item", which is left out anyway), so Forever's quests have none.

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
  kind: 1 creature, 2 object, 3 item, 4 area (one digit); map: the world map
  id, 0 Eastern Kingdoms and 1 Kalimdor as one digit, a longer one between
  "#" signs (Forever's Zephras Isle: <kind>#2991#<name>|...); each coordinate
  is three characters, the value plus COORD_BIAS in base 64 with the digits
  "0" (chr 48) to "o" (chr 111). Places are kept on the open-world maps that
  have zone maps (0, 1 and 2991 today), never inside an instance.
  Decoded, an objective is { kind, "name", "alt", map, x1, y1, x2, y2, ... }.
  An objective may have no coordinates at all (one kept for a needed item).

  The needed items stand in a table of their own beside it, so no older
  Route (or any reader of the objective strings) ever sees them:
  MelloUI_QuestNeededItems = {
    [questID] = "<obj>|<item>|<count>|<item name>|<from><map><source name>|<x1><y1>...~...",
  }
  one record per place a needed item comes from. obj: the objective it is
  needed for (its place among the quest's packed objectives, counted from 1);
  item: its item id; count: the most of it that drops for the quest (how many
  the bags must hold, where the objective takes them at once); from: 1 a creature
  drops it, 2 an object holds it, 3 a vendor sells it; map and coordinates as
  an objective's. The same item's records repeat its obj|item|count|name.

  MelloUI_QuestMadeItems = { [questID] = "<obj>,<obj>..." }: the objectives
  whose item is made by using other items; once the bags hold them all, the
  tracker says to use them.

  Made items (the user, 2026-10-04, Traditions of the Bluff -- buy four things
  from four vendors, combine them, use it at a spot: "i want all these types of
  quests to work like that"), from the client's own tables (SpellEffect,
  SpellReagents, ItemEffect, ItemXItemEffect, exported with wow.export into the
  cache like Map): an item is made when a spell that an item casts on use
  creates it; it is made from that spell's reagents and the items that cast it
  (an item made by more than one such spell is left alone: which one?). A
  quest's item objective that comes from no place of its own (nothing drops it,
  holds it or sells it) gets those items as its needed items, each from where
  it comes from, and is marked made; one whose needed items (ReqSourceId) are
  all among them is marked made too (Pendant of the Sea Lion's two halves). A
  spell that calls a creature makes nothing (Ishamuhale's Fang: the carcass
  calls the beast). Only a whole recipe: every part from a place (most of a
  Darkmoon deck's cards drop anywhere: none of them then), none of them another
  objective of the quest (Answering Air's Call's fragment is made of the very
  essences the quest asks for). A Forever item comes from what its Wowhead page
  says drops it or holds it, else from what sells it; for a part, only what
  drops it at MIN_CHANCE or more (the page's count out of kills), and nothing
  that drops it when more than WORLD_DROP kinds of creature do (a world drop:
  the Forever Darkmoon decks' cards).

    python Tools/build_quest_objectives.py [--fetch]
"""
import argparse
import html
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
        # plain text on one line, as the quest log shows it: the page's HTML can
        # break a name ("Telenos\nLeafwhisper") and escapes quotes ("&quot;Badwind&quot; Bennic")
        entry = (kind, int(oid), " ".join(html.unescape(name).split()))
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
WORLD_DROP = 20    # a made item's part that more kinds of creature drop (Wowhead) is a world drop: no place

# Needed items the quest turns into another item on the way, not into the
# objective: held or not says nothing about what is left to do once that has
# begun, so the route would send the player back for one they have already
# turned (review, 2026-09-28). (quest, item): why.
NOT_NEEDED = {
    (2930, 9279): "Data Rescue: the white punch card becomes the yellow, blue and red one before the prismatic one",
}

# Made items (see the top): the client's tables say which spell creates an item and which item casts it on use
CREATE_ITEM = 24   # SpellEffect.Effect: the spell creates EffectItemType
ON_USE = 0         # ItemEffect.TriggerType: the item casts SpellID when it is used


def load_made_from():
    """{made item: {item it is made from: how many}} from the client's tables (see the top)."""
    creates = defaultdict(set)                     # spell -> the items it creates
    for r in db2("SpellEffect"):
        if int(r.get("Effect") or 0) == CREATE_ITEM and int(r.get("EffectItemType") or 0) > 0:
            creates[int(r["SpellID"])].add(int(r["EffectItemType"]))
    on_use = {}                                    # item effect -> its spell, when it creates an item
    for r in db2("ItemEffect"):
        spell = int(r.get("SpellID") or 0)
        if int(r.get("TriggerType") or 0) == ON_USE and spell in creates:
            on_use[int(r["ID"])] = spell
    cast_by = defaultdict(set)                     # spell -> the items that cast it on use
    for r in db2("ItemXItemEffect"):
        spell = on_use.get(int(r.get("ItemEffectID") or 0))
        if spell:
            cast_by[spell].add(int(r["ItemID"]))
    reagents = defaultdict(dict)                   # spell -> {item: how many}
    for r in db2("SpellReagents"):
        spell = int(r.get("SpellID") or 0)
        if spell in cast_by:
            for k in range(8):
                item = int(r.get(f"Reagent_{k}") or 0)
                if item > 0:
                    reagents[spell][item] = max(int(r.get(f"ReagentCount_{k}") or 0), 1)
    recipes = defaultdict(list)                    # made item -> [{item: how many}], one per spell
    for spell in sorted(cast_by):
        for made in creates[spell]:
            parts = dict(reagents.get(spell, {}))
            for user in cast_by[spell]:
                parts.setdefault(user, 1)
            parts.pop(made, None)
            if parts:
                recipes[made].append(parts)
    return {made: found[0] for made, found in recipes.items() if len(found) == 1}


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


def thin_tagged(points, grid=GRID, cap=CAP):
    """thin() for [((map, x, y), tag)]: each point kept keeps its tag (the
    source a needed item's place belongs to)."""
    cells = {}
    for (m, x, y), tag in points:
        cells.setdefault((m, int(x // grid), int(y // grid)), ((m, round(x), round(y)), tag))
    out = sorted(cells.values(), key=lambda c: c[0])
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


def pack_map(m):
    """A world map id in the packed form: one digit below 10 (0 Eastern
    Kingdoms, 1 Kalimdor: as before 0.14.0), else between "#" signs."""
    if not isinstance(m, int) or m < 0:
        raise ValueError(f"map {m!r} cannot be packed")
    return str(m) if m < 10 else f"#{m}#"


def check_text(text):
    """A name or objective text that can be packed: no field separator, no line break."""
    if "|" in text or "~" in text:
        raise ValueError(f"{text!r}: '|' and '~' separate the packed fields")
    if any(ord(ch) < 32 for ch in text):
        raise ValueError(f"{text!r}: a line break or control character cannot be packed")


def pack_places(pts):
    """The places on the map of the first one: (map, their coordinates); none
    (an objective kept for a needed item): map 0 and no coordinates."""
    if not pts:
        return 0, ""
    m = pts[0][0]
    return m, "".join(pack_coord(x) + pack_coord(y) for pm, x, y in pts if pm == m)


def pack_objectives(objs):
    """One quest's objectives [(kind, name, alt, [(map, x, y), ...])] as its
    packed string: <kind><map><name>|<alt>|<coordinates>~ per objective, with
    the places on the map of its first place (pack_map); none for one kept
    for a needed item alone."""
    parts = []
    for kind, name, alt, pts in objs:
        if not 0 < kind < 10:
            raise ValueError(f"kind {kind!r} must be one digit")
        for text in (name, alt):
            check_text(text)
        m, coords = pack_places(pts)
        parts.append(f"{kind}{pack_map(m)}{name}|{alt}|{coords}~")
    return "".join(parts)


def pack_needed(gates, count_objs):
    """One quest's needed items [(obj, item, count, item name, [(from, source
    name, [(map, x, y), ...]), ...])] as its packed string: <obj>|<item>|
    <count>|<item name>|<from><map><source name>|<coordinates>~ per place one
    comes from. `count_objs`: how many objectives the quest has packed."""
    parts = []
    for obj, item, count, item_name, groups in gates:
        if not 0 < obj <= count_objs:
            raise ValueError(f"needed item {item!r}: objective {obj!r} is not one of the quest's {count_objs}")
        if not (isinstance(item, int) and item > 0 and isinstance(count, int) and count > 0):
            raise ValueError(f"needed item {item!r} x {count!r} cannot be packed")
        check_text(item_name)
        for source, name, pts in groups:
            if source not in (1, 2, 3):
                raise ValueError(f"needed item {item!r}: source kind {source!r} must be 1, 2 or 3")
            if not pts:
                raise ValueError(f"needed item {item!r}: {name!r} has no place")
            check_text(name)
            m, coords = pack_places(pts)
            parts.append(f"{obj}|{item}|{count}|{item_name}|{source}{pack_map(m)}{name}|{coords}~")
    return "".join(parts)


def write_data(path, out, gates=None, made=None):
    """MelloUI_Companion/QuestObjectiveData.lua from {questID: [(kind, name, alt, [(map, x, y), ...])]},
    the needed items {questID: [(obj, item, count, item name, [(from, source name, [(map, x, y), ...])])]}
    and the objectives made by using them {questID: [obj, ...]}."""
    gates = gates or {}
    made = made or {}
    with open(os.path.abspath(path), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by Tools/build_quest_objectives.py from cmangos classic-db and Wowhead's Forever pages. Do not edit by hand.\n")
        fh.write("-- [questID] = packed objectives, one string per quest; Route decodes the tracked quest's (ObjectivesOf).\n")
        fh.write("-- Each objective is <kind><map><name>|<alt>|<x1><y1><x2><y2>...~ : kind 1 creature, 2 object, 3 item,\n")
        fh.write("-- 4 area; map the world map id, 0 Eastern Kingdoms and 1 Kalimdor as one digit, a longer one between\n")
        fh.write("-- '#' signs (#2991# Zephras Isle); world coordinates in yards, three characters each: the\n")
        fh.write(f"-- value plus {COORD_BIAS} in base 64, digits \"0\" (chr 48) to \"o\" (chr 111). An objective kept for a\n")
        fh.write("-- needed item alone has no coordinates.\n")
        fh.write("-- MelloUI_QuestNeededItems, below: [questID] = the items the bags must hold before an objective can be\n")
        fh.write("-- done (not objectives themselves), one record per place one comes from:\n")
        fh.write("-- <obj>|<item>|<count>|<item name>|<from><map><source name>|<x1><y1>...~ : obj the objective it is\n")
        fh.write("-- needed for (its place in the quest's string, from 1), item its id, count the most of it that drops for\n")
        fh.write("-- the quest; from 1 a creature drops it, 2 an object holds it, 3 a vendor sells it; map and coordinates\n")
        fh.write("-- as an objective's.\n\n")
        fh.write("MelloUI_QuestObjectiveData = {\n")
        for qid in sorted(out):
            fh.write(f"\t[{qid}]={lua_str(pack_objectives(out[qid]))},\n")
        fh.write("}\n\n")
        fh.write("MelloUI_QuestNeededItems = {\n")
        for qid in sorted(gates):
            fh.write(f"\t[{qid}]={lua_str(pack_needed(gates[qid], len(out[qid])))},\n")
        fh.write("}\n")
        if made:
            fh.write("\n-- MelloUI_QuestMadeItems: [questID] = the objectives (their places in the quest's string) whose item is\n")
            fh.write("-- made by using their needed items; once the bags hold them all, the tracker says to use them.\n")
            fh.write("MelloUI_QuestMadeItems = {\n")
            for qid in sorted(made):
                for obj in made[qid]:
                    if not (qid in gates and any(g[0] == obj for g in gates[qid])):
                        raise ValueError(f"quest {qid}: objective {obj} is made, but needs no item")
                fh.write(f"\t[{qid}]={lua_str(','.join(str(o) for o in made[qid]))},\n")
            fh.write("}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(HERE, "..", "MelloUI_Companion", "QuestObjectiveData.lua"))
    ap.add_argument("--fetch", action="store_true", help="download the Wowhead item / NPC / object pages Forever quests need")
    args = ap.parse_args()

    sql = fetch_file(CMANGOS_SQL, os.path.join(CACHE, "ClassicDB.sql.gz"))
    made_from = load_made_from()
    log(f"  {len(made_from)} items are made by using other items (the client's spells)")
    zones, _ = load_zone_maps()
    listing = load_listing()
    # The maps Route can walk: open-world maps (no instance, no battleground)
    # that have zone maps: Eastern Kingdoms, Kalimdor, Forever's Zephras Isle.
    open_world = {int(r["ID"]) for r in db2("Map") if (r.get("InstanceType") or "0") == "0"}
    world_maps = {z["mapID"] for z in zones} & open_world
    log("  objective places kept on maps " + ", ".join(str(m) for m in sorted(world_maps)))

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
    iname, istack = {}, {}                         # item entry -> name; -> how many one stack holds
    for r in sql_rows(sql, "item_template"):
        iname[int(r["entry"])] = r["name"]
        istack[int(r["entry"])] = int(r.get("stackable") or 0)
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
        points = [p for p in points if p[0] in world_maps]   # the open world: what Route can walk
        if quest_zone:
            here = [p for p in points if zone_of(p) == quest_zone]
            if here:
                points = here
        return thin(points)

    def spawns_of(source, entry):
        return spawnsO.get(entry, []) if source == 2 else spawnsC.get(entry, [])

    def classic_sources(item):
        """Where a Classic item comes from, [(from, entry)]: the creatures that
        drop it (1), then the objects that hold it (2); when neither has a
        place, the vendors who sell it (3)."""
        found = [(1, c) for c in dropsC.get(item, ())] + [(2, o) for o in dropsO.get(item, ())]
        if not any(spawns_of(src, e) for src, e in found):
            found = [(3, v) for v in sells.get(item, ())]
        return found

    def source_places(sources, quest_zone):
        """[(from, entry)] -> [(from, name, places)]: the places kept as an
        objective's are (the open world, the quest's zone when any lie there,
        one per GRID yards, CAP in all), those of one name together, in the
        sources' order; a source left with none (or no name) is dropped."""
        tagged, order = [], []
        for src, e in sources:
            key = (src, oname.get(e, "") if src == 2 else cname.get(e, ""))
            if key not in order:
                order.append(key)
            tagged += [(p, key) for p in spawns_of(src, e) if p[0] in world_maps]
        if quest_zone:
            here = [t for t in tagged if zone_of(t[0]) == quest_zone]
            if here:
                tagged = here
        groups = defaultdict(list)
        for p, key in thin_tagged(tagged):
            groups[key].append(p)
        return [(src, name, groups[(src, name)]) for src, name in order if name and groups[(src, name)]]

    def made_objectives(objs, obj_item, gates, qzone, groups_of, skip=()):
        """The objectives (their places in objs) whose item is made by using other items (made_from). One whose item
        comes from no place of its own gets them as its needed items (added to `gates`; `groups_of(item, zone)` gives
        an item's name and its sources' places, `skip` the items the quest giver hands over); one already gated only
        by them is made too."""
        made = []
        for n, item in sorted(obj_item.items()):
            parts = made_from.get(item)
            if not parts:
                continue
            mine = [g for g in gates if g[0] == n]
            if mine:
                if all(g[1] in parts for g in mine):
                    made.append(n)
                continue
            if objs[n][3]:
                continue   # it drops, an object holds it or a vendor sells it: no need to make it
            if any(part in obj_item.values() for part in parts):
                stats["made: made of another objective's item (left alone)"] += 1
                continue
            found = []
            for part, count in sorted(parts.items()):
                if part in skip:
                    continue
                name, groups = groups_of(part, qzone)
                if not (name and groups):
                    break
                found.append((n, part, count, name, groups))
            else:
                if found:
                    gates.extend(found)
                    made.append(n)
                continue
            stats["made: a part comes from no place (left alone)"] += 1
        return made

    def needed_items(r, slots, kinds, owners, qzone):
        """The items the quest needs in the bags that are not objectives
        (ReqSourceId1-4), each on the objectives it is needed for:
        [(objective index in objs, item, count, item name, [(from, name, places)])].
        `slots`: each objective's number (1-4; 0 an area), `kinds`: its kind
        (1-4, as packed), `owners`: the creatures and objects (("c" | "o",
        entry)) it is done at or comes from."""
        qid = int(r["entry"])
        given = int(r.get("SrcItemId") or 0)
        collected = {int(r.get(f"ReqItemId{i}") or 0) for i in range(1, 5)}
        numbered = [n for n, slot in enumerate(slots) if slot]
        out, seen = [], set()
        for i in range(1, 5):
            item = int(r.get(f"ReqSourceId{i}") or 0)
            if not item:
                continue
            stats["needed items"] += 1
            if item == given:
                stats["needed: handed over by the quest giver"] += 1
                continue
            if item in collected:
                stats["needed: a collect objective itself"] += 1
                continue
            if (qid, item) in NOT_NEEDED:
                stats["needed: NOT_NEEDED"] += 1
                continue
            # the most that drops for the quest; 0: up to a stack (cmangos'
            # HasQuestForItem -- 1846 Dragonmaw Shinbones)
            count = int(r.get(f"ReqSourceCount{i}") or 0) or istack.get(item) or 1
            # the objective of the same number; else the only one; else every one
            linked = [n for n in numbered if slots[n] == i] or numbered
            if not linked:
                stats["needed: no objective to need it for"] += 1
                continue
            sources = classic_sources(item)
            groups = source_places(sources, qzone)
            if not groups:
                stats["needed: no place in the open world"] += 1
                continue
            mine = {("o" if src == 2 else "c", e) for src, e in sources}
            for n in linked:
                if mine <= owners[n]:
                    stats["needed: comes from the objective itself"] += 1
                elif kinds[n] == 3 and mine & owners[n]:
                    # the collect objective's item drops from some of the same
                    # creatures or objects: it is had without this one
                    stats["needed: its sources drop the objective's item too"] += 1
                elif (n, item) not in seen:
                    seen.add((n, item))
                    out.append((n, item, count, iname.get(item, ""), groups))
        return out

    log("building objectives")
    out, gates_out, made_out, stats = {}, {}, {}, defaultdict(int)
    for r in sql_rows(sql, "quest_template"):
        qid = int(r["entry"])
        if qid not in listing:
            continue
        qzone = listing[qid].get("category") or 0
        qzone = qzone if qzone > 0 else 0
        # each objective, its number (the quest's 1-4, 0 an area) and where it
        # is done or its item comes from (needed_items)
        objs, slots, owners, obj_item = [], [], [], {}
        for i in range(1, 5):
            alt = (r.get(f"ObjectiveText{i}") or "").strip()
            target = int(r.get(f"ReqCreatureOrGOId{i}") or 0)
            if target > 0:
                pts = places(spawnsC.get(target, []), qzone)
                objs.append((1, cname.get(target, ""), alt, pts))
                slots.append(i)
                owners.append({("c", target)})
            elif target < 0:
                pts = places(spawnsO.get(-target, []), qzone)
                objs.append((2, oname.get(-target, ""), alt, pts))
                slots.append(i)
                owners.append({("o", -target)})
            item = int(r.get(f"ReqItemId{i}") or 0)
            if item:
                pts = []
                for c in dropsC.get(item, ()):
                    pts += spawnsC.get(c, [])
                for o in dropsO.get(item, ()):
                    pts += spawnsO.get(o, [])
                mine = {("c", c) for c in dropsC.get(item, ())} | {("o", o) for o in dropsO.get(item, ())}
                if not pts:
                    for v in sells.get(item, ()):
                        pts += spawnsC.get(v, [])
                    mine |= {("c", v) for v in sells.get(item, ())}
                obj_item[len(objs)] = item
                objs.append((3, iname.get(item, ""), "", places(pts, qzone)))
                slots.append(i)
                owners.append(mine)
        for t in explore.get(qid, []):
            if t in triggers:
                objs.append((4, "", "", places([triggers[t]], 0)))
                slots.append(0)
                owners.append(set())
        gates = needed_items(r, slots, [o[0] for o in objs], owners, qzone)
        made = made_objectives(objs, obj_item, gates, qzone,
                               lambda part, z: (iname.get(part, ""), source_places(classic_sources(part), z)),
                               skip={int(r.get("SrcItemId") or 0)})
        # an objective with no place is left out, unless an item is needed
        # for it (its sources stand in for it while the item is missing)
        gated = {g[0] for g in gates}
        keep = [n for n, o in enumerate(objs) if o[3] or n in gated]
        if keep:
            at = {n: k + 1 for k, n in enumerate(keep)}
            out[qid] = [objs[n] for n in keep]
            for n in keep:
                stats[("creature", "object", "item", "area")[objs[n][0] - 1]] += 1
            if gates:
                gates_out[qid] = [(at[n], item, count, name, groups) for n, item, count, name, groups in gates]
                stats["needed: kept (objective, item)"] += len(gates)
                stats["needed: objectives kept for them alone"] += sum(1 for n in gated if not objs[n][3])
            if made:
                made_out[qid] = [at[n] for n in made]
                stats["made: objectives made by using their needed items"] += len(made)
    stats["classic quests"] = len(out)
    stats["quests with needed items"] = len(gates_out)

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

    def forever_sources(i, min_chance=0):
        """Where a Forever item comes from, [(from, entry)]: what its Wowhead page says drops it (1; with `min_chance`,
        only at that many percent or more, by the page's count out of kills) or holds it (2), else what sells it (3)."""
        page = read_page("item", i)

        def often(d):
            count, outof = d.get("count"), d.get("outof")
            if not min_chance or not (isinstance(count, int) and isinstance(outof, int) and outof > 0 and count > 0):
                return True
            return 100.0 * count / outof >= min_chance
        drops = listview(page, "dropped-by")
        if min_chance and len(drops) > WORLD_DROP:
            drops = []   # a world drop: no place to farm it
        found = [(1, int(d["id"])) for d in drops if d.get("id") and often(d)]
        found += [(2, int(d["id"])) for d in listview(page, "contained-in-object") if d.get("id")]
        if not found:
            found = [(3, int(d["id"])) for d in listview(page, "sold-by") if d.get("id")]
        return found

    def item_sources(i):
        """Creatures and objects an item comes from: ([npc ids], [object ids])."""
        if i in iname:   # a Classic item: classic-db's loot, then vendors
            npcs, objs = list(dropsC.get(i, ())), list(dropsO.get(i, ()))
            if not npcs and not objs:
                npcs = list(sells.get(i, ()))
            return npcs, objs
        found = forever_sources(i)
        return [e for src, e in found if src != 2], [e for src, e in found if src == 2]

    def page_title(kind, i, word):
        """A name from a Wowhead page's title ("Bundle of Herbs - Item - Forever")."""
        m = re.search(r"<title>(.*?) - " + word, read_page(kind, i) or "")
        return " ".join(html.unescape(m.group(1)).split()) if m else ""

    def forever_groups(i, quest_zone):
        """A made item's part: its name and its sources' places, as a needed item's groups [(from, name, places)]."""
        if i in iname:
            return iname[i], source_places(classic_sources(i), quest_zone)
        tagged, order = [], []
        for src, e in forever_sources(i, MIN_CHANCE):
            if src == 2:
                name, pts = oname.get(e) or page_title("object", e, "Object"), object_points(e)
            else:
                name, pts = cname.get(e) or page_title("npc", e, "NPC"), creature_points(e)
            key = (src, name)
            if name and key not in order:
                order.append(key)
            tagged += [(p, key) for p in pts if p[0] in world_maps]
        if quest_zone:
            here = [t for t in tagged if zone_of(t[0]) == quest_zone]
            if here:
                tagged = here
        groups = defaultdict(list)
        for p, key in thin_tagged(tagged):
            groups[key].append(p)
        return page_title("item", i, "Item"), [(src, name, groups[(src, name)]) for src, name in order if groups[(src, name)]]

    def missing_pages():
        need = set()
        for _, objs in forever:
            for kind, i, _ in objs:
                if kind == "npc" and i not in spawnsC and not read_page("npc", i):
                    need.add(("npc", i))
                elif kind == "object" and i not in spawnsO and not read_page("object", i):
                    need.add(("object", i))
                elif kind == "item" and i in made_from and i not in iname:
                    for part in made_from[i]:
                        if part in iname:
                            continue
                        if not read_page("item", part):
                            need.add(("item", part))
                        for src, e in forever_sources(part):
                            if src == 2 and e not in spawnsO and not read_page("object", e):
                                need.add(("object", e))
                            elif src != 2 and e not in spawnsC and not read_page("npc", e):
                                need.add(("npc", e))
                    if not read_page("item", i):
                        need.add(("item", i))
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
        entries, gates, obj_item = [], [], {}
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
                obj_item[len(entries)] = i
                entries.append((3, name, "", places(pts, qzone)))
        made = made_objectives(entries, obj_item, gates, qzone, forever_groups)
        gated = {g[0] for g in gates}
        keep = [n for n, e in enumerate(entries) if e[3] or n in gated]
        if keep:
            at = {n: k + 1 for k, n in enumerate(keep)}
            out[qid] = [entries[n] for n in keep]
            stats["forever quests"] += 1
            for n in keep:
                stats[("creature", "object", "item", "area")[entries[n][0] - 1]] += 1
            if gates:
                gates_out[qid] = [(at[n], item, count, name, groups) for n, item, count, name, groups in gates]
                stats["needed: kept (objective, item)"] += len(gates)
            if made:
                made_out[qid] = [at[n] for n in made]
                stats["made: objectives made by using their needed items"] += len(made)
    stats["quests"] = len(out)

    write_data(args.out, out, gates_out, made_out)
    log(f"wrote {args.out}: " + ", ".join(f"{k} {v}" for k, v in sorted(stats.items())))


if __name__ == "__main__":
    main()
