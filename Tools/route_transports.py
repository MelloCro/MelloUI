#!/usr/bin/env python3
"""
Route's ways across the sea against the real ground and the transports' real seconds (docs/plans/route-ground.md;
the user, 2026-10-20: "lifts/transports used when faster"). Offline.

  transports  the Quest List's boats and zeppelins (Media/QuestListData.lua): each dock's expected seconds to the next
              one, the wait included (Tools/build_quest_list.py's transport_seconds)
  pairs       for each transport between the two continents: places 150-900 yd from its two docks, one on each side
  best        the quickest of every transport the side may take from one continent to the other: the navmesh's way to
              its dock (Detour), its seconds, the navmesh's way from the dock it lands at
  ours        FindRoute across the continents in the Lua test world (this checkout's Route.lua and companion), its
              legs walked over each continent's navmesh (Tools/route_bench.py's score), its crossing at its dock's
              seconds; which transport it took against the best one

    python Tools/route_transports.py [--side alliance|horde|both] [--per 3] [--seed 1]
"""
import argparse
import json
import math
import os
import random
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import route_bench as rb  # noqa: E402
from nav_grid import UNIT, build_out  # noqa: E402

RUN = 7.0
NEAR = (150.0, 900.0)


def transports():
    """[(kind, side, label, from, (map, x, y), (map, x, y), seconds)] -- boats and zeppelins with seconds"""
    text = open(os.path.join(ROOT, "Media", "QuestListData.lua"), encoding="utf-8").read()
    blk = text[text.index("\ttransports = {"):]
    blk = blk[:blk.index("\n\t},")]
    import csv
    out = []
    for raw in re.findall(r"\{([^{}]*)\}", blk):
        r = next(csv.reader([raw]))
        kind, side = int(r[0]), int(r[1])
        secs = float(r[13]) if len(r) >= 14 else 0.0
        if kind in (3, 4):
            secs = PORTAL_TRAM[kind]   # (Route's own: the data has no path for them)
        if secs > 0:
            out.append((kind, side, r[2], r[3], (int(r[4]), float(r[5]), float(r[6])),
                        (int(r[10]), float(r[11]), float(r[12])), secs))
    return out


PORTAL_TRAM = {3: 10.0, 4: 180.0}   # Route.lua's M.DOCK_SECONDS


class World:
    """Route's Lua test world over both continents, a side's: FindRoute between them in world yards"""

    def __init__(self, side):
        sys.path.insert(0, rb.ETA)
        import eta_world
        eta_world.ROOT = ROOT.replace("\\", "/").rstrip("/") + "/"
        import tempfile
        tmp = tempfile.mkdtemp()
        path = os.path.join(tmp, "Route.lua")
        hook = ("\nns.__T = { FindRoute = FindRoute, Build = Build, live = live, Search = Search, "
                "docks = function() return docks end }\n")
        open(path, "w", encoding="utf-8").write(open(os.path.join(ROOT, "MelloUI_Route", "Route.lua"),
                                                     encoding="utf-8").read() + hook)
        lua = eta_world.world(path, terrain=True)
        lua.execute('function UnitFactionGroup() return "%s" end' % ("Horde" if side == 2 else "Alliance"))
        # (the world's places as this client's maps have them -- Forever's UiMapAssignment, as the companion's data
        # and v180/transports: the test world's own bounds are retail's, and put the docks hundreds of yards off)
        lua.execute("""
            local FB = { [0] = { 1415, 35199.9, 23466.6, 16000.0, 7466.6 },
                         [1] = { 1414, 36799.8, 24533.2, 17066.6, 12799.9 } }
            local size = C_Map.GetMapWorldSize
            C_Map.GetMapWorldSize = function(id)
                for _, b in pairs(FB) do if b[1] == id then return b[2], b[3] end end
                return size(id)
            end
            C_Map.GetMapPosFromWorldPos = function(wcont, v)
                local b = FB[wcont]
                if not b then return nil end
                return b[1], { x = (b[4] - v.y) / b[2], y = (b[5] - v.x) / b[3] }
            end""")
        lua.execute("Start()")
        lua.execute("ns.__T.Build.Want() for i = 1, 40000 do Frames(1) if ns.__T.Build.Ready() then break end end")
        assert lua.eval("ns.__T.Build.Ready()"), "the graph did not build"
        self.lua = lua
        self.rects = rb.continent_rects()
        self.scale = {}
        for m, cont in rb.CONTINENTS.items():
            g = lua.eval("M.Ground.grids[%d]" % cont)
            self.scale[m] = (g["sx"], g["sy"])
        self.find = lua.eval("""function(c1, a, b, c2, c, d)
          local p, cost = ns.__T.FindRoute(c1, a, b, c2, c, d)
          local out = {}
          for i, q in ipairs(p or {}) do out[i] = { q[1], q[2], q[3], q[4], tostring(q[5]) } end
          return out, cost or -1
        end""")

    def yards(self, m, x, y):
        cont = rb.CONTINENTS[m]
        r, (sx, sy) = self.rects[cont], self.scale[m]
        return (r["y1"] - y) * sx, (r["x1"] - x) * sy

    def world(self, cont, e, s):
        m = {v: k for k, v in rb.CONTINENTS.items()}[cont]
        r, (sx, sy) = self.rects[cont], self.scale[m]
        return m, r["x1"] - s / sy, r["y1"] - e / sx

    def route(self, a, b):
        """[(map, x, y, kind, id)], cost"""
        ea, sa = self.yards(a[0], a[1], a[2])
        eb, sb = self.yards(b[0], b[1], b[2])
        pts, cost = self.find(rb.CONTINENTS[a[0]], ea, sa, rb.CONTINENTS[b[0]], eb, sb)
        out = []
        for i in range(1, len(pts) + 1):
            q = pts[i]
            m, x, y = self.world(q[1], q[2], q[3])
            out.append((m, x, y, q[4], q[5]))
        return out, cost


