#!/usr/bin/env python3
"""
Trace the roads drawn on the Forever zone maps into a road graph for the
Route module, so routes follow roads everywhere from the first login instead
of only where someone has walked.

Stages (each one caches its result under MelloUI-BuildData/cache):

  python Tools/trace_roads.py fetch      download the zone map tiles of the build (wago.tools)
  python Tools/trace_roads.py assemble   stitch the tiles into one image per zone
  python Tools/trace_roads.py trace      find the roads on every zone image; previews + segments
  python Tools/trace_roads.py bake       write Media/RoadData.lua from the segments and the review
  python Tools/trace_roads.py all        everything in order
  python Tools/trace_roads.py trace --zone 1429   one zone only (Elwynn Forest), for tuning

The tracing is a best effort on hand-painted art: mountain ridges, labels,
icons and lake shores look much like roads up close. Tools/roads_review.html
shows every zone with its traced segments; click a segment to drop it, draw
missing roads, and save the result as Tools/roads/review.json. The bake
applies that review on top of the automatic trace (Tools/roads/segments.json).

Sources: wago.tools DB2 tables UiMap, UiMapXMapArt, UiMapArt, UiMapArtStyleLayer,
UiMapArtTile, WorldMapOverlay, WorldMapOverlayTile and UiMapAssignment for the
build, and the textures by file id. The zone's world bounds (UiMapAssignment)
place every pixel in the world; the continent's bounds turn that into the
"continent yards" the Route module uses (what C_Map.GetMapWorldSize gives in
game). Media/RoadData.lua carries the continent sizes it was traced with and
the module rescales if the client reports different ones.

Output format (the Route module's graph): graphs[continent][cell] = { yards
east, yards south, { [cell] = seconds } }, cell = floor(x / 10) .. ":" .. floor(y / 10).
"""
import argparse
import csv
import io
import json
import math
import os
import sys
import time
import warnings
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image
from paths import CACHE

warnings.filterwarnings("ignore", category=FutureWarning)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
BUILD = "1.60.1.69913"
WAGO_CSV = "https://wago.tools/db2/{table}/csv?build={build}"
WAGO_FILE = "https://wago.tools/api/casc/{fdid}?version={build}"
TILES = os.path.join(CACHE, "maptiles", BUILD)
ZONES = os.path.join(CACHE, "zonemaps", BUILD)
TRACES = os.path.join(CACHE, "roadtraces", BUILD)
ROADS = os.path.join(HERE, "roads")                   # committed: segments.json (auto), review.json (by hand)
SEGMENTS = os.path.join(ROADS, "segments.json")
REVIEW = os.path.join(ROADS, "review.json")
OUT = os.path.join(ROOT, "Media", "RoadData.lua")

