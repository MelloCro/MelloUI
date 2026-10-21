#!/usr/bin/env python3
"""
MelloUI_Companion/RoadData.lua from the real ground (docs/plans/route-ground.md): Route's walk grid and graph made from
wowsim's navmesh (Tools/nav_grid.py, Tools/nav_graph.py) in place of the roads traced from the map art and the
terrain's height grid (Tools/trace_roads.py's bake, which this replaces).

  walk      per continent, the ground as 4.17 yd cells, one run-length string per row; a cell's letter is its kind
            and which of its sides the character walks across: "A".."P" walkable ground, "Q".."f" water (swum),
            each + the open sides (1 east, 2 south, 4 south-east, 8 south-west), "z" no floor. A speck of no floor
            in open ground (a tree's trunk, a post: under OPEN_SPECK cells, open ground all round) is walked round by
            the player and counted walkable. edges = 1 marks the format (Route.lua's M.Ground reads either)
  graphs    the navmesh graph's nodes and links (real seconds; Route scales them to its map yards) outside the
            capitals, and the capitals' walked streets (Tools/roads/recorded.json) as before; each street's end at
            its city's gate joined to the graph outside over links the navmesh walks. navmesh = 1: the companion's
            links are the ground's own (no node is joined to its neighbours by distance alone)
  sizes     the continents' sizes in the companion's yards, as before

    python Tools/nav_bake.py [--maps 0,1] [--check]

Continent yards are Route's: east = (the continent's world y1) - world y, south = (its world x1) - world x.
"""
import argparse
import io
import math
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from nav_grid import UNIT, ORIGIN, E, S, SE, SW, build_out  # noqa: E402

MAPS = {0: 1415, 1: 1414}
SPAN_BAKE = 1.08      # the graph's links thinned for the game's memory: every way kept within 8 % (Route smooths it)
OUT = os.path.join(ROOT, "MelloUI_Companion", "RoadData.lua")
OPEN_SPECK = 5        # cells: a no-floor speck smaller, in open ground, is walked round (a tree's trunk)
SPECK_ACROSS = 3      # cells either side of a speck its way across is asked of the navmesh between ...
SPECK_ROUND = 8.0     # ... and the way round it no longer than the straight line by this many yards (the route
                      # bench, Feralas: a thin ridge taken for a trunk drew a leg through it, 36 s round)


GATE_LINKS = 3
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
NONE = "z"
FULL = E | S | SE | SW


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, flush=True)