def ground_at(G, x, y):
    """(x, y, z): a dock's boarding place -- Tools/nav_graph.py's (the floor nearest the ship's stop on the biggest
    piece of ground round it); else the place itself"""
    import nav_graph
    p = nav_graph.boarding_place(G, x, y)
    if p:
        return p
    g = G.nav.ground(x, y)
    return (x, y, g["z"] if g["ok"] else None)


def walk(G, a, b):
    """the navmesh's way from a to b: seconds, or None"""
    d = G.nav.path(a, b, points=False)
    if not d["ok"] or (b[2] is not None and abs(d["to"][2] - b[2]) > 6):
        return None
    return d["seconds"]


def place(G, rng, dock):
    """a walkable place 150-900 yd from a dock, on the mainland's (or the island's own) piece, the navmesh's way to the
    dock: (x, y, z)"""
    for _ in range(300):
        ang = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(*NEAR)
        x, y = dock[0] + d * math.cos(ang), dock[1] + d * math.sin(ang)
        r, c = G.cell(x, y)
        if not (0 <= r < G.H and 0 <= c < G.W) or G.kind[r, c] != 1 or G.edges[r, c] != 15:
            continue
        p = G.world(r, c)
        # (on the dock's own piece of ground: not the mountain over Ironforge, nor a roof)
        if G.piece(p) < 0 or G.piece(p) != G.piece(dock):
            continue
        if walk(G, p, dock) is not None:
            return p
    return None


