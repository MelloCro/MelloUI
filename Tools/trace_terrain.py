#!/usr/bin/env python3
"""
Route over the real ground (docs/plans/route-terrain.md, the user's option A): the walkable ground of each continent,
measured offline from the client's own terrain tiles, so routes go round ridges instead of over them.

Stages (each caches under MelloUI-BuildData/cache/terrain):

  python Tools/trace_terrain.py wdt        the continents' WDT files (their tiles' file ids), raw by fdid through the
                                           patched wow.export (the user's install; F:/wow.export)
  python Tools/trace_terrain.py adt        every root ADT those WDTs name, raw by fdid (local only: never shipped)
  python Tools/trace_terrain.py grid       the height grid -> the walkable grid per continent (cache .npz) and a
                                           picture per continent for a look
  python Tools/trace_terrain.py check      the known places (the Northshire ridge, the Deathknell hills, Lakeshire's
                                           bridge, a walkable hill) on the grid, with a picture each
  python Tools/trace_terrain.py all        wdt, adt, grid

The ground graph itself is laid by Tools/trace_roads.py's bake (it reads this grid): ground nodes on the walkable
cells, linked where the straight segment stays walkable, and the coarse walk grid the runtime checks its straight
legs on. Only that derived data ships (MelloUI_Companion/RoadData.lua); the client's tiles stay in the cache.

The terrain format (the client's chunked files, the four-letter tags stored reversed):
  WDT  MAID: 64 x 64 entries (row = tile y) of 8 file ids: root ADT, obj0, obj1, tex0, lod, map texture,
       map texture N, minimap texture
  ADT  (root) MCNK x 256 (16 x 16 per tile): a 128-byte header (its index x / y at 4 / 8, holes at 0x3C, its
       position at 0x68: x north, y west, z the base height) then sub-chunks; MCVT: 145 heights (rows of 9 outer, 8
       inner, ..., 9 outer: 17 rows), each added to the base. MH2O: the water per chunk (an instance's min / max
       height).
  A tile is 533.33 yards; a chunk 33.33; an outer vertex 4.17. World x = 17066.67 - (tile y * 533.33 + ...),
  world y = 17066.67 - (tile x * 533.33 + ...).
"""
import argparse
import json
import math
import os
import struct
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from paths import CACHE  # noqa: E402

TERRAIN = os.path.join(CACHE, "terrain")
EXPORT = r"F:/Download-Backup/WoWExport"
APP = r"F:/wow.export"
DRIVER = os.path.join(ROOT, "..", "wow-export-patched-win-x64-0.2.19", "patch", "autorun_driver.py")
RAW_DIR = "terrain_raw"                       # under EXPORT: the client's files, never in the repo

TILE = 1600.0 / 3.0                           # 533.33 yards
CHUNK = TILE / 16.0                           # 33.33
UNIT = CHUNK / 8.0                            # 4.17: one outer vertex to the next
ZERO = 32.0 * TILE                            # 17066.67

# the continents: world map id -> (WDT fdid, name). Their WDT file ids are the Map table's (WdtFileDataID).
MAPS = {0: (775971, "Eastern Kingdoms"), 1: (782779, "Kalimdor"), 2991: (7198644, "Zephras Isle")}

