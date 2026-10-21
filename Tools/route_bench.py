#!/usr/bin/env python3
"""
Route's walking routes against the game's real ground, zone by zone (docs/plans/route-ground.md; the user, 2026-10-20:
"calculate the best and fastest routes, i want to aim for 100% accuracy, no more running around in circles").

  ground     wowsim's navmesh (Tools/navmesh.py) and its grid (Tools/nav_grid.py: 4.17 yd cells, which neighbours the
             character walks straight to), the zones from the ground's own areas (Tools/nav_zones.py)
  pairs      per zone: start cells on walkable ground, each with ends at short (60-300 yd), mid (300-900) and long
             (900-2500) straight distances, inside the zone and across its borders; both ends on one piece of ground
  reference  the quickest way: Dijkstra over the grid's edges (a window round the pair), pulled straight with the
             navmesh's own walks; and the navmesh's own path search (Detour) where it reaches -- the quicker of the two
  ours       FindRoute in the Lua test world (MelloUI Test/tests/feat/eta) with this checkout's Route.lua and companion
             data; its segments walked one after another over the navmesh: one that gets stuck (a wall, a drop, a cliff)
             is a FAIL, and its time is the reference's between its two ends
  report     per zone: pairs, time / best (median, 90 %, worst), within 5 % / 15 %, routes through a wall, no route;
             a line per pair in <out>/pairs_<map>.jsonl

    python Tools/route_bench.py --map 0 [--zones 1429,1436] [--sources 12] [--seed 1] [--src MelloUI_Route/Route.lua]
                                [--out dir] [--skip-route]
Environment: MELLOUI_BUILD_DATA (the navgrid's folder: <it>/cache/nav), WOWSIM / NAV_DIR (the navmesh), ETA (the test
world's folder).
"""
import argparse
import json
import math
import os
import random
import sys
import time

import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from navmesh import Nav  # noqa: E402
from nav_grid import UNIT, ORIGIN, E, S, SE, SW, build_out  # noqa: E402
from nav_zones import Zones, CAPITALS, CONTINENTS, UNDER_Z, under_city  # noqa: E402

RUN, SWIM = 7.0, 4.7
WALL_SECONDS = 3.0          # a stuck segment whose way round costs this much more: a real wall (a tree's trunk less)
WALL_SHARE = 0.15           # ... and this share of the segment's own time (a weave round woods on a long one is none)


def real_wall(st):
    """a stuck segment (kind, yards, reason, extra seconds, ...) that is a wall the player must find a way round"""
    return st[3] >= WALL_SECONDS and st[3] >= WALL_SHARE * st[1] / RUN
BANDS = (("short", 60, 300), ("mid", 300, 900), ("long", 900, 2500))
BIG_PIECE = 2000    # polygons: a piece of ground a start may lie on (an island's, the mainland's; not a roof)
DIRS = ((E, 0, 1, 1.0), (S, 1, 0, 1.0), (SE, 1, 1, math.sqrt(2)), (SW, 1, -1, math.sqrt(2)))
ETA = os.environ.get("ETA", r"F:/Download-Backup/Project Web/MelloUI Test/tests/feat/eta")