def score_route(route, A, B, GA, GB, mine):
    """Route's way walked: its legs over each continent's navmesh (Tools/route_bench.py's score), a crossing -- its
    first boat, zeppelin, tram or portal -- at the seconds of the dock it leaves from, boarded and left at the docks'
    boarding places -> (seconds, what it took, [walked seconds], stuck) or a reason it was not scored"""
    if any(p[3] == "flight" for p in route):
        return "a flight"
    cross = next((k for k in range(1, len(route)) if route[k][0] != route[k - 1][0] or route[k][3] == "boat"), None)
    if cross is None:
        sc = rb.score(GA, [(p[0], p[1], p[2], p[3], -1) for p in route], A, B, 0)
        return (sc[0], "walking", [sc[0]], sc[1]) if sc else "a boat inside a leg"
    dep = route[cross - 1]
    took = min(mine, key=lambda u: math.hypot(u[4][1] - dep[1], u[4][2] - dep[2]) if u[4][0] == dep[0] else 1e9)
    part1 = [(p[0], p[1], p[2], p[3], -1) for p in route[:cross]]
    part2 = [(p[0], p[1], p[2], p[3], -1) for p in route[cross:]]
    G2 = GB if route[cross][0] != route[cross - 1][0] or GB is not GA else GA
    # (the ship boarded and left at the pier's end: the dock's boarding place, not its stop on the water)
    end1 = ground_at(GA, dep[1], dep[2])
    part1[-1] = (part1[-1][0], end1[0], end1[1], part1[-1][3], -1)
    s1 = rb.score(GA, part1, A, end1, 0) if len(part1) > 1 else (0.0, [], {})
    beg2 = ground_at(G2, part2[0][1], part2[0][2])
    part2[0] = (part2[0][0], beg2[0], beg2[1], part2[0][3], -1)
    s2 = rb.score(G2, part2, beg2, B, 0) if len(part2) > 1 else (0.0, [], {})
    if s1 is None or s2 is None:
        return "a second crossing"
    return s1[0] + took[6] + s2[0], took[2] + " from " + took[3], [s1[0], s2[0]], s1[1] + s2[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--side", default="both")
    ap.add_argument("--per", type=int, default=3, help="pairs a transport")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default=os.path.join(build_out(), "bench", "transports.jsonl"))
    a = ap.parse_args()
    t0 = time.perf_counter()
    Gs = {0: rb.Ground(0), 1: rb.Ground(1)}
    rows = transports()
    sides = {"alliance": [1], "horde": [2], "both": [1, 2]}[a.side]
    out = []
    for side in sides:
        W = World(side)
        mine = [t for t in rows if t[1] in (0, side)]
        rng = random.Random(a.seed * 7 + side)
        for t in mine:
            src, dst = t[4], t[5]
            if src[0] not in Gs or dst[0] not in Gs:
                continue   # (Zephras Isle: no navmesh)
            GA, GB = Gs[src[0]], Gs[dst[0]]
            one = src[0] == dst[0]
            dock_a, dock_b = ground_at(GA, src[1], src[2]), ground_at(GB, dst[1], dst[2])
            for _ in range(a.per):
                A, B = place(GA, rng, dock_a), place(GB, rng, dock_b)
                if not (A and B):
                    continue
                # the best: every transport from A's continent to B's this side may take, and on one continent the
                # walk too (the polygons' own way, as the zone bench's reference)
                best, best_t = None, None
                if one and GA.piece(A) == GA.piece(B):
                    ref = GA.references(A, [B])[0]
                    if ref:
                        best, best_t = "walking", ref[1]
                for u in mine:
                    if u[4][0] != src[0] or u[5][0] != dst[0]:
                        continue
                    da, db = ground_at(GA, u[4][1], u[4][2]), ground_at(GB, u[5][1], u[5][2])
                    w1, w2 = walk(GA, A, da), walk(GB, db, B)
                    if w1 is None or w2 is None:
                        continue
                    total = w1 + u[6] + w2
                    if best_t is None or total < best_t:
                        best, best_t = u[2] + " from " + u[3], total
                if best is None:
                    continue
                route, cost = W.route((src[0],) + A, (dst[0],) + B)
                rec = {"side": side, "from": t[3], "label": t[2], "one": one,
                       "a": [src[0]] + [round(v, 1) for v in A], "b": [dst[0]] + [round(v, 1) for v in B],
                       "best": best, "ref": round(best_t, 1)}
                if not route:
                    rec["none"] = True
                    out.append(rec)
                    continue
                sc = score_route(route, A, B, GA, GB, mine)
                if isinstance(sc, str):
                    rec["skipped"] = sc
                    out.append(rec)
                    continue
                total, took, walks, stuck = sc
                rec.update(took=took, time=round(total, 1), ratio=round(total / max(1.0, best_t), 3),
                           walk=[round(w) for w in walks], stuck=stuck, route_cost=round(cost, 1))
                out.append(rec)
                print("  %-6s %-46s best %-46s %6.0f s, Route %-46s %6.0f s (x%.2f)" % (
                    ("H" if side == 2 else "A") + (" one" if one else ""), t[2] + " from " + t[3], best, best_t, took,
                    total, rec["ratio"]), flush=True)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as fh:
        for r in out:
            fh.write(json.dumps(r) + "\n")
    sc = [r for r in out if r.get("ratio")]
    ratios = sorted(r["ratio"] for r in sc)
    same = sum(1 for r in sc if r["took"] == r["best"])
    for one in (False, True):
        part = sorted(r["ratio"] for r in sc if r.get("one") == one)
        if part:
            print("  %s: %d scored, median %.3f, 90%% %.3f, worst %.2f, within 15%% %.0f%%, the best taken %d" % (
                "one continent" if one else "across the sea", len(part), rb.pct(part, .5), rb.pct(part, .9),
                max(part), 100 * sum(1 for x in part if x <= 1.15) / len(part),
                sum(1 for r in sc if r.get("one") == one and r["took"] == r["best"])))
    print("pairs %d, scored %d, no route %d: time / best median %.3f, 90%% %.3f, worst %.2f; within 15%% %.0f%%; the best "
          "transport taken %d of %d (%.0f s)" % (
              len(out), len(sc), sum(1 for r in out if r.get("none")), rb.pct(ratios, .5), rb.pct(ratios, .9),
              max(ratios) if ratios else 0, 100 * sum(1 for x in ratios if x <= 1.15) / max(1, len(sc)), same, len(sc),
              time.perf_counter() - t0))


if __name__ == "__main__":
    main()
