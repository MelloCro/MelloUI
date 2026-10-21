#!/usr/bin/env python3
"""
How well a walk grid the game could carry answers "is this straight line walkable?", against the navmesh's own walks
(docs/plans/route-ground.md): for random lines on walkable ground, how many a grid calls clear that get stuck in the
game (false clear: a route through a wall) and how many it calls blocked that are walkable (false wall: a detour).

  cells    the line sampled once per cell (Route.lua's M.Ground.Walk): blocked on a wall or no-ground cell
  edges    the line followed cell to cell (a DDA): blocked where it crosses a side the grid marks shut

    python Tools/nav_gridcheck.py --map 0 [--n 20000]
"""
import argparse
import math
import os
import random
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from navmesh import Nav  # noqa: E402
from nav_grid import UNIT, ORIGIN, E, S, SE, SW, build_out  # noqa: E402

FULL = E | S | SE | SW


def load(map_id):
    d = np.load(os.path.join(build_out(), "navgrid_%d.npz" % map_id))
    return {k: d[k] for k in d.files}


def east_west_open(kind, edges):
    """per cell: whether its east side and its south side are open (both cells walkable and the edge walked)"""
    e_open = (edges & E) > 0
    s_open = (edges & S) > 0
    return e_open, s_open


def fold_cells(kind, edges, f, rule):
    """the grid at f x f cells: letter per cell -- 'w' walk, 's' swim, 'x' wall, 'n' none"""
    H, W = kind.shape
    h, w = H // f, W // f
    k = kind[:h * f, :w * f].reshape(h, f, w, f)
    e = edges[:h * f, :w * f].reshape(h, f, w, f)
    walk = (k == 1)
    swim = (k == 2)
    none = (k == 0)
    # a sub-cell is "shut" where it has walkable neighbours it cannot walk to (a cliff's edge, a fence, a wall)
    shut = (k > 0) & (e != FULL)
    n = f * f
    out = np.full((h, w), ord("w"), np.uint8)
    if rule == "half":
        bad = (none.sum(axis=(1, 3)) + shut.sum(axis=(1, 3)))
        out[swim.sum(axis=(1, 3)) * 2 >= n] = ord("s")
        out[bad * 2 >= n] = ord("x")
        out[none.sum(axis=(1, 3)) * 2 >= n] = ord("n")
    elif rule == "any":
        out[swim.sum(axis=(1, 3)) * 2 >= n] = ord("s")
        out[(none | shut).any(axis=(1, 3))] = ord("x")
        out[none.sum(axis=(1, 3)) * 2 >= n] = ord("n")
    return out


def clean(letters, min_cells):
    """walls in small specks (a tree, a post: walked round) let through"""
    from scipy import ndimage
    x = letters == ord("x")
    lab, n = ndimage.label(x, structure=np.ones((3, 3)))
    if n == 0:
        return letters
    sizes = np.bincount(lab.ravel())
    small = sizes < min_cells
    small[0] = False
    out = letters.copy()
    out[small[lab]] = ord("w")
    return out


def line_cells(letters, f, r0, c0, a, b):
    """Route's check: sampled once per cell (f x 4.17 yd), the end cells not asked: True clear, False blocked"""
    cell = UNIT * f
    ar, ac = (ORIGIN - a[0]) / cell - r0 / f, (ORIGIN - a[1]) / cell - c0 / f
    br, bc = (ORIGIN - b[0]) / cell - r0 / f, (ORIGIN - b[1]) / cell - c0 / f
    steps = max(1, int(math.ceil(math.hypot(br - ar, bc - ac))))
    qa, ra_ = int(math.floor(ac)), int(math.floor(ar))
    qb, rb_ = int(math.floor(bc)), int(math.floor(br))
    H, W = letters.shape
    for i in range(steps + 1):
        t = i / steps
        r = int(math.floor(ar + (br - ar) * t))
        q = int(math.floor(ac + (bc - ac) * t))
        if (q == qa and r == ra_) or (q == qb and r == rb_):
            continue
        if r < 0 or q < 0 or r >= H or q >= W:
            return False
        v = letters[r, q]
        if v == ord("x") or v == ord("n"):
            return False
    return True