# ------------------------------------------------------------------------------------------------- the ground
class Ground:
    def __init__(self, map_id):
        self.map_id = map_id
        d = np.load(os.path.join(build_out(), "navgrid_%d.npz" % map_id))
        self.r0, self.c0 = int(d["r0"]), int(d["c0"])
        self.kind, self.z, self.edges, self.floors = d["kind"], d["z"], d["edges"], d["floors"]
        self.H, self.W = self.kind.shape
        self.nav = Nav(map_id)
        self.anchors = None
        self.zones = Zones(map_id, d)
        self._pieces()
        # the graph's nodes with their heights (Tools/nav_graph.py): a route's point on one is scored on its floor
        self.gtree = None
        gp = os.path.join(build_out(), "navgraph_%d.npz" % map_id)
        if os.path.exists(gp):
            from scipy.spatial import cKDTree
            self.gnodes = np.load(gp)["nodes"]
            self.gtree = cKDTree(self.gnodes[:, :2])

    def lift_ride(self, a, b):
        """a segment of Route's from one lift's boarding place to its other (Tools/nav_graph.py's anchors: the link it
        rides): (seconds, the other place) or None"""
        if self.anchors is None:
            self.anchors = []
            path = os.path.join(build_out(), "navanchors_%d.json" % self.map_id)
            if os.path.exists(path):
                with open(path, encoding="utf-8") as fh:
                    self.anchors = [(tuple(pb), tuple(pt), secs) for _, pb, pt, secs in json.load(fh)]
        for pb, pt, secs in self.anchors:
            for p, q in ((pb, pt), (pt, pb)):
                if math.hypot(a[0] - p[0], a[1] - p[1]) <= 3.0 and math.hypot(b[0] - q[0], b[1] - q[1]) <= 3.0:
                    return secs, q
        return None

    def node_z(self, x, y, layer=None):
        """the height of the graph's node at (x, y) (within half a yard; of that layer -- 1 an underground capital's
        streets -- where one is given), else None"""
        if self.gtree is None:
            return None
        for i in self.gtree.query_ball_point((x, y), 0.5):
            if layer is None or self.gnodes.shape[1] < 5 or int(self.gnodes[i, 4]) == layer:
                return float(self.gnodes[i, 2])
        return None

    def world(self, r, c):
        """grid (local row, col) -> world x, y, z"""
        return (ORIGIN - (r + self.r0 + 0.5) * UNIT, ORIGIN - (c + self.c0 + 0.5) * UNIT,
                float(self.z[r, c]) if self.kind[r, c] else None)

    def cell(self, x, y):
        return int((ORIGIN - x) // UNIT) - self.r0, int((ORIGIN - y) // UNIT) - self.c0

    def graph(self, ra, rb, ca, cb):
        """the window's cells as a sparse graph of seconds: (matrix, index of each cell or -1)"""
        k = self.kind[ra:rb, ca:cb]
        e = self.edges[ra:rb, ca:cb]
        h, w = k.shape
        idx = np.full((h, w), -1, np.int64)
        on = k > 0
        idx[on] = np.arange(int(on.sum()))
        factor = np.where(k == 2, RUN / SWIM, 1.0)
        rows, cols, vals = [], [], []
        for bit, dr, dc, ln in DIRS:
            a = (e & bit) > 0
            # the neighbour inside the window
            r_ok = np.zeros_like(a)
            if dc >= 0:
                r_ok[:h - dr, :w - dc] = a[:h - dr, :w - dc]
            else:
                r_ok[:h - dr, -dc:] = a[:h - dr, -dc:]
            ii, jj = np.nonzero(r_ok)
            ni, nj = ii + dr, jj + dc
            src, dst = idx[ii, jj], idx[ni, nj]
            ok = (src >= 0) & (dst >= 0)
            cost = UNIT * ln / RUN * 0.5 * (factor[ii, jj] + factor[ni, nj])
            rows += [src[ok], dst[ok]]
            cols += [dst[ok], src[ok]]
            vals += [cost[ok], cost[ok]]
        n = int(on.sum())
        m = csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n))
        return m, idx

    def _pieces(self):
        """the navmesh's own polygons and joins (Tools/nav_polys.py): the pieces of ground, exactly"""
        from scipy.sparse.csgraph import connected_components
        from nav_polys import Polys
        t0 = time.perf_counter()
        self.P = Polys(self.map_id, path=self.nav.path_file)
        self.PG = self.P.graph()
        # the lifts (Tools/nav_lifts.py): a timed join between their two landings' polygons
        import nav_lifts
        from scipy.sparse import csr_matrix
        rows, cols, vals = [], [], []
        self.lifts, self.lift_seconds = [], {}
        for lift in nav_lifts.LIFTS:
            if lift["map"] != self.map_id:
                continue
            b, t = nav_lifts.landings(self.nav, lift)
            pb, pt = (self.P.locate(*b) if b else -1), (self.P.locate(*t) if t else -1)
            if pb >= 0 and pt >= 0:
                rows += [pb, pt]
                cols += [pt, pb]
                vals += [lift["seconds"], lift["seconds"]]
                self.lifts.append((lift["name"], b, t, lift["seconds"]))
                self.lift_seconds[(pb, pt)] = self.lift_seconds[(pt, pb)] = lift["seconds"]
        if rows:
            self.PG = (self.PG + csr_matrix((vals, (rows, cols)), shape=self.PG.shape)).tocsr()
        n, lab = connected_components(self.PG, directed=False)
        self.plab = lab
        self.piece_size = np.bincount(lab)
        print("polygons: %d, joins %d, %d pieces (largest %d) in %.0f s" % (
            self.P.n, self.PG.nnz // 2, n, int(self.piece_size.max()), time.perf_counter() - t0), flush=True)

    def poly(self, p):
        return self.P.locate(p[0], p[1], p[2])

    def piece(self, p):
        i = self.poly(p)
        return int(self.plab[i]) if i >= 0 else -1

    # -------------------------------------------------------------------------------------------- the reference
    def pull(self, pts, cum):
        """a way of points pulled straight with the navmesh's walks: [(x, y, z)], seconds (exact: every leg walked)"""
        out, i, total = [pts[0]], 0, 0.0
        n = len(pts)
        cur = pts[0]
        while i < n - 1:
            lo, hi = i + 1, n - 1
            best, best_t, best_at = i + 1, None, None
            while lo <= hi:
                mid = (lo + hi) // 2
                w = self.nav.arrives(cur, pts[mid])
                if w["ok"] and w["seconds"] <= cum[mid] - cum[i] + 1e-3:
                    best, best_t, best_at = mid, w["seconds"], w["at"]
                    lo = mid + 1
                else:
                    hi = mid - 1
            if best_t is None:
                # (no straight walk to the next point: the navmesh's own path there)
                d = self.nav.path(cur, pts[i + 1])
                if d["ok"]:
                    best_t, best_at = d["seconds"], d["to"]
                    for q in d["points"][1:-1]:
                        out.append(q)
                else:
                    best_t, best_at = cum[i + 1] - cum[i], pts[i + 1]
            total += best_t
            cur = (best_at[0], best_at[1], best_at[2])
            out.append(cur)
            i = best
        return out, total

    def references(self, A, targets):
        """the quickest ways from world point A to each target point: [(points, seconds, polygon seconds) or None]"""
        s = self.poly(A)
        if s < 0:
            return [None] * len(targets)
        far = max(math.hypot(t[0] - A[0], t[1] - A[1]) for t in targets)
        dist, pred = dijkstra(self.PG, indices=int(s), return_predecessors=True, limit=far * 3 / RUN + 120)
        out = []
        for B in targets:
            ti = self.poly(B)
            if ti < 0 or not np.isfinite(dist[ti]):
                out.append(None)
                continue
            chain = [int(ti)]
            while chain[-1] != s:
                chain.append(int(pred[chain[-1]]))
            chain.reverse()
            P = self.P
            pts = [tuple(A)] + [(float(P.cx[k]), float(P.cy[k]), float(P.cz[k])) for k in chain[1:-1]] + [tuple(B)]
            cum = [0.0]
            for k in range(1, len(pts)):
                ride = self.lift_seconds.get((chain[k - 1], chain[k])) if len(chain) == len(pts) else None
                if ride is not None:
                    cum.append(cum[-1] + ride)
                    continue
                cum.append(cum[-1] + math.dist(pts[k - 1], pts[k]) / RUN *
                           (RUN / SWIM if 0 < k < len(pts) - 1 and P.area[chain[k]] == 2 else 1.0))
            way, secs = self.pull(pts, cum)
            for span in (1100.0, 550.0):
                legs = self.legs(way, span)
                if legs:
                    if legs[1] < secs - 0.01:
                        way, secs = legs
                    break
            out.append((way, secs, cum[-1]))
        return out

    def legs(self, way, span=450.0):
        """the way found again by the navmesh's own search (Detour) between points about `span` yards apart on it, each
        leg's corners kept, then pulled straight over the joins: (points, seconds) or None"""
        stops = [0]
        run = 0.0
        for k in range(1, len(way)):
            run += math.hypot(way[k][0] - way[k - 1][0], way[k][1] - way[k - 1][1])
            if run >= span or k == len(way) - 1:
                stops.append(k)
                run = 0.0
        pts = [tuple(way[0])]
        cum = [0.0]
        cur = tuple(way[0])
        for a, b in zip(stops, stops[1:]):
            d = self.nav.path(cur, tuple(way[b]))
            if not d["ok"]:
                return None
            for q in d["points"][1:]:
                cum.append(cum[-1] + math.dist(pts[-1], q) / RUN)
                pts.append(tuple(q))
            # (the leg's own time, swum stretches included, over its last point)
            cur = tuple(d["to"])
        return self.pull(pts, [c * 1.0 for c in self._timed(pts)])

    def _timed(self, pts):
        """cumulative seconds along a way of navmesh corners, each leg walked (a stuck one at three times its length)"""
        cum = [0.0]
        for k in range(1, len(pts)):
            w = self.nav.arrives(pts[k - 1], pts[k])
            cum.append(cum[-1] + (w["seconds"] if w["ok"] else 3 * math.dist(pts[k - 1], pts[k]) / RUN))
        return cum

    def detour(self, a, b):
        p = self.nav.path(a, b)
        return (p["points"], p["seconds"]) if p["ok"] else None


# ------------------------------------------------------------------------------------------------- ours
class Ours:
    def __init__(self, src, map_id, conts, learned=True, root=None):
        sys.path.insert(0, ETA)
        import eta_world
        eta_world.ROOT = (root or ROOT).replace("\\", "/").rstrip("/") + "/"
        import tempfile
        tmp = tempfile.mkdtemp()
        path = os.path.join(tmp, "Route.lua")
        hook = "\nns.__T = { FindRoute = FindRoute, Build = Build, live = live, Search = Search }\n"
        open(path, "w", encoding="utf-8").write(open(src, encoding="utf-8").read() + hook)
        t0 = time.perf_counter()
        routes = None
        if not learned:
            routes = os.path.join(tmp, "RouteData.lua")
            open(routes, "w", encoding="utf-8").write("MelloUI_RouteData = { graphs = {} }\n")
        lua = eta_world.world(path, terrain=True, routes=routes)
        lua.execute("Start()")
        lua.execute("ns.__T.Build.Want() for i = 1, 40000 do Frames(1) if ns.__T.Build.Ready() then break end end")
        assert lua.eval("ns.__T.Build.Ready()"), "the graph did not build"
        lua.globals().PYCLOCK = time.perf_counter
        lua.execute("debugprofilestop = function() return PYCLOCK() * 1000 end")
        self.lua = lua
        self.cont = CONTINENTS[map_id]
        gi = lua.eval("M.Ground.grids[%d]" % self.cont)
        self.sx, self.sy = gi["sx"], gi["sy"]
        b = conts[self.cont]
        self.x1, self.y1 = b["x1"], b["y1"]
        self.find = lua.eval("""function(a, b, c, d, ua, ub)
          local t = debugprofilestop()
          local p, cost = ns.__T.FindRoute(%d, a, b, %d, c, d, nil, nil, ua, ub)
          local ms = debugprofilestop() - t
          local out = {}
          for i, q in ipairs(p or {}) do
            local key = type(q[5]) == "string" and q[5]:match("^%%d+|(.*)$")
            out[i] = { q[1], q[2], q[3], q[4], key and (key:byte(1) == 117 and 1 or 0) or -1 }
          end
          return out, cost or -1, ms
        end""" % (self.cont, self.cont))
        print("Route's world built in %.0f s (scale %.4f x %.4f)" % (time.perf_counter() - t0, self.sx, self.sy),
              flush=True)

    def yards(self, x, y):
        """world -> Route's client yards (east, south)"""
        return (self.y1 - y) * self.sx, (self.x1 - x) * self.sy

    def world(self, e, s):
        return self.x1 - s / self.sy, self.y1 - e / self.sx

    def route(self, a, b, ua=None, ub=None):
        """Route's way from a to b (world), each end on an underground capital's streets (True), not (False) or not
        known (None) -- as the game's map of the place says: [(cont, x, y, kind, layer: 1, 0, or -1 for no node)]"""
        ea, sa = self.yards(a[0], a[1])
        eb, sb = self.yards(b[0], b[1])
        pts, cost, ms = self.find(ea, sa, eb, sb, ua, ub)
        out = []
        for i in range(1, len(pts) + 1):
            q = pts[i]
            x, y = self.world(q[2], q[3])
            out.append((q[1], x, y, q[4], q[5]))
        return out, cost, ms


def continent_rects():
    from nav_zones import table
    out = {}
    for r in table("UiMapAssignment"):
        if r["OrderIndex"] == "0" and int(r["UiMapID"]) in (1414, 1415):
            out[int(r["UiMapID"])] = {"x0": float(r["Region_0"]), "y0": float(r["Region_1"]),
                                      "x1": float(r["Region_3"]), "y1": float(r["Region_4"])}
    return out


# ------------------------------------------------------------------------------------------------- scoring
def score(G, route, a, b, ref_secs):
    """Route's polyline walked over the navmesh, segment after segment from the start's floor: seconds, stuck
    segments [(kind, yards, reason)], yards by kind"""
    total, stuck, kinds = 0.0, [], {}
    cur = a
    for i in range(1, len(route)):
        p = route[i]
        if p[3] in ("boat", "flight"):
            return None
        layer = p[4] if len(p) > 4 and p[4] >= 0 else None
        nxt = (p[1], p[2], b[2] if i == len(route) - 1 else G.node_z(p[1], p[2], layer))
        if nxt[2] is None and cur[2] is not None:
            # (a point with no height of its own -- a walked street's, a guess's: the floor there nearest the one the
            # player walks on, as they follow the line on their own level; not the highest, which over an underground
            # city's street is the ground above it)
            fl = G.nav.ground(nxt[0], nxt[1])["floors"]
            if fl:
                nxt = (nxt[0], nxt[1], min((f[0] for f in fl), key=lambda z: abs(z - cur[2])))
        ln = math.hypot(nxt[0] - cur[0], nxt[1] - cur[1])
        kinds[p[3]] = kinds.get(p[3], 0) + ln
        if ln < 0.5:
            continue
        ride = G.lift_ride(cur, nxt)
        if ride:
            # (a lift: its link's seconds, the wait and the ride)
            total += ride[0]
            cur = ride[1]
            kinds["lift"] = kinds.get("lift", 0) + ln
            kinds[p[3]] -= ln
            continue
        w = G.nav.arrives(cur, nxt)
        if w["ok"]:
            total += w["seconds"]
            cur = w["at"]
            continue
        d = G.nav.path(cur, nxt)
        if d["ok"]:
            total += d["seconds"]
            # (the way round, over the straight walk's time: a tree's trunk costs a second, a cliff minutes)
            stuck.append((p[3], round(ln), w["reason"], round(d["seconds"] - ln / RUN, 1),
                          [round(cur[0], 1), round(cur[1], 1)], [round(nxt[0], 1), round(nxt[1], 1)]))
            cur = d["to"]
        else:
            stuck.append((p[3], round(ln), w["reason"], round(2 * ln / RUN, 1),
                          [round(cur[0], 1), round(cur[1], 1)], [round(nxt[0], 1), round(nxt[1], 1)]))
            # (no way at all on the navmesh between the two: the straight line's time thrice, a guess)
            total += 3 * ln / RUN
            g = G.nav.ground(nxt[0], nxt[1])
            cur = (nxt[0], nxt[1], g["z"] if g["ok"] else None)
    return total, stuck, kinds


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * p))] if v else float("nan")


