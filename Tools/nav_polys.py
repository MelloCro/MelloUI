#!/usr/bin/env python3
"""
The navmesh's own polygons and how they join (Tools/navmesh.py's file, read without the library): the exact
connectivity of the real ground, for the reference way of Route's bench (Tools/route_bench.py) and the bake
(docs/plans/route-ground.md). Offline.

  P = Polys(map_id)            every polygon of the map's navmesh (the last record of each ADT tile)
  P.cx, P.cy, P.cz             centroids in WORLD yards (x north, y west, z up); P.area 1 ground, 2 water
  P.graph()                    a scipy matrix of the joins: polygon to polygon, seconds between centroids
  P.near(x, y[, z])            the polygon under a world point (the one whose height is nearest z, else the highest)

The file (wowsim's tools/nav/nav_internal.h, version 2): a MapHeader, then per ADT a record "WSNR" (x, y, tiles,
payload bytes, z range, polygons), the payload (per navmesh tile: int32 size, Detour tile data), "WSNE". A tile's data
is Detour 1.6.0's (dtCreateNavMeshData, DT_POLYREF64): dtMeshHeader (100 bytes), vertices (Recast space: x = world y,
y = world z, z = world x), polygons (32 bytes: firstLink, verts[6], neis[6], flags, vertCount, areaAndtype). A
neighbour 1..n is the tile's own polygon; one with DT_EXT_LINK (0x8000) lies over the tile's side (neis & 0xff: 0 +x,
2 +z, 4 -x, 6 -z) and is joined to the polygons of the next tile whose edge on the facing side overlaps it, as Detour's
connectExtLinks does (heights within the climb).
"""
import os
import struct
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

EXT = 0x8000
RUN, SWIM = 7.0, 4.7
HEAD = struct.Struct("<iiiiiI9i3f3f3ff")    # dtMeshHeader


def records(path):
    """{(adt x, adt y): (offset of the payload, bytes, tiles)}: the last whole record of each ADT"""
    out = {}
    with open(path, "rb") as f:
        head = f.read(12)
        magic, version, hb = struct.unpack("<4sII", head)
        assert magic == b"WSNV" and version == 2, "not a map navmesh"
        size = os.fstat(f.fileno()).st_size
        pos = hb
        while pos + 40 <= size:
            f.seek(pos)
            rh = f.read(40)
            m, x, y, ntiles, payload = struct.unpack_from("<4siiIQ", rh)
            if m != b"WSNR" or pos + 40 + payload + 8 > size:
                break
            f.seek(pos + 40 + payload)
            if f.read(8)[4:] != b"WSNE":
                break
            out[(x, y)] = (pos + 40, payload, ntiles)
            pos += 40 + payload + 8
    return out