CONTINENTS = {1414: "Kalimdor", 1415: "Eastern Kingdoms"}
WALK = 7.0          # yards per second, as in Route.lua
CELL = 10           # yards per graph cell, as in Route.lua
NODE_STEP = 20      # yards between nodes along a road
JOIN_YARDS = 30     # roads whose nodes come this close are linked (crossings, segment ends)


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, file=sys.stderr, flush=True)


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    import urllib.request
    os.makedirs(os.path.dirname(path), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "MelloUI road tracer"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    with open(path, "wb") as fh:
        fh.write(data)
    return path


def db2(table):
    path = os.path.join(CACHE, f"{table}_{BUILD}.csv")
    fetch(WAGO_CSV.format(table=table, build=BUILD), path)
    with open(path, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


# ---------------------------------------------------------------------------
# Zones of the two continents, with their art and world bounds
# ---------------------------------------------------------------------------

def load_zones(only=None):
    ui = {int(r["ID"]): r for r in db2("UiMap")}
    xart = {}
    for r in db2("UiMapXMapArt"):
        xart.setdefault(int(r["UiMapID"]), []).append(int(r["UiMapArtID"]))
    art = {int(r["ID"]): r for r in db2("UiMapArt")}
    layers = {int(r["ID"]): r for r in db2("UiMapArtStyleLayer")}
    tiles = {}
    for r in db2("UiMapArtTile"):
        if int(r["LayerIndex"]) == 0:
            tiles.setdefault(int(r["UiMapArtID"]), []).append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
    assign = {}
    for r in db2("UiMapAssignment"):
        assign.setdefault(int(r["UiMapID"]), []).append(r)
    # The base art is the blank parchment; the explored areas (roads, towns,
    # forests) are overlay pieces pasted at an offset, each made of tiles.
    overlay_tiles = {}
    for r in db2("WorldMapOverlayTile"):
        if int(r["LayerIndex"]) == 0:
            overlay_tiles.setdefault(int(r["WorldMapOverlayID"]), []).append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
    overlays = {}
    for r in db2("WorldMapOverlay"):
        overlays.setdefault(int(r["UiMapArtID"]), []).append({
            "id": int(r["ID"]), "x": int(r["OffsetX"]), "y": int(r["OffsetY"]),
            "w": int(r["TextureWidth"]), "h": int(r["TextureHeight"]),
            "tiles": sorted(overlay_tiles.get(int(r["ID"]), [])),
        })

    def continent_of(i):
        for _ in range(8):
            r = ui.get(i)
            if not r:
                return None
            if r["Type"] == "2":
                return i
            i = int(r["ParentUiMapID"])
        return None

    def bounds(uimap):
        a = assign[uimap][0]
        # world x runs north, world y runs west: Region_0/1 = min x/y, Region_3/4 = max x/y
        return float(a["Region_0"]), float(a["Region_1"]), float(a["Region_3"]), float(a["Region_4"])

    conts = {}
    for c in CONTINENTS:
        x0, y0, x1, y1 = bounds(c)
        conts[c] = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "width": y1 - y0, "height": x1 - x0}
    zones = []
    for i, r in sorted(ui.items()):
        if r["Type"] != "3":
            continue
        cont = continent_of(i)
        if cont not in CONTINENTS or i not in xart or i not in assign:
            continue
        if only and i not in only:
            continue
        a = art[xart[i][0]]
        lay = layers[int(a["UiMapArtStyleID"])]
        x0, y0, x1, y1 = bounds(i)
        zones.append({
            "id": i, "name": r["Name_lang"], "cont": cont,
            "tiles": sorted(tiles.get(xart[i][0], [])),
            "overlays": overlays.get(xart[i][0], []),
            "width": int(lay["LayerWidth"]), "height": int(lay["LayerHeight"]), "tile": int(lay["TileWidth"]),
            "x0": x0, "y0": y0, "x1": x1, "y1": y1,
        })
    return zones, conts


def zone_image_path(z):
    return os.path.join(ZONES, f"{z['id']}.png")


def explored_mask_path(z):
    return os.path.join(ZONES, f"{z['id']}_explored.png")


def stage_fetch(zones):
    jobs = []
    for z in zones:
        for _, _, fdid in z["tiles"]:
            jobs.append((WAGO_FILE.format(fdid=fdid, build=BUILD), os.path.join(TILES, f"{fdid}.blp")))
        for o in z["overlays"]:
            for _, _, fdid in o["tiles"]:
                jobs.append((WAGO_FILE.format(fdid=fdid, build=BUILD), os.path.join(TILES, f"{fdid}.blp")))
    todo = [j for j in jobs if not os.path.exists(j[1])]
    log(f"{len(jobs)} tiles for {len(zones)} zones, {len(todo)} to download")
    with ThreadPoolExecutor(max_workers=6) as pool:
        for i, _ in enumerate(pool.map(lambda j: fetch(*j), todo), 1):
            if i % 50 == 0:
                log(f"  {i}/{len(todo)}")
    log("tiles ready")


def stage_assemble(zones):
    os.makedirs(ZONES, exist_ok=True)
    for z in zones:
        out = zone_image_path(z)
        if os.path.exists(out) and os.path.exists(explored_mask_path(z)):
            continue
        t = z["tile"]
        cols = math.ceil(z["width"] / t)
        rows = math.ceil(z["height"] / t)
        canvas = Image.new("RGB", (cols * t, rows * t))
        for row, col, fdid in z["tiles"]:
            im = Image.open(os.path.join(TILES, f"{fdid}.blp")).convert("RGB")
            canvas.paste(im, (col * t, row * t))
        canvas = canvas.crop((0, 0, z["width"], z["height"])).convert("RGBA")
        # explored areas on top, each piece tiled from its top-left corner;
        # their alpha is kept apart, roads only exist on explored art
        explored = Image.new("L", canvas.size, 0)
        for o in z["overlays"]:
            piece = Image.new("RGBA", (max(o["w"], 1), max(o["h"], 1)), (0, 0, 0, 0))
            for row, col, fdid in o["tiles"]:
                im = Image.open(os.path.join(TILES, f"{fdid}.blp")).convert("RGBA")
                piece.paste(im, (col * t, row * t), im)
            canvas.alpha_composite(piece, (o["x"], o["y"]))
            explored.paste(piece.getchannel("A"), (o["x"], o["y"]), piece.getchannel("A"))
        canvas.convert("RGB").save(out)
        explored.save(explored_mask_path(z))
        log(f"  {z['id']} {z['name']}: {canvas.size[0]}x{canvas.size[1]}, {len(z['overlays'])} explored pieces")
    log("zone images ready in " + ZONES)


# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------

# How the roads are painted: a tan core line about five pixels wide with a
# dark brown outline on both sides, over green, brown, red or white ground.
# Mountain ridges, lake shores, labels and icons have dark outlines too. The
# mask asks for a light line with a darker line on BOTH sides (ridges have a
# shadow on one side, shores one dark line between two light areas), joins
# the pieces along their direction, thins them, then drops what is packed
# like a mountain mesh and what is too short to be a road.
TRACE = {
    "side": (2.5, 3.5, 4.5, 5.5),   # px from the road's centre line to the dark outline on each side
    "side_drop": 26,         # how much darker both outlines must be than the centre
    "join": 15,              # px; pieces found along one direction are joined over gaps up to this
    "hue": (26, 52),         # PIL hue 0..255 (42 = pure yellow, 30 = orange-tan)
    "sat": (60, 240),
    "val_min": 125,
    "explored_margin": 6,    # px; keep away from the edge of the explored art
    "density_window": 61,    # px; window for the line density around a thinned pixel
    "max_density": 0.068,    # line pixels per window pixel; a road is 0.03-0.06, a ridge mesh 0.07-0.12
    "min_skeleton": 80,      # px; thinned pieces shorter than this are dropped (letters, icons, ridge strokes)
    "max_branching": 0.3,    # junction pixels per skeleton pixel; icons branch far more
    "simplify": 1.5,         # px; polyline simplification tolerance
}


def line_footprint(length, deg):
    """A straight line of `length` px at `deg` degrees, as a morphology footprint."""
    from skimage.draw import line
    r = length // 2
    fp = np.zeros((2 * r + 1, 2 * r + 1), bool)
    th = math.radians(deg)
    dx, dy = math.cos(th) * r, math.sin(th) * r
    rr, cc = line(int(round(r - dy)), int(round(r - dx)), int(round(r + dy)), int(round(r + dx)))
    fp[rr, cc] = True
    return fp


def road_mask(img, explored=None):
    from scipy.ndimage import gaussian_filter, shift
    from skimage.morphology import closing, erosion, disk, remove_small_objects
    hsv = np.asarray(img.convert("HSV")).astype(np.int16)
    h, s = hsv[:, :, 0], hsv[:, :, 1]
    p = TRACE
    v = gaussian_filter(hsv[:, :, 2].astype(np.float32), 0.8)
    colour_ok = (h >= p["hue"][0]) & (h <= p["hue"][1]) & (s >= p["sat"][0]) & (s <= p["sat"][1]) & (v >= p["val_min"])
    if explored is not None:
        colour_ok &= erosion(np.asarray(explored) > 128, disk(p["explored_margin"]))
    mask = np.zeros(v.shape, bool)
    # the outlines are hand drawn and wobble, so on each side the darkest
    # pixel within a band of distances counts; the pieces found for one
    # direction are then joined along that direction, which mends a road
    # that fades in and out but leaves the short strokes of a ridge apart
    for deg in range(0, 180, 12):
        th = math.radians(deg)
        ux, uy = -math.sin(th), math.cos(th)
        side_a = np.full(v.shape, 1e9, np.float32)
        side_b = np.full(v.shape, 1e9, np.float32)
        for d in p["side"]:
            np.minimum(side_a, shift(v, (uy * d, ux * d), order=1, mode="nearest"), out=side_a)
            np.minimum(side_b, shift(v, (-uy * d, -ux * d), order=1, mode="nearest"), out=side_b)
        along = (np.minimum(v - side_a, v - side_b) > p["side_drop"]) & colour_ok
        mask |= closing(along, line_footprint(p["join"], deg))
    mask = closing(mask, disk(1))
    mask = remove_small_objects(mask, max_size=40)
    return mask


def prune_dense(skel, window, max_density):
    from scipy.ndimage import uniform_filter
    density = uniform_filter(skel.astype(np.float32), window)
    return skel & (density <= max_density)


def prune_branchy(skel, max_branching, min_size):
    from scipy.ndimage import convolve
    from skimage.measure import label
    lab = label(skel, connectivity=2)
    nb = convolve(skel.astype(np.int16), np.ones((3, 3), np.int16), mode="constant") - 1
    junction = skel & (nb >= 3)
    keep = np.zeros(lab.max() + 1, bool)
    sizes = np.bincount(lab.ravel())
    junctions = np.bincount(lab[junction], minlength=lab.max() + 1)
    for i in range(1, lab.max() + 1):
        if sizes[i] >= min_size and junctions[i] / sizes[i] <= max_branching:
            keep[i] = True
    return keep[lab]


def trace_zone(z):
    from skimage.morphology import skeletonize
    img = Image.open(zone_image_path(z)).convert("RGB")
    explored = Image.open(explored_mask_path(z)) if os.path.exists(explored_mask_path(z)) else None
    mask = road_mask(img, explored)
    skel = skeletonize(mask)
    skel = prune_dense(skel, TRACE["density_window"], TRACE["max_density"])
    skel = prune_branchy(skel, TRACE["max_branching"], TRACE["min_skeleton"])
    return img, mask, skel


# ---------------------------------------------------------------------------
# Skeleton -> polylines
# ---------------------------------------------------------------------------

def simplify(points, tol):
    """Douglas-Peucker."""
    if len(points) < 3:
        return points
    (x0, y0), (x1, y1) = points[0], points[-1]
    dx, dy = x1 - x0, y1 - y0
    norm = math.hypot(dx, dy) or 1.0
    best, idx = 0.0, 0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        d = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / norm
        if d > best:
            best, idx = d, i
    if best > tol:
        return simplify(points[:idx + 1], tol)[:-1] + simplify(points[idx:], tol)
    return [points[0], points[-1]]


def skeleton_polylines(skel, tol):
    """Split the thinned lines at junctions and walk each branch."""
    from scipy.ndimage import convolve
    nb = convolve(skel.astype(np.int16), np.ones((3, 3), np.int16), mode="constant") - 1
    junction = skel & (nb >= 3)
    H, W = skel.shape
    px = set(zip(*np.nonzero(skel)))       # (y, x)
    jn = set(zip(*np.nonzero(junction)))
    branches = px - jn
    visited = set()
    lines = []

    def neighbours(p, pool):
        y, x = p
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy or dx:
                    q = (y + dy, x + dx)
                    if q in pool:
                        yield q

    def endpoint_or_junction_neighbour(p):
        for q in neighbours(p, jn):
            return q
        return None

    for start in sorted(branches):
        if start in visited:
            continue
        deg = sum(1 for _ in neighbours(start, branches))
        if deg > 1:
            continue          # walk from the ends of each branch
        path = [start]
        visited.add(start)
        cur = start
        while True:
            nxt = [q for q in neighbours(cur, branches) if q not in visited]
            if not nxt:
                break
            cur = nxt[0]
            visited.add(cur)
            path.append(cur)
        # a junction at either end is part of the road: include it so branches meet
        j0 = endpoint_or_junction_neighbour(path[0])
        j1 = endpoint_or_junction_neighbour(path[-1])
        if j0:
            path.insert(0, j0)
        if j1:
            path.append(j1)
        pts = [(float(x), float(y)) for y, x in path]
        lines.append(simplify(pts, tol))
    # branches with no free end (loops) are walked from any pixel
    for start in sorted(branches - visited):
        if start in visited:
            continue
        path = [start]
        visited.add(start)
        cur = start
        while True:
            nxt = [q for q in neighbours(cur, branches) if q not in visited]
            if not nxt:
                break
            cur = nxt[0]
            visited.add(cur)
            path.append(cur)
        pts = [(float(x), float(y)) for y, x in path]
        if len(pts) > 2:
            lines.append(simplify(pts, tol))
    return lines


def polyline_length(pts):
    return sum(math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]) for i in range(1, len(pts)))


