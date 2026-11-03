"""
build_dungeon_maps.py -- the dungeon maps' data (MelloUI_Map/MapDungeons.lua) and art (MelloUI_Map/Media/Dungeons).

The user, 2026-11-02: "once inside of the dungeon, to open the dungeon map, with boss positions and loot seen on the
right side of the map"; the look: B of Workspace/BuildData/output/dungeonmap_sketch (slate); then "Several floors, we
need to spread them into Wings, floor plans for forever dungeons". Plan: docs/plans/dungeon-map.md.

The client has no dungeon maps (no UiMap of an instance), so each one is laid from what the minimap draws inside:
  rooms     the client's floor pictures (WMOMinimapTexture: one a model's group of rooms and block of 128 units, 2 px
            a unit, anchored at the group's corner, its rows from the bottom), placed as the instance's own files
            place each model (the WDT's MODF for a map of one model, else its tiles' obj0 MODF) -- the same layout as
            the map's caves (build_map_data.cave_list, MapCanvas CavePlace). The client's own files by file ID: none
            of its art ships.
  ground    the instance map's own minimap tiles (its WDT's MAID), by file ID.
  edge      MelloUI's own: the rooms' outline (a hairline and a soft glow round everything walkable), white, tinted
            at runtime by the palette; BLP DXT5 tiles of 512 px (256 yards).
  cove      MelloUI's own: the parts open to the sky (the outdoor groups of a model with rooms, which have no
            pictures: The Deadmines' ship and docks) drawn from above out of the model's own triangles, each in its
            material's average colour, lit from the north-west; BLP DXT5 tiles as the edge's.
  wings     a dungeon of several floors split so no two floors lie on each other: each group of rooms (and each part
            open to the sky) a unit with its footprint (from above) and its floor's height; two units that cover the
            same ground at heights more than ZSEP apart go to different wings, the lowest first; a unit then joins the
            wing its neighbours at its height are in, and wings with nothing on each other's ground are one; a wing
            with no boss and little ground (SMALL) joins the wing it touches, drawn over it. Each wing
            is named by the game's own area name of most of its rooms (WMOAreaTable: what the minimap names as you walk
            in, its group's MOGP uniqueID), and lists the area names that are most of all its own (the map shows the
            wing you are in by GetMinimapZoneText). A dungeon of one floor is one wing.
  doors     (the user, 2026-11-02: "show where the entrances and exits are in the dungeon, and arrows in specific spots
            where you enter other wings") where you come in -- the classic database's teleports into the instance
            (areatrigger_teleport's target), the way out the same door -- in the wing whose rooms are there.
  links     the doorways between two wings: the model's own portals (MOPV, MOPT, MOPR in its root) between a group of
            one wing and a group of another, or reached through groups of no wing (corridors with no picture) within
            LINK_STEPS; standing (not flat) and no wider or taller than LINK_MAX (the rest are openings to look
            through); at the portal's middle, up or down by the groups' floors; one a pair of wings within LINK_APART.
  bosses    Dungeon Info's bosses in its order (MelloUI_DungeonInfo/DungeonInfoData.lua), each where the classic
            database spawns its creature on the instance's map (the creature of its name, as build_dungeoninfo.py
            matches them), in the wing whose rooms are under that spot at its height; a boss spawned nowhere (summoned
            in his fight) has no place. GPL-3.0 data (cmangos).

Only the instances with a door on the world map (the Quest List's entrances: Forever's doors) get a plan. With two or
more bosses placed, only the models with rooms within NEAR of them are drawn (a dungeon in open land has far caves and
huts on its map).

The files come from wago.tools by the client's build (the source wowsim's fetch_forever.py uses), kept in
Workspace/BuildData/cache/dungeonmap/raw (only what is missing is fetched). Pictures are read with Pillow.

    python Tools/build_dungeon_maps.py            all of Dungeon Info's instances with a door on the world map
    python Tools/build_dungeon_maps.py 36 33      only these instance maps (the data file keeps the others)
    python Tools/build_dungeon_maps.py --check    the data file matches the art on disk (no fetch, no writes)

Coordinates: the game's world position (x north, y west) is E = 32 * TILE - y yards east and S = 32 * TILE - x yards
south of the terrain grid's 0, 0; a plan's e0, s0 is its top left there, its w, h its size in yards.
"""
import csv
import importlib.util
import io
import math
import os
import re
import struct
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import blp_dxt  # noqa: E402
import paths  # noqa: E402

REPO = paths.ADDON
DB2 = os.path.join(paths.WORKSPACE, "GameData", "WoWExport", "db2")
CACHE = os.path.join(paths.CACHE, "dungeonmap", "raw")
LISTFILE = os.path.join(paths.WORKSPACE, "Software", "wowsim", "assets", "blizzard", "_forever-1.60.1.70425", "_work",
                        "listfile-wago.csv")
DI_DATA = os.path.join(REPO, "MelloUI_DungeonInfo", "DungeonInfoData.lua")
QUESTS = os.path.join(REPO, "Media", "QuestListData.lua")   # (its entrances: the doors on the world map)
OUT = os.path.join(REPO, "MelloUI_Map", "MapDungeons.lua")
ART = os.path.join(REPO, "MelloUI_Map", "Media", "Dungeons")
BUILD = "1.60.1.70425"
WAGO = "https://wago.tools/api/casc/%d?download&version=" + BUILD
AGENT = "MelloUI build_dungeon_maps (dev tool)"

TILE = 1600.0 / 3.0          # yards a terrain tile
EDGE_W = 32 * TILE           # the grid's 0, 0 from the world's middle
K = 2.0                      # px a yard: the floor pictures' own density, the art's
KL = 0.5                     # px a yard: the units' footprints (the wings' split)
BLOCK = 128                  # a floor picture's block, in the model's units
ART_PX = 512                 # an art tile (256 yards)
MARGIN = 26.0                # yards round a plan
NEAR = 200.0                 # yards round the bosses a model of the dungeon reaches into (two or more bosses placed)
SKY = 600.0                  # an outdoor group this wide: the model's sky, not drawn
OUTDOOR = 0x8                # MOGI flag: open to the sky
WALL = 0.08                  # a triangle this near edge-on from above: a wall, not drawn
ZSEP = 8.0                   # yards between two floors' heights: another floor
OVERLAP = 30                 # footprint px (KL) two units must share to lie on each other
TOUCH = 3                    # footprint px (KL, one grown by 2) two units must share to be neighbours
SMALL = 0.1                  # a wing with no boss and less ground than this share of the biggest's: joins a neighbour
LINK_STEPS = 3               # groups of no wing a doorway's way to another wing may pass
LINK_APART = 75.0            # yards: the doorways between the same two wings nearer than this are one
LINK_MAX = 25.0              # yards: a portal wider or taller is an opening to look through (a city's ring over its
                             # lava), not a doorway; a portal lying flat (|normal z| over LINK_TILT) a hole in a floor