SLOPE_MAX = 1.2        # rise over run between neighbouring vertices: steeper is a wall (about 50 degrees)
WATER_DEEP = 1.6       # yards of water over the ground: swimming


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------------------------------- the files
def chunks(data, start=0, end=None):
    """the (tag, offset of its body, size) of each chunk; the tag as it reads (b'MCNK')"""
    end = len(data) if end is None else end
    pos = start
    while pos + 8 <= end:
        tag = data[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        yield tag, pos + 8, size
        pos += 8 + size


def read_wdt(path):
    """{ (tx, ty): root ADT fdid }"""
    data = open(path, "rb").read()
    out = {}
    for tag, off, size in chunks(data):
        if tag == b"MAID":
            n = size // 32
            for i in range(n):
                vals = struct.unpack_from("<8I", data, off + i * 32)
                if vals[0]:
                    ty, tx = divmod(i, 64)
                    out[(tx, ty)] = vals[0]
    return out


def read_adt(path):
    """the tile's heights at its outer vertices: a 129 x 129 array (row = south, column = west steps from the
    tile's north-west corner), NaN where a chunk is missing or holed; and the water's top over each vertex (NaN
    where none)."""
    data = open(path, "rb").read()
    h = np.full((129, 129), np.nan, dtype=np.float32)
    water = np.full((16, 16), np.nan, dtype=np.float32)
    mh2o = None
    for tag, off, size in chunks(data):
        if tag == b"MH2O":
            mh2o = (off, size)
        elif tag == b"MCNK":
            hdr = data[off:off + 128]
            ix, iy = struct.unpack_from("<II", hdr, 4)
            holes = struct.unpack_from("<H", hdr, 0x3C)[0]
            base = struct.unpack_from("<3f", hdr, 0x68)[2]
            for stag, soff, ssize in chunks(data, off + 128, off + size):
                if stag == b"MCVT" and ssize >= 145 * 4:
                    v = struct.unpack_from("<145f", data, soff)
                    for r in range(9):
                        row = v[r * 17:r * 17 + 9]
                        y = iy * 8 + r
                        for c in range(9):
                            h[y, ix * 8 + c] = base + row[c]
                    break
            if holes:
                # (a hole: no ground there -- a cave mouth, a building's floor: the WMO's, not ours; left as it is)
                pass
    if mh2o:
        off, size = mh2o
        # 256 headers: offset of instances, layer count, offset of attributes
        for i in range(256):
            o_inst, n_layers, _ = struct.unpack_from("<III", data, off + i * 12)
            if n_layers and o_inst:
                # an instance: liquid type, vertex format, min height, max height, ...
                try:
                    _, _, mn, mx = struct.unpack_from("<HHff", data, off + o_inst)
                except struct.error:
                    continue
                cy, cx = divmod(i, 16)
                water[cy, cx] = mx
    return h, water


# --------------------------------------------------------------------------------------------------- the export
def driver(spec):
    path = os.path.join(TERRAIN, "spec_%d.json" % int(time.time()))
    json.dump(spec, open(path, "w"), indent=1)
    cmd = [sys.executable, DRIVER, "--app", APP, "--export-dir", EXPORT, "run", "--spec", path]
    log(" ".join(cmd))
    return subprocess.call(cmd)


def stage_wdt():
    os.makedirs(TERRAIN, exist_ok=True)
    ids = os.path.join(TERRAIN, "wdt_ids.txt")
    open(ids, "w").write("\n".join(str(v[0]) for v in MAPS.values()) + "\n")
    return driver({"raw": [{"idFile": ids.replace("\\", "/"), "ext": ".wdt", "dir": RAW_DIR}], "quitWhenDone": True})


def wdt_tiles(wmap):
    path = os.path.join(EXPORT, RAW_DIR, "%d.wdt" % MAPS[wmap][0])
    return read_wdt(path) if os.path.exists(path) else {}


def stage_adt():
    ids = []
    for wmap in MAPS:
        tiles = wdt_tiles(wmap)
        log("%s: %d tiles" % (MAPS[wmap][1], len(tiles)))
        ids += [fd for fd in tiles.values()
                if not os.path.exists(os.path.join(EXPORT, RAW_DIR, "%d.adt" % fd))]
    if not ids:
        log("every ADT exported already")
        return 0
    path = os.path.join(TERRAIN, "adt_ids.txt")
    open(path, "w").write("\n".join(str(i) for i in ids) + "\n")
    return driver({"raw": [{"idFile": path.replace("\\", "/"), "ext": ".adt", "dir": RAW_DIR}], "quitWhenDone": True})


# --------------------------------------------------------------------------------------------------- the grid
def continent_heights(wmap):
    """the continent's heights at every outer vertex: (array, tx0, ty0) with the array covering the tiles' box,
    row = south from the box's north edge, column = west from its east... (the world: x north, y west)"""
    tiles = wdt_tiles(wmap)
    if not tiles:
        return None
    txs = [t[0] for t in tiles]
    tys = [t[1] for t in tiles]
    tx0, tx1, ty0, ty1 = min(txs), max(txs), min(tys), max(tys)
    W = (tx1 - tx0 + 1) * 128 + 1
    H = (ty1 - ty0 + 1) * 128 + 1
    hg = np.full((H, W), np.nan, dtype=np.float32)
    wg = np.full((H, W), np.nan, dtype=np.float32)
    for (tx, ty), fd in tiles.items():
        path = os.path.join(EXPORT, RAW_DIR, "%d.adt" % fd)
        if not os.path.exists(path):
            continue
        h, water = read_adt(path)
        r0, c0 = (ty - ty0) * 128, (tx - tx0) * 128
        block = hg[r0:r0 + 129, c0:c0 + 129]
        np.copyto(block, h, where=~np.isnan(h))
        wb = np.repeat(np.repeat(water, 8, axis=0), 8, axis=1)
        wv = wg[r0:r0 + 128, c0:c0 + 128]
        np.copyto(wv, wb, where=~np.isnan(wb))
    return hg, wg, tx0, ty0


def walk_grid(hg, wg):
    """per vertex cell (between four vertices): 1 walkable, 2 water (swim), 0 blocked, 255 no data"""
    H, W = hg.shape
    run = UNIT
    dx = np.abs(np.diff(hg, axis=1)) / run          # H x W-1
    dy = np.abs(np.diff(hg, axis=0)) / run          # H-1 x W
    steep = np.zeros((H - 1, W - 1), dtype=bool)
    with np.errstate(invalid="ignore"):
        steep |= dx[:-1, :] > SLOPE_MAX
        steep |= dx[1:, :] > SLOPE_MAX
        steep |= dy[:, :-1] > SLOPE_MAX
        steep |= dy[:, 1:] > SLOPE_MAX
    nodata = np.isnan(hg[:-1, :-1]) | np.isnan(hg[1:, 1:]) | np.isnan(hg[:-1, 1:]) | np.isnan(hg[1:, :-1])
    ground = (hg[:-1, :-1] + hg[1:, 1:] + hg[:-1, 1:] + hg[1:, :-1]) / 4.0
    wtop = wg[:-1, :-1]
    with np.errstate(invalid="ignore"):
        deep = (wtop - ground) > WATER_DEEP
    out = np.ones((H - 1, W - 1), dtype=np.uint8)
    out[steep] = 0
    out[deep & ~steep] = 2
    out[deep & steep] = 2          # (steep under water is the lake's own floor: swum over)
    out[nodata] = 255
    return out


def stage_grid():
    os.makedirs(TERRAIN, exist_ok=True)
    for wmap in MAPS:
        res = continent_heights(wmap)
        if res is None:
            log("%s: no WDT yet" % MAPS[wmap][1])
            continue
        hg, wg, tx0, ty0 = res
        grid = walk_grid(hg, wg)
        np.savez_compressed(os.path.join(TERRAIN, "walk_%d.npz" % wmap), grid=grid, tx0=tx0, ty0=ty0,
                            heights=hg.astype(np.float16))
        frac = {k: float(np.mean(grid == v)) for k, v in (("walk", 1), ("swim", 2), ("wall", 0), ("none", 255))}
        log("%s: %d x %d cells (4.17 yd), %s" % (MAPS[wmap][1], grid.shape[1], grid.shape[0],
                                                ", ".join("%s %.0f%%" % (k, v * 100) for k, v in frac.items())))
        picture(grid, os.path.join(TERRAIN, "walk_%d.png" % wmap))


def picture(grid, path, scale=4):
    from PIL import Image
    small = grid[::scale, ::scale]
    rgb = np.zeros(small.shape + (3,), dtype=np.uint8)
    rgb[small == 1] = (120, 170, 90)
    rgb[small == 2] = (70, 110, 200)
    rgb[small == 0] = (90, 60, 40)
    rgb[small == 255] = (20, 20, 20)
    Image.fromarray(rgb).save(path)
    log("picture -> %s" % path)


# --------------------------------------------------------------------------------------------------- the world
def world_to_cell(wx, wy, tx0, ty0):
    """world x (north), y (west) -> (row, column) in the continent's vertex grid"""
    col = (ZERO - wy) / UNIT - tx0 * 128
    row = (ZERO - wx) / UNIT - ty0 * 128
    return row, col


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("stage", choices=["wdt", "adt", "grid", "all"])
    a = ap.parse_args()
    if a.stage in ("wdt", "all"):
        stage_wdt()
    if a.stage in ("adt", "all"):
        stage_adt()
    if a.stage in ("grid", "all"):
        stage_grid()
    return 0


if __name__ == "__main__":
    sys.exit(main())
