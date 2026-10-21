"""MelloUI Map's data (docs/plans/seamless-map.md, stage M2; the user's picks 2026-10-20: C soft outlines, H places
not explored yet dimmed; then B of the zoom sketch: the world painting under everything, each continent's painting cut
to its land), made from the client's own tables as wow.export wrote them (F:/Download-Backup/WoWExport/db2): numbers
only, never a picture of the game's.

  MelloUI_Map/MapData.lua
      outline[uiMapID] = { x, y }        where a zone's name goes (0..1 of its art): the middle of its outline
      pieces[uiMapArtID] = { { w, h, x, y, fileID ... }, ... }
                                         every piece of a zone's map (WorldMapOverlay + its tiles), the explored and
                                         the not explored alike: the map draws the ones the client calls explored
                                         full and the rest faint
  MelloUI_Map/Media/Outlines/<uiMapID>.tga
                                         a zone's soft outline, a mask over its art: the union of its pieces' hit
                                         rectangles (WorldMapOverlay.HitRect*, in the art's own pixels), widened and
                                         blurred -- our geometry from the table's numbers, 128 x 128 for the art's
                                         1002 x 668; (2026-10-21, the user: "extend the zones to the coast") then
                                         stretched over the land beside it no zone covers, out to the terrain's true
                                         coast (the minimap's own pictures of each terrain tile tell land from
                                         water: their open water is near black), so its own painted coast shows;
                                         a hole between zones big enough to paint is left (Tools/map_gaps.py)
  MelloUI_Map/Media/Outlines/city.tga    a soft-edged rectangle (a city's art, which has no pieces)
  MapData.minimap[mapID]                 (M3, the user's pick A: the close zoom in the minimap's ground) the minimap's
                                         tiles of a continent's world map (Map.ID: 0 the Eastern Kingdoms, 1 Kalimdor):
                                         from its WDT (the client's own file, WoWExport/terrain_raw: the MAID table,
                                         one 533.33-yard tile an entry, its 8th field the minimap texture's file ID),
                                         placed on Azeroth (947) by its UiMapAssignment: x, y the north-west corner of
                                         tile (0, 0), w, h one tile, tiles the column, row and file of each
  MapData.minimapWater                   the file of a tile that is all open water (the Eastern Kingdoms' 28, 48): the
                                         sea past the tiles in the minimap's own water
  MelloUI_Map/Media/Outlines/<continent uiMapID>.tga
                                         a continent's land, a mask over its art (256 x 256 for its 1002 x 668): its
                                         zones' outlines laid where the client places each zone on it (UiMapAssignment),
                                         joined, a little wider and soft; MapData.land[uiMapID] = true for each

  MapData.caves[mapID]                   (after M4, the user 2026-10-20: "Caves at close zoom") each cave of a
                                         continent: a model of the client's (a WMO) placed in its terrain tiles'
                                         obj0 files (MODF: its file, place, turn and size; WoWExport/obj0_raw by the
                                         WDT's MAID 2nd field), with pictures in the client's WMOMinimapTexture (one a
                                         group of rooms and block of 128 units: its file, anchored at the group's
                                         corner, MOGI in the model's root file, WoWExport/wmo_root_raw, 2 px a unit,
                                         its rows from the bottom) and more than half of those rooms under the ground
                                         there (the root ADTs' heights): mines, caves, crypts, the underground halls --
                                         not a house's or a tower's floor plan, which would hide its roof. Per cave its
                                         origin in terrain tiles (x east, y south of the grid's 0, 0), its turn
                                         (degrees), its size, then each picture's file, anchor (the model's units) and
                                         file size (px; WoWExport/wmo_minimap_raw, its header)

  The caves' exports (wow.export's raw mode, by file ID): the obj0 files of every tile (MAID's 2nd field), the root
  files of the models they place, the WMOMinimapTexture table (db2) and the pictures of the caves found (their size
  only is read).

Masks as MelloUI's others: 32-bit TGA, top-left origin, white with the same alpha (colour and alpha both say it).
Deterministic: the same tables give the same bytes.

    python Tools/build_map_data.py            write them
    python Tools/build_map_data.py --check    exit 1 unless every file is up to date
"""
import csv
import io
import math
import os
import struct
import sys
from collections import defaultdict

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB2 = r"F:/Download-Backup/WoWExport/db2/"
MAP = os.path.join(ROOT, "MelloUI_Map")
DATA = os.path.join(MAP, "MapData.lua")
OUTLINES = os.path.join(MAP, "Media", "Outlines")