LINK_TILT = 0.5
DOOR_APART = 20.0            # yards: two ways in nearer than this are one
LIGHT = np.array([-0.45, 0.35, 0.82]) / np.linalg.norm([-0.45, 0.35, 0.82])
HAIR = (2, 0.8)              # the hairline: px out, its blur (at K)
GLOW = (6, 10.0)             # the glow: px out, its blur
HAIR_A, GLOW_A = 0.75, 0.12  # their strengths (the sketch's B)
JOBS = 4


def log(*a):
    print(*a, flush=True)


# ------------------------------------------------------------------ files
def chunks(data, start=0, end=None, forward=False):
    pos, end = start, len(data) if end is None else end
    while pos + 8 <= end:
        tag = data[pos:pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        yield (tag if forward else tag[::-1]), pos + 8, size
        pos += 8 + size


def cached(fid, ext):
    return os.path.join(CACHE, "%d%s" % (fid, ext))


def download(job):
    fid, ext = job
    path = cached(fid, ext)
    if os.path.isfile(path):
        return True
    req = urllib.request.Request(WAGO % fid, headers={"User-Agent": AGENT})
    why = ""
    for _ in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
            if data:
                tmp = path + ".part"
                with open(tmp, "wb") as f:
                    f.write(data)
                os.replace(tmp, path)
                return True
        except urllib.error.HTTPError as e:
            if e.code == 404:      # (not in the build: asking again changes nothing)
                why = "not in the build"
                break
            why = "HTTP %d" % e.code
        except OSError as e:
            why = "%s: %s" % (type(e).__name__, e)
    log("    could not fetch %d%s (%s)" % (fid, ext, why))
    return False


def fetch(jobs):
    """the files not cached yet, a few at once; the ones that came"""
    os.makedirs(CACHE, exist_ok=True)
    jobs = sorted({(f, e) for f, e in jobs if f})
    todo = [j for j in jobs if not os.path.isfile(cached(*j))]
    if todo:
        log("  fetching %d files" % len(todo))
        with ThreadPoolExecutor(JOBS) as pool:
            list(pool.map(download, todo))
    return {j for j in jobs if os.path.isfile(cached(*j))}


def read(fid, ext):
    path = cached(fid, ext)
    return open(path, "rb").read() if os.path.isfile(path) else None


_pics = {}


def picture(fid):
    """a BLP's pixels (RGBA), or None"""
    if fid not in _pics:
        data = read(fid, ".blp")
        try:
            _pics[fid] = Image.open(io.BytesIO(data)).convert("RGBA") if data else None
        except Exception:      # (a file Pillow cannot read: left out)
            _pics[fid] = None
    return _pics[fid]


def blp_size(fid):
    data = read(fid, ".blp")
    return struct.unpack_from("<2I", data, 12) if data else None


_names = None


def by_name(name):
    """a file's ID by its path (the build's listfile): an old map's WDT names its model"""
    global _names
    if _names is None:
        _names = {}
        if os.path.isfile(LISTFILE):
            for line in open(LISTFILE, encoding="utf-8", errors="replace"):
                i, _, p = line.rstrip("\n").partition(";")
                if i.isdigit():
                    _names[p.lower()] = int(i)
    return _names.get(name.lower().replace("\\", "/"))


def rows(table):
    with open(os.path.join(DB2, table + ".csv"), encoding="utf-8") as f:
        return list(csv.DictReader(f))


# ------------------------------------------------------------------ Dungeon Info's instances, the doors, the bosses
def instances():
    """[(key, map, name, [(encounter, boss name), ...])] in Dungeon Info's order"""
    out, cur = [], None
    head = re.compile(r'^\t\t\[(\d+)\] = \{ (\d+), \d, "((?:[^"\\]|\\.)*)"')
    boss = re.compile(r'^\t\t\t\{ (\d+), "((?:[^"\\]|\\.)*)", \{')
    for line in open(DI_DATA, encoding="utf-8"):
        m = head.match(line)
        if m:
            cur = (int(m.group(1)), int(m.group(2)), m.group(3), [])
            out.append(cur)
            continue
        b = boss.match(line)
        if b and cur:
            cur[3].append((int(b.group(1)), b.group(2).replace('\\"', '"')))
    return out


def door_keys():
    """the instances with a door on the world map (the Quest List's entrances, Media/QuestListData.lua: the doors of
    Forever's world): only those get a plan -- an instance with no door there is not one you can walk into"""
    text = open(QUESTS, encoding="utf-8").read()
    head = text.index("\tentrances = {")
    block = text[head:text.index("\n\t},", head)]
    return {int(k) for k in re.findall(r"^\t\t\{(\d+),", block, re.M)}


def teleports(maps):
    """{map: [(world x, world y, z)]} where the classic database's teleports into each instance land (its entrances)"""
    spec = importlib.util.spec_from_file_location("bql", os.path.join(HERE, "build_quest_list.py"))
    bql = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bql)
    out = defaultdict(list)
    for r in bql.sql_rows(os.path.join(paths.CACHE, "ClassicDB.sql.gz"), "areatrigger_teleport"):
        m = int(r["target_map"])
        if m in maps:
            out[m].append((float(r["target_position_x"]), float(r["target_position_y"]), float(r["target_position_z"])))
    return out


def boss_spawns(maps):
    """{map: {creature name: (world x, world y, z)}} from the classic database (the first spawn of each name)"""
    spec = importlib.util.spec_from_file_location("bql", os.path.join(HERE, "build_quest_list.py"))
    bql = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bql)
    sql = os.path.join(paths.CACHE, "ClassicDB.sql.gz")
    names = {int(r["Entry"]): r["Name"] for r in bql.sql_rows(sql, "creature_template")}
    out = defaultdict(dict)
    for r in bql.sql_rows(sql, "creature"):
        m = int(r["map"])
        if m in maps:
            n = names.get(int(r["id"]))
            if n and n not in out[m]:
                out[m][n] = (float(r["position_x"]), float(r["position_y"]), float(r["position_z"]))
    return out


_areas = None


def area_name(wmo, unique):
    """the game's area name of a model's group (WMOAreaTable by the group's MOGP uniqueID; its own name, else its
    AreaTable row's), else the model's own (WMOGroupID -1), else ''"""
    global _areas
    if _areas is None:
        area = {r["ID"]: r["AreaName_lang"] for r in rows("AreaTable")}
        _areas = {}
        for r in rows("WMOAreaTable"):
            _areas[(int(r["WMOID"]), int(r["WMOGroupID"]))] = r["AreaName_lang"] or area.get(r["AreaTableID"], "")
    name = _areas.get((wmo, unique)) or _areas.get((wmo, -1)) or ""
    return "" if re.search(r"unused", name, re.I) else name   # (the table's own placeholders: no name a player sees)