W = {}   # a worker's ground and Route world (bench_init)


def bench_init(map_id, src, skip_route, learned=True, root=None):
    from nav_grid import below_normal
    below_normal()
    W["G"] = Ground(map_id)
    W["ours"] = None if skip_route else Ours(src, map_id, continent_rects(), learned, root)
    W["big"] = int(np.argmax(W["G"].piece_size))


def bench_zone(job):
    """one zone's pairs: (zone, seed, sources, capitals) -> [record]"""
    zone, seed, sources, capitals = job
    G, ours, big = W["G"], W["ours"], W["big"]
    Z = G.zones
    rng = random.Random(seed * 100003 + zone)
    zi = Z.ids.index(zone)
    cells = np.argwhere((Z.raster == zi) & (G.kind == 1) & (G.edges == (E | S | SE | SW)))
    out = []
    if len(cells) < 50:
        return out
    for _ in range(sources):
        src = None
        for _try in range(50):
            c = tuple(cells[rng.randrange(len(cells))])
            pc = G.piece(G.world(*c))
            if pc >= 0 and G.piece_size[pc] >= BIG_PIECE:
                src, big = c, pc   # (an island's ground is its own piece: its ends on it)
                break
        if src is None:
            continue
        targets, bands = [], []
        for band, lo, hi in BANDS:
            for k in range(2):
                for _try in range(120):
                    ang = rng.uniform(0, 2 * math.pi)
                    d = rng.uniform(lo, hi) / UNIT
                    t = (int(src[0] + d * math.sin(ang)), int(src[1] + d * math.cos(ang)))
                    if not (0 <= t[0] < G.H and 0 <= t[1] < G.W):
                        continue
                    if G.kind[t] != 1 or G.edges[t] != (E | S | SE | SW):
                        continue
                    # (the first end of a band in the zone, the second anywhere: across its border)
                    if Z.of(*t) in CAPITALS and not capitals:
                        continue
                    if k == 0 and Z.of(*t) != zone:
                        continue
                    if G.piece(G.world(*t)) != big:
                        continue
                    targets.append(t)
                    bands.append(band)
                    break
        if not targets:
            continue
        A = G.world(*src)
        out += records(G, ours, zone, A, [G.world(*t) for t in targets], bands)
    return out