ART_W, ART_H = 1002, 668        # a zone map's art layer
Q = 4                           # the outlines drawn at a quarter of it (the masks are 128 px: the same shapes, faster)
QW, QH = (ART_W + Q - 1) // Q, (ART_H + Q - 1) // Q
SIZE = 128                      # a mask's side
GROW, BLUR = 30, 24             # the outline: the hit rectangles widened, then softened (art px; the sketch's pick)
EDGE = 40                       # ... and faded out before the art's own edge (art px): a zone's land that reaches the
                                # border of its picture would end there in a hard line (the neighbour's picture covers it)
CITY_EDGE = 12                  # the city mask's soft edge (mask px)
PIECE_TRIM = 0.15               # a piece with no hit rectangle: its picture's rectangle, this share in from each side
TERRAIN_MAP = {1414: 1, 1415: 0}   # each continent's world map (Map.ID): the terrain its coasts are taken from
TERRAIN_ART = ("map_m3_png", ".png"), ("map_zoom_png", ".png"), ("map_gap_raw", ".blp")   # (WoWExport: the minimap's
                                # pictures by file ID, exported for the close zoom and for the gaps)
TILE_PX = 32                    # a terrain tile's minimap picture read at this size for the land
WATER_LUM = 22                  # the minimap draws open water near black (its all-sea tile: about 5): darker than
                                # this, smoothed over a few px, is water
LAKE = 900                      # water enclosed by land, smaller than this (continent art px), is a lake: land
COAST_SCALE = 2                 # the coasts worked out at twice the continent painting's size (smoother shapes)
COAST_REACH = 60                # a zone takes uncovered land up to this far from its outline (continent art px)
COAST_SEA = 3                   # ... its outline then reaching this far past the land, softly (quarter px)
HOLE_AREA, HOLE_RINGED = 600, 0.6   # uncovered land this big (continent art px), this share of its edge on zones'
                                # outlines, is a hole between zones: left to paint (Tools/map_gaps.py)
CONTINENT, ZONE = 2, 3          # UIMapType
LAND_SIZE = 256                 # a continent's land mask's side (its zones' outlines need more than a zone's 128)
LAND_GROW, LAND_BLUR = 3, 2     # its zones' outlines joined, then widened and softened (quarter px)
TERRAIN = r"F:/Download-Backup/WoWExport/terrain_raw/"
WDT = {0: 775971, 1: 782779}    # each continent's world map (Map.ID): its WDT's file ID (Map.WdtFileDataID)
TILE = 1600.0 / 3.0             # yards a terrain tile
WATER_TILE = (0, 28, 48)        # an Eastern Kingdoms tile that is all open sea (west of Stormwind's harbour)
EXPORT = r"F:/Download-Backup/WoWExport/"
CAVE_SHARE = 0.5                # a model is a cave when more than this share of its pictured rooms (by area) is under
                                # the ground: 676 placed models at 0, 298 at 1, a handful between (Sunken Hollow .59)
CAVE_BLOCK = 128                # the model's units a picture's block (256 px at 2 px a unit)


def rows(name):
    return list(csv.DictReader(open(DB2 + name + ".csv", encoding="utf-8")))


def tga(img):
    """32-bit uncompressed TGA, top-left origin: white, the image's L as the alpha"""
    w, h = img.size
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    body = bytearray()
    px = img.load()
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            body += bytes((v, v, v, v))
    return head + bytes(body)


# A map's rectangle on another (0..1 there), as the client's C_Map.GetMapRectOnMap works it out: the map's world
# region (its own UiMapAssignment) carried through the other's assignment of the same world map (MapID)
def region(a):
    # (Region_0..2: the least x, y, z of the world region; Region_3..5 the most; world x runs north, y west)
    return float(a["Region_0"]), float(a["Region_1"]), float(a["Region_3"]), float(a["Region_4"])


