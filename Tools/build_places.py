#!/usr/bin/env python3
"""
Build Media/PlaceData.lua: named places in the open world, so a quest line
can say where its NPC stands ("Turn in: Gryan Stoutmantle, Sentinel Hill")
instead of only the zone.

Sources (all in the build cache, MelloUI-BuildData/cache):
  AreaPOI           the towns and camps the world map names (the Forever
                    export when there is one, else the Classic Era one)
  TaxiNodes         the flight points (through build_quest_list.build_taxi,
                    the same list QuestListData ships)
  WorldMapOverlay   the named sub-zones a zone map uncovers when explored,
  + UiMapXMapArt    placed at the middle of each one's hit area on the map,
  + UiMapAssignment which is how Forever's own zones (Zephras Isle) get
  + AreaTable       names: the other two tables know nothing of them

Every place has a reach in yards: a point is "at" a place when it is within
that place's reach. Towns and camps reach REACH_POI, flight points
REACH_FLIGHT, a sub-zone half the size of its hit area (REACH_MIN ..
REACH_MAX). Where one name is found more than once close by, the town
(AreaPOI) wins over the flight point, and both over the sub-zone.

Usage:
  python Tools/build_places.py [--out Media/PlaceData.lua] [--check] [--coverage]

--check      exit 1 when the file on disk differs from a fresh build
--coverage   print how many of the quests' turn-in spots get a place
"""

import argparse
import math
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_quest_list import db2, build_taxi, lua_str, log, JUNK  # noqa: E402

OUT = os.path.join(HERE, "..", "Media", "PlaceData.lua")
QUEST_DATA = os.path.join(HERE, "..", "Media", "QuestListData.lua")

REACH_POI = 250       # yards: a town or camp's own point (the levelling report measured 250)
REACH_FLIGHT = 300    # a flight point (measured 300)
REACH_MIN = 150       # a sub-zone: half its hit area, kept inside these
REACH_MAX = 400
SAME_PLACE = 500      # one name within this many yards is one place
POI_EVENT_FLAG = 0x80  # AreaPOI flag of world-event markers ("Under Attack", the Ashenvale bases, towers' states)


def open_world_maps():
    """World map ids a player walks around in: the Map table's InstanceType 0."""
    return {int(r["ID"]) for r in db2("Map") if (r.get("InstanceType") or "0") == "0"}


def zone_bounds():
    """UiMap id -> (world map id, x0, y0, x1, y1) of its largest region, for
    zone and city maps (UiMap types 3 and 4)."""
    uimaps = {int(r["ID"]): r for r in db2("UiMap")}
    best = {}
    for r in db2("UiMapAssignment"):
        ui_id = int(r["UiMapID"])
        ui = uimaps.get(ui_id)
        if not ui or ui["Type"] not in ("3", "4"):
            continue
        x0, y0, x1, y1 = float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"])
        area = abs((x1 - x0) * (y1 - y0))
        if ui_id not in best or area > best[ui_id][0]:
            best[ui_id] = (area, int(r["MapID"]), x0, y0, x1, y1, ui["Name_lang"])
    return {k: v[1:] for k, v in best.items()}


def inside(bounds, cont, wx, wy):
    """True when a world point lies on one of the zone maps."""
    for m, x0, y0, x1, y1, _ in bounds.values():
        if m == cont and x0 <= wx <= x1 and y0 <= wy <= y1:
            return True
    return False


def poi_places(worlds, bounds):
    out = []
    for r in db2("AreaPOI"):
        name = (r.get("Name_lang") or "").strip()
        cont = int(r.get("ContinentID") or -1)
        if not name or JUNK.search(name) or name.endswith("!") or cont not in worlds:
            continue
        if int(r.get("Flags") or 0) & POI_EVENT_FLAG:
            continue
        wx, wy = float(r["Pos_0"]), float(r["Pos_1"])
        if inside(bounds, cont, wx, wy):
            out.append((cont, wx, wy, REACH_POI, name, 0))
    return out