def records(G, ours, zone, A, Bs, bands, ua=False, ubs=None):
    """the pairs from A (world, with its floor's height) to each of Bs: the best way, Route's, scored; ua and ubs[i]
    whether the ends are on an underground capital's streets (as the game's map of the place says: Route's layers)"""
    Z = G.zones
    out = []
    refs = G.references(A, Bs)
    ubs = ubs or [False] * len(Bs)
    for B, band, ref, ub in zip(Bs, bands, refs, ubs):
        if ref is None:
            continue
        way, secs, poly_secs = ref
        rb, cb = G.cell(B[0], B[1])
        rec = {"zone": zone, "zname": Z.name.get(zone), "band": band,
               "to_zone": Z.of(rb, cb) if 0 <= rb < G.H and 0 <= cb < G.W else 0,
               "a": [round(v, 1) for v in A], "b": [round(v, 1) for v in B],
               "yards": round(math.hypot(B[0] - A[0], B[1] - A[1])), "ref": round(secs, 2),
               "ref_pull": round(secs, 2), "ref_poly": round(poly_secs, 2), "ref_points": len(way),
               "ref_way": [[round(q[0], 1), round(q[1], 1)] for q in way]}
        if rec["yards"] < 1400:
            dt = G.detour(A, B)
            if dt:
                rec["detour"] = round(dt[1], 2)
                if dt[1] < secs:
                    rec["ref"] = round(dt[1], 2)
                    rec["ref_from"] = "detour"
                    rec["ref_way"] = [[round(q[0], 1), round(q[1], 1)] for q in dt[0]]
        if ua or ub:
            rec["under"] = [bool(ua), bool(ub)]
        if ours:
            route, cost, ms = ours.route(A, B, ua, ub)
            rec["ms"] = round(ms, 2)
            if not route:
                rec["none"] = True
            else:
                sc = score(G, route, A, B, rec["ref"])
                if sc is None:
                    rec["skipped"] = "boat or flight"
                else:
                    rec.update(time=round(sc[0], 2), ratio=round(sc[0] / max(rec["ref"], 0.1), 3),
                               stuck=sc[1], kinds={k: round(v) for k, v in sc[2].items()}, points=len(route),
                               route=[[round(p[1], 1), round(p[2], 1), p[3]] + ([p[4]] if p[4] > 0 else [])
                                      for p in route])
        out.append(rec)
    return out


