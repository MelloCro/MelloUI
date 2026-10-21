#!/usr/bin/env python3
"""
A bench pair drawn (Tools/route_bench.py's jsonl): the real ground round it (Tools/nav_grid.py: walkable green, water
blue, no floor dark, a cell with a side not walked across orange), the best way (white) and Route's (red, its points
dotted), its stuck segments' starts marked (yellow). For reading the worst routes.

    python Tools/route_show.py <pairs.jsonl> [--worst 8] [--index i] [--out dir] [--map 0]
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from nav_grid import UNIT, ORIGIN, E, S, build_out  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jsonl")
    ap.add_argument("--worst", type=int, default=8)
    ap.add_argument("--index", type=int, action="append")
    ap.add_argument("--map", type=int, default=0)
    ap.add_argument("--out", default=None)
    ap.add_argument("--px", type=int, default=900)
    a = ap.parse_args()
    recs = [json.loads(l) for l in open(a.jsonl, encoding="utf-8")]
    for i, r in enumerate(recs):
        r["_i"] = i
    if a.index:
        pick = [recs[i] for i in a.index]
    else:
        pick = sorted([r for r in recs if r.get("ratio")], key=lambda r: -r["ratio"])[:a.worst]
    d = np.load(os.path.join(build_out(), "navgrid_%d.npz" % a.map))
    kind, edges, r0, c0 = d["kind"], d["edges"], int(d["r0"]), int(d["c0"])
    out = a.out or os.path.join(os.path.dirname(a.jsonl), "show")
    os.makedirs(out, exist_ok=True)
    for r in pick:
        pts = [r["a"][:2], r["b"][:2]] + [q[:2] for q in r.get("ref_way", [])] + [q[:2] for q in r.get("route", [])]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        pad = 60
        rmin = int((ORIGIN - max(xs) - pad) / UNIT) - r0
        rmax = int((ORIGIN - min(xs) + pad) / UNIT) - r0
        cmin = int((ORIGIN - max(ys) - pad) / UNIT) - c0
        cmax = int((ORIGIN - min(ys) + pad) / UNIT) - c0
        rmin, cmin = max(0, rmin), max(0, cmin)
        k = kind[rmin:rmax, cmin:cmax]
        e = edges[rmin:rmax, cmin:cmax]
        img = np.zeros(k.shape + (3,), np.uint8)
        img[k == 0] = (30, 26, 22)
        img[k == 1] = (110, 150, 80)
        img[k == 2] = (60, 100, 170)
        img[(k == 1) & ((e & (E | S)) != (E | S))] = (190, 120, 60)
        h, w = k.shape
        scale = a.px / max(h, w)
        im = Image.fromarray(img).resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.NEAREST)
        dr = ImageDraw.Draw(im)

        def xy(p):
            rr = (ORIGIN - p[0]) / UNIT - r0 - rmin
            cc = (ORIGIN - p[1]) / UNIT - c0 - cmin
            return cc * scale, rr * scale

        way = [xy(q) for q in r.get("ref_way", [])]
        if len(way) > 1:
            dr.line(way, fill=(255, 255, 255), width=3)
        route = [xy(q) for q in r.get("route", [])]
        if len(route) > 1:
            dr.line(route, fill=(230, 40, 40), width=2)
            for q in route:
                dr.ellipse((q[0] - 2, q[1] - 2, q[0] + 2, q[1] + 2), fill=(230, 40, 40))
        for st in r.get("stuck", []):
            if len(st) > 4 and st[3] >= 3:
                q = xy(st[4])
                dr.ellipse((q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5), outline=(255, 230, 0), width=2)
        for p, col in ((r["a"], (0, 255, 255)), (r["b"], (255, 0, 255))):
            q = xy(p)
            dr.rectangle((q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5), outline=col, width=2)
        dr.text((6, 6), "%s %s %d yd  ratio %.2f  ours %.0f s  best %.0f s" % (
            r["zname"], r["band"], r["yards"], r.get("ratio", 0), r.get("time", 0), r["ref"]), fill=(255, 255, 255))
        name = os.path.join(out, "pair_%03d.png" % r["_i"])
        im.save(name)
        print(name, r.get("ratio"), r["yards"], r.get("kinds"), [(s[0], s[2], s[3]) for s in r.get("stuck", [])
                                                                if len(s) > 3 and s[3] >= 3])


if __name__ == "__main__":
    main()
