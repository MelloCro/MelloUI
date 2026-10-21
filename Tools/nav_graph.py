#!/usr/bin/env python3
"""
Route's graph from the real ground (docs/plans/route-ground.md): the corridors the quickest walks use, as nodes and
straight links the navmesh allows. Offline; Tools/nav_bake.py lays it into MelloUI_Companion/RoadData.lua.

  ways      from start places on a lattice (every SRC yards of walkable ground on the big pieces) to end places
            round each (every TGT yards, out to REACH): the best way (Tools/route_bench.py's reference: the polygons'
            Dijkstra, pulled straight with the navmesh's walks, searched again by Detour in legs) -- its corners are
            where a quickest walk bends: round a rock, a cliff's end, a bridge's head, a gate
  nodes     the corners, merged within MERGE yards (the most used place kept), and a lattice every FILL yards where
            no corner is within FILL_GAP (so every place has a node near); never two in one of Route's 10-yard cells
  links     each way's own legs, and between nodes within LINK yards whose straight walk the navmesh allows; priced
            by the walk's real seconds (swum yards at the swimming speed); a link two others cover within SPAN (their
            sum no more than SPAN times it) dropped

    python Tools/nav_graph.py --map 0 [--jobs 6] [--src 250] [--tgt 180] [--reach 1500]

Writes <NAV_OUT>/navgraph_<map>.npz: nodes (world x, y, z, uses), links (i, j, seconds).
"""
import argparse
import re
import json
import math
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from nav_grid import UNIT, ORIGIN, E, S, SE, SW, ZGAP, build_out, below_normal  # noqa: E402

FULL = E | S | SE | SW
MERGE = 6.0
FILL = 70.0
FILL_GAP = 45.0
LINK = 160.0
LINK_K = 24
SPAN = 1.02
CELL = 10.0          # Route.lua's CELL: one node per cell
SPACE = CELL * math.sqrt(2) + 0.1   # two nodes this far apart never share a cell
CELL_SAFE = SPACE
MIN_PIECE = 60       # polygons: a piece of ground smaller is a roof, a ledge, a rock's top
LOCAL_STEP = 60.0    # yards between the local ways' places (every walkable cell's ground, rough or open)
LOCAL_REACH = 140.0
LOCAL_K = 6
LIFT_PIECE = 2000    # polygons: the main ground of a lift's floor (a shaft's closed base is a few)
LIFT_K = 10          # lattice places round a lift's boarding place its ways go to
DOCK_REACH = 90.0    # yards round a ship's stop its boarding place is looked for (the pier's end)
DOCK_K = 8           # lattice places round a dock's boarding place its ways go to
CITY_STEP = 15.0     # yards between a capital's places (its streets; each street floor of an underground one)
CITY_REACH = 60.0    # yards to the places a capital's place has its ways to ...
CITY_K = 8           # ... the nearest so many (on its own floor: heights count thrice)
CITY_SPACE = CELL_SAFE   # yards between nodes in a capital: as near as Route's cells allow (its lanes, its doors)
JOBS = 6


W = {}


def init(map_id):
    below_normal()
    import route_bench as rb
    W["G"] = rb.Ground(map_id)
    big = W["G"].piece_size
    W["ok_piece"] = big >= MIN_PIECE


def ways(job):
    """one start place: [(points)] its best ways to the end places round it"""
    src, targets = job
    G = W["G"]
    A = G.world(*src)
    if G.piece(A) < 0:
        return []
    out = []
    pa = G.piece(A)
    tg = []
    for t in targets:
        B = G.world(*t)
        if G.piece(B) == pa:
            tg.append(B)
    for k in range(0, len(tg), 64):
        for ref in G.references(A, tg[k:k + 64]):
            if ref:
                out.append([tuple(round(v, 2) for v in q) for q in ref[0]])
    return out


def local_ways(job):
    """one lattice place: the navmesh's own ways (Detour) to its lattice neighbours -- every rough place gets the
    corners of its way out (a hill's ramp, a gap between rocks), joined"""
    src, targets = job
    G = W["G"]
    A = G.world(*src)
    out = []
    for t in targets:
        B = G.world(*t)
        d = G.nav.path(A, B)
        straight = math.hypot(B[0] - A[0], B[1] - A[1])
        if d["ok"] and d["yards"] <= 2.5 * straight + 20 and len(d["points"]) >= 2:
            out.append([tuple(round(v, 2) for v in q) for q in d["points"]])
    return out


def lift_anchors(map_id):
    """the lifts on this map (Tools/nav_lifts.py): a boarding place by each landing on the main ground of its floor
    (a piece of at least LIFT_PIECE polygons: not the closed base of a shaft), the two 15 yd apart at least on the map
    (Route's graph is flat: one node a 10-yard cell), each as near its shaft as that allows -> [(name, bottom, top,
    seconds: the wait, the ride and the steps to and from the car)]"""
    import nav_lifts
    G = W["G"]
    out = []
    for lift in nav_lifts.LIFTS:
        if lift["map"] != map_id:
            continue
        levels = []
        for zl in (lift["bottom"], lift["top"]):
            c = []
            for r in (4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0):
                for k in range(24):
                    a = 2 * math.pi * k / 24
                    x, y = lift["x"] + r * math.cos(a), lift["y"] + r * math.sin(a)
                    for fz, area in G.nav.ground(x, y)["floors"]:
                        if abs(fz - zl) <= 6.0:
                            p = (x, y, fz)
                            pc = G.piece(p)
                            if pc >= 0 and G.piece_size[pc] >= LIFT_PIECE:
                                c.append((r, p))
                            break
            levels.append(c)
        best = None
        for rb, pb in levels[0]:
            for rt, pt in levels[1]:
                if math.hypot(pb[0] - pt[0], pb[1] - pt[1]) >= 15.0 and (best is None or rb + rt < best[0]):
                    best = (rb + rt, pb, pt)
        if best:
            out.append((lift["name"], best[1], best[2], lift["seconds"] + best[0] / 7.0))
        else:
            out.append((lift["name"], None, None, 0))
    return out