def flight_places(worlds):
    out = []
    nodes, _ = build_taxi()
    for _, (name, cont, wx, wy, _) in sorted(nodes.items()):
        if cont not in worlds or re.match(r"^Flight point \d+$", name):
            continue
        # "Sentinel Hill, Westfall" -> "Sentinel Hill"
        out.append((cont, wx, wy, REACH_FLIGHT, name.split(",")[0].strip(), 1))
    return out


def overlay_places(worlds, bounds):
    """The named sub-zones of each zone map: the middle of each explored
    overlay's hit area, from map pixels to world yards."""
    areas = {int(r["ID"]): r for r in db2("AreaTable")}
    art_of = defaultdict(list)                 # UiMapArt -> [UiMap]
    for r in db2("UiMapXMapArt"):
        if (r.get("PhaseID") or "0") == "0":
            art_of[int(r["UiMapArtID"])].append(int(r["UiMapID"]))
    style_of = {int(r["ID"]): int(r["UiMapArtStyleID"]) for r in db2("UiMapArt")}
    layer = {}
    for r in db2("UiMapArtStyleLayer"):
        if (r.get("LayerIndex") or "0") == "0":
            layer[int(r["UiMapArtStyleID"])] = (float(r["LayerWidth"]), float(r["LayerHeight"]))
    out = []
    for r in db2("WorldMapOverlay"):
        art = int(r["UiMapArtID"])
        size = layer.get(style_of.get(art, -1))
        aid = int(r.get("AreaID_0") or 0)
        area = areas.get(aid)
        if not size or not area:
            continue
        name = (area.get("AreaName_lang") or "").strip()
        if not name or JUNK.search(name) or int(area.get("ParentAreaID") or 0) == 0:
            continue
        left, right = float(r["HitRectLeft"]), float(r["HitRectRight"])
        top, bottom = float(r["HitRectTop"]), float(r["HitRectBottom"])
        if right <= left or bottom <= top:
            continue
        w, h = size
        for ui_id in art_of.get(art, ()):
            b = bounds.get(ui_id)
            if not b:
                continue
            cont, x0, y0, x1, y1, zone_name = b
            if cont not in worlds or name == zone_name:
                continue
            px, py = (left + right) / 2 / w, (top + bottom) / 2 / h
            wy = y1 - px * (y1 - y0)
            wx = x1 - py * (x1 - x0)
            yards_w = (right - left) / w * abs(y1 - y0)
            yards_h = (bottom - top) / h * abs(x1 - x0)
            reach = max(REACH_MIN, min(REACH_MAX, max(yards_w, yards_h) / 2))
            out.append((cont, wx, wy, reach, name, 2))
    return out


def build():
    """{continent: [(wx, wy, reach, name, rank)]}, sorted by world x; rank 0
    town, 1 flight point, 2 sub-zone (not written to the file)."""
    worlds = open_world_maps()
    bounds = zone_bounds()
    found = poi_places(worlds, bounds) + flight_places(worlds) + overlay_places(worlds, bounds)
    # rank: town, flight point, sub-zone; then a fixed order so the output never moves
    found.sort(key=lambda p: (p[5], p[0], p[4], round(p[1], 1), round(p[2], 1)))
    kept = defaultdict(list)
    stats = defaultdict(int)
    for cont, wx, wy, reach, name, rank in found:
        same = next((k for k in kept[cont] if k[3] == name and math.hypot(k[0] - wx, k[1] - wy) < SAME_PLACE), None)
        if same:
            continue
        kept[cont].append((round(wx, 1), round(wy, 1), int(round(reach)), name, rank))
        stats[("town", "flight point", "sub-zone")[rank]] += 1
    for cont in kept:
        kept[cont].sort(key=lambda k: (k[0], k[1], k[3]))
    log("  places: " + ", ".join(f"{k} {v}" for k, v in sorted(stats.items())) +
        "; by map: " + ", ".join(f"{c} {len(v)}" for c, v in sorted(kept.items())))
    return kept