CITY_BANDS = (("city-short", 20, 150), ("city-mid", 150, 500))
def city_rect(G, zone):
    """a capital's region as grid rows and columns: (r0, r1, c0, c1)"""
    from nav_zones import table
    for r in table("UiMapAssignment"):
        if int(r["UiMapID"]) == zone and r["OrderIndex"] == "0" and int(r["MapID"]) == G.map_id:
            x0, y0, x1, y1 = (float(r["Region_%d" % i]) for i in (0, 1, 3, 4))
            ra, ca = G.cell(x1, y1)
            rb, cb = G.cell(x0, y0)
            return max(0, ra), min(G.H, rb + 1), max(0, ca), min(G.W, cb + 1)
    return None


def under_floors(G, zone, x, y, floors):
    """the floors at (x, y) that are an underground capital's streets: [(z, area)] (Tools/nav_zones.py's rule)"""
    return [(z, a) for z, a in floors if UNDER_Z[zone][0] <= z <= UNDER_Z[zone][1]
            and under_city(G.map_id, G.nav, x, y, z) == zone]


def bench_city(job):
    """a capital's pairs, on its own floors (the Undercity and Ironforge lie under the ground the grid's highest floor
    is): places on any floor of the city's cells that lie on the big piece of ground; ends in the city (short, mid) and
    outside it (out: 300-900 yd)"""
    zone, seed, sources, _ = job
    G, ours, big = W["G"], W["ours"], W["big"]
    Z = G.zones
    rng = random.Random(seed * 100003 + zone)
    zi = Z.ids.index(zone)
    under = zone in UNDER_Z
    if under:
        box = city_rect(G, zone)
        if not box:
            return []
        cells = np.argwhere(G.kind[box[0]:box[1], box[2]:box[3]] > 0) + np.array([box[0], box[2]])
    else:
        cells = np.argwhere((Z.raster == zi) & (G.kind > 0))
    if len(cells) < 50:
        return []
    # (the city's own piece of ground: the one most of its cells' floors are on -- the mainland's, Teldrassil's for
    # Darnassus; the ground hidden under a city -- Stormwind's flat terrain under its streets, a piece of 2,579
    # polygons of its own -- is no place a player stands)
    from collections import Counter
    probe = [cells[rng.randrange(len(cells))] for _ in range(300)]
    if under:
        own = Counter(G.piece((x, y, z)) for x, y, _ in (G.world(r, c) for r, c in probe)
                      for z, _a in under_floors(G, zone, x, y, G.nav.ground(x, y)["floors"]))
    else:
        own = Counter(G.piece(G.world(r, c)) for r, c in probe if G.kind[r, c] == 1)
    own.pop(-1, None)
    if not own:
        return []
    big = own.most_common(1)[0][0]

    piece = [None]

    def place(inside=True, near=None, lo=0.0, hi=0.0):
        for _try in range(400 if under else 200):
            if near is None:
                r, c = cells[rng.randrange(len(cells))]
            else:
                ang = rng.uniform(0, 2 * math.pi)
                d = rng.uniform(lo, hi) / UNIT
                r, c = int(near[0] + d * math.sin(ang)), int(near[1] + d * math.cos(ang))
                if not (0 <= r < G.H and 0 <= c < G.W) or G.kind[r, c] == 0:
                    continue
                if not under and (Z.raster[r, c] == zi) != inside:
                    continue
            x, y, _ = G.world(r, c)
            fl = G.nav.ground(x, y)["floors"]
            if under:
                # (in the city: its streets' floors; outside it: the floors that are not)
                streets = under_floors(G, zone, x, y, fl)
                fl = streets if inside else [f for f in fl if f not in streets]
            if not fl:
                continue
            fz, area = fl[rng.randrange(len(fl))]
            p = (x, y, fz)
            pc = G.piece(p) if area == 1 else -1
            if pc >= 0 and pc == (piece[0] if piece[0] is not None else big):
                return (r, c), p
        return None, None
    out = []
    for _ in range(sources):
        piece[0] = None
        cell, A = place()
        if A is None:
            continue
        piece[0] = G.piece(A)
        Bs, bands, ubs = [], [], []
        for band, lo, hi in CITY_BANDS:
            for _k in range(2):
                _, B = place(True, cell, lo, hi)
                if B:
                    Bs.append(B)
                    bands.append(band)
                    ubs.append(under)
        _, B = place(False, cell, 300, 900)
        if B:
            Bs.append(B)
            bands.append("city-out")
            ubs.append(False)
        out += records(G, ours, zone, A, Bs, bands, under, ubs)
    return out