def anchor_ways(job):
    """a lift's boarding place: the navmesh's own ways to the lattice places round it"""
    A, targets = job
    G = W["G"]
    out = []
    for t in targets:
        B = G.world(*t)
        d = G.nav.path(A, B)
        if d["ok"] and len(d["points"]) >= 2:
            out.append([tuple(round(v, 2) for v in q) for q in d["points"]])
    return out


def city_places(map_id):
    """the capitals' places on this map: [(zone, layer, (x, y, z))] -- an open city's every CITY_STEP yards of its
    streets (the grid's floor, the city's own cells), an underground one's on each of its street floors (Tools/
    nav_zones.py's rule; layer 1: Route keeps them apart from the ground above), all on the city's own piece of ground
    (the one most of them are on: the mainland's, Teldrassil's for Darnassus -- not the ground hidden under a city)"""
    from collections import Counter
    from nav_zones import CAPITALS, UNDER_Z, city_region, under_city
    G = W["G"]
    out = []
    for zone in CAPITALS:
        reg = city_region(map_id, zone)
        if not reg:
            continue
        x0, y0, x1, y1 = reg
        found = []
        for x in np.arange(x0 + CITY_STEP / 2, x1, CITY_STEP):
            for y in np.arange(y0 + CITY_STEP / 2, y1, CITY_STEP):
                x, y = float(x), float(y)
                if zone in UNDER_Z:
                    for fz, area in G.nav.ground(x, y)["floors"]:
                        if area == 1 and under_city(map_id, G.nav, x, y, fz) == zone:
                            found.append((1, (x, y, float(fz))))
                else:
                    r, c = G.cell(x, y)
                    if 0 <= r < G.H and 0 <= c < G.W and G.kind[r, c] == 1 and G.zones.of(r, c) == zone:
                        found.append((0, G.world(r, c)))
        pieces = [G.piece(p) for _, p in found]
        common = Counter(pc for pc in pieces if pc >= 0).most_common(1)
        if not common:
            continue
        own = common[0][0]
        out += [(zone, layer, p) for (layer, p), pc in zip(found, pieces) if pc == own]
    return out


def city_ways(job):
    """a capital's place: the navmesh's own ways to its neighbours, each arriving on the neighbour's floor"""
    A, targets = job
    G = W["G"]
    out = []
    for B in targets:
        d = G.nav.path(A, B)
        straight = math.hypot(B[0] - A[0], B[1] - A[1])
        if (d["ok"] and abs(d["to"][2] - B[2]) <= G.nav.ZTOL and d["yards"] <= 2.5 * straight + 20
                and len(d["points"]) >= 2):
            out.append([tuple(round(v, 2) for v in q) for q in d["points"]])
    return out


def city_batch(jobs):
    out = []
    for job in jobs:
        out += city_ways(job)
    return out


def city_pass(map_id, jobs, stall):
    """the capitals' ways (city_places, city_ways): [way]"""
    import multiprocessing as mp
    from scipy.spatial import cKDTree
    t0 = time.perf_counter()
    pool = mp.Pool(jobs, initializer=init, initargs=(map_id,))
    try:
        places = pool.apply(city_places, (map_id,))
        print("city places: %d (%d on underground floors), %.0f s" % (
            len(places), sum(1 for p in places if p[1]), time.perf_counter() - t0), flush=True)
        cjobs = []
        for key in sorted(set((z, l) for z, l, _ in places)):
            pts = [p for z, l, p in places if (z, l) == key]
            arr = np.array([(p[0], p[1], 3 * p[2]) for p in pts])
            tree = cKDTree(arr)
            for i, p in enumerate(pts):
                dd, ii = tree.query(arr[i], k=CITY_K + 1, distance_upper_bound=CITY_REACH)
                near = [pts[j] for d_, j in zip(np.atleast_1d(dd), np.atleast_1d(ii)) if j < len(pts) and j > i]
                if near:
                    cjobs.append((p, near))
        batches = [cjobs[k:k + 32] for k in range(0, len(cjobs), 32)]
        print("city ways to find: %d" % sum(len(j[1]) for j in cjobs), flush=True)
        it = pool.imap_unordered(city_batch, batches)
        out = []
        for n in range(len(batches)):
            try:
                out += it.next(timeout=stall)
            except mp.TimeoutError:
                print("STALLED after %d of %d city batches" % (n, len(batches)), flush=True)
                pool.terminate()
                break
        print("city ways: %d in %.0f s" % (len(out), time.perf_counter() - t0), flush=True)
        return out
    finally:
        pool.close()


