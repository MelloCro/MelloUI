"""MelloUI Map's waters (2.1.55, docs/plans/map-level-labels.md; the user's pick H of the map level labels sketch:
"Hooks on the water", a badge on each zone's coast, lakes and rivers with the fishing skill the water needs).

Where a zone's waters are, from the client's own terrain: the liquids its terrain files hold (each root .adt's MH2O
chunk: per map chunk its liquid cells and their kind -- the open sea, a region's rivers and lakes, lava and slime left
out), inside each zone's outline as MelloUI's map draws it
(MelloUI_Map/Media/Outlines/<uiMapID>.tga, the coast-stretched masks) and a little past it (the sea along its coast).
Numbers only: where a badge goes on the zone's map (0..1), never a picture.

  MelloUI_Map/MapWaters.lua
      waters[uiMapID] = { x, y, kind, ... }   kind 1 the sea along the coast, 2 a lake, 3 a river (a thin water)

Per zone: the waters touching it, each its own badge -- a lake or river at its deepest point (the water farthest from
the shore; a river: the middle of its length), the coast at up to COAST_MAX points along it, SPACING apart; at most
ZONE_MAX a zone, the biggest waters first. Deterministic: the same files give the same bytes.

    python Tools/build_map_waters.py            write it
    python Tools/build_map_waters.py --check    exit 1 unless it is up to date
    python Tools/build_map_waters.py --view 1411 [out.png]   a zone's water and badges drawn, to look at
"""
import os
import sys

import numpy as np
import cv2
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_map_data as B  # noqa: E402

OUT = os.path.join(B.MAP, "MapWaters.lua")
GW, GH = 600, 400          # a zone's grid (its art's 1002 x 668, about three fifths)
NEAR = 14                   # grid px past the outline still the zone's (the sea along its coast)
MIN_AREA = 56              # grid px: a smaller water is no badge (a pond, a puddle the minimap shows)
RIVER = 4.5                # a water no deeper than this (grid px from the shore) is a river
COAST_MAX = 3              # badges along one coast
SPACING = 140               # grid px between two badges of a zone
SHORE = (4, 14)             # a coast badge stands this far out from the shore (grid px)
ZONE_MAX = 5


# (the terrain files' liquids, by the kind each instance names -- Forever's own numbers; its LiquidType table was not
# exported, so each kind was placed by where it lies: 1250 the open sea round both continents; 7 the lava of the
# Burning Steppes; 5 Un'Goro's tar, Felwood's and Silithus's slime. Every other kind is a region's rivers and lakes)
SEA = {1250}
NOT_WATER = {5, 7}
CELLS = 128   # a terrain tile's liquid cells across (16 chunks of 8)
LAND, INLAND, OPEN_SEA = 0, 1, 2


