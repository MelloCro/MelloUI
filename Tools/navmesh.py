#!/usr/bin/env python3
"""
The game's real ground for Route's tools: wowsim's walking navmesh (wierdview/wow-forever-api-simulator, issue #30), read
through its library's C API (wowsim_nav.dll, wowsim_nav.h) with ctypes -- the terrain, the water and the buildings'
and models' collision as the character walks it (0.6 yd round, 2 yd tall, 1 yd steps, 50 degree slopes, 7 yd/s, swims
at 4.7). Offline only: the bench (Tools/route_bench.py) and the bake (Tools/nav_graph.py) ask it; nothing ships.

  nav = Nav(map_id[, bounds])         a handle (one per thread or process: the library's handles are not shared)
  nav.ground(x, y[, z])               the floor at a world point: {ok, z, area, depth, floors}
  nav.path(a, b)                      the quickest way on foot: {ok, partial, reason, points, yards, swim, seconds}
  nav.walk(points)                    the polyline walked straight: {ok, reason, segment, at, yards, swim, seconds}
  nav.walks(lines), nav.paths(pairs)  the same in one call each (the library's batches)

Points are WORLD yards (x north, y west, z up; z None = the column's highest floor). Route's continent yards are
east = (the continent's world y1) - y, south = (its world x1) - x (Tools/trace_roads.py).

The sim's folder: WOWSIM (default the v0.9.1 install); the navmesh: <pack>/terrain/<map>/map.nav, or NAV_DIR/<map>.
"""
import ctypes as C
import math
import os

# (0.9.1: its library ends a walk over floors stacked on each other instead of looping for ever -- wowsim#32; the
# Blizzard data and the navmesh are 0.9's, its assets folder linked in)
WOWSIM = os.environ.get("WOWSIM", r"C:\Users\mortu\Downloads\wowsim-win64-v0.9.1\wowsim-win64")
PACK = os.path.join(WOWSIM, "assets", "blizzard", "_forever-1.60.1.70425")
NAN = float("nan")

REASONS = {0: "none", 1: "wall", 2: "slope", 3: "step", 4: "drop", 5: "water edge", 6: "deep water", 7: "lava",
           8: "void", 9: "narrow", 10: "edge", 11: "unloaded", 12: "no mesh", 13: "no path", 14: "error", 15: "floor"}
FLOOR = 15   # (ours: the walk ended on another floor than its end's)
AREA = {0: "none", 1: "ground", 2: "water"}


class Point(C.Structure):
    _fields_ = [("x", C.c_double), ("y", C.c_double), ("z", C.c_double)]


class Bounds(C.Structure):
    _fields_ = [("min_x", C.c_double), ("min_y", C.c_double), ("max_x", C.c_double), ("max_y", C.c_double)]


class Info(C.Structure):
    _fields_ = [("version", C.c_int), ("map_id", C.c_int), ("adts_in_file", C.c_int), ("adts_loaded", C.c_int),
                ("tiles_loaded", C.c_int), ("polys_loaded", C.c_longlong), ("bytes_loaded", C.c_longlong),
                ("geom_bytes_loaded", C.c_longlong), ("has_geom", C.c_int),
                ("radius", C.c_double), ("height", C.c_double), ("climb", C.c_double), ("slope", C.c_double),
                ("cs", C.c_double), ("ch", C.c_double), ("run", C.c_double), ("swim", C.c_double),
                ("tile_cells", C.c_int),
                ("min_x", C.c_double), ("max_x", C.c_double), ("min_y", C.c_double), ("max_y", C.c_double),
                ("min_z", C.c_double), ("max_z", C.c_double),
                ("wmo_filter", C.c_char * 32), ("placement", C.c_char * 128), ("build", C.c_char * 32)]


class Floor(C.Structure):
    _fields_ = [("z", C.c_double), ("area", C.c_int)]


class GroundResult(C.Structure):
    _fields_ = [("ok", C.c_int), ("reason", C.c_int), ("z", C.c_double), ("area", C.c_int), ("dz", C.c_double),
                ("snap", C.c_double), ("snapped", C.c_int), ("at", Point), ("depth", C.c_double),
                ("nfloors", C.c_int), ("detail", C.c_char * 160)]


class PathResult(C.Structure):
    _fields_ = [("ok", C.c_int), ("partial", C.c_int), ("reason", C.c_int), ("npoints", C.c_int), ("polys", C.c_int),
                ("yards", C.c_double), ("swim_yards", C.c_double), ("seconds", C.c_double), ("straight", C.c_double),
                ("frm", Point), ("to", Point), ("detail", C.c_char * 160)]