def line_edges(kind, edges, r0, c0, a, b):
    """cell to cell along the line (4.17 yd), every side crossed open"""
    ar, ac = (ORIGIN - a[0]) / UNIT - r0, (ORIGIN - a[1]) / UNIT - c0
    br, bc = (ORIGIN - b[0]) / UNIT - r0, (ORIGIN - b[1]) / UNIT - c0
    r, c = int(math.floor(ar)), int(math.floor(ac))
    rt, ct = int(math.floor(br)), int(math.floor(bc))
    dr, dc = br - ar, bc - ac
    sr = 1 if dr > 0 else -1
    sc = 1 if dc > 0 else -1
    tdr = abs(1 / dr) if dr else math.inf
    tdc = abs(1 / dc) if dc else math.inf
    tmr = ((math.floor(ar) + 1 - ar) if dr > 0 else (ar - math.floor(ar))) * tdr if dr else math.inf
    tmc = ((math.floor(ac) + 1 - ac) if dc > 0 else (ac - math.floor(ac))) * tdc if dc else math.inf
    H, W = kind.shape
    for _ in range(100000):
        if r == rt and c == ct:
            return True
        if tmr < tmc:
            nr, nc = r + sr, c
            tmr += tdr
            if not (0 <= nr < H):
                return False
            ok = (edges[min(r, nr), c] & S) > 0
        else:
            nr, nc = r, c + sc
            tmc += tdc
            if not (0 <= nc < W):
                return False
            ok = (edges[r, min(c, nc)] & E) > 0
        if not ok:
            return False
        r, c = nr, nc
    return False