def boarding_place(G, x, y, reach=None):
    """a transport's boarding place by its stop (x, y): the walkable floor nearest it on the biggest piece of ground
    round it -- the street, not the mountain over Ironforge's tram station; the island's own for Rut'theran Village's
    -- at least LIFT_PIECE polygons: (x, y, z) or None"""
    for rad in (0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 25.0, 30.0, 35.0, 40.0, 50.0, 60.0, 70.0, 80.0, reach or DOCK_REACH):
        n = max(1, int(2 * math.pi * rad / 4.0))
        best = None
        for k in range(n):
            a = 2 * math.pi * k / n
            px, py = x + rad * math.cos(a), y + rad * math.sin(a)
            for fz, area in G.nav.ground(px, py)["floors"]:
                p = (px, py, fz)
                pc = G.piece(p) if area == 1 else -1
                if pc >= 0 and G.piece_size[pc] >= LIFT_PIECE and (best is None or G.piece_size[pc] > best[0]):
                    best = (G.piece_size[pc], p)
        if best:
            return best[1]
    return None


def dock_places(map_id):
    """the transports' docks on this map (the Quest List's: boats, zeppelins, the tram's and the portal's ends): a
    boarding place each -- the walkable floor nearest the ship's stop on a big piece of ground (a pier's end), the
    nearest first -> [(label, (x, y, z))] (the route bench, 2026-10-21: Auberdine's piers had no node within 150 yd of
    a ship, and Route never took its boats)"""
    import csv
    G = W["G"]
    text = open(os.path.join(os.path.dirname(HERE), "Media", "QuestListData.lua"), encoding="utf-8").read()
    blk = text[text.index("\ttransports = {"):]
    blk = blk[:blk.index("\n\t},")]
    out = []
    for raw in re.findall(r"\{([^{}]*)\}", blk):
        r = next(csv.reader([raw]))
        if int(r[4]) != map_id:
            continue
        x, y = float(r[5]), float(r[6])
        out.append((r[2] + " (" + r[3] + ")", boarding_place(G, x, y)))
    return out


def local_batch(jobs):
    out = []
    for job in jobs:
        out += local_ways(job)
    return out


