#!/usr/bin/env python3
"""
Which zone each cell of the real ground lies in (Tools/nav_grid.py's cells), for Route's bench and bake: the ground's
own areas (the navmesh's map.area: the AreaTable ID of every 33.3-yard chunk, as the client's MCNK has it) walked up to
the zone that has a world map (UiMapAssignment), and that map's name. Offline.

  Z = Zones(map_id, grid)    grid: Tools/nav_grid.py's npz (its r0, c0)
  Z.of(r, c)                 the zone's uiMapID of a cell (0: none)
  Z.raster                   the zone of every cell, as the grid (uint16 index into Z.ids)
  Z.name[uiMap], Z.cont[uiMap], Z.ids
"""
import csv
import glob
import math
import os
import struct

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CONTINENTS = {0: 1415, 1: 1414}
CAPITALS = (1453, 1455, 1457, 1454, 1456, 1458)   # Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity
# the capitals under the ground (Ironforge, the Undercity): their streets are the floors in the city's rect (its map's
# region, UiMapAssignment) between these heights with other ground above them -- at the place itself or round it (a
# hollow in the mountain over Ironforge's streets has no walkable ground above); the zone raster names the ground over
# them (Dun Morogh, Tirisfal), and Route's graph keeps their nodes apart (Tools/nav_bake.py: a layer of their own)
UNDER_Z = {1455: (400.0, 560.0), 1458: (-80.0, 10.0)}
COVER = 12.0          # yards of height to the floor above
COVER_RING = 12.0     # yards round the place the floors above are looked for too
COVER_SHARE = 1 / 3   # ... the share of the nine places that must be covered
PER = 128
CHUNK = 8                                          # cells a chunk (33.3 yd)


def cache():
    bd = os.environ.get("MELLOUI_BUILD_DATA") or r"F:\Download-Backup\Project Web\MelloUI-BuildData"
    return os.path.join(bd, "cache")


def table(name):
    paths = sorted(glob.glob(os.path.join(cache(), "%s_1.60.1.*.csv" % name)))
    return list(csv.DictReader(open(paths[-1], encoding="utf-8")))


def area_file(map_id):
    from navmesh import nav_file
    return os.path.join(os.path.dirname(nav_file(map_id)), "map.area")


def read_areas(map_id):
    """{(tx, ty): 16 x 16 uint32 (rows iy, columns ix)}"""
    out = {}
    with open(area_file(map_id), "rb") as f:
        head = f.read(44)
        assert head[:4] == b"WSAR", "not an area file"
        bits = f.read(4096)
        for k, b in enumerate(bits):
            if b:
                tx, ty = divmod(k, 64)
                f.seek(44 + 4096 + k * 1024)
                ids = struct.unpack("<256I", f.read(1024))
                out[(tx, ty)] = np.array(ids, np.uint32).reshape(16, 16)
    return out


def city_region(map_id, zone):
    """a capital's region (its map's first, UiMapAssignment): (x0, y0, x1, y1) in world yards, or None"""
    for r in table("UiMapAssignment"):
        if int(r["UiMapID"]) == zone and r["OrderIndex"] == "0" and int(r["MapID"]) == map_id:
            return tuple(float(r["Region_%d" % i]) for i in (0, 1, 3, 4))
    return None


def under_city(map_id, nav, x, y, z):
    """the underground capital whose streets (x, y, z) is on, or 0 (UNDER_Z, COVER: nav a Tools/navmesh.py Nav)"""
    for zone, (lo, hi) in UNDER_Z.items():
        if not lo <= z <= hi:
            continue
        reg = REGIONS.get((map_id, zone), False)
        if reg is False:
            reg = REGIONS[(map_id, zone)] = city_region(map_id, zone)
        if not reg or not (reg[0] <= x <= reg[2] and reg[1] <= y <= reg[3]):
            continue
        covered = 0
        for k in range(9):
            if k == 0:
                px, py = x, y
            else:
                a = (k - 1) * math.pi / 4
                px, py = x + COVER_RING * math.cos(a), y + COVER_RING * math.sin(a)
            fl = nav.ground(px, py)["floors"]
            if any(f[0] - z >= COVER for f in fl):
                covered += 1
        if covered >= 9 * COVER_SHARE:
            return zone
    return 0


REGIONS = {}


class Zones:
    def __init__(self, map_id, grid):
        self.map_id = map_id
        cont = CONTINENTS[map_id]
        uimap = {int(r["ID"]): r for r in table("UiMap")}
        self.uimap = uimap
        areas = {int(r["ID"]): r for r in table("AreaTable")}
        # the zones and cities on this continent: a Zone map (type 3) whose parents reach the continent
        zones = {}
        for i, r in uimap.items():
            if r["Type"] != "3":
                continue
            p, seen = int(r["ParentUiMapID"]), 0
            while p and p != cont and seen < 6:
                p = int(uimap[p]["ParentUiMapID"]) if p in uimap else 0
                seen += 1
            if p == cont:
                zones[i] = r["Name_lang"]
        self.name = zones
        self.name[0] = "(no zone)"
        # an area's map: the zone map whose assignment names the area or one of its parents
        by_area = {}
        for r in table("UiMapAssignment"):
            u, a = int(r["UiMapID"]), int(r["AreaID"])
            if u in zones and a and int(r["MapID"]) == map_id:
                by_area.setdefault(a, u)
        cache_of = {}

        def zone_of_area(a):
            if a in cache_of:
                return cache_of[a]
            z, seen, x = 0, 0, a
            while x and seen < 8:
                if x in by_area:
                    z = by_area[x]
                    break
                x = int(areas[x]["ParentAreaID"]) if x in areas else 0
                seen += 1
            cache_of[a] = z
            return z

        self.ids = [0] + sorted(zones)
        index = {u: i for i, u in enumerate(self.ids)}
        r0, c0 = int(grid["r0"]), int(grid["c0"])
        H, W = grid["kind"].shape
        raster = np.zeros((H, W), np.uint16)
        for (tx, ty), ids in read_areas(map_id).items():
            rr, cc = ty * PER - r0, tx * PER - c0
            if rr < 0 or cc < 0 or rr >= H or cc >= W:
                continue
            zi = np.vectorize(lambda a: index.get(zone_of_area(int(a)), 0))(ids).astype(np.uint16)
            raster[rr:rr + PER, cc:cc + PER] = np.kron(zi, np.ones((CHUNK, CHUNK), np.uint16))
        self.raster = raster
        self.r0, self.c0 = r0, c0
        self.cont = cont

    def of(self, r, c):
        return self.ids[int(self.raster[r, c])]

    def cells(self, ui):
        return np.argwhere(self.raster == self.ids.index(ui))