# ------------------------------------------------------------------------------------------------- the walk grid
def opened(kind, edges, across=None):
    """specks of no floor in open ground (a trunk, a post, a small rock) made walkable, the sides round them open;
    across(r1, c1, r2, c2) -> False where the navmesh's way between two cells either side of one is no short way round
    (a thin wall, a ridge): that speck stays shut"""
    from scipy import ndimage
    none = kind == 0
    lab, n = ndimage.label(none, structure=np.ones((3, 3)))
    if n == 0:
        return kind, edges
    sizes = np.bincount(lab.ravel())
    small = (sizes < OPEN_SPECK)
    small[0] = False
    speck = small[lab]
    st = np.ones((3, 3))
    H, W = kind.shape
    # a shut side the specks do not explain: between two floors, neither of them beside any no-floor cell -- a fence's
    # rail, a cliff's lip between two floors; and the big no-floor pieces (a cliff, a wall, a house)
    near_none = ndimage.binary_dilation(none, structure=st)
    unexplained = np.zeros_like(none)
    for bit, dr, dc in ((E, 0, 1), (S, 1, 0), (SE, 1, 1), (SW, 1, -1)):
        a = np.zeros_like(none)
        b = np.zeros_like(none)
        r1, r2 = slice(0, H - dr), slice(dr, H)
        if dc >= 0:
            c1, c2 = slice(0, W - dc), slice(dc, W)
        else:
            c1, c2 = slice(-dc, W), slice(0, W + dc)
        shut = (kind[r1, c1] > 0) & (kind[r2, c2] > 0) & ((edges[r1, c1] & bit) == 0)
        lone = shut & ~near_none[r1, c1] & ~near_none[r2, c2]
        a[r1, c1] |= lone
        b[r2, c2] |= lone
        unexplained |= a | b
    big = none & ~speck
    # a speck opened where nothing near it is a fence or a cliff: no unexplained shut side within 2 cells, no big
    # no-floor piece beside it
    bad = ndimage.binary_dilation(unexplained, structure=st, iterations=2) | ndimage.binary_dilation(big, structure=st,
                                                                                                    iterations=2)
    bad_lab = np.unique(lab[bad & speck])
    keep = speck.copy()
    keep[np.isin(lab, bad_lab)] = False
    if across is not None:
        # (each speck kept asked across it, north to south and west to east, where both sides have floor)
        walled = []
        H_, W_ = kind.shape
        objs = ndimage.find_objects(lab)
        for lb in np.unique(lab[keep]):
            sl = objs[lb - 1]
            r = (sl[0].start + sl[0].stop - 1) // 2
            c = (sl[1].start + sl[1].stop - 1) // 2
            k = SPECK_ACROSS
            for r1, c1, r2, c2 in ((sl[0].start - k, c, sl[0].stop - 1 + k, c), (r, sl[1].start - k, r, sl[1].stop - 1 + k)):
                if (0 <= r1 < H_ and 0 <= r2 < H_ and 0 <= c1 < W_ and 0 <= c2 < W_
                        and kind[r1, c1] > 0 and kind[r2, c2] > 0 and not across(r1, c1, r2, c2)):
                    walled.append(lb)
                    break
        keep[np.isin(lab, walled)] = False
        log("  specks a wall on the navmesh (kept shut): %d" % len(walled))
    k2 = kind.copy()
    k2[keep] = 1
    e2 = edges.copy()
    zone = ndimage.binary_dilation(keep, structure=np.ones((3, 3)), iterations=1)
    H, W = kind.shape
    rr, cc = np.nonzero(zone)
    for bit, dr, dc in ((E, 0, 1), (S, 1, 0), (SE, 1, 1), (SW, 1, -1)):
        nr, nc = rr + dr, cc + dc
        ok = (nr < H) & (nc >= 0) & (nc < W)
        r1, c1, r2, c2 = rr[ok], cc[ok], nr[ok], nc[ok]
        both = (k2[r1, c1] > 0) & (k2[r2, c2] > 0) & zone[r2, c2]
        e2[r1[both], c1[both]] |= bit
    log("  specks walked round: %d of %d no-floor pieces (%d cells)" % (len(np.unique(lab[keep])), n, int(keep.sum())))
    return k2, e2


def rows_of(kind, edges):
    code = np.where(kind == 0, -1, (kind.astype(np.int32) - 1) * 16 + (edges & 15).astype(np.int32))
    out = []
    for r in range(code.shape[0]):
        row = code[r]
        cut = np.flatnonzero(np.diff(row)) + 1
        starts = np.concatenate(([0], cut))
        ends = np.concatenate((cut, [len(row)]))
        parts = []
        for s, e in zip(starts, ends):
            v = int(row[s])
            ch = NONE if v < 0 else LETTERS[v]
            n = e - s
            parts.append(ch if n == 1 else "%s%d" % (ch, n))
        out.append("".join(parts))
    return out


BURN_Z = 6.0   # yards: a walk opens a side only between cells whose floor is this near its own height there (a steep
               # ramp's cell centre is a few yards off the walk's line; a walkway over a street 10 and more)