def stage_trace(zones, preview=True):
    os.makedirs(TRACES, exist_ok=True)
    os.makedirs(ROADS, exist_ok=True)
    segments = {}
    if os.path.exists(SEGMENTS):
        with open(SEGMENTS, encoding="utf-8") as fh:
            segments = json.load(fh).get("zones", {})
    for z in zones:
        img, mask, skel = trace_zone(z)
        lines = [l for l in skeleton_polylines(skel, TRACE["simplify"]) if polyline_length(l) >= 12]
        segments[str(z["id"])] = {
            "name": z["name"], "cont": z["cont"], "width": z["width"], "height": z["height"],
            "segments": [{"id": f"{z['id']}-{i}", "points": [[round(x, 1), round(y, 1)] for x, y in l]} for i, l in enumerate(lines)],
        }
        if preview:
            from skimage.morphology import dilation, disk
            over = np.asarray(img).copy()
            over[dilation(skel, disk(1))] = (255, 0, 0)
            Image.fromarray(over).save(os.path.join(TRACES, f"{z['id']}.png"))
        log(f"  {z['id']} {z['name']}: {int(skel.sum())} line px, {len(lines)} segments")
    with open(SEGMENTS, "w", encoding="utf-8") as fh:
        json.dump({"build": BUILD, "zones": segments}, fh, separators=(",", ":"))
    log(f"segments -> {SEGMENTS}; previews in {TRACES}")