def tile_liquid(path):
    """a root terrain file's water (CELLS x CELLS uint8: LAND, INLAND, OPEN_SEA) from its MH2O chunk: per map chunk
    its liquid instances, each a rectangle of cells with its own kind and, when given, a bitmap of the cells it has"""
    import struct
    out = np.zeros((CELLS, CELLS), np.uint8)
    d = open(path, "rb").read()
    for tag, pos, size in B.chunks(d):
        if tag != b"MH2O":
            continue
        for i in range(256):
            off, layers, _ = struct.unpack_from("<3I", d, pos + i * 12)
            cy, cx = divmod(i, 16)
            for k in range(layers):
                kind, _lvf, _lo, _hi, xo, yo, w, h, bits, _v = struct.unpack_from("<HHffBBBBII", d, pos + off + k * 24)
                if kind in NOT_WATER or w == 0 or h == 0:
                    continue
                val = OPEN_SEA if kind in SEA else INLAND
                for j in range(w * h):
                    if bits:
                        byte = d[pos + bits + j // 8]
                        if not (byte >> (j % 8)) & 1:
                            continue
                    x, y = cx * 8 + xo + j % w, cy * 8 + yo + j // w
                    if out[y, x] != OPEN_SEA:
                        out[y, x] = val
        break
    return out


def continent_water(assign, cont):
    """the continent's water where its painting lies (uint8 LAND / INLAND / OPEN_SEA, its art px x SCALE): every
    terrain tile's liquids (where there is no tile, sea -- as terrain_land has it), placed as build_map_data places
    the minimap's tiles (the same grid, the same transform)"""
    mapID = B.TERRAIN_MAP.get(cont)
    tiles = B.maid(mapID) if mapID is not None else None
    world = None
    for a in assign.get(cont, []):
        if int(a["MapID"]) == mapID:
            x0, y0, x1, y1 = B.region(a)
            if world is None or (x1 - x0) * (y1 - y0) > world[0]:
                world = ((x1 - x0) * (y1 - y0), a)
    if not tiles or world is None:
        return None
    a, edge = world[1], 32 * B.TILE
    u0, v0 = B.to_ui(a, edge, edge)
    u1, v1 = B.to_ui(a, edge - B.TILE, edge - B.TILE)
    du, dv = u1 - u0, v1 - v0
    import hashlib
    roots = [t[0] for t in tiles]
    key = hashlib.sha1(repr((roots, sorted(SEA), sorted(NOT_WATER), CELLS)).encode()).hexdigest()[:12]
    cache = os.path.join(B.ROOT, "Workspace", "BuildData", "cache", "terrain_liquid_%d_%s.png" % (mapID, key))
    if os.path.isfile(cache):
        grid = Image.open(cache)
    else:
        arr = np.full((64 * CELLS, 64 * CELLS), OPEN_SEA, np.uint8)
        for k, fid in enumerate(roots):
            if not fid:
                continue
            path = B.TERRAIN + "%d.adt" % fid
            if os.path.isfile(path):
                ty, tx = divmod(k, 64)
                arr[ty * CELLS:(ty + 1) * CELLS, tx * CELLS:(tx + 1) * CELLS] = tile_liquid(path)
        grid = Image.fromarray(arr)
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        grid.save(cache)
    W, H = B.ART_W * SCALE, B.ART_H * SCALE
    wat = grid.transform((W, H), Image.AFFINE, (CELLS / (W * du), 0, (0.5 / W - u0) / du * CELLS,
                                                0, CELLS / (H * dv), (0.5 / H - v0) / dv * CELLS), Image.NEAREST,
                         fillcolor=OPEN_SEA)
    return np.asarray(wat)


SCALE = 3   # the continent's water at its art's size times this


def zone_waters(assign, cont, mid, water):
    """a zone's badges: [(x, y, kind)], 0..1 of its map; plus the grids (for --view)"""
    r = B.rect_on(assign, mid, cont)
    path = os.path.join(B.OUTLINES, "%d.tga" % mid)
    if not r or not os.path.isfile(path):
        return [], None
    H, W = water.shape
    x0, x1, y0, y1 = r
    # (the zone's grid from the continent's water: a grid pixel's middle on the continent)
    a, e = (x1 - x0) * W / GW, (y1 - y0) * H / GH
    cls = np.asarray(Image.fromarray(water).transform(
        (GW, GH), Image.AFFINE, (a, 0, x0 * W + a / 2 - 0.5, 0, e, y0 * H + e / 2 - 0.5), Image.NEAREST))
    wat, sea = cls > LAND, cls == OPEN_SEA
    out = np.asarray(Image.open(path).getchannel("A").resize((GW, GH), Image.BILINEAR)) >= 128
    near = cv2.dilate(out.astype(np.uint8), np.ones((2 * NEAR + 1, 2 * NEAR + 1), np.uint8)) > 0
    # (the sea and the inland waters grouped apart: a river that runs into the sea is its own water)
    w = wat & near
    depth = cv2.distanceTransform(w.astype(np.uint8), cv2.DIST_L2, 5)
    groups = []
    for part, is_sea in ((sea & near, True), (wat & ~sea & near, False)):
        n, lab, stats, _ = cv2.connectedComponentsWithStats(part.astype(np.uint8), 8)
        groups += [(lab == i, is_sea, int(stats[i, cv2.CC_STAT_AREA])) for i in range(1, n)]
    found = []
    for m, is_sea, area in sorted(groups, key=lambda g: -g[2]):
        if area < MIN_AREA:
            continue
        if is_sea:
            # (along the coast: water a little out from the shore, inside the outline's reach, farthest-first apart)
            cand = m & (depth >= SHORE[0]) & (depth <= SHORE[1]) & near
            ys, xs = np.nonzero(cand)
            if len(xs) == 0:
                continue
            pts = list(zip(xs.tolist(), ys.tolist()))
            cx, cy = np.mean(xs), np.mean(ys)
            # (the first: the candidate nearest the coast's own middle; then each farthest from those taken)
            first = min(pts, key=lambda p: ((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p))
            took = [first]
            while len(took) < COAST_MAX:
                best, bd = None, -1
                for p in pts:
                    d = min((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 for q in took)
                    if d > bd or (d == bd and p < best):
                        best, bd = p, d
                if best is None or bd < SPACING * SPACING:
                    break
                took.append(best)
            found += [(p[0], p[1], 1, area) for p in took]
        else:
            # (a lake's or river's badge inside the zone's outline where the water reaches it: a river along a border
            # is marked on the zone's side)
            if (m & out).any():
                m = m & out
            dm = np.where(m, depth, 0)
            deep = float(dm.max())
            if deep <= RIVER:
                # (a river: the water pixel nearest its middle)
                ys, xs = np.nonzero(m)
                cx, cy = np.mean(xs), np.mean(ys)
                k = int(np.argmin((xs - cx) ** 2 + (ys - cy) ** 2))
                found.append((int(xs[k]), int(ys[k]), 3, area))
            else:
                y, x = np.unravel_index(int(np.argmax(dm)), dm.shape)
                found.append((int(x), int(y), 2, area))
    # (the zone's at most: the biggest waters first, each SPACING from those kept)
    kept = []
    for x, y, kind, area in sorted(found, key=lambda f: (-f[3], f[2], f[0], f[1])):
        if len(kept) >= ZONE_MAX:
            break
        if all((x - k[0]) ** 2 + (y - k[1]) ** 2 >= SPACING * SPACING * 0.5 for k in kept):
            kept.append((x, y, kind))
    badges = [(round((x + 0.5) / GW, 3), round((y + 0.5) / GH, 3), kind) for x, y, kind in kept]
    return badges, (wat, out, near, kept)


def build(view=None):
    maps = {int(r["ID"]): r for r in B.rows("UiMap")}
    assign = {}
    for r in B.rows("UiMapAssignment"):
        assign.setdefault(int(r["UiMapID"]), []).append(r)
    zones = {}
    for mid, m in maps.items():
        if int(m["Type"]) == B.ZONE and os.path.isfile(os.path.join(B.OUTLINES, "%d.tga" % mid)):
            zones.setdefault(int(m["ParentUiMapID"]), []).append(mid)
    result, views = {}, {}
    for cont in sorted(zones):
        water = continent_water(assign, cont)
        if water is None:
            continue
        for mid in sorted(zones[cont]):
            badges, grids = zone_waters(assign, cont, mid, water)
            if badges:
                result[mid] = badges
            if view == mid:
                views[mid] = grids
    out = ["-- MelloUI Map's waters, made by Tools/build_map_waters.py from the client's own terrain (the minimap's pictures",
           "-- of each terrain tile) inside each zone's outline: numbers only; never edit by hand (run the tool).",
           "-- docs/plans/map-level-labels.md (the fishing badges).",
           "local _, ns = ...",
           "-- [uiMapID] = { x, y, kind, ... }: a badge's place on the zone's map (0..1); kind 1 the coast, 2 a lake,",
           "-- 3 a river",
           "ns.MapWaters = {"]
    for mid in sorted(result):
        out.append("\t[%d] = { %s }," % (mid, ", ".join("%s, %s, %d" % b for b in result[mid])))
    out += ["}", ""]
    return "\n".join(out), views


def main():
    args = sys.argv[1:]
    if args and args[0] == "--view":
        mid = int(args[1])
        dest = args[2] if len(args) > 2 else "waters_%d.png" % mid
        _, views = build(view=mid)
        wat, out, near, kept = views[mid]
        img = np.zeros((GH, GW, 3), np.uint8)
        img[out] = (90, 70, 40)
        img[wat & near] = (200, 120, 40)
        img[wat & ~near] = (90, 50, 20)
        for x, y, kind in kept:
            cv2.circle(img, (x, y), 6, ((0, 255, 0), (0, 200, 255), (255, 0, 255))[kind - 1], -1)
        Image.fromarray(img[:, :, ::-1]).resize((GW * 3 // 2, GH * 3 // 2), Image.NEAREST).save(dest)
        print(dest, kept)
        return
    text, _ = build()
    if args and args[0] == "--check":
        cur = open(OUT, encoding="utf-8").read() if os.path.isfile(OUT) else ""
        if cur != text:
            print("MapWaters.lua is out of date: run python Tools/build_map_waters.py")
            sys.exit(1)
        print("MapWaters.lua is up to date")
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(OUT, text.count("\n\t["), "zones")


if __name__ == "__main__":
    main()