def burned(kind, edges, r0, c0, segs, z):
    """the grid opened along straight walks the navmesh allows (the graph's links, the best ways' legs: world (x, y, z)
    pairs): the cells they cross made floor, every side crossed open -- a ramp, a bridge or a gap narrower than the
    cells' centre-to-centre walks found is then on the grid as the graph has it; (2026-10-21) only where the cells'
    floor is the walk's own (BURN_Z): a link on a walkway opened the sides of the street 20 yd under it (the route
    bench's Orgrimmar: the grid's ways dropped off its terraces)"""
    H, W = kind.shape
    k2, e2 = kind.copy(), edges.copy()
    opened_sides = 0
    for k in range(0, len(segs), 200000):
        A = np.array([s[0] for s in segs[k:k + 200000]], np.float64)
        B = np.array([s[1] for s in segs[k:k + 200000]], np.float64)
        ar, ac = (ORIGIN - A[:, 0]) / UNIT - r0, (ORIGIN - A[:, 1]) / UNIT - c0
        br, bc = (ORIGIN - B[:, 0]) / UNIT - r0, (ORIGIN - B[:, 1]) / UNIT - c0
        n = np.maximum(1, np.ceil(np.maximum(np.abs(br - ar), np.abs(bc - ac)) / 0.4)).astype(np.int64)
        seg = np.repeat(np.arange(len(n)), n + 1)
        start = np.repeat(np.cumsum(n + 1) - (n + 1), n + 1)
        t = (np.arange(len(seg)) - start) / np.repeat(n, n + 1)
        rr = np.floor(ar[seg] + (br - ar)[seg] * t).astype(np.int64)
        cc = np.floor(ac[seg] + (bc - ac)[seg] * t).astype(np.int64)
        zs = A[:, 2][seg] + (B[:, 2] - A[:, 2])[seg] * t
        inside = (rr >= 0) & (rr < H) & (cc >= 0) & (cc < W)
        # (a cell on the walk's own floor, or one with none: the cell's grid floor this near the walk's height)
        own = np.zeros(len(rr), bool)
        zc = np.full(len(rr), np.nan)
        zc[inside] = z[rr[inside], cc[inside]]
        own[inside] = ~np.isfinite(zc[inside]) | (np.abs(zc[inside] - zs[inside]) <= BURN_Z)
        k2[rr[inside & own], cc[inside & own]] = np.maximum(k2[rr[inside & own], cc[inside & own]], 1)
        same = (seg[1:] == seg[:-1]) & own[1:] & own[:-1]
        r1, c1, r2, c2 = rr[:-1][same], cc[:-1][same], rr[1:][same], cc[1:][same]
        ok = ((r1 != r2) | (c1 != c2)) & (np.minimum(r1, r2) >= 0) & (np.maximum(r1, r2) < H) & \
            (np.minimum(c1, c2) >= 1) & (np.maximum(c1, c2) < W - 1)
        r1, c1, r2, c2 = r1[ok], c1[ok], r2[ok], c2[ok]
        dr, dc = r2 - r1, c2 - c1
        # a side crossed east-west: the west cell's east side; north-south: the north cell's south side
        m = (dr == 0)
        np.bitwise_or.at(e2, (r1[m], np.minimum(c1, c2)[m]), E)
        m = (dc == 0)
        np.bitwise_or.at(e2, (np.minimum(r1, r2)[m], c1[m]), S)
        # a corner crossed: the diagonal and both ways round it
        m = (dr != 0) & (dc != 0)
        rn, cw = np.minimum(r1, r2)[m], np.minimum(c1, c2)[m]
        down_right = ((dr > 0) == (dc > 0))[m]
        np.bitwise_or.at(e2, (rn[down_right], cw[down_right]), SE)
        ce = np.maximum(c1, c2)[m]
        np.bitwise_or.at(e2, (rn[~down_right], ce[~down_right]), SW)
        for rows_, cols_ in ((rn, cw), (rn + 1, cw), (rn, ce), (rn + 1, ce)):
            k2[rows_, cols_] = np.maximum(k2[rows_, cols_], 1)
        np.bitwise_or.at(e2, (rn, cw), E | S)
        np.bitwise_or.at(e2, (rn + 1, cw), E)
        np.bitwise_or.at(e2, (rn, ce), S)
        opened_sides += int(len(r1))
    log("  sides crossed by the navmesh's own walks: %d; sides opened %d" % (
        opened_sides, int(((e2 ^ edges) != 0).sum())))
    return k2, e2


def pieces4(kind, edges):
    """the grid's pieces as a line check walks them (east and south sides): a label per cell, -1 no floor"""
    from scipy.sparse import csr_matrix
    from scipy.sparse.csgraph import connected_components
    H, W = kind.shape
    idx = np.full((H, W), -1, np.int64)
    on = kind > 0
    idx[on] = np.arange(int(on.sum()))
    rows, cols = [], []
    a = (edges[:, :-1] & E) > 0
    i, j = np.nonzero(a & on[:, :-1] & on[:, 1:])
    rows.append(idx[i, j])
    cols.append(idx[i, j + 1])
    a = (edges[:-1, :] & S) > 0
    i, j = np.nonzero(a & on[:-1, :] & on[1:, :])
    rows.append(idx[i, j])
    cols.append(idx[i + 1, j])
    n = int(on.sum())
    m = csr_matrix((np.ones(sum(len(r) for r in rows)), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n))
    _, lab = connected_components(m, directed=False)
    out = np.full((H, W), -1, np.int64)
    out[on] = lab
    return out


