#!/usr/bin/env python3
"""
A road map check (docs/plans/services-nearest-roads.md section 3): find the holes in MelloUI's road graph
(MelloUI_Companion/RoadData.lua) before a player does.

For every pair of service points on a continent (innkeepers, flight masters, banks, mailboxes from
Media/QuestListData.lua) less than PAIR_MAX yards apart in a straight line, the road cost between them (the
Route module's graph: Dijkstra over its links, each end joined to its nearest node). A pair whose road is more than
DETOUR times the straight line AND more than EXTRA yards longer is listed, grouped by the zone of its first point,
with where the two road networks come closest. Some long detours are real (rivers, cliffs): the list is for a
person to look at, not a failure. Also lists the road "islands": parts of the graph that reach nothing else.

    python Tools/check_roads.py                  the report (text)
    python Tools/check_roads.py --json out.json  the same as data

Reads only the repo; nothing in it ships.
"""
import argparse
import heapq
import json
import math
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
ROADS = os.path.join(ROOT, "MelloUI_Companion", "RoadData.lua")
QDATA = os.path.join(ROOT, "Media", "QuestListData.lua")
sys.path.insert(0, HERE)

WALK = 7.0          # yards a second, as Route.lua
PAIR_MAX = 2500     # yards: pairs closer than this in a straight line are checked
DETOUR = 3.0        # a road this many times the straight line ...
EXTRA = 1000        # ... and this many yards longer is a hole
KINDS = ("innkeeper", "banker", "mailbox")
CONT_OF_WORLD = {0: 1415, 1: 1414}   # world map id -> continent UiMap


def load_graph(path=ROADS):
    """{ cont: { key: (x, y, { key: seconds }) } } from RoadData.lua"""
    graphs, cont = defaultdict(dict), None
    pat = re.compile(r'\["(\d+:\d+)"\]=\{([-\d.]+),([-\d.]+),\{(.*?)\}\}')
    edge = re.compile(r'\["(\d+:\d+)"\]=([\d.]+)')
    for line in open(path, encoding="utf-8"):
        m = re.match(r'\s*\[(\d+)\] = \{', line)
        if m:
            cont = int(m.group(1))
            continue
        if cont is None:
            continue
        m = pat.search(line)
        if m:
            graphs[cont][m.group(1)] = (float(m.group(2)), float(m.group(3)),
                                        {k: float(v) for k, v in edge.findall(m.group(4))})
    return graphs


def load_bounds():
    """continent UiMap -> (x1, y1): world x north, world y west; continent yards = (y1 - wy, x1 - wx)"""
    from paths import CACHE
    import csv
    path = os.path.join(CACHE, "UiMapAssignment_1.60.1.69913.csv")
    out = {}
    for r in csv.DictReader(open(path, encoding="utf-8")):
        if r["UiMapID"] in ("1414", "1415") and r["OrderIndex"] == "0":
            out[int(r["UiMapID"])] = (float(r["Region_3"]), float(r["Region_4"]))
    return out


def load_points(bounds):
    """service points: (cont, x, y, kind, name)"""
    text = open(QDATA, encoding="utf-8").read()
    pts = []
    svc = text[text.index("\tservices = {"):]
    svc = svc[:svc.index("\n\t},")]
    for m in re.finditer(r'\{"(\w+)","([^"]*)","([^"]*)",(\d),(\d+),([-\d.]+),([-\d.]+)', svc):
        kind, name, _, _, wmap, wx, wy = m.groups()
        cont = CONT_OF_WORLD.get(int(wmap))
        if kind in KINDS and cont in bounds:
            x1, y1 = bounds[cont]
            pts.append((cont, y1 - float(wy), x1 - float(wx), kind, name))
    tax = text[text.index("\ttaxiNodes = {\n\t\t[") if "\ttaxiNodes = {\n\t\t[" in text else 0:]
    for m in re.finditer(r'\[(\d+)\] = \{"([^"]*)",(\d+),([-\d.]+),([-\d.]+),(\d)\}', tax):
        _, name, wmap, wx, wy, _ = m.groups()
        cont = CONT_OF_WORLD.get(int(wmap))
        if cont in bounds:
            x1, y1 = bounds[cont]
            pts.append((cont, y1 - float(wy), x1 - float(wx), "flight", name))
    return pts


class Graph:
    def __init__(self, nodes):
        self.nodes = nodes
        self.keys = list(nodes)
        self.xy = [(nodes[k][0], nodes[k][1]) for k in self.keys]
        try:
            from scipy.spatial import cKDTree
            self.tree = cKDTree(self.xy)
        except ImportError:
            self.tree = None

    def nearest(self, x, y):
        if self.tree is not None:
            d, i = self.tree.query((x, y))
            return self.keys[i], d
        best = min(range(len(self.keys)), key=lambda i: (self.xy[i][0] - x) ** 2 + (self.xy[i][1] - y) ** 2)
        return self.keys[best], math.hypot(self.xy[best][0] - x, self.xy[best][1] - y)

    def dijkstra(self, src, limit=None):
        dist = {src: 0.0}
        q = [(0.0, src)]
        while q:
            d, n = heapq.heappop(q)
            if d > dist.get(n, 1e18):
                continue
            if limit and d > limit:
                break
            for m, w in self.nodes[n][2].items():
                if m in self.nodes and d + w < dist.get(m, 1e18):
                    dist[m] = d + w
                    heapq.heappush(q, (d + w, m))
        return dist

    def islands(self):
        seen, out = set(), []
        for k in self.keys:
            if k in seen:
                continue
            comp, stack = [], [k]
            seen.add(k)
            while stack:
                n = stack.pop()
                comp.append(n)
                for m in self.nodes[n][2]:
                    if m in self.nodes and m not in seen:
                        seen.add(m)
                        stack.append(m)
            out.append(comp)
        out.sort(key=len, reverse=True)
        return out