def lattice(kind, edges, step_cells, r_off=0, c_off=0, open_only=True):
    """cells on walkable ground (open ground all round, or any with open_only False), one every step_cells"""
    H, W_ = kind.shape
    rr = np.arange(r_off, H, step_cells)
    cc = np.arange(c_off, W_, step_cells)
    R, Cc = np.meshgrid(rr, cc, indexing="ij")
    R, Cc = R.ravel(), Cc.ravel()
    ok = (kind[R, Cc] == 1)
    if open_only:
        ok &= (edges[R, Cc] == FULL)
    return list(zip(R[ok].tolist(), Cc[ok].tolist()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--src", type=float, default=250.0)
    ap.add_argument("--tgt", type=float, default=180.0)
    ap.add_argument("--reach", type=float, default=1500.0)
    ap.add_argument("--only", default="", help="r0,c0,r1,c1 of grid cells: a part, for a test")
    ap.add_argument("--stall", type=int, default=600)
    ap.add_argument("--space", type=float, default=None, help="yards between nodes at least (SPACE)")
    ap.add_argument("--from-ways", action="store_true", help="the ways of the last run (navways, navanchors): links only")
    ap.add_argument("--link", type=float, default=None, help="yards a link reaches (LINK)")
    ap.add_argument("--cities", action="store_true", help="the capitals' ways made anew (city_pass), then the graph "
                    "from the last run's ways and them")
    a = ap.parse_args()
    global SPACE, LINK
    if a.space:
        SPACE = max(SPACE, a.space)
    if a.link:
        LINK = a.link
    t0 = time.perf_counter()
    d = np.load(os.path.join(build_out(), "navgrid_%d.npz" % a.map))
    kind, edges, z = d["kind"], d["edges"], d["z"]
    r0, c0 = int(d["r0"]), int(d["c0"])
    H, Wd = kind.shape
    box = None
    if a.only:
        box = [int(v) for v in a.only.split(",")]
    city_path = os.path.join(build_out(), "navcityways_%d.npy" % a.map)
    if a.from_ways or a.cities:
        all_ways = [[tuple(float(v) for v in q) for q in w]
                    for w in np.load(os.path.join(build_out(), "navways_%d.npy" % a.map), allow_pickle=True)]
        with open(os.path.join(build_out(), "navanchors_%d.json" % a.map), encoding="utf-8") as fh:
            anchors = [(n, tuple(pb), tuple(pt), sec) for n, pb, pt, sec in json.load(fh)]
        print("the last run's ways: %d" % len(all_ways), flush=True)
        if a.cities:
            city = city_pass(a.map, a.jobs, a.stall)
            np.save(city_path, np.array([np.array(w, np.float32) for w in city], dtype=object), allow_pickle=True)
        elif os.path.exists(city_path):
            city = [[tuple(float(v) for v in q) for q in w] for w in np.load(city_path, allow_pickle=True)]
            print("the capitals' ways: %d" % len(city), flush=True)
        else:
            city = []
        docks, dways = dock_pass(a.map, kind, edges, r0, c0, a.jobs)
        build_graph(a.map, all_ways + city + dways, kind, edges, z, r0, c0, box, anchors, docks)
        return
    srcs = lattice(kind, edges, int(a.src / UNIT))
    tgts = lattice(kind, edges, int(a.tgt / UNIT), int(a.tgt / UNIT / 2), int(a.tgt / UNIT / 2))
    if box:
        srcs = [s for s in srcs if box[0] <= s[0] < box[2] and box[1] <= s[1] < box[3]]
    from scipy.spatial import cKDTree
    tt = cKDTree(np.array(tgts, float))
    reach = a.reach / UNIT
    jobs = []
    for s in srcs:
        near = tt.query_ball_point(s, reach)
        if near:
            jobs.append((s, [tgts[i] for i in near]))
    print("map %d: %d start places, %d end places, %d ways to find" % (
        a.map, len(jobs), len(tgts), sum(len(j[1]) for j in jobs)), flush=True)
    import multiprocessing as mp
    pool = mp.Pool(a.jobs, initializer=init, initargs=(a.map,))
    it = pool.imap_unordered(ways, jobs, chunksize=1)
    all_ways = []
    try:
        for n in range(len(jobs)):
            try:
                res = it.next(timeout=a.stall)
            except mp.TimeoutError:
                print("STALLED after %d of %d start places" % (n, len(jobs)), flush=True)
                pool.terminate()
                break
            all_ways += res
            if n % 50 == 0:
                el = time.perf_counter() - t0
                print("  %d/%d start places, %d ways, %.0f s" % (n + 1, len(jobs), len(all_ways), el), flush=True)
        # the local ways: a lattice over every walkable cell, each place's navmesh way to its LOCAL_K nearest within
        # LOCAL_REACH (a pocket of rough ground the long ways passed by)
        loc = lattice(kind, edges, int(LOCAL_STEP / UNIT), open_only=False)
        if box:
            loc = [s for s in loc if box[0] <= s[0] < box[2] and box[1] <= s[1] < box[3]]
        lt = cKDTree(np.array(loc, float))
        ljobs = []
        for i, s in enumerate(loc):
            near = [j for j in lt.query(s, k=LOCAL_K + 1, distance_upper_bound=LOCAL_REACH / UNIT)[1]
                    if j < len(loc) and j > i]
            if near:
                ljobs.append((s, [loc[j] for j in near]))
        print("local ways: %d places, %d ways to find" % (len(ljobs), sum(len(j[1]) for j in ljobs)), flush=True)
        n_long = len(all_ways)
        batches = [ljobs[k:k + 32] for k in range(0, len(ljobs), 32)]
        it = pool.imap_unordered(local_batch, batches)
        for n in range(len(batches)):
            try:
                res = it.next(timeout=a.stall)
            except mp.TimeoutError:
                print("STALLED after %d of %d local batches" % (n, len(batches)), flush=True)
                pool.terminate()
                break
            all_ways += res
            if n % 100 == 0:
                print("  %d/%d local batches, %d ways, %.0f s" % (n + 1, len(batches), len(all_ways) - n_long,
                                                               time.perf_counter() - t0), flush=True)
        # the lifts: their boarding places, and the ways from them to the lattice round
        anchors = pool.apply(lift_anchors, (a.map,))
        ajobs = []
        for name, pb, pt, secs in anchors:
            if not pb:
                print("lift %s: no boarding places 15 yd apart on the main ground" % name, flush=True)
                continue
            print("lift %s: boarding at (%.1f, %.1f, %.1f) and (%.1f, %.1f, %.1f), %.1f s" % ((name,) + pb + pt + (secs,)),
                  flush=True)
            for p in (pb, pt):
                cell = ((ORIGIN - p[0]) / UNIT - r0, (ORIGIN - p[1]) / UNIT - c0)
                near = [j for j in lt.query(cell, k=LIFT_K)[1] if j < len(loc)]
                ajobs.append((p, [loc[j] for j in near]))
        for res in pool.map(anchor_ways, ajobs):
            all_ways += res
        print("ways: %d in %.0f s" % (len(all_ways), time.perf_counter() - t0), flush=True)
        np.save(os.path.join(build_out(), "navways_%d.npy" % a.map),
                np.array([np.array(w, np.float32) for w in all_ways], dtype=object), allow_pickle=True)
        with open(os.path.join(build_out(), "navanchors_%d.json" % a.map), "w", encoding="utf-8") as fh:
            json.dump([x for x in anchors if x[1]], fh)
    finally:
        pool.close()
    docks, dways = dock_pass(a.map, kind, edges, r0, c0, a.jobs)
    build_graph(a.map, all_ways + dways, kind, edges, z, r0, c0, box, [x for x in anchors if x[1]], docks)


def dock_pass(map_id, kind, edges, r0, c0, jobs):
    """the docks' boarding places (dock_places) and the navmesh's ways from each to the DOCK_K lattice places nearest
    it -> ([(x, y, z)], [way])"""
    import multiprocessing as mp
    from scipy.spatial import cKDTree
    loc = lattice(kind, edges, int(LOCAL_STEP / UNIT), open_only=False)
    lt = cKDTree(np.array(loc, float))
    pool = mp.Pool(min(jobs, 4), initializer=init, initargs=(map_id,))
    try:
        places = pool.apply(dock_places, (map_id,))
        ajobs, kept = [], []
        for label, p in places:
            if not p:
                print("dock %s: no boarding place within %.0f yd" % (label, DOCK_REACH), flush=True)
                continue
            kept.append(p)
            cell = ((ORIGIN - p[0]) / UNIT - r0, (ORIGIN - p[1]) / UNIT - c0)
            near = [j for j in lt.query(cell, k=DOCK_K)[1] if j < len(loc)]
            ajobs.append((p, [loc[j] for j in near]))
        ways = []
        for res in pool.map(anchor_ways, ajobs):
            ways += res
    finally:
        pool.close()
    print("docks: %d boarding places, %d ways" % (len(kept), len(ways)), flush=True)
    return kept, ways


BRIDGE_REACH = 260.0  # yards: a piece of the graph cut off from the rest looks this far for a node of another
BRIDGE_TRIES = 10     # ... and asks the navmesh for a way to so many of the nearest
BRIDGE_FLOOR = 4.0    # yards of height a way's corner and a node it is taken for may be apart (one floor)
BRIDGE_OVER, BRIDGE_PLUS = 2.0, 10.0   # a bridge's leg: its way within twice the straight walk and 10 s (priced by it)
NEAR_OVER, NEAR_PLUS = 1.08, 1.5   # a near-straight link: its way round within 8 % + 1.5 s of the straight walk's time
WIND_REACH, WIND_RISE = 25.0, 6.0   # a winding link: two nodes this near on the map, a floor apart at least, ...
WIND_OVER, WIND_PLUS = 3.0, 15.0     # ... whose way is a stair winding over itself (within this of the straight walk;
                                     # Orgrimmar's spiral from 54 to 33 yd: no node a turn, Route one a cell -- the
                                     # route bench, 2026-10-21: 104 s round the city for a 17 s walk down it)
NEAR_CAP = 2.5    # ... and NEAR_CAP seconds at most (the route bench: a link whose way round a rock or a stand of trees
                  # cost 3 s or more drew its line through them -- the graph's corners there are the way, 2026-10-20)


def init_nav(map_id):
    """a link checker's worker: a navmesh handle of its own, the one without map.nav.geom where there is one (a stuck
    walk's reason is not needed here, and asking it is most of a stuck walk's time: NAV_FAST)"""
    below_normal()
    from navmesh import Nav
    fast = os.environ.get("NAV_FAST")
    path = os.path.join(fast, str(map_id), "map.nav") if fast else None
    W["nav"] = Nav(map_id, path=path if path and os.path.exists(path) else None)


def link_price(nav, a, b, over=None, plus=None):
    """a link's seconds by check_links' rule (the straight walk both ways, arriving on the end's floor; else the
    navmesh's way round within NEAR_OVER, NEAR_PLUS and NEAR_CAP of it -- or within `over` times the straight walk
    and `plus` seconds where given: a bridge's leg, the only join of a piece), or None"""
    fw, bw = nav.walks_ok([(a, b)])[0], nav.walks_ok([(b, a)])[0]
    if fw[0] and bw[0]:
        return max(fw[1], bw[1])
    d = nav.path(a, b, points=False)
    straight = math.dist(a, b) / 7.0
    limit = (straight * over + plus) if over else min(straight * NEAR_OVER + NEAR_PLUS, straight + NEAR_CAP)
    if d["ok"] and abs(d["to"][2] - b[2]) <= nav.ZTOL and d["seconds"] <= limit:
        return d["seconds"]
    return None


def check_links(batch):
    """[(i, j, a, b)] -> [(i, j, seconds)]: the straight walk both ways (arriving on each end's floor), else a
    near-straight way round (the navmesh's own, within NEAR_OVER and NEAR_PLUS of the straight walk), priced by it"""
    nav = W["nav"]
    segs = [(a, b) for _, _, a, b in batch]
    fw = nav.walks_ok(segs)
    bw = nav.walks_ok([(b, a) for a, b in segs])
    out = []
    for (i, j, a, b), (ok, secs, _, _), (ok2, secs2, _, _) in zip(batch, fw, bw):
        if ok and ok2:
            out.append((i, j, max(secs, secs2), 0))
            continue
        d = nav.path(a, b, points=False)
        straight = math.dist(a, b) / 7.0
        if not (d["ok"] and abs(d["to"][2] - b[2]) <= nav.ZTOL):
            continue
        if d["seconds"] <= min(straight * NEAR_OVER + NEAR_PLUS, straight + NEAR_CAP):
            out.append((i, j, d["seconds"], 1))
        elif (math.hypot(a[0] - b[0], a[1] - b[1]) <= WIND_REACH and abs(a[2] - b[2]) >= WIND_RISE
              and d["seconds"] <= straight * WIND_OVER + WIND_PLUS):
            out.append((i, j, d["seconds"], 2))   # (a winding stair: priced by its way)
    return out


def tagged(job):
    name, k, batch = job
    return k, globals()[name](batch)


def pooled(name, batches, map_id, jobs, stall):
    """a worker function (by name) over the batches with link checkers' workers (init_nav); a pool that answers
    nothing for `stall` seconds is stuck in the library (wowsim#32: a walk that never returns): it is ended, its
    batches in hand (the first `jobs` unfinished) dropped, and a new pool goes on with the rest -> {batch: result}"""
    import multiprocessing as mp
    todo = list(range(len(batches)))
    done = {}
    dropped = 0
    while todo:
        pool = mp.Pool(jobs, initializer=init_nav, initargs=(map_id,))
        it = pool.imap_unordered(tagged, [(name, k, batches[k]) for k in todo])
        stalled = False
        try:
            for _ in range(len(todo)):
                k, res = it.next(timeout=stall)
                done[k] = res
        except mp.TimeoutError:
            stalled = True
        pool.terminate()
        left = [k for k in todo if k not in done]
        if stalled:
            dropped += min(jobs, len(left))
            left = left[jobs:]
            print("  a worker stuck (wowsim#32): %d batches dropped so far, %d to go" % (dropped, len(left)), flush=True)
        todo = left
    return done


def build_graph(map_id, all_ways, kind, edges, z, r0, c0, box=None, anchors=(), docks=()):
    from scipy.spatial import cKDTree
    t0 = time.perf_counter()
    # the corners: every way's inner points, and its two ends
    pts, uses = [], []
    for w in all_ways:
        for q in w:
            pts.append(q)
    P = np.array(pts, np.float64)
    print("corners: %d" % len(P), flush=True)
    # merged within MERGE yards (and close in height): grid hashing, the most used place of each group kept
    key = np.floor(P[:, 0] / MERGE).astype(np.int64) * 100003 + np.floor(P[:, 1] / MERGE).astype(np.int64)
    order = np.lexsort((np.round(P[:, 2] / 3.0), key))
    groups = {}
    for i in order:
        k = (int(key[i]), int(round(P[i, 2] / 3.0)))
        groups.setdefault(k, []).append(i)
    nodes = []
    for k, idx in groups.items():
        sub = P[idx]
        nodes.append((float(sub[:, 0].mean()), float(sub[:, 1].mean()), float(sub[:, 2].mean()), len(idx)))
    N = np.array(nodes)
    print("merged: %d" % len(N), flush=True)
    # the lattice where no corner is near
    tree = cKDTree(N[:, :2])
    fill = []
    step = int(FILL / UNIT)
    for (r, c) in lattice(kind, edges, step, step // 2, step // 2):
        if box and not (box[0] <= r < box[2] and box[1] <= c < box[3]):
            continue
        x, y = ORIGIN - (r + r0 + 0.5) * UNIT, ORIGIN - (c + c0 + 0.5) * UNIT
        if not tree.query_ball_point((x, y), FILL_GAP):
            fill.append((x, y, float(z[r, c]), 0))
    if fill:
        N = np.vstack([N, np.array(fill)])
    print("with the lattice: %d (+%d)" % (len(N), len(fill)), flush=True)
    # the lifts' boarding places, kept before any other node (Tools/nav_lifts.py), and the docks'
    for name, pb, pt, secs in anchors:
        N = np.vstack([N, np.array([pb + (1e9,), pt + (1e9,)])])
    for p in docks:
        N = np.vstack([N, np.array([tuple(p) + (1e9,)])])
    # each node's layer: 1 on an underground capital's streets (Tools/nav_zones.py's rule), else 0 -- Route keys the
    # two apart (the ground over Ironforge's and the Undercity's streets lies in the same cells)
    from navmesh import Nav
    from nav_zones import CAPITALS, UNDER_Z, city_region, under_city
    nav = Nav(map_id)
    low = min(lo for lo, _ in UNDER_Z.values())
    high = max(hi for _, hi in UNDER_Z.values())
    layer = np.zeros(len(N))
    for i in range(len(N)):
        zz = N[i, 2]
        if low <= zz <= high and under_city(map_id, nav, N[i, 0], N[i, 1], zz):
            layer[i] = 1
    nav.close()
    N = np.column_stack([N, layer])
    print("on underground streets: %d" % int(layer.sum()), flush=True)
    regions = [r for r in (city_region(map_id, zc) for zc in CAPITALS) if r]

    def in_city(x, y):
        return any(r[0] <= x <= r[2] and r[1] <= y <= r[3] for r in regions)
    # never two of a layer in one of Route's 10-yard cells, whatever the client's map scale (its yards are the
    # companion's times WorldSize / size, 1 or more): nodes SPACE yards apart at least (CITY_SPACE in a capital), the
    # most used kept first
    N = N[np.argsort(-N[:, 3], kind="stable")]
    grid = {}
    keep = []
    for i in range(len(N)):
        x, y, li = N[i, 0], N[i, 1], int(N[i, 4])
        gx, gy = math.floor(x / SPACE), math.floor(y / SPACE)
        near = CITY_SPACE if in_city(x, y) else SPACE
        clash = False
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for j in grid.get((li, gx + dx, gy + dy), ()):
                    # (two lifts' boarding places keep only the cells' own distance: a lift's two lie 15 yd apart)
                    rad = CELL_SAFE if N[i, 3] >= 1e9 and N[j, 3] >= 1e9 else near
                    if (N[j, 0] - x) ** 2 + (N[j, 1] - y) ** 2 < rad * rad:
                        clash = True
                        break
                if clash:
                    break
            if clash:
                break
        if not clash:
            grid.setdefault((li, gx, gy), []).append(i)
            keep.append(i)
    N = N[keep]
    print("spaced %.1f yd (%.1f in a capital): %d" % (SPACE, CITY_SPACE, len(N)), flush=True)
    # links: each way's legs (node to node along it), then every pair within LINK the navmesh walks
    tree = cKDTree(N[:, :2])
    cand = set()
    for w in all_ways:
        ids = []
        for q in w:
            d, i = tree.query(q[:2])
            if d <= MERGE * 1.5 and (not ids or ids[-1] != i):
                ids.append(int(i))
        for a_, b_ in zip(ids, ids[1:]):
            cand.add((min(a_, b_), max(a_, b_)))
    nb = tree.query_ball_point(N[:, :2], LINK)
    for i, lst in enumerate(nb):
        # (the nearest on its own floor first: heights count twice)
        lst = sorted(lst, key=lambda j: (N[j, 0] - N[i, 0]) ** 2 + (N[j, 1] - N[i, 1]) ** 2
                     + (2 * (N[j, 2] - N[i, 2])) ** 2)[:LINK_K + 1]
        for j in lst:
            if j != i:
                cand.add((min(i, j), max(i, j)))
    cand = sorted(cand)
    # (two floors too far apart for the line's length: asked only as a winding stair, within WIND_REACH -- wowsim
    # 0.9.1 ends a walk over stacked floors, #32)
    segs, pairs = [], []
    for i, j in cand:
        dx = math.hypot(N[i, 0] - N[j, 0], N[i, 1] - N[j, 1])
        if abs(N[i, 2] - N[j, 2]) > dx * 1.25 + 2.0 and dx > WIND_REACH:
            continue
        segs.append(((N[i, 0], N[i, 1], N[i, 2]), (N[j, 0], N[j, 1], N[j, 2])))
        pairs.append((i, j))
    print("candidate links: %d (%.0f s)" % (len(segs), time.perf_counter() - t0), flush=True)
    # each candidate: the straight walk both ways, else a near-straight way round (a line the trees' trunks or a
    # rock's corner block, whose navmesh way round costs little more -- the player weaves round them; priced by it);
    # in the link checkers' pool, which survives a walk that never returns (wowsim#32)
    work = [(i, j, a, b) for (i, j), (a, b) in zip(pairs, segs)]
    batches = [work[k:k + 1000] for k in range(0, len(work), 1000)]
    done = pooled("check_links", batches, map_id, JOBS, 120)
    links, near = [], 0
    winding = 0
    for res in done.values():
        for i, j, secs, bent in res:
            links.append((i, j, secs))
            near += bent == 1
            winding += bent == 2
    print("walkable links: %d, %d of them near-straight, %d winding; %d of %d candidate batches checked (%.0f s)" % (
        len(links), near, winding, len(done), len(batches), time.perf_counter() - t0), flush=True)
    links = prune(len(N), links)
    print("after pruning: %d links, %.1f a node" % (len(links), 2 * len(links) / max(1, len(N))), flush=True)
    N, links = bridges(map_id, N, links)
    # the lifts: a link between their two boarding places, priced as the wait, the ride and the steps
    for name, pb, pt, secs in anchors:
        db, ib = tree.query(pb[:2])
        dt, it = tree.query(pt[:2])
        if db < 0.5 and dt < 0.5 and ib != it:
            links.append((int(ib), int(it), secs))
            print("lift %s: linked, %.1f s" % (name, secs), flush=True)
        else:
            print("lift %s: a boarding place lost (%.1f, %.1f yd off)" % (name, db, dt), flush=True)
    path = os.path.join(build_out(), "navgraph_%d.npz" % map_id)
    np.savez_compressed(path, nodes=N, links=np.array(links, np.float64))
    print("wrote %s in %.0f s" % (path, time.perf_counter() - t0))


def bridges(map_id, N, links):
    """the graph's pieces joined where the ground joins them: a piece cut off from the rest (its corners thinned out
    of a winding pass, so no two nodes either side see each other) asks the navmesh for its way from each of its nodes
    to the nearest nodes of other pieces (BRIDGE_TRIES within BRIDGE_REACH yards, on its floor); the first way found is
    laid in, its corners new nodes (or the node of their layer already within CELL_SAFE), joined along it at its own
    yards. A real island finds no way. -> (N, links)"""
    from scipy.sparse import csr_matrix
    from scipy.sparse.csgraph import connected_components
    from scipy.spatial import cKDTree
    from navmesh import Nav
    from nav_zones import UNDER_Z, under_city
    t0 = time.perf_counter()
    nav = Nav(map_id)
    low = min(lo for lo, _ in UNDER_Z.values())
    high = max(hi for _, hi in UNDER_Z.values())
    N = [list(r) for r in N]
    links = list(links)
    parent = list(range(len(N)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    n0 = len(N)
    A = csr_matrix((np.ones(len(links)), ([int(i) for i, _, _ in links], [int(j) for _, j, _ in links])),
                   shape=(n0, n0))
    _, lab = connected_components(A, directed=False)
    first = {}
    for i in range(n0):
        parent[i] = first.setdefault(int(lab[i]), i)   # (each piece's first node its root)
    sizes = np.bincount(lab)
    order = np.argsort(sizes)   # (the smallest pieces first)
    tree = cKDTree(np.array([(r[0], r[1]) for r in N]))
    added_nodes, added_links, joined, tried = 0, 0, 0, 0
    main = int(np.argmax(sizes))
    def bridge_piece(members):
        """one piece's bridge to another (the nearest pairs of its nodes and the others', the navmesh's way laid in):
        1 when it was joined, else 0"""
        nonlocal tried, added_nodes, added_links
        # (its nodes nearest another piece first: every node within reach asked -- the nearest few of a node in a
        # dense piece are its own, 2026-10-21: Rut'theran Village's portal and the ground outside Ironforge's gate
        # were left cut off)
        cands = []
        root = find(int(members[0]))
        for i in members:
            for j in tree.query_ball_point((N[i][0], N[i][1]), BRIDGE_REACH):
                if find(int(j)) != root and N[j][4] == N[i][4]:
                    cands.append((math.hypot(N[j][0] - N[i][0], N[j][1] - N[i][1]), int(i), int(j)))
        cands.sort()
        # (one try a node pair's other piece: the nearest pairs into each piece, not one piece's every pair)
        seen, picked = set(), []
        for c in cands:
            key = (find(c[2]),)
            if key not in seen or len(picked) < BRIDGE_TRIES // 2:
                picked.append(c)
                seen.add(key)
            if len(picked) >= BRIDGE_TRIES:
                break
        cands = picked
        for dd, i, j in cands:
            tried += 1
            a, b = tuple(N[i][:3]), tuple(N[j][:3])
            w = nav.path(a, b)
            # (a long way is still the way: its corners are laid in and it is priced at its own yards -- Rut'theran
            # Village's portal to the village is 781 yd round the tree's roots for two nodes 158 yd apart)
            if not (w["ok"] and abs(w["to"][2] - b[2]) <= nav.ZTOL and w["yards"] <= 6 * dd + 600):
                continue
            pts = w["points"]
            # its corners, each the node of its layer and floor within CELL_SAFE (a corner whose cell another floor's
            # node holds left out: Route keeps one node a cell), else a new one -- pending until every link along it
            # walks both ways, arriving on the next one's floor (2026-10-21, the route bench: Stormwind's Cathedral
            # Square, a corner snapped to the crypt's node 25 yd below -- a link no one walks)
            seq, pending = [i], []
            for q in pts[1:-1]:
                layer = 1.0 if low <= q[2] <= high and under_city(map_id, nav, q[0], q[1], q[2]) else 0.0
                near = [k for k in tree.query_ball_point((q[0], q[1]), CELL_SAFE) if N[k][4] == layer]
                near += [k for k in range(n0, len(N)) if N[k][4] == layer
                         and (N[k][0] - q[0]) ** 2 + (N[k][1] - q[1]) ** 2 < CELL_SAFE * CELL_SAFE]
                near_new = [m for m, pq in enumerate(pending) if pq[4] == layer
                            and (pq[0] - q[0]) ** 2 + (pq[1] - q[1]) ** 2 < CELL_SAFE * CELL_SAFE]
                same = [k for k in near if abs(N[k][2] - q[2]) <= BRIDGE_FLOOR]
                if same:
                    k = min(same, key=lambda k_: (N[k_][0] - q[0]) ** 2 + (N[k_][1] - q[1]) ** 2)
                elif near or near_new:
                    continue
                else:
                    pending.append([q[0], q[1], q[2], 0.0, layer])
                    k = -len(pending)   # (a pending node: its index once laid in)
                if k != seq[-1]:
                    seq.append(k)
            if seq[-1] != j:
                seq.append(j)

            def at(k):
                return N[k] if k >= 0 else pending[-k - 1]
            segs = [(tuple(at(u)[:3]), tuple(at(v)[:3])) for u, v in zip(seq, seq[1:])]
            # (each leg as any link: the straight walk both ways, else a near-straight way round arriving on its
            # floor -- check_links' rule)
            prices = [link_price(nav, a_, b_, BRIDGE_OVER, BRIDGE_PLUS) for a_, b_ in segs]
            if any(pr is None for pr in prices):
                continue
            fw = [(True, pr, 0, 0) for pr in prices]
            bw = fw
            base = len(N)
            for pq in pending:
                N.append(pq)
                parent.append(len(N) - 1)
                added_nodes += 1

            def real(k):
                return k if k >= 0 else base + (-k - 1)
            for (u, v), f, g in zip(zip(seq, seq[1:]), fw, bw):
                ru, rv = real(u), real(v)
                links.append((ru, rv, max(f[1], g[1])))
                added_links += 1
                ra, rb = find(ru), find(rv)
                if ra != rb:
                    parent[ra] = rb
            return 1
        return 0

    # (passes until none joins: small pieces joined to one another first may reach the rest on the next)
    groups = [np.nonzero(lab == int(comp))[0] for comp in order if int(comp) != main and sizes[int(comp)]]
    for _pass in range(3):
        before = joined
        by_root = {}
        for members in groups:
            for i in members:
                by_root.setdefault(find(int(i)), []).append(int(i))
        groups = sorted((np.array(v) for r, v in by_root.items() if r != find(first[main])), key=len)
        for members in groups:
            if find(int(members[0])) == find(first[main]):
                continue
            joined += bridge_piece(members)
        if joined == before:
            break
    nav.close()
    roots = set(find(i) for i in range(len(N)))
    print("bridges: %d pieces joined (%d ways asked), %d nodes and %d links laid in; %d pieces left (%.0f s)" % (
        joined, tried, added_nodes, added_links, len(roots), time.perf_counter() - t0), flush=True)
    return np.array(N), links


def spanner(n, links, stretch):
    """the fewest links that keep every pair's way within `stretch` of the full graph's (a greedy spanner): the links
    taken cheapest first, one kept only where the links kept so far have no way within `stretch` times it"""
    import heapq
    adj = [[] for _ in range(n)]
    out = []
    for i, j, s in sorted(links, key=lambda t: t[2]):
        bound = s * stretch
        # Dijkstra from i, no farther than bound: is j reached?
        dist = {i: 0.0}
        heap = [(0.0, i)]
        found = False
        while heap:
            d, u = heapq.heappop(heap)
            if u == j:
                found = True
                break
            if d > dist.get(u, 1e18):
                continue
            for v, w in adj[u]:
                nd = d + w
                if nd <= bound and nd < dist.get(v, 1e18):
                    dist[v] = nd
                    heapq.heappush(heap, (nd, v))
        if not found:
            adj[i].append((j, s))
            adj[j].append((i, s))
            out.append((i, j, s))
    return out


def prune(n, links, span=None):
    """drop a link two others cover: a -> b -> c no dearer than `span` (SPAN) times a -> c (the longest dropped first)"""
    span = span or SPAN
    adj = [dict() for _ in range(n)]
    for i, j, s in links:
        adj[i][j] = s
        adj[j][i] = s
    out = []
    for i, j, s in sorted(links, key=lambda t: -t[2]):
        covered = False
        a, b = (i, j) if len(adj[i]) <= len(adj[j]) else (j, i)
        for m, s1 in adj[a].items():
            if m == b:
                continue
            s2 = adj[b].get(m)
            if s2 is not None and s1 + s2 <= s * span:
                covered = True
                break
        if covered:
            del adj[i][j]
            del adj[j][i]
        else:
            out.append((i, j, s))
    return out


if __name__ == "__main__":
    main()