def joining(kind, edges, r0, c0, segs, z):
    """of the navmesh's walks, the fewest that join the grid's pieces as the navmesh joins them: the shortest first,
    one only where its two ends lie in pieces not joined yet (a spanning tree over the pieces), each end on its cell's
    own floor (BURN_Z)"""
    lab = pieces4(kind, edges)
    H, W = kind.shape
    parent = {}

    def find(a):
        while parent.get(a, a) != a:
            parent[a] = parent.get(parent[a], parent[a])
            a = parent[a]
        return a
    order = sorted(range(len(segs)), key=lambda k: (segs[k][0][0] - segs[k][1][0]) ** 2 + (segs[k][0][1] - segs[k][1][1]) ** 2)
    out = []
    for k in order:
        a, b = segs[k]
        ra, ca = int((ORIGIN - a[0]) / UNIT) - r0, int((ORIGIN - a[1]) / UNIT) - c0
        rb, cb = int((ORIGIN - b[0]) / UNIT) - r0, int((ORIGIN - b[1]) / UNIT) - c0
        if not (0 <= ra < H and 0 <= rb < H and 0 <= ca < W and 0 <= cb < W):
            continue
        pa, pb = int(lab[ra, ca]), int(lab[rb, cb])
        if pa < 0 or pb < 0:
            continue
        if not (abs(z[ra, ca] - a[2]) <= BURN_Z and abs(z[rb, cb] - b[2]) <= BURN_Z):
            continue   # (an end on another floor than its cell's)
        fa, fb = find(pa), find(pb)
        if fa != fb:
            parent[fa] = fb
            out.append(segs[k])
    log("  walks that join the grid's pieces: %d of %d" % (len(out), len(segs)))
    return out


def walk_grid(map_id, cont):
    d = np.load(os.path.join(build_out(), "navgrid_%d.npz" % map_id))
    kind, edges, z0 = d["kind"], d["edges"], d["z"]
    r0, c0 = int(d["r0"]), int(d["c0"])
    # the graph's links and the best ways' legs burned in (Tools/nav_graph.py)
    gpath = os.path.join(build_out(), "navgraph_%d.npz" % map_id)
    wpath = os.path.join(build_out(), "navways_%d.npy" % map_id)
    segs = []
    if os.path.exists(gpath):
        g = np.load(gpath)
        N, L = g["nodes"], g["links"]
        for i, j, _ in L:
            segs.append((N[int(i), :3], N[int(j), :3]))
    if os.path.exists(wpath):
        for w in np.load(wpath, allow_pickle=True):
            for a, b in zip(w[:-1], w[1:]):
                segs.append((a[:3], b[:3]))
    if segs:
        kind, edges = burned(kind, edges, r0, c0, joining(kind, edges, r0, c0, segs, z0), z0)
    # (the cells with any floor, and a cell round them: the rest is the sea's no floor)
    on = np.argwhere(kind > 0)
    ra, ca = on.min(axis=0)
    rb, cb = on.max(axis=0) + 1
    ra, ca = max(0, ra - 1), max(0, ca - 1)
    kind, edges = kind[ra:rb + 1, ca:cb + 1], edges[ra:rb + 1, ca:cb + 1]
    zz = d["z"][ra:rb + 1, ca:cb + 1]
    from navmesh import Nav
    nav = Nav(map_id)

    def across(r1, c1, r2, c2):
        a = (ORIGIN - (r0 + ra + r1 + 0.5) * UNIT, ORIGIN - (c0 + ca + c1 + 0.5) * UNIT, float(zz[r1, c1]))
        b = (ORIGIN - (r0 + ra + r2 + 0.5) * UNIT, ORIGIN - (c0 + ca + c2 + 0.5) * UNIT, float(zz[r2, c2]))
        w = nav.path(a, b, points=False)
        return bool(w["ok"]) and w["yards"] <= math.dist(a[:2], b[:2]) + SPECK_ROUND
    kind, edges = opened(kind, edges, across)
    nav.close()
    x1, y1 = cont["x1"], cont["y1"]
    e0 = (c0 + ca) * UNIT - (ORIGIN - y1)
    s0 = (r0 + ra) * UNIT - (ORIGIN - x1)
    rows = rows_of(kind, edges)
    return {"cell": UNIT, "e0": e0, "s0": s0, "w": kind.shape[1], "h": kind.shape[0], "rows": rows}


def under_walk(map_id, cont):
    """the underground capitals' own walk grids (Tools/nav_grid.py --under): [walk_grid's dict], none without them"""
    path = os.path.join(build_out(), "navunder_%d.npz" % map_id)
    if not os.path.exists(path):
        return []
    d = np.load(path)
    out = []
    x1, y1 = cont["x1"], cont["y1"]
    for zone in d["zones"]:
        r0, c0 = int(d["%d_r0" % zone]), int(d["%d_c0" % zone])
        kind, edges = d["%d_kind" % zone], d["%d_edges" % zone]
        out.append({"zone": int(zone), "cell": UNIT, "e0": c0 * UNIT - (ORIGIN - y1), "s0": r0 * UNIT - (ORIGIN - x1),
                    "w": kind.shape[1], "h": kind.shape[0], "rows": rows_of(kind, edges)})
    return out