def bench_any(job):
    return bench_city(job) if job[0] in CAPITALS else bench_zone(job)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", type=int, default=0)
    ap.add_argument("--zones", default="")
    ap.add_argument("--sources", type=int, default=12, help="start cells per zone (each with up to 6 ends)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--src", default=os.path.join(ROOT, "MelloUI_Route", "Route.lua"))
    ap.add_argument("--out", default=os.path.join(build_out(), "bench"))
    ap.add_argument("--capitals", action="store_true", help="the capitals too (multi-floor: z matters)")
    ap.add_argument("--skip-route", action="store_true", help="only the reference (a check of the ground)")
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--no-learned", action="store_true", help="without the learned paths (MelloUI_Route/RouteData.lua)")
    ap.add_argument("--root", default=None, help="another addon folder's data and Route.lua (a release's, to compare)")
    ap.add_argument("--stall", type=int, default=900, help="seconds a zone may take (wowsim#32: a walk that hangs)")
    ap.add_argument("--tag", default="")
    ap.add_argument("--report", default=None, help="only the report of a run's jsonl (pairs_<map><tag>.jsonl)")
    a = ap.parse_args()
    if a.report:
        report([json.loads(ln) for ln in open(a.report, encoding="utf-8")])
        return
    if a.root and a.src == os.path.join(ROOT, "MelloUI_Route", "Route.lua"):
        a.src = os.path.join(a.root, "MelloUI_Route", "Route.lua")
    os.makedirs(a.out, exist_ok=True)
    t0 = time.perf_counter()
    from nav_grid import build_out as _bo
    d = np.load(os.path.join(_bo(), "navgrid_%d.npz" % a.map))
    Z = Zones(a.map, d)
    zone_ids = [u for u in Z.ids if u]
    if a.zones:
        zone_ids = [int(v) for v in a.zones.split(",")]
    elif not a.capitals:
        zone_ids = [u for u in zone_ids if u not in CAPITALS]
    jobs = [(z, a.seed, a.sources, a.capitals) for z in zone_ids]
    results = []
    if a.jobs <= 1:
        bench_init(a.map, a.src, a.skip_route, not a.no_learned, a.root)
        for job in jobs:
            tz = time.perf_counter()
            res = bench_city(job) if job[0] in CAPITALS else bench_zone(job)
            results += res
            print("  %-24s %3d pairs in %.0f s" % (Z.name.get(job[0]), len(res), time.perf_counter() - tz), flush=True)
    else:
        import multiprocessing as mp
        pool = mp.Pool(min(a.jobs, len(jobs)), initializer=bench_init, initargs=(a.map, a.src, a.skip_route, not a.no_learned, a.root))
        it = pool.imap_unordered(bench_any, jobs)
        done = set()
        try:
            for _ in jobs:
                try:
                    res = it.next(timeout=a.stall + 300)
                except mp.TimeoutError:
                    print("STALLED: zones not done: %s" % [Z.name.get(j[0]) for j in jobs if j[0] not in done],
                          flush=True)
                    pool.terminate()
                    break
                if res:
                    done.add(res[0]["zone"])
                    print("  %-24s %3d pairs (%.0f s)" % (res[0]["zname"], len(res), time.perf_counter() - t0),
                          flush=True)
                results += res
        finally:
            pool.close()
    path = os.path.join(a.out, "pairs_%d%s.jsonl" % (a.map, a.tag))
    with open(path, "w", encoding="utf-8") as fh:
        for r in results:
            fh.write(json.dumps(r) + "\n")
    report(results, Z)
    print("bench in %.0f s -> %s" % (time.perf_counter() - t0, path))