def closest_between(g, a_set, b_set):
    """where two node sets come closest: (yards, a key, b key)"""
    if not a_set or not b_set:
        return None
    try:
        from scipy.spatial import cKDTree
        bl = list(b_set)
        tree = cKDTree([g.nodes[k][:2] for k in bl])
        best = None
        for k in a_set:
            d, i = tree.query(g.nodes[k][:2])
            if best is None or d < best[0]:
                best = (d, k, bl[i])
        return best
    except ImportError:
        return None


def check(graphs, points, pair_max=PAIR_MAX, detour=DETOUR, extra=EXTRA, zone_of=None):
    """-> holes [{a, b, straight, road, kind, closest}], islands {cont: [sizes]}"""
    holes, islands = [], {}
    for cont, nodes in graphs.items():
        if not nodes:
            continue
        g = Graph(nodes)
        comps = g.islands()
        islands[cont] = [len(c) for c in comps]
        pts = [p for p in points if p[0] == cont]
        near = {}
        for p in pts:
            near[p] = g.nearest(p[1], p[2])
        for i, a in enumerate(pts):
            ka, offa = near[a]
            dist = None
            for b in pts[i + 1:]:
                straight = math.hypot(a[1] - b[1], a[2] - b[2])
                if straight >= pair_max or straight < 1:
                    continue
                if dist is None:
                    dist = g.dijkstra(ka, limit=(pair_max * detour * 2 + extra) / WALK)
                kb, offb = near[b]
                road = dist.get(kb)
                road_yd = (road * WALK + offa + offb) if road is not None else None
                if road_yd is None or (road_yd > detour * straight and road_yd > straight + extra):
                    reach = set(dist)
                    other = set(g.dijkstra(kb, limit=(pair_max * detour * 2 + extra) / WALK))
                    holes.append({"cont": cont, "a": a[4], "a_kind": a[3], "b": b[4], "b_kind": b[3],
                                  "straight": round(straight), "road": round(road_yd) if road_yd else None,
                                  "zone": zone_of(cont, a[1], a[2]) if zone_of else None,
                                  "closest": closest_between(g, reach - other, other - reach)})
    return holes, islands


def zone_finder(bounds_cont):
    """(cont, x, y) -> the smallest zone map (UiMapAssignment) holding a continent-yards point, by name"""
    from paths import CACHE
    import csv
    maps = {}
    for r in csv.DictReader(open(os.path.join(CACHE, "UiMap_1.60.1.69913.csv"), encoding="utf-8")):
        maps[r["ID"]] = (r.get("Name_lang") or r.get("Name") or r["ID"], r.get("Type"), r.get("ParentUiMapID"))
    rects = defaultdict(list)
    for r in csv.DictReader(open(os.path.join(CACHE, "UiMapAssignment_1.60.1.69913.csv"), encoding="utf-8")):
        m = maps.get(r["UiMapID"])
        if not m or m[1] not in ("3", "4", "5") or r["OrderIndex"] != "0":
            continue
        x0, y0, x1, y1 = (float(r[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))
        for cont, (cx1, cy1) in bounds_cont.items():
            # a zone rect in continent yards: east = cy1 - wy, south = cx1 - wx
            rects[cont].append(((x1 - x0) * (y1 - y0), cy1 - y1, cx1 - x1, cy1 - y0, cx1 - x0, m[0]))

    def find(cont, x, y):
        best = None
        for area, e0, s0, e1, s1, name in rects.get(cont, ()):
            if e0 <= x <= e1 and s0 <= y <= s1 and (best is None or area < best[0]):
                best = (area, name)
        return best[1] if best else "?"
    return find


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--json", help="write the report as JSON here")
    args = ap.parse_args()
    graphs = load_graph()
    bounds = load_bounds()
    points = load_points(bounds)
    try:
        zone_of = zone_finder(bounds)
    except (OSError, KeyError):
        zone_of = None
    holes, islands = check(graphs, points, zone_of=zone_of)
    if zone_of:
        per = defaultdict(lambda: [0, 0])
        for h in holes:
            per[h["zone"]][0 if h["straight"] >= 150 else 1] += 1
        print("== by zone (pairs; then the ones under 150 yd apart: one place whose points snap to two networks)")
        for z, (far, near_) in sorted(per.items(), key=lambda kv: -sum(kv[1])):
            print("  %-28s %4d  (%d)" % (z, far, near_))
    by_cont = defaultdict(list)
    for h in holes:
        by_cont[h["cont"]].append(h)
    names = {1414: "Kalimdor", 1415: "Eastern Kingdoms"}
    for cont in sorted(graphs):
        hs = sorted(by_cont[cont], key=lambda h: -(h["road"] or 1e9) / max(h["straight"], 1))
        print("== %s: %d service pairs with a road far longer than the straight line" % (names.get(cont, cont), len(hs)))
        for h in hs[:60]:
            c = h["closest"]
            gap = (" | the networks come within %d yd at %s" % (c[0], c[1])) if c else ""
            road = ("%d yd" % h["road"]) if h["road"] else "no road"
            print("  %-34s -> %-34s straight %5d yd, road %s%s" % (h["a"][:34], h["b"][:34], h["straight"], road, gap))
        sizes = islands.get(cont, [])
        print("  islands: %d pieces; the largest %s; small ones (< 20 nodes): %d" % (
            len(sizes), sizes[:3], len([s for s in sizes if s < 20])))
    if args.json:
        json.dump({"holes": holes, "islands": islands}, open(args.json, "w", encoding="utf-8"), indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