# ------------------------------------------------------------------------------------------------- the graph
OPEN_CITIES = {1453, 1454, 1456, 1457}   # Stormwind, Orgrimmar, Thunder Bluff, Darnassus: open air, the navmesh's own
UNDER_CITIES = {1455, 1458}              # Ironforge, the Undercity: under the ground (the grid's highest floor is not
                                         # theirs): their walked streets, joined at their gates
KEEP_OPEN_STREETS = False   # the open cities' walked streets laid too (they cut corners: the navmesh's graph has them)
KEEP_UNDER_STREETS = False  # the underground ones' too (2D lines through their lifts and floors: the navmesh's graph has
                            # their floors, as a layer of their own -- Tools/nav_graph.py's city pass)
CITY_CLEAR = 40.0     # yards: no navmesh node this near an underground city's walked street
STREET_JOIN = 25.0    # yards: a walked street's node of an open city joins graph nodes this near the navmesh walks to
STREET_LINKS = 2


def key_of(e, s):
    return (math.floor(e / 10), math.floor(s / 10))


def city_rects(zones, cont_id, conts):
    out = {}
    cont = conts[cont_id]
    for z in zones:
        if z["cont"] == cont_id and z["id"] in OPEN_CITIES | UNDER_CITIES:
            out[z["id"]] = (cont["y1"] - z["y1"], cont["y1"] - z["y0"], cont["x1"] - z["x1"], cont["x1"] - z["x0"])
    return out


class Graph:
    """nodes (east, south) in the companion's yards, one per 10-yard cell of a layer (an underground capital's streets
    one, the rest the other: Route keys them apart); links (i, j) -> seconds"""

    def __init__(self):
        self.pos, self.at, self.links, self.under = [], {}, {}, []

    def node(self, e, s, under=False):
        k = (bool(under),) + key_of(e, s)
        i = self.at.get(k)
        if i is None:
            i = len(self.pos)
            self.pos.append((round(e, 1), round(s, 1)))
            self.under.append(bool(under))
            self.at[k] = i
        return i

    def has(self, e, s, under=False):
        return (bool(under),) + key_of(e, s) in self.at

    def link(self, i, j, secs):
        if i == j:
            return
        k = (min(i, j), max(i, j))
        secs = round(secs, 1)
        if k not in self.links or self.links[k] > secs:
            self.links[k] = secs