# ---------------------------------------------------------------------------
# Graph
# ---------------------------------------------------------------------------

def zone_to_yards(z, cont):
    """Function mapping a zone image pixel to continent yards (east, south)."""
    W, H = z["width"], z["height"]
    zx0, zy0, zx1, zy1 = z["x0"], z["y0"], z["x1"], z["y1"]

    def f(px, py):
        u, v = px / W, py / H
        wy = zy1 - u * (zy1 - zy0)      # world y runs west, so map east is decreasing y
        wx = zx1 - v * (zx1 - zx0)      # world x runs north, so map south is decreasing x
        return cont["y1"] - wy, cont["x1"] - wx
    return f


def inner_maps(z, zones):
    """Zones drawn inside this one on its map (cities): their roads come from
    their own maps, so their area is left out here."""
    out = []
    for o in zones:
        if o is z or o["cont"] != z["cont"]:
            continue
        if o["x0"] >= z["x0"] and o["x1"] <= z["x1"] and o["y0"] >= z["y0"] and o["y1"] <= z["y1"]:
            out.append(o)
    return out


def load_review():
    if not os.path.exists(REVIEW):
        return {"removed": [], "added": {}}
    with open(REVIEW, encoding="utf-8") as fh:
        r = json.load(fh)
    return {"removed": r.get("removed", []), "added": r.get("added", {})}