def report(results, Z=None):
    def line(name, rs):
        sc = [r for r in rs if r.get("ratio")]
        if not sc:
            return "  %-24s n %4d  (none scored; %d no route)" % (name, len(rs), sum(1 for r in rs if r.get("none")))
        ratio = [r["ratio"] for r in sc]
        walls = sum(1 for r in sc if any(real_wall(st) for st in r["stuck"]))
        return ("  %-24s n %4d  time/best med %.3f  90%% %.3f  worst %5.2f   <=5%% %3.0f%%  <=15%% %3.0f%%   "
                "walls %3d (%2.0f%%)  none %d  ms med %.1f" % (
                    name, len(sc), pct(ratio, .5), pct(ratio, .9), max(ratio),
                    100 * sum(1 for x in ratio if x <= 1.05) / len(sc), 100 * sum(1 for x in ratio if x <= 1.15) / len(sc),
                    walls, 100 * walls / len(sc), sum(1 for r in rs if r.get("none")),
                    pct([r["ms"] for r in sc], .5)))
    zones = []
    for r in results:
        if r["zone"] not in zones:
            zones.append(r["zone"])
    for z in zones:
        print(line(results[[r["zone"] for r in results].index(z)]["zname"], [r for r in results if r["zone"] == z]))
    for band, _, _ in BANDS + CITY_BANDS + (("city-out", 0, 0),):
        rs = [r for r in results if r["band"] == band]
        if rs:
            print(line("(%s)" % band, rs))
    print(line("ALL", results))
    det = [r for r in results if "detour" in r and r.get("ref_pull")]
    if det:
        q = [r["detour"] / max(0.1, r["ref_pull"]) for r in det]
        print("  reference check: Detour's path / the grid's pulled way: median %.3f, 10%% %.3f, 90%% %.3f (n %d)" % (
            pct(q, .5), pct(q, .1), pct(q, .9), len(q)))
    reasons = {}
    for r in results:
        for st in r.get("stuck", []):
            if real_wall(st):
                reasons[(st[0], st[2])] = reasons.get((st[0], st[2]), 0) + 1
    if reasons:
        print("  real walls (way round >= %.0f s and %.0f %% of the segment) by kind and reason: " % (
            WALL_SECONDS, WALL_SHARE * 100) + ", ".join(
            "%s/%s %d" % (k, w, n) for (k, w), n in sorted(reasons.items(), key=lambda x: -x[1])))


if __name__ == "__main__":
    main()