def bake_graph(map_id, cont_id, conts, zones, recorded, nav, notes):
    import trace_roads as tr
    from scipy.spatial import cKDTree
    cont = conts[cont_id]
    x1, y1 = cont["x1"], cont["y1"]
    G = Graph()
    rects = city_rects(zones, cont_id, conts)
    # the walked streets (as Tools/trace_roads.py laid them): a node every WALKED_STEP yards, priced between the nodes
    streets = []   # (city, [node], first?)
    for cid, lines in recorded.items():
        if not (KEEP_UNDER_STREETS if cid in UNDER_CITIES else KEEP_OPEN_STREETS):
            continue   # (a city's streets are the navmesh graph's: exact, where the walked ones cut corners)
        for n_line, (c, line) in enumerate(lines):
            if c != cont_id:
                continue
            run = [line[0]]
            for (ax, ay), (bx, by) in zip(line, line[1:]):
                d = math.hypot(bx - ax, by - ay)
                k = max(1, int(d / tr.WALKED_STEP))
                for t in range(1, k + 1):
                    run.append((ax + (bx - ax) * t / k, ay + (by - ay) * t / k))
            ids = []
            for e, s in run:
                i = G.node(e, s)
                if ids and ids[-1] != i:
                    a, b = G.pos[ids[-1]], G.pos[i]
                    G.link(ids[-1], i, math.hypot(a[0] - b[0], a[1] - b[1]) / tr.WALK)
                if not ids or ids[-1] != i:
                    ids.append(i)
            streets.append((cid, ids, n_line == 0))
    walked = set(i for _, ids, _ in streets for i in ids)
    if walked:
        wk = sorted(walked)
        wp = [G.pos[i] for i in wk]
        for a, b in cKDTree(wp).query_pairs(tr.WALKED_JOIN):
            G.link(wk[a], wk[b], math.hypot(wp[a][0] - wp[b][0], wp[a][1] - wp[b][1]) / tr.WALK)
    # the navmesh graph everywhere (its nodes are joined only by their own links, never by distance: the ground over
    # an underground city's streets lies beside them unjoined); a node on a cell a street holds left out
    d = np.load(os.path.join(build_out(), "navgraph_%d.npz" % map_id))
    N, L = d["nodes"], d["links"]
    if SPAN_BAKE:
        # (pruned again for the game's memory: a link two others cover within SPAN_BAKE, the longest first)
        from nav_graph import spanner
        before = len(L)
        t_ = time.perf_counter()
        L = spanner(len(N), [(int(i), int(j), float(s_)) for i, j, s_ in L], SPAN_BAKE)
        notes.append("  %d: links kept within %.0f %% of the full graph's ways: %d -> %d (%.0f s)" % (
            cont_id, (SPAN_BAKE - 1) * 100, before, len(L), time.perf_counter() - t_))
    ids = [None] * len(N)
    clash = 0
    # (an underground city's streets lie under other ground -- Ironforge's mountain, the Undercity's ruins: no
    # navmesh node within CITY_CLEAR of one of them, so a station's or an end's nearest nodes there are its streets)
    under = [G.pos[i] for cid, ids_, _ in streets if cid in UNDER_CITIES for i in ids_]
    ut = cKDTree(under) if under else None
    for i, row in enumerate(N):
        x, y = row[0], row[1]
        e, s = y1 - y, x1 - x
        under = len(row) > 4 and row[4] == 1   # (Tools/nav_graph.py's layer: an underground capital's streets)
        if G.has(e, s, under) or (not under and ut is not None and ut.query_ball_point((e, s), CITY_CLEAR)):
            clash += 1
            continue
        ids[i] = G.node(e, s, under)
    nav_links = 0
    for i, j, secs in L:
        a, b = ids[int(i)], ids[int(j)]
        if a is not None and b is not None:
            G.link(a, b, float(secs))
            nav_links += 1
    navnodes = [i for i in ids if i is not None]
    nt = cKDTree([G.pos[i] for i in navnodes]) if navnodes else None

    def world(i):
        e, s = G.pos[i]
        return (x1 - s, y1 - e, None)

    def join(i, reach, most, rect=None, outside=False):
        """street node i to the graph nodes within reach the navmesh walks to: how many"""
        e, s = G.pos[i]
        near = sorted(nt.query_ball_point((e, s), reach),
                      key=lambda k: (G.pos[navnodes[k]][0] - e) ** 2 + (G.pos[navnodes[k]][1] - s) ** 2)
        made = 0
        for k in near[:16]:
            o = navnodes[k]
            if outside and rect:
                oe, os_ = G.pos[o]
                if rect[0] <= oe <= rect[1] and rect[2] <= os_ <= rect[3]:
                    continue
            w = nav.walk([world(i), world(o)])
            if w["ok"]:
                G.link(i, o, w["seconds"])
                made += 1
                if made >= most:
                    break
        return made
    joined_open = joined_gate = 0
    marks = tr.recorded_gates(conts).get(cont_id, [])
    if nt is not None:
        for cid, sids, first in streets:
            rect = rects.get(cid)
            if cid in OPEN_CITIES:
                # an open city: its streets and the navmesh's ways through it, joined wherever the navmesh walks
                for i in sids[::2]:
                    joined_open += join(i, STREET_JOIN, STREET_LINKS) > 0
            elif rect:
                # under the ground: only the street's ends at the gate, to the graph outside the city's map
                for i, is_first in ((sids[0], first), (sids[-1], False)):
                    e, s = G.pos[i]
                    edge = min(e - rect[0], rect[1] - e, s - rect[2], rect[3] - s)
                    if (edge <= tr.GATE_EDGE or (is_first and edge <= tr.GATE_FIRST)
                            or any(math.hypot(e - mx, s - my) <= tr.GATE_MARK for mx, my in marks)):
                        joined_gate += join(i, tr.GATE_REACH, GATE_LINKS, rect, outside=True) > 0
    notes.append("  %d: %d nodes (%d walked), %d links (%d the navmesh's), %d navmesh nodes on a street's cell left "
                 "out; street nodes joined in open cities %d, at gates %d" % (
                     cont_id, len(G.pos), len(walked), len(G.links), nav_links, clash, joined_open, joined_gate))
    return G


ALPHABET = "".join(chr(c) for c in range(33, 127) if c not in (34, 92))   # base 92: "!" to "~" without '"' and '\'


OFFSET = 20000   # yards added to a node's east and south (some lie past the continent map's edge): 0 to 57,868 packed