class WalkResult(C.Structure):
    _fields_ = [("ok", C.c_int), ("reason", C.c_int), ("segment", C.c_int), ("at", Point),
                ("yards", C.c_double), ("swim_yards", C.c_double), ("seconds", C.c_double), ("straight", C.c_double),
                ("detail", C.c_char * 192)]


_LIB = None


def lib():
    global _LIB
    if _LIB is None:
        if hasattr(os, "add_dll_directory"):
            os.add_dll_directory(WOWSIM)
        L = C.CDLL(os.path.join(WOWSIM, "wowsim_nav.dll"))
        L.wsn_open.restype = C.c_void_p
        L.wsn_open.argtypes = [C.c_char_p, C.POINTER(Bounds)]
        L.wsn_load.restype = C.c_int
        L.wsn_load.argtypes = [C.c_void_p, C.POINTER(Bounds)]
        L.wsn_close.argtypes = [C.c_void_p]
        L.wsn_last_error.restype = C.c_char_p
        L.wsn_last_error.argtypes = [C.c_void_p]
        L.wsn_info_get.argtypes = [C.c_void_p, C.POINTER(Info)]
        L.wsn_ground.restype = C.c_int
        L.wsn_ground.argtypes = [C.c_void_p, C.c_double, C.c_double, C.c_double, C.c_double, C.POINTER(Floor),
                                 C.c_int, C.POINTER(GroundResult)]
        L.wsn_path.restype = C.c_int
        L.wsn_path.argtypes = [C.c_void_p, C.POINTER(Point), C.POINTER(Point), C.c_double, C.POINTER(Point), C.c_int,
                               C.POINTER(PathResult)]
        L.wsn_walk.restype = C.c_int
        L.wsn_walk.argtypes = [C.c_void_p, C.POINTER(Point), C.c_int, C.c_double, C.POINTER(WalkResult)]
        L.wsn_path_batch.restype = C.c_int
        L.wsn_path_batch.argtypes = [C.c_void_p, C.POINTER(Point), C.POINTER(Point), C.c_int, C.c_double,
                                     C.POINTER(Point), C.c_int, C.POINTER(PathResult)]
        L.wsn_walk_batch.restype = C.c_int
        L.wsn_walk_batch.argtypes = [C.c_void_p, C.POINTER(Point), C.POINTER(C.c_int), C.c_int, C.c_double,
                                     C.POINTER(WalkResult)]
        L.wsn_version.restype = C.c_char_p
        _LIB = L
    return _LIB


def nav_file(map_id):
    here = os.environ.get("NAV_DIR")
    if here:
        return os.path.join(here, str(map_id), "map.nav")
    return os.path.join(PACK, "terrain", str(map_id), "map.nav")


def _z(z):
    return NAN if z is None else float(z)


def _pt(p):
    return Point(p[0], p[1], _z(p[2] if len(p) > 2 else None))