def to_ui(a, wx, wy):
    x0, y0, x1, y1 = region(a)
    u0, v0, u1, v1 = float(a["UiMin_0"]), float(a["UiMin_1"]), float(a["UiMax_0"]), float(a["UiMax_1"])
    return u0 + (y1 - wy) / (y1 - y0) * (u1 - u0), v0 + (x1 - wx) / (x1 - x0) * (v1 - v0)


def rect_on(assign, child, top):
    """(x0, x1, y0, y1) of child on top, 0..1; None when the tables do not place it there"""
    own = [a for a in assign.get(child, []) if a["OrderIndex"] == "0"] or assign.get(child, [])
    if not own:
        return None
    a = own[0]
    x0, y0, x1, y1 = region(a)
    for t in assign.get(top, []):
        if t["MapID"] != a["MapID"]:
            continue
        tx0, ty0, tx1, ty1 = region(t)
        if tx0 <= x0 and x1 <= tx1 and ty0 <= y0 and y1 <= ty1:
            ua, va = to_ui(t, x1, y1)
            ub, vb = to_ui(t, x0, y0)
            return min(ua, ub), max(ua, ub), min(va, vb), max(va, vb)
    return None


def minimap_tiles(assign, mapID):
    """the minimap's tiles of a continent's world map: its grid on Azeroth (x, y, w, h: 0..1) and [(tx, ty, file)]"""
    path = TERRAIN + "%d.wdt" % WDT[mapID]
    if not os.path.isfile(path):
        return None
    data = open(path, "rb").read()
    maid, pos = None, 0
    while pos + 8 <= len(data):
        tag = data[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        if tag == b"MAID":
            maid = pos + 8
        pos += 8 + size
    world = None
    for a in assign.get(947, []):
        if int(a["MapID"]) == mapID:
            x0, y0, x1, y1 = region(a)
            if world is None or (x1 - x0) * (y1 - y0) > world[0]:
                world = ((x1 - x0) * (y1 - y0), a)
    if maid is None or world is None:
        return None
    a, edge = world[1], 32 * TILE
    # (tile (tx, ty)'s north-west corner: world x = edge - ty * TILE (north), y = edge - tx * TILE (west))
    u0, v0 = to_ui(a, edge, edge)
    u1, v1 = to_ui(a, edge - TILE, edge - TILE)
    tiles = []
    for k in range(4096):
        fid = struct.unpack_from("<8I", data, maid + k * 32)[7]
        if fid:
            tiles.append((k % 64, k // 64, fid))
    return (u0, v0, u1 - u0, v1 - v0), tiles


def chunks(data):
    """a chunked file's chunks: tag (read forwards), start, size"""
    pos = 0
    while pos + 8 <= len(data):
        tag = data[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        yield tag, pos + 8, size
        pos += 8 + size


def maid(mapID):
    """a continent's WDT's MAID: the 8 file IDs of each of its 4096 tiles, or None"""
    path = TERRAIN + "%d.wdt" % WDT[mapID]
    if not os.path.isfile(path):
        return None
    data = open(path, "rb").read()
    at = next((p for t, p, _ in chunks(data) if t == b"MAID"), None)
    return None if at is None else [struct.unpack_from("<8I", data, at + k * 32) for k in range(4096)]


_ground = {}


def ground(tiles, mapID, px, pz):
    """the terrain's height at a point (yards east, south of the grid's 0, 0): the nearest of its chunk's 9 x 9"""
    tx, ty = int(px // TILE), int(pz // TILE)
    key = (mapID, tx, ty)
    if key not in _ground:
        cs = []
        fid = tiles[ty * 64 + tx][0] if 0 <= tx < 64 and 0 <= ty < 64 else 0
        path = TERRAIN + "%d.adt" % fid
        if fid and os.path.isfile(path):
            adt = open(path, "rb").read()
            for tag, p, size in chunks(adt):
                if tag == b"MCNK":
                    wx, wy, wz = struct.unpack_from("<3f", adt, p + 0x68)
                    for t2, p2, _ in chunks(adt[p + 128:p + size]):
                        if t2 == b"MCVT":
                            cs.append((32 * TILE - wy, 32 * TILE - wx, wz, struct.unpack_from("<145f", adt, p + 128 + p2)))
        _ground[key] = cs
    step = TILE / 16
    for px0, pz0, wz, h in _ground[key]:
        if px0 <= px < px0 + step and pz0 <= pz < pz0 + step:
            c = min(8, max(0, int(round((px - px0) / (step / 8)))))
            r = min(8, max(0, int(round((pz - pz0) / (step / 8)))))
            return wz + h[r * 17 + c]
    return None


def cave_list(mapID):
    """a continent's caves: [(x, y, turn, size, [(file, ax, ay, w, h), ...])] (see MapData.caves)"""
    tiles = maid(mapID)
    table = DB2 + "WMOMinimapTexture.csv"
    if tiles is None or not os.path.isfile(table):
        return []
    pictures = defaultdict(list)
    for r in rows("WMOMinimapTexture"):
        pictures[int(r["WMOID"])].append((int(r["GroupNum"]), int(r["BlockX"]), int(r["BlockY"]), int(r["FileDataID"])))
    placed, seen = [], set()
    for k in range(4096):
        path = EXPORT + "obj0_raw/%d.adt" % tiles[k][1]
        if not tiles[k][1] or not os.path.isfile(path):
            continue
        adt = open(path, "rb").read()
        for tag, p, size in chunks(adt):
            if tag != b"MODF":
                continue
            for i in range(size // 64):
                e = struct.unpack_from("<II3f3f6fHHHH", adt, p + i * 64)
                if e[1] in seen or not e[14] & 0x8:   # (each placement once; its model by file ID)
                    continue
                seen.add(e[1])
                placed.append((e[1], e[0], e[2:5], e[6], (e[17] or 1024) / 1024.0))
    roots = {}
    out = []
    for uid, fid, pos, turn, scale in sorted(placed):
        if fid not in roots:
            path = EXPORT + "wmo_root_raw/%d.wmo" % fid
            info = None
            if os.path.isfile(path):
                data = open(path, "rb").read()
                wmo, groups = None, []
                for tag, p, size in chunks(data):
                    if tag == b"MOHD":
                        wmo = struct.unpack_from("<I", data, p + 32)[0]
                    elif tag == b"MOGI":
                        groups = [struct.unpack_from("<6f", data, p + i * 32 + 4) for i in range(size // 32)]
                info = (wmo, groups)
            roots[fid] = info
        info = roots[fid]
        if not info or info[0] not in pictures:
            continue
        wmo, groups = info
        th = math.radians(90 - turn)
        c, s = math.cos(th), math.sin(th)
        under = total = 0.0
        pics = []
        for g, bx, by, file in sorted(pictures[wmo]):
            if g >= len(groups):
                continue
            b = groups[g]
            if bx == 0 and by == 0:
                lx, ly = (b[0] + b[3]) / 2 * scale, (b[1] + b[4]) / 2 * scale
                h = ground(tiles, mapID, pos[0] + lx * c + ly * s, pos[2] + lx * s - ly * c)
                area = (b[3] - b[0]) * (b[4] - b[1])
                total += area
                if h is not None and pos[1] + b[5] * scale < h - 1:
                    under += area
            path = EXPORT + "wmo_minimap_raw/%d.blp" % file
            if os.path.isfile(path):
                w, hh = struct.unpack_from("<2I", open(path, "rb").read(20), 12)
                pics.append((file, round(b[0] + bx * CAVE_BLOCK, 2), round(b[1] + by * CAVE_BLOCK, 2), w, hh))
        if total and under / total > CAVE_SHARE and pics:
            out.append((round(pos[0] / TILE, 5), round(pos[2] / TILE, 5), round(turn, 2), round(scale, 4), pics))
    return out


def continent_land(assign, cont, zone_masks):
    """a continent's land on its own art (quarter size): its zones' outlines where the client places them on it"""
    out = Image.new("L", (QW, QH), 0)
    for mid, mask in sorted(zone_masks.items()):
        r = rect_on(assign, mid, cont)
        if not r:
            continue
        w, h = int(round((r[1] - r[0]) * QW)), int(round((r[3] - r[2]) * QH))
        if w < 2 or h < 2:
            continue
        tmp = Image.new("L", (QW, QH), 0)
        tmp.paste(mask.resize((w, h), Image.BILINEAR), (int(round(r[0] * QW)), int(round(r[2] * QH))))
        out = ImageChops.lighter(out, tmp)
    if not out.getbbox():
        return None
    return out.filter(ImageFilter.MaxFilter(LAND_GROW * 2 + 1)).filter(ImageFilter.GaussianBlur(LAND_BLUR))


_fade = []


def edge_fade():
    """1 inside, falling to 0 over EDGE px toward the art's four edges (our geometry)"""
    if not _fade:
        e = EDGE / Q
        m = Image.new("L", (QW, QH), 0)
        ImageDraw.Draw(m).rectangle((e, e, QW - 1 - e, QH - 1 - e), fill=255)
        _fade.append(m.filter(ImageFilter.GaussianBlur(e / 2)))
    return _fade[0]


def city_mask():
    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).rectangle((CITY_EDGE, CITY_EDGE, SIZE - 1 - CITY_EDGE, SIZE - 1 - CITY_EDGE), fill=255)
    return m.filter(ImageFilter.GaussianBlur(CITY_EDGE / 2))


def zone_mask(ovs):
    """a zone's soft outline on its art (quarter size): the union of its pieces' hit rectangles (WorldMapOverlay
    HitRect*, in the art's own pixels), widened, blurred and faded before the art's edge; None when it has none
    (also Tools/map_gaps.py's: the gaps are measured against the very masks the map draws)"""
    mask = Image.new("L", (QW, QH), 0)
    d = ImageDraw.Draw(mask)
    for o in ovs:
        l, t, r, b = (int(o["HitRectLeft"]), int(o["HitRectTop"]), int(o["HitRectRight"]), int(o["HitRectBottom"]))
        if not (r > l and b > t):
            # (2026-10-21, Tools/map_gaps.py's first sheet: a piece with no hit rectangle -- Silithus's middle,
            # parts of Mulgore, Azshara, Tirisfal, the Eastern Plaguelands, Dun Morogh, the Wetlands -- was cut out
            # of its zone: its picture's own rectangle instead, PIECE_TRIM in from each side, its margins being clear)
            x, y, w, h = int(o["OffsetX"]), int(o["OffsetY"]), int(o["TextureWidth"]), int(o["TextureHeight"])
            l, t, r, b = x + w * PIECE_TRIM, y + h * PIECE_TRIM, x + w * (1 - PIECE_TRIM), y + h * (1 - PIECE_TRIM)
        if r > l and b > t:
            d.rectangle((l / Q, t / Q, r / Q, b / Q), fill=255)
    if not mask.getbbox():
        return None
    mask = mask.filter(ImageFilter.MaxFilter((GROW // Q) * 2 + 1)).filter(ImageFilter.GaussianBlur(BLUR / Q))
    return Image.composite(mask, Image.new("L", mask.size, 0), edge_fade())


def terrain_art(fid):
    for d, ext in TERRAIN_ART:
        p = EXPORT + d + "/" + str(fid) + ext
        if os.path.exists(p):
            return p
    return None


def terrain_land(assign, cont, scale=1):
    """a continent's land where its painting lies (bool, its art px times scale): the terrain's, from the minimap's
    own pictures of every terrain tile (water near black; where there is no tile, sea), placed with the
    continent's own assignment as the map places the minimap ground; small lakes count as land. None when the
    continent has no terrain here"""
    import numpy as np
    import cv2
    if cont not in TERRAIN_MAP:
        return None
    got = minimap_tiles(assign, TERRAIN_MAP[cont])
    world = None
    for a in assign.get(cont, []):
        if int(a["MapID"]) == TERRAIN_MAP[cont]:
            x0, y0, x1, y1 = region(a)
            if world is None or (x1 - x0) * (y1 - y0) > world[0]:
                world = ((x1 - x0) * (y1 - y0), a)
    if not got or world is None:
        return None
    a, edge = world[1], 32 * TILE
    u0, v0 = to_ui(a, edge, edge)
    u1, v1 = to_ui(a, edge - TILE, edge - TILE)
    du, dv = u1 - u0, v1 - v0
    # (the land of every tile, read once: 1,700 pictures take minutes; kept beside the build's other local data,
    # under the tiles' list and the reading's numbers)
    import hashlib
    key = hashlib.sha1(repr((got[1], TILE_PX, WATER_LUM)).encode()).hexdigest()[:12]
    cache = os.path.join(os.path.dirname(ROOT), "MelloUI-BuildData", "cache", "terrain_land_%d_%s.png" % (TERRAIN_MAP[cont], key))
    if os.path.isfile(cache):
        grid = Image.open(cache).convert("L")
    else:
        grid = Image.new("L", (64 * TILE_PX, 64 * TILE_PX), 0)
        for tx, ty, fid in got[1]:
            path = terrain_art(fid)
            if path:
                g = Image.open(path).convert("L").filter(ImageFilter.BoxBlur(3)).resize((TILE_PX, TILE_PX), Image.BOX)
                grid.paste(g.point(lambda v: 255 if v >= WATER_LUM else 0), (tx * TILE_PX, ty * TILE_PX))
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        grid.save(cache)
    W, H = ART_W * scale, ART_H * scale
    # (an art pixel's middle, as a place on the continent (0..1), in the tiles' grid at TILE_PX a tile)
    land = grid.transform((W, H), Image.AFFINE, (TILE_PX / (W * du), 0, (0.5 / W - u0) / du * TILE_PX,
                                                 0, TILE_PX / (H * dv), (0.5 / H - v0) / dv * TILE_PX), Image.BILINEAR)
    keep = np.asarray(land) > 127
    n, lab, stats, _ = cv2.connectedComponentsWithStats((~keep).astype(np.uint8), 4)
    for i in range(1, n):
        x, y, w, h = stats[i, :4]
        if x > 0 and y > 0 and x + w < W and y + h < H and stats[i, cv2.CC_STAT_AREA] < LAKE * scale * scale:
            keep |= lab == i
    return keep


def placed(assign, cont, masks, scale=1):
    """each zone's outline where the client places it on the continent: {uiMapID: uint8 array (its art px x scale)}"""
    import numpy as np
    W, H = ART_W * scale, ART_H * scale
    out = {}
    for mid in sorted(masks):
        r = rect_on(assign, mid, cont)
        if not r:
            continue
        w, h = int(round((r[1] - r[0]) * W)), int(round((r[3] - r[2]) * H))
        if w < 2 or h < 2:
            continue
        m = np.zeros((H, W), np.uint8)
        sm = np.asarray(masks[mid].resize((w, h), Image.BILINEAR))
        X, Y = int(round(r[0] * W)), int(round(r[2] * H))
        xa, ya, xb, yb = max(X, 0), max(Y, 0), min(X + w, W), min(Y + h, H)
        if xb > xa and yb > ya:
            m[ya:yb, xa:xb] = sm[ya - Y:yb - Y, xa - X:xb - X]
            out[mid] = m
    return out


def coast_extend(assign, cont, masks):
    """(the user, 2026-10-21: "extend the zones to the coast") each zone's outline stretched over the uncovered land
    nearest it, out to the terrain's coast and softly past it into its own painted sea; a hole between zones big
    enough to paint is left as it is. masks: {uiMapID: quarter-size L}; the same, stretched"""
    import numpy as np
    import cv2
    S = COAST_SCALE
    land = terrain_land(assign, cont, S)
    if land is None:
        return masks
    on = placed(assign, cont, masks, S)
    cover = np.zeros(land.shape, np.uint8)
    for m in on.values():
        cover = np.maximum(cover, m)
    covered = cover >= 128
    strip = land & ~covered
    n, lab, stats, _ = cv2.connectedComponentsWithStats(strip.astype(np.uint8), 8)
    take = np.zeros(land.shape, bool)
    for i in range(1, n):
        m = lab == i
        ring = (cv2.dilate(m.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0) & ~m
        ringed = float((ring & covered).sum()) / max(1, int(ring.sum()))
        if stats[i, cv2.CC_STAT_AREA] >= HOLE_AREA * S * S and ringed >= HOLE_RINGED:
            continue
        take |= m
    best = np.full(land.shape, np.inf, np.float32)
    owner = np.full(land.shape, -1, np.int32)
    order = sorted(on)
    for k, mid in enumerate(order):
        d = cv2.distanceTransform((on[mid] < 128).astype(np.uint8), cv2.DIST_L2, 5)
        win = take & (d < best) & (d <= COAST_REACH * S)
        owner[win], best[win] = k, d[win]
    out = dict(masks)
    W, H = ART_W * S, ART_H * S
    for k, mid in enumerate(order):
        share = owner == k
        if not share.any():
            continue
        x0, x1, y0, y1 = rect_on(assign, mid, cont)
        # (the zone's quarter grid from the continent's: a quarter pixel's middle on the continent)
        a, e = (x1 - x0) * W / QW, (y1 - y0) * H / QH
        ext = Image.fromarray((share * 255).astype(np.uint8)).transform(
            (QW, QH), Image.AFFINE, (a, 0, x0 * W + a / 2 - 0.5, 0, e, y0 * H + e / 2 - 0.5), Image.BILINEAR)
        ext = ext.filter(ImageFilter.MaxFilter(COAST_SEA * 2 + 1)).filter(ImageFilter.GaussianBlur(COAST_SEA))
        ext = Image.composite(ext, Image.new("L", ext.size, 0), edge_fade())
        out[mid] = ImageChops.lighter(masks[mid], ext)
    return out


def build():
    maps = {int(r["ID"]): r for r in rows("UiMap")}
    art_of = {}
    for r in rows("UiMapXMapArt"):
        art_of.setdefault(int(r["UiMapID"]), int(r["UiMapArtID"]))
    overlays = defaultdict(list)
    for r in rows("WorldMapOverlay"):
        overlays[int(r["UiMapArtID"])].append(r)
    otiles = defaultdict(list)
    for r in rows("WorldMapOverlayTile"):
        if r["LayerIndex"] == "0":
            otiles[int(r["WorldMapOverlayID"])].append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
    assign = defaultdict(list)
    for r in rows("UiMapAssignment"):
        assign[int(r["UiMapID"])].append(r)
    files, outline, pieces, zone_masks = {}, {}, {}, defaultdict(dict)
    for mid in sorted(maps):
        if int(maps[mid]["Type"]) != ZONE or mid not in art_of:
            continue
        art = art_of[mid]
        ovs = sorted(overlays.get(art, []), key=lambda r: int(r["ID"]))
        if not ovs:
            continue
        plist = []
        for o in ovs:
            tl = [f for _, _, f in sorted(otiles[int(o["ID"])])]
            if tl:
                plist.append([int(o["TextureWidth"]), int(o["TextureHeight"]), int(o["OffsetX"]), int(o["OffsetY"])] + tl)
        mask = zone_mask(ovs)
        if mask is None or not plist:
            continue
        zone_masks[int(maps[mid]["ParentUiMapID"])][mid] = mask
        # (the name in the middle of the zone's own land: the outline before its coast is stretched)
        bb = mask.point(lambda v: 255 if v > 128 else 0).getbbox() or mask.getbbox()
        outline[mid] = (round((bb[0] + bb[2]) / 2 / QW, 3), round((bb[1] + bb[3]) / 2 / QH, 3))
        pieces[art] = plist
    for cont in sorted(zone_masks):
        zone_masks[cont] = coast_extend(assign, cont, zone_masks[cont])
        for mid, mask in zone_masks[cont].items():
            files["%d.tga" % mid] = tga(mask.resize((SIZE, SIZE), Image.LANCZOS))
    files["city.tga"] = tga(city_mask())
    land = []
    for cont in sorted(zone_masks):
        if cont in maps and int(maps[cont]["Type"]) == CONTINENT:
            m = continent_land(assign, cont, zone_masks[cont])
            if m is not None:
                files["%d.tga" % cont] = tga(m.resize((LAND_SIZE, LAND_SIZE), Image.LANCZOS))
                land.append(cont)
    out = ["-- MelloUI Map's data, made by Tools/build_map_data.py from the client's own tables (WoWExport/db2):",
           "-- numbers only; never edit by hand (run the tool). docs/plans/seamless-map.md, stage M2.",
           "local _, ns = ...",
           "ns.MapData = {",
           "\t-- [uiMapID] = { x, y }: where a zone's name goes (0..1 of its art); a zone with one has an outline mask",
           "\toutline = {"]
    for mid in sorted(outline):
        out.append("\t\t[%d] = { %s, %s }," % (mid, outline[mid][0], outline[mid][1]))
    out += ["\t},",
            "\t-- [uiMapArtID] = { { w, h, x, y, fileID ... } }: every piece of the zone's map, explored or not",
            "\tpieces = {"]
    for art in sorted(pieces):
        out.append("\t\t[%d] = { %s }," % (art, ", ".join("{ " + ", ".join(str(v) for v in p) + " }" for p in pieces[art])))
    out += ["\t},",
            "\t-- [uiMapID] = true: a continent whose painting is cut to its land (its outline mask)",
            "\tland = { %s }," % ", ".join("[%d] = true" % c for c in land),
            "\t-- (M3) [mapID] = { x, y, w, h: the minimap's tile grid on Azeroth (947, 0..1), tiles: column, row, file ... }",
            "\tminimap = {"]
    water = None
    for mapID in sorted(WDT):
        got = minimap_tiles(assign, mapID)
        if not got:
            continue
        (x, y, w, h), tiles = got
        out.append("\t\t[%d] = { x = %.7f, y = %.7f, w = %.7f, h = %.7f, tiles = {" % (mapID, x, y, w, h))
        for i in range(0, len(tiles), 8):
            out.append("\t\t\t" + " ".join("%d, %d, %d," % t for t in tiles[i:i + 8]))
        out.append("\t\t} },")
        if mapID == WATER_TILE[0]:
            water = next((f for tx, ty, f in tiles if (tx, ty) == WATER_TILE[1:]), None)
    out += ["\t},",
            "\t-- (M3) the file of a tile that is all open sea: the sea past the minimap's tiles",
            "\tminimapWater = %s," % (water or "nil"),
            "\t-- (after M4) [mapID] = { { x, y (terrain tiles east, south of the minimap grid's 0, 0), turn (degrees),",
            "\t-- size, { file, ax, ay (the anchor in the model's units), w, h (the file's px) ... } } }: the caves",
            "\tcaves = {"]
    for mapID in sorted(WDT):
        caves = cave_list(mapID)
        if not caves:
            continue
        out.append("\t\t[%d] = {" % mapID)
        for x, y, turn, size, pics in caves:
            out.append("\t\t\t{ %s, %s, %s, %s, { %s } }," % (x, y, turn, size, ", ".join(
                "%d, %s, %s, %d, %d" % pic for pic in pics)))
        out.append("\t\t},")
    out += ["\t},",
            "}", ""]
    return "\n".join(out), files


def main():
    check = "--check" in sys.argv[1:]
    lua, files = build()
    stale = []
    want = [(DATA, lua.encode("utf-8"))] + [(os.path.join(OUTLINES, n), b) for n, b in sorted(files.items())]
    for path, data in want:
        old = open(path, "rb").read() if os.path.isfile(path) else None
        if old != data:
            stale.append(os.path.relpath(path, ROOT))
            if not check:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, "wb").write(data)
    if check:
        print("map data: %s" % ("up to date" if not stale else "%d stale: %s" % (len(stale), ", ".join(stale[:5]))))
        sys.exit(1 if stale else 0)
    print("map data: %d outlines, %d files written" % (len(files) - 1, len(stale)))


if __name__ == "__main__":
    main()