def packed(v, width):
    v = int(v)
    assert 0 <= v < 92 ** width, (v, width)
    out = []
    for _ in range(width):
        v, d = divmod(v, 92)
        out.append(ALPHABET[d])
    return "".join(reversed(out))


def write_packed(fh, cont_id, G):
    """graphs[cont] = { packed = 1, under = n, nodes = { "...", ... }, links = { "...", ... } }: fixed-width numbers
    in base 92, a node's east and south in tenths of a yard (3 + 3 characters), a link's two nodes, 1-based (3 + 3),
    and its tenths of a second (2), 512 entries a string -- strings the client reads at once (a 13 MB file of numbers
    took a third of a second); Route.lua unpacks them in its build's slices. The nodes from the under-th on are an
    underground capital's streets (G.under), written after the rest"""
    order = sorted(range(len(G.pos)), key=lambda i: G.under[i])
    new = {old: n for n, old in enumerate(order)}
    first = next((n for n, old in enumerate(order) if G.under[old]), None)
    fh.write("\t\t[%d] = { packed = 1, offset = %d,%s\n\t\t\tnodes = {\n" % (
        cont_id, OFFSET, " under = %d," % (first + 1) if first is not None else ""))
    ent = ["%s%s" % (packed(round((e + OFFSET) * 10), 3), packed(round((s + OFFSET) * 10), 3))
           for e, s in (G.pos[old] for old in order)]
    for k in range(0, len(ent), 512):
        fh.write('\t\t\t\t"%s",\n' % "".join(ent[k:k + 512]))
    fh.write("\t\t\t},\n\t\t\tlinks = {\n")
    ent = ["%s%s%s" % (packed(i + 1, 3), packed(j + 1, 3), packed(min(92 * 92 - 1, round(secs * 10)), 2))
           for (i, j), secs in sorted(((min(new[a], new[b]), max(new[a], new[b])), v) for (a, b), v in G.links.items())]
    for k in range(0, len(ent), 512):
        fh.write('\t\t\t\t"%s",\n' % "".join(ent[k:k + 512]))
    fh.write("\t\t\t},\n\t\t},\n")


def write_graph(fh, cont_id, G):
    """graphs[cont] = { nodes = { east, south, ... }, links = { i, j, seconds, ... } } (1-based): arrays of numbers,
    which the client reads far quicker than a table per node; Route builds its own in slices"""
    fh.write("\t\t[%d] = {\n\t\t\tnodes = {\n" % cont_id)
    row = []
    for e, s in G.pos:
        row.append("%s,%s" % (fmt(e), fmt(s)))
        if len(row) == 16:
            fh.write("\t\t\t\t" + ",".join(row) + ",\n")
            row = []
    if row:
        fh.write("\t\t\t\t" + ",".join(row) + ",\n")
    fh.write("\t\t\t},\n\t\t\tlinks = {\n")
    row = []
    for (i, j), secs in sorted(G.links.items()):
        row.append("%d,%d,%s" % (i + 1, j + 1, fmt(secs)))
        if len(row) == 16:
            fh.write("\t\t\t\t" + ",".join(row) + ",\n")
            row = []
    if row:
        fh.write("\t\t\t\t" + ",".join(row) + ",\n")
    fh.write("\t\t\t},\n\t\t},\n")


def fmt(v):
    s = "%.1f" % v
    return s[:-2] if s.endswith(".0") else s