class Nav:
    MAX_POINTS = 2048

    def __init__(self, map_id, bounds=None, path=None):
        self.L = lib()
        self.path_file = path or nav_file(map_id)
        b = C.byref(Bounds(*bounds)) if bounds else None
        self.h = self.L.wsn_open(self.path_file.encode("utf-8"), b)
        if not self.h:
            raise RuntimeError("wsn_open %s: %s" % (self.path_file, self.L.wsn_last_error(None).decode("utf-8", "replace")))
        self._pts = (Point * self.MAX_POINTS)()
        self._floors = (Floor * 16)()

    def close(self):
        if self.h:
            self.L.wsn_close(self.h)
            self.h = None

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass

    def load(self, bounds=None):
        return self.L.wsn_load(self.h, C.byref(Bounds(*bounds)) if bounds else None)

    def info(self):
        i = Info()
        self.L.wsn_info_get(self.h, C.byref(i))
        return {k: (getattr(i, k).decode() if isinstance(getattr(i, k), bytes) else getattr(i, k)) for k, _ in Info._fields_}

    def ground(self, x, y, z=None, snap=-1.0):
        r = GroundResult()
        self.L.wsn_ground(self.h, x, y, _z(z), snap, self._floors, 16, C.byref(r))
        floors = [(self._floors[i].z, self._floors[i].area) for i in range(min(r.nfloors, 16))]
        return {"ok": bool(r.ok), "reason": REASONS.get(r.reason, r.reason), "z": r.z, "area": AREA.get(r.area, r.area),
                "depth": r.depth, "snap": r.snap, "at": (r.at.x, r.at.y, r.at.z), "floors": floors,
                "detail": r.detail.decode("utf-8", "replace")}

    @staticmethod
    def _path_out(r, pts):
        return {"ok": bool(r.ok), "partial": bool(r.partial), "reason": REASONS.get(r.reason, r.reason),
                "points": pts, "yards": r.yards, "swim": r.swim_yards, "seconds": r.seconds, "straight": r.straight,
                "frm": (r.frm.x, r.frm.y, r.frm.z), "to": (r.to.x, r.to.y, r.to.z), "polys": r.polys,
                "detail": r.detail.decode("utf-8", "replace")}

    def path(self, a, b, snap=-1.0, points=True):
        r = PathResult()
        self.L.wsn_path(self.h, C.byref(_pt(a)), C.byref(_pt(b)), snap, self._pts if points else None,
                        self.MAX_POINTS, C.byref(r))
        pts = [(self._pts[i].x, self._pts[i].y, self._pts[i].z) for i in range(min(r.npoints, self.MAX_POINTS))] \
            if points else None
        return self._path_out(r, pts)

    @staticmethod
    def _walk_out(r):
        return {"ok": bool(r.ok), "reason": REASONS.get(r.reason, r.reason), "segment": r.segment,
                "at": (r.at.x, r.at.y, r.at.z), "yards": r.yards, "swim": r.swim_yards, "seconds": r.seconds,
                "straight": r.straight, "detail": r.detail.decode("utf-8", "replace")}

    def walk(self, points, snap=-1.0):
        arr = (Point * len(points))(*[_pt(p) for p in points])
        r = WalkResult()
        self.L.wsn_walk(self.h, arr, len(points), snap, C.byref(r))
        return self._walk_out(r)

    def walks(self, lines, snap=-1.0):
        """many polylines in one call: [walk answer]"""
        n = len(lines)
        if n == 0:
            return []
        flat = [p for ln in lines for p in ln]
        arr = (Point * len(flat))(*[_pt(p) for p in flat])
        counts = (C.c_int * n)(*[len(ln) for ln in lines])
        out = (WalkResult * n)()
        self.L.wsn_walk_batch(self.h, arr, counts, n, snap, out)
        return [self._walk_out(out[i]) for i in range(n)]

    # A walk "arrives" only at its end's own height: the navmesh's raycast follows whatever floor it starts on, and
    # under an overhang, a bridge or a ledge it reaches the end's x, y on another floor than the end's (a walk that
    # succeeds one way and fails the other). ZTOL yards of height between where it ends and the end asked.
    ZTOL = 2.0

    def walks_ok(self, segs, snap=-1.0):
        """many two-point segments [(a, b)] -> [(ok, seconds, reason code, yards walked)], lean; ok only where the walk
        arrives at b's height (when b has one)"""
        n = len(segs)
        if n == 0:
            return []
        arr = (Point * (2 * n))()
        for i, (a, b) in enumerate(segs):
            arr[2 * i] = _pt(a)
            arr[2 * i + 1] = _pt(b)
        counts = (C.c_int * n)(*([2] * n))
        out = (WalkResult * n)()
        self.L.wsn_walk_batch(self.h, arr, counts, n, snap, out)
        res = []
        for i in range(n):
            ok, reason = out[i].ok, out[i].reason
            bz = arr[2 * i + 1].z
            if ok and bz == bz and abs(out[i].at.z - bz) > self.ZTOL:
                ok, reason = 0, FLOOR
            res.append((ok, out[i].seconds, reason, out[i].yards))
        return res

    def arrives(self, a, b, snap=-1.0):
        """a straight walk from a that arrives at b's own floor: its answer (ok False otherwise)"""
        w = self.walk([a, b], snap)
        if w["ok"] and len(b) > 2 and b[2] is not None and abs(w["at"][2] - b[2]) > self.ZTOL:
            w["ok"] = False
            w["reason"] = REASONS[FLOOR]
        return w

    def paths(self, pairs, snap=-1.0, points_each=0):
        n = len(pairs)
        if n == 0:
            return []
        starts = (Point * n)(*[_pt(a) for a, _ in pairs])
        ends = (Point * n)(*[_pt(b) for _, b in pairs])
        out = (PathResult * n)()
        buf = (Point * (n * points_each))() if points_each else None
        self.L.wsn_path_batch(self.h, starts, ends, n, snap, buf, points_each, out)
        res = []
        for i in range(n):
            pts = None
            if points_each:
                pts = [(buf[i * points_each + j].x, buf[i * points_each + j].y, buf[i * points_each + j].z)
                       for j in range(min(out[i].npoints, points_each))]
            res.append(self._path_out(out[i], pts))
        return res


def version():
    return lib().wsn_version().decode()


if __name__ == "__main__":
    import sys
    import time
    m = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    t = time.perf_counter()
    nav = Nav(m)
    print(version(), "opened in %.1f s" % (time.perf_counter() - t))
    print({k: v for k, v in nav.info().items() if k not in ("placement",)})
    print(math.pi)
