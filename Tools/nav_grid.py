#!/usr/bin/env python3
"""
The real ground as a grid, from wowsim's navmesh (Tools/navmesh.py): Route's ground truth for the bench and the bake
(docs/plans/route-ground.md). Offline; nothing ships from here directly.

  cells     UNIT yards (4.17: 128 a side per ADT tile, the terrain's own vertex spacing), aligned to the ADT tiles:
            row r = (17066.67 - world x) / UNIT, column c = (17066.67 - world y) / UNIT (rows run south, columns east)
  kind      the column's highest floor: 0 none (no floor: a wall, a tree trunk, a cliff too steep, the void), 1 ground
            (wading included), 2 water (swum)
  z         that floor's height; floors: how many the column has (a bridge, a building, a cave over the ground)
  edges     whether the character walks straight from the cell's centre to its neighbour's (the navmesh's raycast from
            the highest floor): bit 1 east (c + 1), 2 south (r + 1), 4 south-east, 8 south-west -- a cliff between
            two floors, a fence, a wall is a missing edge

    python Tools/nav_grid.py --map 0 [--jobs 8] [--block 4] [--out <BuildData>/cache/nav]

Writes <out>/navgrid_<map>.npz (r0, c0, kind, z, floors, edges) and a preview PNG. A worker per block of ADT tiles,
each with its own navmesh handle (loaded with a margin for the border's walks), at below-normal priority.
"""
import argparse
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ADT = 1600.0 / 3.0          # 533.33 yd
PER = 128                   # cells a side per ADT
UNIT = ADT / PER            # 4.1667 yd
ORIGIN = 32 * ADT           # 17066.67: world x (y) of row (column) 0
E, S, SE, SW = 1, 2, 4, 8
ZGAP = UNIT * 1.25 + 2.0    # yards of height between two neighbours' floors past which no walk joins them (50 deg)
STEPS = ((E, 0, 1), (S, 1, 0), (SE, 1, 1), (SW, 1, -1))


def build_out():
    if os.environ.get("NAV_OUT"):
        return os.environ["NAV_OUT"]
    bd = os.environ.get("MELLOUI_BUILD_DATA") or os.path.join(os.path.dirname(os.path.dirname(HERE)),
                                                               "MelloUI-BuildData")
    if ".claude" in HERE and not os.environ.get("MELLOUI_BUILD_DATA"):
        bd = r"F:\Download-Backup\Project Web\MelloUI-BuildData"
    return os.path.join(bd, "cache", "nav")


def world_of(r, c):
    """a cell's centre in world yards"""
    return ORIGIN - (r + 0.5) * UNIT, ORIGIN - (c + 0.5) * UNIT