def kept_blocks(path, baked):
    """the continents this bake makes no navmesh for (Zephras Isle, 2521: wowsim builds Eastern Kingdoms and Kalimdor),
    kept as the companion has them: {"sizes": [lines], "walk": [lines], "graphs": [lines]} of each such continent"""
    import re
    lines = open(path, encoding="utf-8").read().split("\n")
    out = {"sizes": [], "walk": [], "graphs": []}
    section = None
    i = 0
    while i < len(lines):
        ln = lines[i]
        m = re.match(r"^\t(sizes|walk|graphs) = \{", ln)
        if m:
            section = m.group(1)
            i += 1
            continue
        m = re.match(r"^\t\t\[(\d+)\] = ", ln)
        if m and section and int(m.group(1)) not in baked:
            if section == "sizes":
                if int(m.group(1)) not in MAPS.values():   # (the two continents' sizes are written anew)
                    out["sizes"].append(ln)
            else:
                # the block to its closing line at the same depth
                block = [ln]
                close = "\t\t} }," if section == "walk" else "\t\t},"
                i += 1
                while i < len(lines) and lines[i] != close:
                    block.append(lines[i])
                    i += 1
                block.append(lines[i])
                out[section] += block
        i += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--maps", default="0,1")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--span", type=float, default=None, help="prune within this (1.06 = 6 %%; 0 = as built)")
    a = ap.parse_args()
    global SPAN_BAKE
    if a.span is not None:
        SPAN_BAKE = a.span
    import trace_roads as tr
    from navmesh import Nav
    baked = set(MAPS[int(v)] for v in a.maps.split(","))
    kept = kept_blocks(a.out, baked) if os.path.exists(a.out) else {}
    zones, conts = tr.load_zones()
    recorded = tr.load_recorded(conts)
    walk, graphs, notes, unders = {}, {}, [], {}
    for m in (int(v) for v in a.maps.split(",")):
        cid = MAPS[m]
        t0 = time.perf_counter()
        walk[cid] = walk_grid(m, conts[cid])
        log("walk grid %d: %d x %d, %d KB" % (cid, walk[cid]["w"], walk[cid]["h"],
                                            sum(len(r) for r in walk[cid]["rows"]) // 1024))
        unders[cid] = under_walk(m, conts[cid])
        for u in unders[cid]:
            log("  under grid %d (%d): %d x %d, %d KB" % (cid, u["zone"], u["w"], u["h"],
                                                      sum(len(r) for r in u["rows"]) // 1024))
        nav = Nav(m)
        before = len(notes)
        graphs[cid] = bake_graph(m, cid, conts, zones, recorded, nav, notes)
        nav.close()
        for line in notes[before:]:
            log(line)
        log("  (%.0f s)" % (time.perf_counter() - t0))
    with io.open(a.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by Tools/nav_bake.py from wowsim's navmesh of the client's ground (build 1.60.1.70425) and\n")
        fh.write("-- the capitals' walked streets. Do not edit by hand. Route's walk grid and graph in continent yards of the\n")
        fh.write("-- sizes below: graphs[continent uiMapID] = { nodes = { east, south, ... }, links = { i, j, seconds, ... } }\n")
        fh.write("-- where the navmesh made it (navmesh[continent]), else [cell] = { east, south, { [cell] = seconds } }.\n\n")
        fh.write("MelloUI_RoadData = {\n")
        fh.write('\tbuild = "%s",\n' % tr.BUILD)
        # (the continents whose graph is the navmesh's: their links are the ground's own, in real seconds)
        fh.write("\tnavmesh = { %s },\n" % ", ".join("[%d] = 1" % c for c in sorted(graphs)))
        fh.write("\tsizes = {\n")
        for c, b in conts.items():
            fh.write("\t\t[%d] = { %.1f, %.1f },\n" % (c, b["width"], b["height"]))
        for ln in kept.get("sizes", []):
            fh.write(ln + "\n")
        fh.write("\t},\n")
        fh.write("\twalk = {\n")
        for c, wg in walk.items():
            fh.write("\t\t[%d] = { cell = %.4f, e0 = %.2f, s0 = %.2f, w = %d, h = %d, edges = 1, rows = {\n" % (
                c, wg["cell"], wg["e0"], wg["s0"], wg["w"], wg["h"]))
            for row in wg["rows"]:
                fh.write('\t\t\t"%s",\n' % row)
            fh.write("\t\t} },\n")
        for ln in kept.get("walk", []):
            fh.write(ln + "\n")
        fh.write("\t},\n")
        # (the underground capitals' streets: grids of their own, as walk's -- Route asks them for a point on them)
        fh.write("\twalk_under = {\n")
        for c, lst in unders.items():
            if not lst:
                continue
            fh.write("\t\t[%d] = {\n" % c)
            for wg in lst:
                fh.write("\t\t\t{ cell = %.4f, e0 = %.2f, s0 = %.2f, w = %d, h = %d, edges = 1, rows = {\n" % (
                    wg["cell"], wg["e0"], wg["s0"], wg["w"], wg["h"]))
                for row in wg["rows"]:
                    fh.write('\t\t\t\t"%s",\n' % row)
                fh.write("\t\t\t} },\n")
            fh.write("\t\t},\n")
        fh.write("\t},\n\tgraphs = {\n")
        for c, G in graphs.items():
            write_packed(fh, c, G)
        for ln in kept.get("graphs", []):
            fh.write(ln + "\n")
        fh.write("\t},\n}\n")
    log("wrote %s (%d KB)" % (a.out, os.path.getsize(a.out) // 1024))


if __name__ == "__main__":
    main()