class Polys:
    def __init__(self, map_id, path=None, adts=None, climb=1.0):
        from navmesh import nav_file
        self.path = path or nav_file(map_id)
        t0 = time.perf_counter()
        recs = records(self.path)
        if adts is not None:
            recs = {k: v for k, v in recs.items() if k in adts}
        tiles = []          # (tile x, tile z, first polygon, polygon count, bmin, bmax)
        verts_l, poly_v, poly_n, poly_nv, poly_area = [], [], [], [], []
        vbase = 0
        pbase = 0
        with open(self.path, "rb") as f:
            for (ax, ay), (off, nbytes, ntiles) in sorted(recs.items()):
                f.seek(off)
                buf = f.read(nbytes)
                p = 0
                for _ in range(ntiles):
                    (size,) = struct.unpack_from("<i", buf, p)
                    p += 4
                    h = HEAD.unpack_from(buf, p)
                    magic, version, tx, tz, layer, _uid, npoly, nvert = h[:8]
                    bmin, bmax = h[18:21], h[21:24]
                    vo = p + 100
                    v = np.frombuffer(buf, np.float32, nvert * 3, vo).reshape(nvert, 3)
                    po = vo + ((12 * nvert + 3) & ~3)
                    raw = np.frombuffer(buf, np.uint8, npoly * 32, po).reshape(npoly, 32)
                    pv = raw[:, 4:16].copy().view(np.uint16).reshape(npoly, 6).astype(np.int64)
                    pn = raw[:, 16:28].copy().view(np.uint16).reshape(npoly, 6).astype(np.int64)
                    nv = raw[:, 30].astype(np.int64)
                    area = (raw[:, 31] & 0x3F).astype(np.uint8)
                    tiles.append((tx, tz, pbase, npoly, bmin, bmax))
                    verts_l.append(v)
                    poly_v.append(pv + vbase)
                    poly_n.append(pn)
                    poly_nv.append(nv)
                    poly_area.append(area)
                    vbase += nvert
                    pbase += npoly
                    p += size
        self.verts = np.concatenate(verts_l) if verts_l else np.zeros((0, 3), np.float32)
        self.pv = np.concatenate(poly_v)
        self.pn = np.concatenate(poly_n)
        self.nv = np.concatenate(poly_nv)
        self.area = np.concatenate(poly_area)
        self.tiles = tiles
        self.climb = climb
        n = len(self.nv)
        # centroids (Recast space), then world
        mask = np.arange(6)[None, :] < self.nv[:, None]
        vv = self.verts[np.where(mask, self.pv, self.pv[:, :1])]
        cnt = self.nv[:, None].astype(np.float64)
        c = (vv * mask[:, :, None]).sum(axis=1) / cnt
        self.cx, self.cy, self.cz = c[:, 2], c[:, 0], c[:, 1]
        self.n = n
        self.seconds_read = time.perf_counter() - t0

    # -------------------------------------------------------------------------------------------- the joins
    def joins(self):
        """[(a, b)] polygon pairs that share an edge (inside a tile, and over the tiles' sides)"""
        n = self.n
        pa, pb = [], []
        ii, kk = np.nonzero((self.pn > 0) & ((self.pn & EXT) == 0) & (np.arange(6)[None, :] < self.nv[:, None]))
        # the tile's own neighbour: its index in the tile, +1
        tile_first = np.zeros(n, np.int64)
        for tx, tz, first, cnt, _, _ in self.tiles:
            tile_first[first:first + cnt] = first
        pa.append(ii)
        pb.append(tile_first[ii] + self.pn[ii, kk] - 1)
        # over the sides: edges with an outward link, matched to the next tile's edges on the facing side
        by_tile = {(tx, tz): (first, cnt, bmin, bmax) for tx, tz, first, cnt, bmin, bmax in self.tiles}
        ei, ek = np.nonzero(((self.pn & EXT) != 0) & (np.arange(6)[None, :] < self.nv[:, None]))
        side = self.pn[ei, ek] & 0xFF
        v0 = self.verts[self.pv[ei, ek]]
        v1 = self.verts[self.pv[ei, (ek + 1) % np.maximum(self.nv[ei], 1)]]
        # (the next vertex wraps at the polygon's own count)
        nxt = np.where(ek + 1 < self.nv[ei], ek + 1, 0)
        v1 = self.verts[self.pv[ei, nxt]]
        owner_tile = {}
        for tx, tz, first, cnt, _, _ in self.tiles:
            owner_tile[first] = (tx, tz)
        tkey = np.zeros(n, np.int64)
        for tx, tz, first, cnt, _, _ in self.tiles:
            tkey[first:first + cnt] = (tx + 100000) * 1000000 + (tz + 100000)
        # group the side edges: [(tile key, side)] -> rows
        groups = {}
        keys = tkey[ei] * 8 + side
        order = np.argsort(keys, kind="stable")
        ks = keys[order]
        bounds = np.flatnonzero(np.diff(ks)) + 1
        starts = np.concatenate(([0], bounds))
        ends = np.concatenate((bounds, [len(ks)]))
        for s0, s1 in zip(starts, ends):
            groups[int(ks[s0])] = order[s0:s1]
        OFF = {0: (1, 0), 2: (0, 1), 4: (-1, 0), 6: (0, -1)}
        for key, rows in groups.items():
            sd = key % 8
            if sd not in OFF:
                continue
            tk = key // 8
            tx, tz = tk // 1000000 - 100000, tk % 1000000 - 100000
            dx, dz = OFF[sd]
            ok = ((tx + dx + 100000) * 1000000 + (tz + dz + 100000)) * 8 + (sd + 4) % 8
            other = groups.get(ok)
            if other is None:
                continue
            # the coordinate along the side: z for sides 0/4 (x fixed), x for 2/6
            ax = 2 if sd in (0, 4) else 0
            a0, a1 = v0[rows, ax], v1[rows, ax]
            b0, b1 = v0[other, ax], v1[other, ax]
            alo, ahi = np.minimum(a0, a1), np.maximum(a0, a1)
            blo, bhi = np.minimum(b0, b1), np.maximum(b0, b1)
            ya0, ya1 = v0[rows, 1], v1[rows, 1]
            yb0, yb1 = v0[other, 1], v1[other, 1]
            for i in range(len(rows)):
                lo = np.maximum(alo[i], blo)
                hi = np.minimum(ahi[i], bhi)
                cand = np.flatnonzero(hi - lo > 0.01)
                if not len(cand):
                    continue
                # heights at the overlap's middle, both edges
                mid = 0.5 * (lo[cand] + hi[cand])
                ta = (mid - a0[i]) / np.where(a1[i] - a0[i] == 0, 1, a1[i] - a0[i])
                ha = ya0[i] + (ya1[i] - ya0[i]) * ta
                tb = (mid - b0[cand]) / np.where(b1[cand] - b0[cand] == 0, 1, b1[cand] - b0[cand])
                hb = yb0[cand] + (yb1[cand] - yb0[cand]) * tb
                good = cand[np.abs(ha - hb) <= self.climb + 0.5]
                if len(good):
                    pa.append(np.full(len(good), ei[rows[i]]))
                    pb.append(ei[other[good]])
        a = np.concatenate(pa)
        b = np.concatenate(pb)
        keep = a != b
        return a[keep], b[keep]

    def _index(self):
        if getattr(self, "_tile_of", None) is not None:
            return
        tx, tz, first, cnt, bmin, bmax = self.tiles[0]
        self.tw = bmax[0] - bmin[0]
        self.ox, self.oz = bmin[0] - tx * self.tw, bmin[2] - tz * self.tw
        self._tile_of = {(t[0], t[1]): (t[2], t[3]) for t in self.tiles}

    def locate(self, x, y, z=None):
        """the polygon under a world point: the one whose plane height is nearest z (else the highest), or -1"""
        self._index()
        rx, rz = y, x
        tx = int(np.floor((rx - self.ox) / self.tw))
        tz = int(np.floor((rz - self.oz) / self.tw))
        best, best_key = -1, None
        for ddx in (0, -1, 1):
            for ddz in (0, -1, 1):
                t = self._tile_of.get((tx + ddx, tz + ddz))
                if not t:
                    continue
                first, cnt = t
                for i in range(first, first + cnt):
                    k = int(self.nv[i])
                    vv = self.verts[self.pv[i, :k]]
                    # inside the convex polygon (either winding), in x / z
                    xs, zs = vv[:, 0], vv[:, 2]
                    cross = (np.roll(xs, -1) - xs) * (rz - zs) - (np.roll(zs, -1) - zs) * (rx - xs)
                    if not ((cross >= -1e-4).all() or (cross <= 1e-4).all()):
                        continue
                    h = float(vv[:, 1].mean())
                    key = -h if z is None else abs(h - z)
                    if best_key is None or key < best_key:
                        best, best_key = i, key
                if best >= 0 and (ddx, ddz) == (0, 0):
                    return best
        return best

    def cached_joins(self):
        """joins(), kept beside the grid (<NAV_OUT>/polyjoins_<map>.npz) for this navmesh file's size and time"""
        from nav_grid import build_out
        st = os.stat(self.path)
        stamp = "%d:%d:%d" % (st.st_size, int(st.st_mtime), self.n)
        path = os.path.join(build_out(), "polyjoins_%s.npz" % os.path.basename(os.path.dirname(self.path)))
        if os.path.exists(path):
            d = np.load(path)
            if str(d["stamp"]) == stamp:
                return d["a"], d["b"]
        a, b = self.joins()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # (written whole under another name, then put in place: several workers may make it at once)
        tmp = "%s.%d.tmp.npz" % (path[:-4], os.getpid())
        try:
            np.savez(tmp, a=a, b=b, stamp=stamp)
            os.replace(tmp, path)
        except OSError:
            pass
        return a, b

    def graph(self):
        from scipy.sparse import csr_matrix
        a, b = self.cached_joins()
        d = np.sqrt((self.cx[a] - self.cx[b]) ** 2 + (self.cy[a] - self.cy[b]) ** 2 + (self.cz[a] - self.cz[b]) ** 2)
        f = np.where(self.area == 2, RUN / SWIM, 1.0)
        cost = d / RUN * 0.5 * (f[a] + f[b])
        m = csr_matrix((np.concatenate([cost, cost]), (np.concatenate([a, b]), np.concatenate([b, a]))),
                       shape=(self.n, self.n))
        m.sum_duplicates()
        return m


if __name__ == "__main__":
    m = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    P = Polys(m)
    print("%d polygons, %d vertices, %d tiles, read in %.1f s" % (P.n, len(P.verts), len(P.tiles), P.seconds_read))
    t = time.perf_counter()
    g = P.graph()
    from scipy.sparse.csgraph import connected_components
    nc, lab = connected_components(g, directed=False)
    sizes = np.bincount(lab)
    print("joins %d in %.1f s; %d pieces, largest %d polygons" % (g.nnz // 2, time.perf_counter() - t, nc, sizes.max()))