def cell_of(x, y):
    return int((ORIGIN - x) // UNIT), int((ORIGIN - y) // UNIT)


def adts_of(map_id):
    """the ADT tiles the navmesh file holds: [(tx, ty)] (tx the column's, ty the row's)"""
    import struct
    from navmesh import nav_file
    out = []
    with open(nav_file(map_id), "rb") as f:
        head = f.read(12)
        _, version, hb = struct.unpack("<3I", head)
        size = os.fstat(f.fileno()).st_size
        pos = hb
        while pos + 40 <= size:
            f.seek(pos)
            rh = f.read(40)
            magic, x, y, ntiles, payload = struct.unpack_from("<4sii I Q", rh)
            if magic != b"WSNR" or pos + 40 + payload + 8 > size:
                break
            f.seek(pos + 40 + payload)
            if f.read(8)[4:] != b"WSNE":
                break
            out.append((x, y))
            pos += 40 + payload + 8
    return sorted(set(out))


def below_normal():
    if os.name == "nt":
        try:
            import ctypes
            k = ctypes.windll.kernel32
            k.SetPriorityClass(k.GetCurrentProcess(), 0x4000)   # BELOW_NORMAL_PRIORITY_CLASS
        except Exception:
            pass


PW = {}
BIG_PIECE = 1000   # polygons: a piece of ground this big is the ground people walk (a roof, an awning, a rock's top is not)


def init_grid(map_id):
    """a grid worker: the navmesh's polygons and their pieces (Tools/nav_polys.py), to choose a cell's floor"""
    below_normal()
    from nav_polys import Polys
    from scipy.sparse.csgraph import connected_components
    P = Polys(map_id)
    _, lab = connected_components(P.graph(), directed=False)
    PW["P"], PW["lab"], PW["big"] = P, lab, np.bincount(lab) >= BIG_PIECE


def floor_of(x, y, floors):
    """a cell's floor (z, area): the highest on a big piece of ground -- a street under an awning, a roof or a
    ledge is its street -- else the highest (a bridge's deck over its river is the ground's piece too)"""
    if len(floors) > 1 and PW:
        P, lab, big = PW["P"], PW["lab"], PW["big"]
        for fz, area in floors:
            i = P.locate(x, y, fz)
            if i >= 0 and big[lab[i]]:
                return fz, area
    return floors[0]


def work(job):
    """one block of ADT tiles: (map, [(tx, ty)]) -> [(tx, ty, kind, z, floors, edges)]"""
    below_normal()
    from navmesh import Nav
    map_id, tiles = job
    xs = [t[0] for t in tiles]
    ys = [t[1] for t in tiles]
    # world bounds of the block and a margin (the walks over its border end in the next tile)
    min_x, max_x = ORIGIN - (max(ys) + 1) * ADT - 10, ORIGIN - min(ys) * ADT + 10
    min_y, max_y = ORIGIN - (max(xs) + 1) * ADT - 10, ORIGIN - min(xs) * ADT + 10
    nav = Nav(map_id, (min_x, min_y, max_x, max_y))
    out = []
    for tx, ty in tiles:
        # this tile's cells and a ring of one cell round it (the neighbours its edges reach)
        r0, c0 = ty * PER - 1, tx * PER - 1
        n = PER + 2
        kind = np.zeros((n, n), np.uint8)
        z = np.full((n, n), np.nan, np.float32)
        floors = np.zeros((n, n), np.uint8)
        for i in range(n):
            for j in range(n):
                x, y = world_of(r0 + i, c0 + j)
                g = nav.ground(x, y)
                if g["ok"]:
                    fz, area = floor_of(x, y, g["floors"]) if g["floors"] else (g["z"], 2 if g["area"] == "water" else 1)
                    kind[i, j] = 2 if area == 2 else 1
                    z[i, j] = fz
                    floors[i, j] = min(255, len(g["floors"]))
        edges = np.zeros((PER, PER), np.uint8)
        segs, where = [], []
        for i in range(1, PER + 1):
            for j in range(1, PER + 1):
                if not kind[i, j]:
                    continue
                xa, ya = world_of(r0 + i, c0 + j)
                for bit, di, dj in STEPS:
                    # (two floors too far apart for any slope the character climbs: never asked -- wowsim#32, a
                    # walk from an upper floor to a spot with only a lower one never returns)
                    if kind[i + di, j + dj] and abs(z[i, j] - z[i + di, j + dj]) <= ZGAP * (1.4142 if di and dj else 1):
                        xb, yb = world_of(r0 + i + di, c0 + j + dj)
                        segs.append(((xa, ya, float(z[i, j])), (xb, yb, float(z[i + di, j + dj]))))
                        where.append((i - 1, j - 1, bit))
        for k in range(0, len(segs), 4096):
            res = nav.walks_ok(segs[k:k + 4096])
            for (i, j, bit), (ok, _, _, _) in zip(where[k:k + 4096], res):
                if ok:
                    edges[i, j] |= bit
        out.append((tx, ty, kind[1:-1, 1:-1].copy(), z[1:-1, 1:-1].copy(), floors[1:-1, 1:-1].copy(), edges))
    nav.close()
    return out


def under_grids(map_id):
    """the underground capitals' streets as grids of their own (Ironforge, the Undercity: the grid above has the ground
    over them): their map's region, each cell's floor the highest of its street floors (Tools/nav_zones.py's rule), its
    edges walked on them -> {zone: (r0, c0, kind, z, edges)}"""
    from navmesh import Nav
    from nav_zones import UNDER_Z, city_region, under_city
    nav = Nav(map_id)
    out = {}
    for zone in UNDER_Z:
        reg = city_region(map_id, zone)
        if not reg:
            continue
        t0 = time.perf_counter()
        ra, ca = cell_of(reg[2], reg[3])
        rb, cb = cell_of(reg[0], reg[1])
        h, w = rb - ra + 1, cb - ca + 1
        kind = np.zeros((h, w), np.uint8)
        z = np.full((h, w), np.nan, np.float32)
        lo, hi = UNDER_Z[zone]
        for i in range(h):
            for j in range(w):
                x, y = world_of(ra + i, ca + j)
                for fz, area in nav.ground(x, y)["floors"]:   # (highest first)
                    if lo <= fz <= hi and under_city(map_id, nav, x, y, fz) == zone:
                        kind[i, j] = 2 if area == 2 else 1
                        z[i, j] = fz
                        break
        edges = np.zeros((h, w), np.uint8)
        segs, where = [], []
        for i in range(h):
            for j in range(w):
                if not kind[i, j]:
                    continue
                xa, ya = world_of(ra + i, ca + j)
                for bit, di, dj in STEPS:
                    i2, j2 = i + di, j + dj
                    if (0 <= i2 < h and 0 <= j2 < w and kind[i2, j2]
                            and abs(z[i, j] - z[i2, j2]) <= ZGAP * (1.4142 if di and dj else 1)):
                        xb, yb = world_of(ra + i2, ca + j2)
                        segs.append(((xa, ya, float(z[i, j])), (xb, yb, float(z[i2, j2]))))
                        where.append((i, j, bit))
        for k in range(0, len(segs), 4096):
            res = nav.walks_ok(segs[k:k + 4096])
            for (i, j, bit), (ok, _, _, _) in zip(where[k:k + 4096], res):
                if ok:
                    edges[i, j] |= bit
        out[zone] = (ra, ca, kind, z, edges)
        print("under grid %d: %d x %d, %d cells on its streets (%.0f s)" % (
            zone, h, w, int((kind > 0).sum()), time.perf_counter() - t0), flush=True)
    nav.close()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--block", type=int, default=3)
    ap.add_argument("--out", default=None)
    ap.add_argument("--stall", type=int, default=120, help="seconds without a finished tile: the run stops")
    ap.add_argument("--only", default="", help="tx0,ty0,tx1,ty1: only these ADT tiles (a test)")
    ap.add_argument("--under", action="store_true", help="only the underground capitals' grids (navunder_<map>.npz)")
    a = ap.parse_args()
    if a.under:
        res = under_grids(a.map)
        arrays = {}
        for zone, (r0_, c0_, k_, z_, e_) in res.items():
            arrays.update({"%d_r0" % zone: r0_, "%d_c0" % zone: c0_, "%d_kind" % zone: k_, "%d_z" % zone: z_,
                           "%d_edges" % zone: e_})
        path = os.path.join(a.out if getattr(a, "out", None) else build_out(), "navunder_%d.npz" % a.map)
        np.savez_compressed(path, zones=np.array(sorted(res)), **arrays)
        print("wrote %s" % path)
        return
    out_dir = a.out or build_out()
    os.makedirs(out_dir, exist_ok=True)
    tiles = adts_of(a.map)
    if a.only:
        x0, y0, x1, y1 = (int(v) for v in a.only.split(","))
        tiles = [t for t in tiles if x0 <= t[0] <= x1 and y0 <= t[1] <= y1]
    print("map %d: %d ADT tiles" % (a.map, len(tiles)), flush=True)
    tx0, tx1 = min(t[0] for t in tiles), max(t[0] for t in tiles)
    ty0, ty1 = min(t[1] for t in tiles), max(t[1] for t in tiles)
    r0, c0 = ty0 * PER, tx0 * PER
    H, W = (ty1 - ty0 + 1) * PER, (tx1 - tx0 + 1) * PER
    kind = np.zeros((H, W), np.uint8)
    z = np.full((H, W), np.nan, np.float32)
    floors = np.zeros((H, W), np.uint8)
    edges = np.zeros((H, W), np.uint8)
    blocks = {}
    for t in tiles:
        blocks.setdefault((t[0] // a.block, t[1] // a.block), []).append(t)
    jobs = [(a.map, v) for v in blocks.values()]
    t0 = time.perf_counter()
    done = 0
    done_tiles = set()
    below_normal()
    from multiprocessing import Pool
    import multiprocessing as mp
    pool = Pool(a.jobs, initializer=init_grid, initargs=(a.map,))
    it = pool.imap_unordered(work, jobs)
    left = len(jobs)
    try:
        while left:
            try:
                res = it.next(timeout=a.stall)
            except mp.TimeoutError:
                # (a worker that answers nothing for `stall` seconds is stuck in the library: the run ends with the
                # tiles still to do named, rather than never)
                missing = sorted(set(tiles) - done_tiles)
                print("STALLED: no tile for %d s; %d tiles not done: %s" % (a.stall, len(missing), missing[:40]),
                      flush=True)
                pool.terminate()
                break
            left -= 1
            for tx, ty, k, zz, fl, ed in res:
                done_tiles.add((tx, ty))
                rr, cc = ty * PER - r0, tx * PER - c0
                kind[rr:rr + PER, cc:cc + PER] = k
                z[rr:rr + PER, cc:cc + PER] = zz
                floors[rr:rr + PER, cc:cc + PER] = fl
                edges[rr:rr + PER, cc:cc + PER] = ed
                done += 1
            el = time.perf_counter() - t0
            print("  %d/%d tiles, %.0f s, eta %.0f s" % (done, len(tiles), el, el / done * (len(tiles) - done)),
                  flush=True)
    finally:
        pool.close()
    path = os.path.join(out_dir, "navgrid_%d.npz" % a.map)
    np.savez_compressed(path, r0=r0, c0=c0, unit=UNIT, kind=kind, z=z, floors=floors, edges=edges)
    print("wrote %s: %d x %d, ground %d, water %d, multi-floor %d, in %.0f s" % (
        path, H, W, int((kind == 1).sum()), int((kind == 2).sum()), int((floors > 1).sum()), time.perf_counter() - t0))
    try:
        from PIL import Image
        img = np.zeros((H, W, 3), np.uint8)
        img[kind == 1] = (120, 160, 90)
        img[kind == 2] = (60, 100, 170)
        full = (edges & (E | S)) == (E | S)
        img[(kind == 1) & ~full] = (200, 120, 60)
        Image.fromarray(img).save(os.path.join(out_dir, "navgrid_%d.png" % a.map))
    except Exception as e:  # noqa: BLE001
        print("preview:", e)


if __name__ == "__main__":
    main()