# ------------------------------------------------------------------ a map's files
def modf(data, at, size):
    """a MODF chunk's placements: (file ID or name index, uid, pos (E, height, S), turn, flags, scale)"""
    out = []
    for i in range(size // 64):
        e = struct.unpack_from("<II3f3f6fHHHH", data, at + i * 64)
        out.append(dict(ref=e[0], uid=e[1], pos=e[2:5], turn=e[6], flags=e[14], scale=(e[17] or 1024) / 1024.0))
    return out


def mwmo_names(data):
    for t, p, s in chunks(data):
        if t == b"MWMO":
            raw = data[p:p + s]
            names, off = {}, 0
            for part in raw.split(b"\0"):
                names[off] = part.decode("latin-1")
                off += len(part) + 1
            return names
    return {}


def root_info(fid):
    data = read(fid, ".wmo")
    if not data:
        return None
    info = dict(wmo=None, groups=[], mats=[], gfid=[])
    for t, p, s in chunks(data):
        if t == b"MOHD":
            info["wmo"] = struct.unpack_from("<I", data, p + 32)[0]
        elif t == b"MOGI":
            info["groups"] = [dict(flags=struct.unpack_from("<I", data, p + i * 32)[0],
                                   bb=struct.unpack_from("<6f", data, p + i * 32 + 4)) for i in range(s // 32)]
        elif t == b"MOMT":
            info["mats"] = [struct.unpack_from("<16I", data, p + i * 64)[3] for i in range(s // 64)]
        elif t == b"GFID":
            info["gfid"] = list(struct.unpack_from("<%dI" % (s // 4), data, p))
        elif t == b"MOPV":
            info["pv"] = np.frombuffer(data, "<f4", s // 4, p).reshape(-1, 3)
        elif t == b"MOPT":
            info["pt"] = [struct.unpack_from("<HH4f", data, p + i * 20) for i in range(s // 20)]
        elif t == b"MOPR":
            info["pr"] = [struct.unpack_from("<HH", data, p + i * 8) for i in range(s // 8)]
    # its portals: the middle of each (the model's units) and the groups it joins
    ports = []
    for start, count, nx, ny, nz, _ in info.get("pt", []):
        pv = info.get("pv")
        if pv is not None and count and start + count <= len(pv):
            v = pv[start:start + count]
            door = max(np.ptp(v[:, 0]), np.ptp(v[:, 1])) <= LINK_MAX and np.ptp(v[:, 2]) <= LINK_MAX \
                and abs(nz) <= LINK_TILT
            ports.append(dict(c=v.mean(axis=0), groups=set(), door=door))
        else:
            ports.append(None)
    for portal, group in info.get("pr", []):
        if portal < len(ports) and ports[portal] is not None:
            ports[portal]["groups"].add(group)
    info["portals"] = [q for q in ports if q and len(q["groups"]) >= 2]
    return info


def group_file(fid):
    """a group file's MOGP: (its uniqueID -- WMOAreaTable's WMOGroupID --, its drawn triangles [(material, (x, y, z) *
    3)]), or (None, [])"""
    data = read(fid, ".wmo")
    if not data:
        return None, []
    mogp = next((p for t, p, _ in chunks(data) if t == b"MOGP"), None)
    if mogp is None:
        return None, []
    unique = struct.unpack_from("<I", data, mogp + 0x38)[0]
    end = mogp + struct.unpack_from("<I", data, mogp - 4)[0]
    sub = {t: (p, s) for t, p, s in chunks(data, mogp + 0x44, end)}
    if not all(k in sub for k in (b"MOPY", b"MOVI", b"MOVT")):
        return unique, []
    vt = np.frombuffer(data, "<f4", sub[b"MOVT"][1] // 4, sub[b"MOVT"][0]).reshape(-1, 3)
    ix = np.frombuffer(data, "<u2", sub[b"MOVI"][1] // 2, sub[b"MOVI"][0]).reshape(-1, 3)
    py = np.frombuffer(data, "u1", sub[b"MOPY"][1], sub[b"MOPY"][0]).reshape(-1, 2)
    n = min(len(ix), len(py))
    return unique, [(int(py[i, 1]), vt[ix[i]]) for i in range(n) if py[i, 1] != 0xFF and ix[i].max() < len(vt)]


def group_unique(fid):
    """a group file's MOGP uniqueID (WMOAreaTable's WMOGroupID) alone, or None"""
    data = read(fid, ".wmo")
    mogp = next((p for t, p, _ in chunks(data) if t == b"MOGP"), None) if data else None
    return struct.unpack_from("<I", data, mogp + 0x38)[0] if mogp is not None else None


def material_colours(info):
    out = {}
    for i, f in enumerate(info["mats"]):
        img = picture(f) if f else None
        if img is not None:
            a = np.asarray(img.resize((16, 16), Image.BOX)).reshape(-1, 4).astype(np.float32)
            keep = a[a[:, 3] > 100] if (a[:, 3] > 100).any() else a
            out[i] = tuple(int(v) for v in keep[:, :3].mean(axis=0))
    return out


def placement(pl):
    E, Z, S = pl["pos"]
    th = math.radians(90 - pl["turn"])
    return E, Z, S, math.cos(th), math.sin(th), pl["scale"]


def model_near(pl, info, pics, box):
    """a model with a floor picture whose block's middle lies in the box (E0, S0, E1, S1); a model with none: kept"""
    if not pics:
        return True
    E, _, S, c, s, sc = placement(pl)
    for g, bx, by, _ in pics:
        if g >= len(info["groups"]):
            continue
        bb = info["groups"][g]["bb"]
        lx, ly = bb[0] + (bx + 0.5) * BLOCK, bb[1] + (by + 0.5) * BLOCK
        x, y = E + (lx * c + ly * s) * sc, S + (lx * s - ly * c) * sc
        if box[0] <= x <= box[2] and box[1] <= y <= box[3]:
            return True
    return False


def corners(p, axis):
    out = []
    for dx in (0, 1):
        for dy in (0, 1):
            lx, ly = p["ax"] + dx * p["fw"] / 2, p["ay"] + dy * p["fh"] / 2
            E = p["E"] + (lx * p["c"] + ly * p["s"]) * p["sc"]
            S = p["S"] + (lx * p["s"] - ly * p["c"]) * p["sc"]
            out.append(S if axis else E)
    return out


def affine(p, e0, s0, k=K):
    """the art's px (k a yard from e0, s0) -> the picture's px (MapCanvas CavePlace's In and Coord)"""
    a1, a2 = p["c"] / p["sc"], p["s"] / p["sc"]
    u0, v0 = e0 - p["E"], s0 - p["S"]
    lx = (a1 / k, a2 / k, a1 * u0 + a2 * v0)
    ly = (a2 / k, -a1 / k, a2 * u0 - a1 * v0)
    return (2 * lx[0], 2 * lx[1], 2 * (lx[2] - p["ax"]), -2 * ly[0], -2 * ly[1], p["fh"] - 2 * (ly[2] - p["ay"]))


def draw_pieces(pieces, e0, s0, k, W, H, out):
    """the pictures' alpha into out (H x W, uint8, k px a yard from e0, s0), each in its own box"""
    for p in pieces:
        img = picture(p["f"])
        if img is None:
            continue
        xs, ys = corners(p, 0), corners(p, 1)
        x0, y0 = max(0, int((min(xs) - e0) * k) - 2), max(0, int((min(ys) - s0) * k) - 2)
        x1, y1 = min(W, int((max(xs) - e0) * k) + 3), min(H, int((max(ys) - s0) * k) + 3)
        if x1 <= x0 or y1 <= y0:
            continue
        a, b, c, d, e, f = affine(p, e0, s0, k)
        lay = img.transform((x1 - x0, y1 - y0), Image.AFFINE, (a, b, a * x0 + b * y0 + c, d, e, d * x0 + e * y0 + f),
                            Image.BILINEAR, fillcolor=(0, 0, 0, 0))
        out[y0:y1, x0:x1] = np.maximum(out[y0:y1, x0:x1], np.asarray(lay)[:, :, 3])


def dilate(a, r):
    """a mask grown by r px each way (a square), in numpy"""
    out = a.copy()
    for d in range(1, r + 1):
        out[:, d:] |= a[:, :-d]
        out[:, :-d] |= a[:, d:]
    b = out.copy()
    for d in range(1, r + 1):
        out[d:, :] |= b[:-d, :]
        out[:-d, :] |= b[d:, :]
    return out


def grow(img, px, blur):
    m = img.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else img
    if blur:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(m).astype(np.float32) / 255


def write_art(name, rgba):
    os.makedirs(ART, exist_ok=True)
    data = blp_dxt.encode_blp(np.ascontiguousarray(rgba), "dxt5", mips=True)
    with open(os.path.join(ART, name + ".blp"), "wb") as f:
        f.write(data)


# ------------------------------------------------------------------ the wings
def footprint(u, e0, s0, W, H):
    """a unit's ground from above at KL: (x0, y0, mask) in the plan's KL px"""
    if u["kind"] == "room":
        xs = [x for p in u["pieces"] for x in corners(p, 0)]
        ys = [y for p in u["pieces"] for y in corners(p, 1)]
    else:
        xs = [x for t in u["tris"] for x, _ in t[1]]
        ys = [y for t in u["tris"] for _, y in t[1]]
    x0, y0 = max(0, int((min(xs) - e0) * KL) - 1), max(0, int((min(ys) - s0) * KL) - 1)
    x1, y1 = min(W, int((max(xs) - e0) * KL) + 2), min(H, int((max(ys) - s0) * KL) + 2)
    w, h = max(1, x1 - x0), max(1, y1 - y0)
    if u["kind"] == "room":
        a = np.zeros((h, w), np.uint8)
        draw_pieces(u["pieces"], e0 + x0 / KL, s0 + y0 / KL, KL, w, h, a)
        mask = a > 64
    else:
        img = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(img)
        for _, pts, _, _ in u["tris"]:
            d.polygon([((x - e0) * KL - x0, (y - s0) * KL - y0) for x, y in pts], fill=255)
        mask = np.asarray(img) > 64
    return x0, y0, mask


def shared(a, b, grown=False):
    """the footprint px two units share (one of them grown: neighbours)"""
    ax, ay, am = a["fp"] if not grown else a["fpg"]
    bx, by, bm = b["fp"]
    x0, y0 = max(ax, bx), max(ay, by)
    x1, y1 = min(ax + am.shape[1], bx + bm.shape[1]), min(ay + am.shape[0], by + bm.shape[0])
    if x1 <= x0 or y1 <= y0:
        return 0
    return int((am[y0 - ay:y1 - ay, x0 - ax:x1 - ax] & bm[y0 - by:y1 - by, x0 - bx:x1 - bx]).sum())


def split(units):
    """the units in wings: lists of units, no two of a wing on each other's ground at another height"""
    n = len(units)
    conflict = [set() for _ in range(n)]
    touch = [dict() for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            dz = abs(units[i]["zmin"] - units[j]["zmin"])
            # (only rooms on rooms are another floor: the parts open to the sky -- a ship's decks over each other --
            # are drawn from above as one picture, the highest over the rest)
            rooms = units[i]["kind"] == "room" and units[j]["kind"] == "room"
            if dz > ZSEP and rooms:
                if shared(units[i], units[j]) >= OVERLAP:
                    conflict[i].add(j)
                    conflict[j].add(i)
            else:
                t = shared(units[i], units[j], grown=True)
                if t >= TOUCH:
                    touch[i][j] = touch[j][i] = t
    order = sorted(range(n), key=lambda i: units[i]["zmin"])
    wing, members = {}, []
    for i in order:   # (the lowest first: each in the first wing it lies on nothing in)
        for w, mem in enumerate(members):
            if not (conflict[i] & mem):
                mem.add(i)
                wing[i] = w
                break
        else:
            members.append({i})
            wing[i] = len(members) - 1
    for _ in range(8):   # (each to the wing its neighbours at its height are in, where it lies on nothing)
        moved = False
        for i in order:
            score = Counter()
            for j, t in touch[i].items():
                score[wing[j]] += t
            if not score:
                continue
            best = max(score, key=lambda w: (score[w], -w))
            if best != wing[i] and score[best] > score.get(wing[i], 0) and not (conflict[i] & members[best]):
                members[wing[i]].discard(i)
                members[best].add(i)
                wing[i] = best
                moved = True
        if not moved:
            break
    groups = [m for m in members if m]
    merged = True
    while merged:   # (two wings with nothing on each other's ground: one)
        merged = False
        groups.sort(key=len)
        for a in range(len(groups)):
            for b in range(len(groups)):
                if a != b and not any(conflict[i] & groups[b] for i in groups[a]):
                    groups[b] |= groups[a]
                    del groups[a]
                    merged = True
                    break
            if merged:
                break
    return [[units[i] for i in sorted(g, key=lambda i: units[i]["zmin"])] for g in groups]


def buildings(units, ways, bosses):
    """the units by building (2.1.0; the user 2026-11-03, of Scarlet Monastery's first wing: its four buildings in
    one, tiny rooms on a big empty plan). Rooms whose floors touch are one site (Scarlet Monastery's Graveyard,
    Library, Armory and Cathedral; Dire Maul's East apart from its West and North, joined inside); a site with a way
    in and a boss on it (KL px spots: on its floors, else the nearest) is a building of its own; every other site and
    the outdoor ground join the building nearest them. A map of fewer than two buildings: all its units as one (open
    land's huts and caves, a gap in a city's floor pictures stay with the dungeon)"""
    rooms = [i for i, u in enumerate(units) if u["kind"] == "room"]
    parent = {i: i for i in rooms}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for a in range(len(rooms)):
        for b in range(a + 1, len(rooms)):
            if shared(units[rooms[a]], units[rooms[b]], grown=True) >= TOUCH:
                parent[find(rooms[a])] = find(rooms[b])
    sites = {}
    for i in rooms:
        sites.setdefault(find(i), []).append(i)
    sites = list(sites.values())
    if len(sites) < 2:
        return [units]

    def box(idx):
        return (min(units[i]["fp"][0] for i in idx), min(units[i]["fp"][1] for i in idx),
                max(units[i]["fp"][0] + units[i]["fp"][2].shape[1] for i in idx),
                max(units[i]["fp"][1] + units[i]["fp"][2].shape[0] for i in idx))

    def gap(p, q):
        return max(0, p[0] - q[2], q[0] - p[2]) + max(0, p[1] - q[3], q[1] - p[3])
    boxes = [box(s) for s in sites]

    def site_at(x, y):
        for k, s in enumerate(sites):
            for i in s:
                ux, uy, m = units[i]["fpg"]
                px, py = int(x) - ux, int(y) - uy
                if 0 <= py < m.shape[0] and 0 <= px < m.shape[1] and m[py, px]:
                    return k
        return min(range(len(sites)), key=lambda k: gap(boxes[k], (x, y, x, y)))
    own = {site_at(x, y) for x, y in ways} & {site_at(x, y) for x, y in bosses}
    # (and a name of its own: the game names the part apart -- Dire Maul's East, only ever "Dire Maul", stays with its
    # West and North)
    names = {k: {units[i]["name"] for i in sites[k] if units[i]["name"]} for k in own}
    own = {k for k in own if names[k] - set().union(*(names[h] for h in own if h != k))}
    if len(own) < 2:
        return [units]
    groups = {k: list(sites[k]) for k in own}
    for k in range(len(sites)):
        if k not in own:
            groups[min(own, key=lambda h: gap(boxes[k], boxes[h]))] += sites[k]
    for i, u in enumerate(units):
        if u["kind"] != "room":
            groups[max(own, key=lambda h: (sum(shared(u, units[j], grown=True) for j in groups[h]),
                                           -gap(box([i]), boxes[h])))].append(i)
    return [[units[i] for i in sorted(g)] for _, g in sorted(groups.items(), key=lambda kv: min(kv[1]))]


def boss_wing(wings, x, y, z):
    """the wing whose rooms are under a boss's spot (KL px) nearest his height; else the nearest rooms' wing"""
    best = None
    for w, us in enumerate(wings):
        for u in us:
            ux, uy, m = u["fpg"]
            px, py = int(x) - ux, int(y) - uy
            if 0 <= py < m.shape[0] and 0 <= px < m.shape[1] and m[py, px]:
                dz = 0 if u["zmin"] - 3 <= z <= u["zmax"] + 3 else min(abs(z - u["zmin"]), abs(z - u["zmax"]))
                if best is None or dz < best[0]:
                    best = (dz, w)
    if best:
        return best[1]
    near = None
    for w, us in enumerate(wings):
        for u in us:
            ux, uy, m = u["fp"]
            ys, xs = np.nonzero(m)
            if len(xs):
                d = float(np.min((xs + ux - x) ** 2 + (ys + uy - y) ** 2))
                if near is None or d < near[0]:
                    near = (d, w)
    return near[1] if near else 0


# ------------------------------------------------------------------ one instance map
def build_map(key, mapID, name, bosses, spawns, wdt_fid, ways):
    log("%s (map %d)" % (name, mapID))
    if not fetch([(wdt_fid, ".wdt")]):
        log("  no WDT")
        return None
    wdt = read(wdt_fid, ".wdt")
    maid, wdt_modf = None, []
    for t, p, s in chunks(wdt):
        if t == b"MAID":
            maid = [struct.unpack_from("<8I", wdt, p + k * 32) for k in range(4096)]
        elif t == b"MODF":
            wdt_modf = modf(wdt, p, s)
    names = mwmo_names(wdt)
    # (a map of one model, no terrain: Wailing Caverns, the Stockade. Its model's own units are the world's turned
    # half round -- north its -x, west its -y: every boss of both on their rooms so, 2026-11-02 -- which is a tile
    # placement's turn at the grid's middle)
    for pl in wdt_modf:
        if abs(pl["pos"][0]) > 0.01 or abs(pl["pos"][2]) > 0.01:
            log("  note: the map's model is placed at %.1f, %.1f (taken as the grid's middle)" % (pl["pos"][0],
                                                                                               pl["pos"][2]))
        pl["pos"] = (EDGE_W, pl["pos"][1], EDGE_W)
    placed = list(wdt_modf)
    tiles = [(k % 64, k // 64, maid[k]) for k in range(4096) if maid and maid[k][0]] if maid else []
    fetch([(m[1], ".adt") for _, _, m in tiles])
    for tx, ty, m in tiles:
        adt = read(m[1], ".adt")
        for t, p, s in chunks(adt or b""):
            if t == b"MODF":
                placed += modf(adt, p, s)
    seen, uniq = set(), []
    for pl in placed:
        if pl["uid"] not in seen:
            seen.add(pl["uid"])
            if not pl["flags"] & 0x8:      # (by name: the WDT's MWMO)
                pl["ref"] = by_name(names.get(pl["ref"], "")) or 0
            uniq.append(pl)
    fetch([(pl["ref"], ".wmo") for pl in uniq])
    models = []
    for pl in uniq:
        info = root_info(pl["ref"]) if pl["ref"] else None
        if info:
            models.append((pl, info))
    fetch([(f, ".blp") for _, info in models for *_, f in PICTURES.get(info["wmo"], [])])
    # the bosses' places; with two or more, only the models round them (a dungeon in open land -- Zul'Gurub -- has
    # far caves and huts on its map that are no part of it)
    places = []
    for enc, bname in bosses:
        hit = spawns.get(bname)
        if not hit:
            hit = next((v for n, v in spawns.items() if n.startswith(bname + "'s ")), None)
        if hit:
            places.append((enc, EDGE_W - hit[1], EDGE_W - hit[0], hit[2]))
    if len(places) >= 2:
        box = (min(p[1] for p in places) - NEAR, min(p[2] for p in places) - NEAR,
               max(p[1] for p in places) + NEAR, max(p[2] for p in places) + NEAR)
        kept = [m for m in models if model_near(m[0], m[1], PICTURES.get(m[1]["wmo"], []), box)]
        if len(kept) < len(models):
            log("  %d models far from every boss left out" % (len(models) - len(kept)))
        models = kept
    # the groups' files (a room group's area name; an outdoor group's triangles) and the outdoor ones' materials
    want, outdoor = [], set()
    for pl, info in models:
        have = {g for g, *_ in PICTURES.get(info["wmo"], [])}
        if not have:
            continue     # (a model with no rooms: scenery round the dungeon -- the houses on the cliff over the cove)
        for g, gi in enumerate(info["groups"]):
            if g >= len(info["gfid"]):
                continue
            bb = gi["bb"]
            if g in have:
                want.append(info["gfid"][g])
            elif gi["flags"] & OUTDOOR and max(bb[3] - bb[0], bb[4] - bb[1]) * pl["scale"] <= SKY:
                want.append(info["gfid"][g])
                outdoor.add((pl["uid"], g))
    fetch([(f, ".wmo") for f in want])
    fetch([(m, ".blp") for pl, info in models if any((pl["uid"], g) in outdoor for g in range(len(info["groups"])))
           for m in info["mats"]])

    # the units: each group of rooms with pictures, each part open to the sky
    units = []
    for pl, info in models:
        pics = PICTURES.get(info["wmo"], [])
        if not pics:
            continue
        E, Z, S, c, s, sc = placement(pl)
        by_group = defaultdict(list)
        for g, bx, by, f in pics:
            if g < len(info["groups"]):
                by_group[g].append((bx, by, f))
        for g, glist in sorted(by_group.items()):
            bb = info["groups"][g]["bb"]
            unique = group_unique(info["gfid"][g]) if g < len(info["gfid"]) else None
            pieces = []
            for bx, by, f in sorted(glist):
                size = blp_size(f)
                if size:
                    ax, ay = round(bb[0] + bx * BLOCK, 2), round(bb[1] + by * BLOCK, 2)
                    pieces.append(dict(f=f, ax=ax, ay=ay, fw=size[0], fh=size[1], E=E, S=S, c=c, s=s, sc=sc))
            if pieces:
                units.append(dict(kind="room", pl=pl, g=g, pieces=pieces, zmin=Z + bb[2] * sc, zmax=Z + bb[5] * sc,
                                  name=area_name(info["wmo"], unique)))
        cols_ = None
        for g, gi in enumerate(info["groups"]):
            if (pl["uid"], g) not in outdoor:
                continue
            if cols_ is None:
                cols_ = material_colours(info)
            unique, raw = group_file(info["gfid"][g])
            tris = []
            for mat, v in raw:
                nrm = np.cross(v[1] - v[0], v[2] - v[0])
                ln = np.linalg.norm(nrm)
                if not ln:
                    continue
                nrm = nrm / ln
                if nrm[2] < 0:
                    nrm = -nrm
                if nrm[2] < WALL:
                    continue
                pts = [(E + (x * c + y * s) * sc, S + (x * s - y * c) * sc) for x, y, _ in v]
                tris.append((float(v[:, 2].max()) * sc + Z, pts, cols_.get(mat, (120, 100, 80)),
                             0.45 + 0.55 * max(0.0, float(nrm @ LIGHT))))
            if tris:
                bb = gi["bb"]
                units.append(dict(kind="out", pl=pl, g=g, tris=tris, zmin=Z + bb[2] * sc, zmax=Z + bb[5] * sc,
                                  name=area_name(info["wmo"], unique)))
    if not units and not places:
        log("  nothing to draw")
        return None

    # the plan: everything drawn and every boss, a margin round it
    xs = [p[1] for p in places]
    ys = [p[2] for p in places]
    for u in units:
        if u["kind"] == "room":
            xs += [x for p in u["pieces"] for x in corners(p, 0)]
            ys += [y for p in u["pieces"] for y in corners(p, 1)]
        else:
            xs += [x for t in u["tris"] for x, _ in t[1]]
            ys += [y for t in u["tris"] for _, y in t[1]]
    pad = MARGIN if units else 6 * MARGIN    # (a map of open ground only: room round its bosses)
    e0, e1, s0, s1 = min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad
    cols, rows_ = int(math.ceil((e1 - e0) * K / ART_PX)), int(math.ceil((s1 - s0) * K / ART_PX))
    W, H = cols * ART_PX, rows_ * ART_PX
    WL, HL = int(W / K * KL), int(H / K * KL)

    # the wings
    for u in units:
        u["fp"] = footprint(u, e0, s0, WL, HL)
        x0, y0, m = u["fp"]
        g = np.zeros((m.shape[0] + 4, m.shape[1] + 4), bool)
        g[2:-2, 2:-2] = m
        u["fpg"] = (x0 - 2, y0 - 2, dilate(g, 2))
        u["area"] = int(m.sum())
    spots = []   # (the ways in, KL px: which buildings have one; the bosses' spots too)
    for wx, wy, _ in ways:
        x, y = EDGE_W - wy - e0, EDGE_W - wx - s0
        if 0 <= x <= e1 - e0 and 0 <= y <= s1 - s0:
            spots.append((x * KL, y * KL))
    wings = []
    marks = [((E - e0) * KL, (S - s0) * KL) for _, E, S, _ in places]
    for b, us in enumerate(buildings(units, spots, marks) if units else []):
        for u in us:
            u["building"] = b
        wings += split(us)
    wings = wings or [[]]
    at = [boss_wing(wings, (E - e0) * KL, (S - s0) * KL, z) for _, E, S, z in places]

    def building(w):
        return wings[w][0]["building"] if wings[w] else 0
    # (a wing of a room or two with no boss -- the Deadmines' room over its first tunnel -- is no wing to pick: it
    # joins the wing of its building it touches most, drawn over it)
    while len(wings) > 1:
        size = [sum(u["area"] for u in us) for us in wings]
        small = [w for w in range(len(wings)) if size[w] < SMALL * max(size) and w not in at
                 and any(v != w and building(v) == building(w) for v in range(len(wings)))]
        if not small:
            break
        w = min(small, key=lambda q: size[q])
        best = max((v for v in range(len(wings)) if v != w and building(v) == building(w)),
                   key=lambda v: (sum(shared(u, o, grown=True) for u in wings[w] for o in wings[v]), size[v]))
        wings[best] += wings[w]
        del wings[w]
        at = [a - 1 if a > w else a for a in at]
    first = {}
    for i, w in enumerate(at):
        first.setdefault(w, i)
    order = sorted(range(len(wings)), key=lambda w: (first.get(w, 1e9),
                                                     sum(u["zmin"] * u["area"] for u in wings[w]) /
                                                     max(1, sum(u["area"] for u in wings[w]))))
    wings = [wings[w] for w in order]
    at = [order.index(w) for w in at]
    # their names: the game's area name of most of each one's ground, one a wing; the names the minimap shows there
    weight = [Counter() for _ in wings]
    for w, us in enumerate(wings):
        for u in us:
            if u["name"]:
                weight[w][u["name"]] += u["area"]
    home = {}
    for nm in {n for c_ in weight for n in c_}:
        home[nm] = max(range(len(wings)), key=lambda w: weight[w][nm])
    # (2.1.0, of Dire Maul's "Wing 3") a wing with no area name of its own: the dungeon's own name for the first one,
    # the name of the first boss met there for the others -- never a bare number
    first_boss = {}
    for (enc, *_), w in zip(places, at):
        first_boss.setdefault(w, dict(bosses).get(enc))
    used, titles = set(), []
    for w in range(len(wings)):
        own_name = next((n for n, _ in weight[w].most_common() if n not in used and n != name), None)
        any_name = next((n for n, _ in weight[w].most_common() if n not in used), None)
        boss = first_boss.get(w) if first_boss.get(w) not in used else None
        pick = own_name or (any_name or boss if w == 0 else boss or any_name)
        if pick:
            used.add(pick)
        titles.append(pick)

    # the ways in: each teleport's landing in the plan, in the wing whose rooms are there
    doors = []
    for wx, wy, wz in ways:
        E, S = EDGE_W - wy, EDGE_W - wx
        x, y = E - e0, S - s0
        if 0 <= x <= e1 - e0 and 0 <= y <= s1 - s0 and all(math.hypot(x - d[0], y - d[1]) > DOOR_APART for d in doors):
            doors.append((x, y, boss_wing(wings, x * KL, y * KL, wz) + 1))
    # the doorways between wings: the models' portals (through groups of no wing -- corridors -- within LINK_STEPS)
    wing_of, floor = {}, {}
    for w, us in enumerate(wings):
        for u in us:
            wing_of[(u["pl"]["uid"], u["g"])] = w
            floor[(u["pl"]["uid"], u["g"])] = u["zmin"]
    links = []
    for pl, info in models:
        ports = info.get("portals") or []
        if not ports:
            continue
        uid = pl["uid"]
        E0, Z0, S0, c, s, sc = placement(pl)
        nbr = defaultdict(set)
        for q in ports:
            for a in q["groups"]:
                nbr[a] |= q["groups"] - {a}

        def reach(start, came):
            """the wings and floors of the first groups of a wing from `start` (no further than LINK_STEPS)"""
            found, seen, edge = [], {came, start}, [start]
            for _ in range(LINK_STEPS):
                nxt = []
                for g in edge:
                    if (uid, g) in wing_of:
                        found.append((wing_of[(uid, g)], floor[(uid, g)]))
                        continue
                    for h in nbr[g] - seen:
                        seen.add(h)
                        nxt.append(h)
                edge = nxt
            return found

        for q in ports:
            if not q["door"]:
                continue   # (an opening to look through, a hole in a floor: no doorway)
            lx, ly, lz = q["c"]
            E = E0 + (lx * c + ly * s) * sc
            S = S0 + (lx * s - ly * c) * sc
            x, y = E - e0, S - s0
            for a in q["groups"]:
                if (uid, a) not in wing_of:
                    continue
                wa, za = wing_of[(uid, a)], floor[(uid, a)]
                for b in q["groups"] - {a}:
                    for wb, zb in reach(b, a):
                        if wb == wa:
                            continue
                        if any(l_[2] == wa and l_[3] == wb and math.hypot(x - l_[0], y - l_[1]) < LINK_APART for l_ in links):
                            continue
                        way = 1 if zb > za + ZSEP / 2 else (-1 if zb < za - ZSEP / 2 else 0)
                        links.append((x, y, wa, wb, way))

    # each wing's art and rooms
    ss = 2 if W * H <= 16e6 else 1        # (the triangles drawn bigger, then shrunk: smooth edges; a huge plan: not)
    out_wings, n_edge, n_cove = [], 0, 0
    for w, us in enumerate(wings, 1):
        walk = np.zeros((H, W), np.uint8)
        draw_pieces([p for u in us if u["kind"] == "room" for p in u["pieces"]], e0, s0, K, W, H, walk)
        cove = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
        tris = sorted((t for u in us if u["kind"] == "out" for t in u["tris"]), key=lambda q: q[0])
        if tris:
            z0, z1 = tris[0][0], tris[-1][0]
            d = ImageDraw.Draw(cove)
            for top, pts, col, lit in tris:
                f = lit * (0.75 + 0.25 * (top - z0) / ((z1 - z0) or 1))
                d.polygon([((x - e0) * K * ss, (y - s0) * K * ss) for x, y in pts],
                          fill=tuple(min(255, int(v * f)) for v in col) + (255,))
        if ss > 1:
            cove = cove.resize((W, H), Image.LANCZOS)
        walk = Image.fromarray(np.maximum(walk, np.asarray(cove)[:, :, 3]))
        a = np.asarray(walk).astype(np.float32) / 255
        edge = np.clip(np.clip(grow(walk, *HAIR) - a, 0, 1) * HAIR_A + np.clip(grow(walk, *GLOW) - a, 0, 1) * GLOW_A,
                       0, 1)
        edge_rgba = np.zeros((H, W, 4), np.uint8)
        edge_rgba[:, :, :3] = 255
        edge_rgba[:, :, 3] = (edge * 255 + 0.5).astype(np.uint8)
        cove_rgba = np.asarray(cove).copy()
        edge_list, cove_list = [], []
        for r in range(rows_):
            for c_ in range(cols):
                box = (slice(r * ART_PX, (r + 1) * ART_PX), slice(c_ * ART_PX, (c_ + 1) * ART_PX))
                for kind, src, lst in (("e", edge_rgba, edge_list), ("o", cove_rgba, cove_list)):
                    part = src[box]
                    if part[:, :, 3].max() > 4:
                        write_art("%d_%d%s%d_%d" % (mapID, w, kind, c_, r), part)
                        lst += [c_, r]
        n_edge += len(edge_list) // 2
        n_cove += len(cove_list) // 2
        # its rooms: per model, its groups' pictures, the lowest group first
        rooms = []
        for pl in sorted({id(u["pl"]): u["pl"] for u in us if u["kind"] == "room"}.values(), key=lambda q: q["uid"]):
            flat = []
            for u in sorted((u for u in us if u["kind"] == "room" and u["pl"] is pl), key=lambda u: (u["zmin"], u["g"])):
                for p in u["pieces"]:
                    flat += [p["f"], p["ax"], p["ay"], p["fw"], p["fh"]]
            E, _, S, _, _, sc = placement(pl)
            rooms.append([round(E / TILE, 5), round(S / TILE, 5), round(pl["turn"], 2), round(sc, 4), flat])
        bx0 = min((u["fp"][0] for u in us), default=0) / KL
        by0 = min((u["fp"][1] for u in us), default=0) / KL
        bx1 = max((u["fp"][0] + u["fp"][2].shape[1] for u in us), default=WL) / KL
        by1 = max((u["fp"][1] + u["fp"][2].shape[0] for u in us), default=HL) / KL
        for i, wi in enumerate(at):
            if wi == w - 1:
                bx0, by0 = min(bx0, places[i][1] - e0 - MARGIN), min(by0, places[i][2] - s0 - MARGIN)
                bx1, by1 = max(bx1, places[i][1] - e0 + MARGIN), max(by1, places[i][2] - s0 + MARGIN)
        out_wings.append(dict(name=titles[w - 1], box=[round(v, 1) for v in (max(0, bx0), max(0, by0), bx1, by1)],
                              areas=sorted(n for n, h in home.items() if h == w - 1), rooms=rooms, edge=edge_list,
                              cove=cove_list))

    # the ground: the instance's minimap tiles under the plan
    ground = []
    for tx, ty, m in tiles:
        if m[7] and tx * TILE < e0 + cols * ART_PX / K and (tx + 1) * TILE > e0 \
                and ty * TILE < s0 + rows_ * ART_PX / K and (ty + 1) * TILE > s0:
            ground += [tx, ty, m[7]]
    bosses_out = []
    for (enc, E, S, _), w in zip(places, at):
        bosses_out += [enc, round(E - e0, 1), round(S - s0, 1), w + 1]
    doors_out = [v for x, y, w in doors for v in (round(x, 1), round(y, 1), w)]
    links_out = [v for x, y, wa, wb, way in links for v in (round(x, 1), round(y, 1), wa + 1, wb + 1, way)]
    log("  %d units in %d wing(s) (%s), %d room pictures, bosses %d of %d, %d way(s) in, %d doorways between wings, "
        "art %d + %d tiles, ground %d tiles" % (
            len(units), len(out_wings), " / ".join(w["name"] or "-" for w in out_wings),
            sum(len(u["pieces"]) for u in units if u["kind"] == "room"), len(places), len(bosses), len(doors),
            len(links), n_edge, n_cove, len(ground) // 3))
    return dict(map=mapID, name=name, w=round(cols * ART_PX / K, 1), h=round(rows_ * ART_PX / K, 1),
                cw=round(e1 - e0, 1), ch=round(s1 - s0, 1), e0=round(e0, 2), s0=round(s0, 2), cols=cols, rows=rows_,
                ground=ground, wings=out_wings, bosses=bosses_out, doors=doors_out, links=links_out)


# ------------------------------------------------------------------ the data file
def lua_list(v):
    return "{ " + ", ".join(lua_val(x) for x in v) + " }"


def lua_val(x):
    if isinstance(x, list):
        return lua_list(x)
    if isinstance(x, float):
        return ("%.5f" % x).rstrip("0").rstrip(".")
    if isinstance(x, str):
        return lua_str(x)
    return str(x)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def read_existing():
    """the plans already in the data file (a partial build keeps the others): {map: lua text}"""
    out = {}
    if os.path.isfile(OUT):
        for line in open(OUT, encoding="utf-8"):
            m = re.match(r"^\t\[(\d+)\] = ", line)
            if m:
                out[int(m.group(1))] = line.rstrip("\n")
    return out


def entry(d):
    wings = []
    for w in d["wings"]:
        wings.append("{ %sbox = %s, areas = %s, edge = %s, cove = %s, rooms = %s }" % (
            ("name = %s, " % lua_str(w["name"])) if w["name"] else "", lua_list(w["box"]), lua_list(w["areas"]),
            lua_list(w["edge"]), lua_list(w["cove"]), lua_list(w["rooms"])))
    return ("\t[%d] = { name = %s, w = %s, h = %s, cw = %s, ch = %s, e0 = %s, s0 = %s, cols = %d, rows = %d, "
            "ground = %s, bosses = %s, doors = %s, links = %s, wings = { %s } }," % (
                d["map"], lua_str(d["name"]), lua_val(d["w"]), lua_val(d["h"]), lua_val(d["cw"]), lua_val(d["ch"]),
                lua_val(d["e0"]), lua_val(d["s0"]), d["cols"], d["rows"], lua_list(d["ground"]),
                lua_list(d["bosses"]), lua_list(d["doors"]), lua_list(d["links"]), ", ".join(wings)))


def write_data(lines):
    head = [
        "-- Generated by Tools/build_dungeon_maps.py. Do not edit by hand (run the tool).",
        "-- The dungeon maps (docs/plans/dungeon-map.md): each instance's plan from the client's own files (its floor",
        "-- pictures and minimap tiles by file ID), MelloUI's own edge and cove art (Media/Dungeons), its wings (a floor",
        "-- each, named by the game's own area names) and its bosses where the classic database spawns them.",
        paths.GPL_NOTICE,
        "local _, ns = ...",
        "",
        "-- [instance map] = { name, w, h (the plan in yards: its art's whole tiles), cw, ch (the dungeon in it, from its",
        "--   top left), e0, s0 (its top left: yards east and south of the terrain grid's 0, 0), cols, rows (its art",
        "--   tiles, 256 yards each), ground: { tile x, tile y, minimap file, ... } (every wing's), bosses: { encounter,",
        "--   x, y (yards in the plan), wing, ... }, doors: { x, y, wing, ... } (the ways in and out), links: { x, y,",
        "--   wing, to wing, way (1 up, -1 down, 0 level), ... } (the doorways between wings), wings: { { name (the",
        "--   game's area name; none: not known), box: { x0,",
        "--   y0, x1, y1 } (yards: what the map opens on), areas: { area names the minimap shows in it }, edge / cove:",
        "--   { column, row, ... } (its art tiles: <map>_<wing>e|o<column>_<row>), rooms: { { x, y (tiles), turn, scale,",
        "--   { file, anchor x, anchor y, width, height, ... } }, ... } (as MapData.caves) }, ... } }",
        "ns.MapDungeons = {",
    ]
    body = [lines[k] for k in sorted(lines)]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(head + body + ["}", ""]))


def plan_art(mapID, text):
    """the art files a plan's line names"""
    out = set()
    for w, (edge, cove) in enumerate(re.findall(r"edge = \{ ([^}]*)\}, cove = \{ ([^}]*)\}", text), 1):
        for letter, lst in (("e", edge), ("o", cove)):
            nums = [int(x) for x in lst.replace(",", " ").split()]
            out |= {"%d_%d%s%d_%d.blp" % (mapID, w, letter, nums[i], nums[i + 1]) for i in range(0, len(nums) - 1, 2)}
    return out


def check():
    lines = read_existing()
    names = set(art_names())
    used, bad = set(), 0
    for mapID, text in sorted(lines.items()):
        want = plan_art(mapID, text)
        used |= want
        for n in sorted(want - names):
            log("missing art: " + n)
            bad += 1
    for n in sorted(names - used):
        log("art no plan uses: " + n)
        bad += 1
    log("%d plans, %d art files, %d problems" % (len(lines), len(names), bad))
    return 1 if bad else 0


PICTURES = defaultdict(list)   # model ID -> its floor pictures: (group, block x, block y, file)


def art_names():
    return os.listdir(ART) if os.path.isdir(ART) else []


def drop(mapID, lines):
    """a map's plan and its art gone"""
    for n in art_names():
        if n.startswith("%d_" % mapID):
            os.remove(os.path.join(ART, n))
    lines.pop(mapID, None)


def main(argv):
    if "--check" in argv:
        return check()
    want = {int(a) for a in argv if a.isdigit()}
    for r in rows("WMOMinimapTexture"):
        PICTURES[int(r["WMOID"])].append((int(r["GroupNum"]), int(r["BlockX"]), int(r["BlockY"]), int(r["FileDataID"])))
    wdts = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in rows("Map")}
    doors = door_keys()
    every = instances()
    todo = [i for i in every if i[0] in doors and (not want or i[1] in want)]
    log("%d instances" % len(todo))
    spawns = boss_spawns({i[1] for i in todo}) if todo else {}
    ways = teleports({i[1] for i in todo}) if todo else {}
    lines = read_existing()
    for key, mapID, name, bosses in every:
        if key not in doors and (mapID in lines or any(n.startswith("%d_" % mapID) for n in art_names())):
            log("%s (map %d): no door on the world map: no plan" % (name, mapID))
            drop(mapID, lines)
    for key, mapID, name, bosses in todo:
        drop(mapID, lines)   # (a map's old art goes first: its tiles may be fewer now)
        if not wdts.get(mapID):
            log("%s (map %d): no WDT in the client" % (name, mapID))
            continue
        d = build_map(key, mapID, name, bosses, spawns.get(mapID, {}), wdts[mapID], ways.get(mapID, []))
        if d:
            lines[mapID] = entry(d)
    write_data(lines)
    log("wrote %s (%d plans)" % (os.path.relpath(OUT, REPO), len(lines)))
    return check()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