def fold_edges(kind, edges, f, rule):
    """the edge grid at f x f cells: kind by majority (walk over swim over none), a side open when `rule` of the f
    sub-sides along it are open ("all" / "any" / "half")"""
    H, W = kind.shape
    h, w = H // f, W // f
    k = kind[:h * f, :w * f].reshape(h, f, w, f)
    walk = (k == 1).sum(axis=(1, 3))
    swim = (k == 2).sum(axis=(1, 3))
    none = (k == 0).sum(axis=(1, 3))
    kk = np.where((walk >= swim) & (walk + swim > none), 1, np.where(swim + walk > none, 2, 0)).astype(np.uint8)
    e = edges[:h * f, :w * f]
    # east side of coarse (i, j): the sub-cells in its last column, their E bits
    eb = ((e[:, f - 1::f] & E) > 0).reshape(h, f, w).sum(axis=1)
    sb = ((e[f - 1::f, :] & S) > 0).reshape(h, w, f).sum(axis=2)
    need = {"all": f, "any": 1, "half": (f + 1) // 2}[rule]
    out = np.zeros((h, w), np.uint8)
    out |= np.where(eb >= need, E, 0).astype(np.uint8)
    out |= np.where(sb >= need, S, 0).astype(np.uint8)
    out[kk == 0] = 0
    return kk, out


def line_edges_f(kind, edges, f, r0, c0, a, b):
    cell = UNIT * f
    ar, ac = (ORIGIN - a[0]) / cell - r0 / f, (ORIGIN - a[1]) / cell - c0 / f
    br, bc = (ORIGIN - b[0]) / cell - r0 / f, (ORIGIN - b[1]) / cell - c0 / f
    return _dda(kind, edges, ar, ac, br, bc)


def _dda(kind, edges, ar, ac, br, bc):
    r, c = int(math.floor(ar)), int(math.floor(ac))
    rt, ct = int(math.floor(br)), int(math.floor(bc))
    dr, dc = br - ar, bc - ac
    sr = 1 if dr > 0 else -1
    sc = 1 if dc > 0 else -1
    tdr = abs(1 / dr) if dr else math.inf
    tdc = abs(1 / dc) if dc else math.inf
    tmr = ((math.floor(ar) + 1 - ar) if dr > 0 else (ar - math.floor(ar))) * tdr if dr else math.inf
    tmc = ((math.floor(ac) + 1 - ac) if dc > 0 else (ac - math.floor(ac))) * tdc if dc else math.inf
    H, W = kind.shape
    for _ in range(100000):
        if r == rt and c == ct:
            return True
        if tmr < tmc:
            nr, nc = r + sr, c
            tmr += tdr
            if not (0 <= nr < H):
                return False
            ok = (edges[min(r, nr), c] & S) > 0
        else:
            nr, nc = r, c + sc
            tmc += tdc
            if not (0 <= nc < W):
                return False
            ok = (edges[r, min(c, nc)] & E) > 0
        if not ok:
            return False
        r, c = nr, nc
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", type=int, default=0)
    ap.add_argument("--n", type=int, default=20000)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    g = load(a.map)
    kind, edges, r0, c0 = g["kind"], g["edges"], int(g["r0"]), int(g["c0"])
    nav = Nav(a.map)
    rng = random.Random(a.seed)
    walkable = np.argwhere(kind == 1)
    lines = []
    while len(lines) < a.n:
        r, c = walkable[rng.randrange(len(walkable))]
        ang = rng.uniform(0, 2 * math.pi)
        d = rng.choice((20, 60, 150, 400)) * rng.uniform(0.5, 1.5) / UNIT
        r2, c2 = int(r + d * math.sin(ang)), int(c + d * math.cos(ang))
        if not (0 <= r2 < kind.shape[0] and 0 <= c2 < kind.shape[1]) or kind[r2, c2] != 1:
            continue
        A = (ORIGIN - (r + r0 + 0.5) * UNIT, ORIGIN - (c + c0 + 0.5) * UNIT, float(g["z"][r, c]))
        B = (ORIGIN - (r2 + r0 + 0.5) * UNIT, ORIGIN - (c2 + c0 + 0.5) * UNIT, float(g["z"][r2, c2]))
        lines.append((A, B))
    t = time.perf_counter()
    truth = [w[0] for w in nav.walks_ok(lines)]
    print("%d lines, %d walkable in the game (%.1f s)" % (len(lines), sum(truth), time.perf_counter() - t))
    variants = {}
    for f in (2, 4):
        for rule in ("half", "any"):
            L = fold_cells(kind, edges, f, rule)
            variants["cells %.1f yd %s" % (UNIT * f, rule)] = (f, L)
            for m in (3, 6):
                variants["cells %.1f yd %s clean<%d" % (UNIT * f, rule, m)] = (f, clean(L, m))
    L1 = fold_cells(kind, edges, 1, "any")
    variants["cells 4.2 yd any"] = (1, L1)
    variants["cells 4.2 yd any clean<4"] = (1, clean(L1, 4))
    for name, (f, L) in variants.items():
        fc = fw = 0
        for (A, B), ok in zip(lines, truth):
            mine = line_cells(L, f, r0, c0, A, B)
            if mine and not ok:
                fc += 1
            if ok and not mine:
                fw += 1
        print("  %-30s false clear %5.2f%% of stuck   false wall %5.2f%% of walkable" % (
            name, 100 * fc / max(1, len(truth) - sum(truth)), 100 * fw / max(1, sum(truth))))
    for f in (2, 4):
        for rule in ("all", "half", "any"):
            kk, ee = fold_edges(kind, edges, f, rule)
            fc = fw = 0
            for (A, B), ok in zip(lines, truth):
                mine = line_edges_f(kk, ee, f, r0, c0, A, B)
                fc += mine and not ok
                fw += ok and not mine
            print("  %-30s false clear %5.2f%% of stuck   false wall %5.2f%% of walkable" % (
                "edges %.1f yd %s" % (UNIT * f, rule), 100 * fc / max(1, len(truth) - sum(truth)),
                100 * fw / max(1, sum(truth))))
    fc = fw = 0
    for (A, B), ok in zip(lines, truth):
        mine = line_edges(kind, edges, r0, c0, A, B)
        fc += mine and not ok
        fw += ok and not mine
    print("  %-30s false clear %5.2f%% of stuck   false wall %5.2f%% of walkable" % (
        "edges 4.2 yd", 100 * fc / max(1, len(truth) - sum(truth)), 100 * fw / max(1, sum(truth))))


if __name__ == "__main__":
    main()