def num(v):
    return str(int(v)) if float(v).is_integer() else repr(float(v))


def render(kept):
    lines = [
        "-- Generated by Tools/build_places.py. Do not edit by hand.",
        "-- Sources: the client's AreaPOI, TaxiNodes, WorldMapOverlay, UiMapAssignment and AreaTable tables.",
        "",
        "-- Named places in the open world, for lines such as \"Turn in: Gryan Stoutmantle, Sentinel Hill\".",
        "-- [world map id] = flat rows of four: world x, world y, reach (yards), name; sorted by world x.",
        "-- A point is at a place when it lies within that place's reach; take the nearest such place.",
        "-- luacheck: globals MelloUI_PlaceData",
        "MelloUI_PlaceData = {",
    ]
    for cont in sorted(kept):
        lines.append(f"\t[{cont}] = {{")
        for wx, wy, reach, name, _ in kept[cont]:
            lines.append(f"\t\t{num(wx)},{num(wy)},{reach},{lua_str(name)},")
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Coverage of the quests' turn-in spots
# ---------------------------------------------------------------------------

def lua_fields(body):
    """Fields of one flat Lua table row: numbers and quoted strings."""
    out, i, n = [], 0, len(body)
    while i < n:
        c = body[i]
        if c == '"':
            j, buf = i + 1, []
            while body[j] != '"':
                if body[j] == "\\":
                    j += 1
                buf.append(body[j])
                j += 1
            out.append("".join(buf))
            i = j + 1
        elif c in ", \t":
            i += 1
        else:
            j = i
            while j < n and body[j] not in ",":
                j += 1
            tok = body[i:j].strip()
            out.append(float(tok) if re.match(r"^-?\d+(\.\d+)?$", tok) else tok)
            i = j
    return out


def turn_in_spots(path=QUEST_DATA):
    """Distinct (continent, world x, world y) of the quests' turn-ins."""
    spots = set()
    text = open(path, encoding="utf-8").read()
    body = text[text.index("\tquests = {"):]
    for m in re.finditer(r"^\t\t\{(.*)\},$", body, re.M):
        f = lua_fields(m.group(1))
        if len(f) >= 27 and f[24] >= 0 and (f[25] or f[26]):
            spots.add((int(f[24]), f[25], f[26]))
    return spots


def coverage(kept, spots, flat=None):
    """Share of spots with a place in reach (each place's own, or `flat`)."""
    hit = 0
    by_cont = defaultdict(lambda: [0, 0])
    for cont, x, y in spots:
        ok = any(math.hypot(px - x, py - y) <= (flat or reach) for px, py, reach, _, _ in kept.get(cont, ()))
        hit += ok
        by_cont[cont][0] += ok
        by_cont[cont][1] += 1
    return hit, len(spots), dict(by_cont)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--coverage", action="store_true")
    args = ap.parse_args()
    kept = build()
    text = render(kept)
    out = os.path.abspath(args.out)
    if args.check:
        old = open(out, encoding="utf-8").read() if os.path.exists(out) else None
        if old != text:
            print(f"build_places --check: {out} is OUT OF DATE: run python Tools/build_places.py")
            return 1
        print("build_places --check: up to date")
    else:
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        log(f"wrote {out}: {sum(len(v) for v in kept.values())} places, {len(text.encode('utf-8'))} bytes")
    if args.coverage:
        spots = turn_in_spots()
        hit, total, by_cont = coverage(kept, spots)
        print(f"coverage: {hit} of {total} turn-in spots have a place in reach ({100.0 * hit / max(1, total):.1f}%)")
        for cont, (h, t) in sorted(by_cont.items()):
            print(f"  map {cont}: {h} of {t}")
        plain = {c: [k for k in v if k[4] < 2] for c, v in kept.items()}
        hit, total, _ = coverage(plain, spots, flat=REACH_FLIGHT)
        print(f"  towns and flight points only, 300 yd: {hit} of {total} ({100.0 * hit / max(1, total):.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