def stage_bake(zones, conts):
    from scipy.spatial import cKDTree
    with open(SEGMENTS, encoding="utf-8") as fh:
        auto = json.load(fh)["zones"]
    review = load_review()
    removed = set(review["removed"])
    graphs = {c: {} for c in CONTINENTS}
    total_nodes, total_links = 0, 0
    for z in zones:
        entry = auto.get(str(z["id"]))
        if not entry:
            log(f"  {z['id']} {z['name']}: not traced yet")
            continue
        lines = [s["points"] for s in entry["segments"] if s["id"] not in removed]
        lines += [a["points"] for a in review["added"].get(str(z["id"]), [])]
        cont = conts[z["cont"]]
        to_yards = zone_to_yards(z, cont)
        inner = inner_maps(z, zones)
        g = graphs[z["cont"]]
        nodes = []           # (x, y) yards of the nodes placed in this zone
        keys = []

        def add_node(yx, yy):
            wy = cont["y1"] - yx
            wx = cont["x1"] - yy
            if any(o["x0"] <= wx <= o["x1"] and o["y0"] <= wy <= o["y1"] for o in inner):
                return None
            k = f"{int(math.floor(yx / CELL))}:{int(math.floor(yy / CELL))}"
            if k not in g:
                g[k] = [round(yx, 1), round(yy, 1), {}]
            nodes.append((yx, yy))
            keys.append(k)
            return k

        def link(ka, kb, cost):
            nonlocal total_links
            if ka == kb:
                return
            cost = round(cost, 1)
            if g[ka][2].get(kb) is None or g[ka][2][kb] > cost:
                g[ka][2][kb] = cost
                g[kb][2][ka] = cost
                total_links += 1

        for pts in lines:
            # walk the polyline placing a node every NODE_STEP yards
            ypts = [to_yards(x, y) for x, y in pts]
            prev_key, prev_pt, carry = None, None, 0.0
            first = True
            for i in range(len(ypts)):
                if i == 0:
                    k = add_node(*ypts[0])
                    prev_key, prev_pt = k, ypts[0]
                    continue
                ax, ay = ypts[i - 1]
                bx, by = ypts[i]
                seg = math.hypot(bx - ax, by - ay)
                at = NODE_STEP - carry
                while at < seg:
                    f = at / seg
                    k = add_node(ax + (bx - ax) * f, ay + (by - ay) * f)
                    if k and prev_key:
                        link(prev_key, k, math.hypot(ax + (bx - ax) * f - prev_pt[0], ay + (by - ay) * f - prev_pt[1]) / WALK)
                    if k:
                        prev_key, prev_pt = k, (ax + (bx - ax) * f, ay + (by - ay) * f)
                    at += NODE_STEP
                carry = seg - (at - NODE_STEP)
                if i == len(ypts) - 1:
                    k = add_node(bx, by)
                    if k and prev_key:
                        link(prev_key, k, math.hypot(bx - prev_pt[0], by - prev_pt[1]) / WALK)
        # crossings and segment ends: link nodes that came close to each other
        if nodes:
            tree = cKDTree(nodes)
            for a, b in tree.query_pairs(JOIN_YARDS):
                d = math.hypot(nodes[a][0] - nodes[b][0], nodes[a][1] - nodes[b][1])
                link(keys[a], keys[b], d / WALK)
        total_nodes += len(set(keys))
        log(f"  {z['id']} {z['name']}: {len(lines)} segments, {len(set(keys))} nodes")
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by Tools/trace_roads.py from the zone map art of build " + BUILD + ". Do not edit by hand.\n")
        fh.write("-- Roads traced from the maps for the Route module, in continent yards of the sizes below;\n")
        fh.write("-- graphs[continent uiMapID][cell] = { yards east, yards south, { [cell] = seconds } }.\n\n")
        fh.write("MelloUI_RoadData = {\n")
        fh.write(f'\tbuild = "{BUILD}",\n')
        fh.write("\tsizes = {\n")
        for c, b in conts.items():
            fh.write(f"\t\t[{c}] = {{ {b['width']:.1f}, {b['height']:.1f} }},\n")
        fh.write("\t},\n\tgraphs = {\n")
        for c, g in graphs.items():
            fh.write(f"\t\t[{c}] = {{\n")
            for k in sorted(g):
                x, y, ln = g[k]
                items = ",".join(f'["{o}"]={cost}' for o, cost in sorted(ln.items()))
                fh.write(f'\t\t\t["{k}"]={{{x},{y},{{{items}}}}},\n')
            fh.write("\t\t},\n")
        fh.write("\t},\n}\n")
    log(f"{total_nodes} nodes, {total_links} links -> {OUT} ({os.path.getsize(OUT) // 1024} KB)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stage", choices=["fetch", "assemble", "trace", "bake", "all"])
    ap.add_argument("--zone", type=int, action="append", help="only this uiMapID (repeatable)")
    a = ap.parse_args()
    zones, conts = load_zones(set(a.zone) if a.zone else None)
    log(f"{len(zones)} zones on {', '.join(CONTINENTS.values())}")
    for c, b in conts.items():
        log(f"  continent {c} {CONTINENTS[c]}: {b['width']:.1f} x {b['height']:.1f} yards")
    if a.stage in ("fetch", "all"):
        stage_fetch(zones)
    if a.stage in ("assemble", "all"):
        stage_assemble(zones)
    if a.stage in ("trace", "all"):
        stage_trace(zones)
    if a.stage in ("bake", "all"):
        stage_bake(zones, conts)


if __name__ == "__main__":
    main()
