#!/usr/bin/env python3
"""
How good a graph from Tools/nav_graph.py is by itself, before Route uses it: the bench's pairs (route_bench.py's
jsonl) routed over it in Python -- each end joined to the nodes within LEG yards whose straight walk the navmesh
allows, Dijkstra over the links, the way pulled straight with the navmesh's walks -- against the best way.

    python Tools/nav_graphcheck.py <pairs.jsonl> [--map 0] [--leg 80]
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from navmesh import Nav  # noqa: E402
from nav_grid import build_out  # noqa: E402

RUN = 7.0


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * p))] if v else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jsonl")
    ap.add_argument("--map", type=int, default=0)
    ap.add_argument("--leg", type=float, default=80.0)
    ap.add_argument("--zone", type=int, default=0)
    ap.add_argument("--dump", default="")
    a = ap.parse_args()
    g = np.load(os.path.join(build_out(), "navgraph_%d.npz" % a.map))
    N, L = g["nodes"], g["links"]
    n = len(N)
    i, j, s = L[:, 0].astype(int), L[:, 1].astype(int), L[:, 2]
    nav = Nav(a.map)
    tree = cKDTree(N[:, :2])
    recs = [json.loads(l) for l in open(a.jsonl, encoding="utf-8")]
    if a.zone:
        recs = [r for r in recs if r["zone"] == a.zone]
    ratios, ours, shown = [], [], []
    for r in recs:
        A, B = tuple(r["a"]), tuple(r["b"])
        legs = []
        for end, P in ((n, A), (n + 1, B)):
            near = tree.query_ball_point(P[:2], a.leg)
            near = sorted(near, key=lambda k: (N[k, 0] - P[0]) ** 2 + (N[k, 1] - P[1]) ** 2)[:16]
            res = nav.walks_ok([(P, tuple(N[k, :3])) for k in near])
            for k, (ok, secs, _, _) in zip(near, res):
                if ok:
                    legs.append((end, k, secs))
        w = nav.arrives(A, B)
        rows = list(i) + [e for e, _, _ in legs]
        cols = list(j) + [k for _, k, _ in legs]
        vals = list(s) + [c for _, _, c in legs]
        if w["ok"]:
            rows.append(n)
            cols.append(n + 1)
            vals.append(w["seconds"])
        m = csr_matrix((vals, (rows, cols)), shape=(n + 2, n + 2))
        dist, pred = dijkstra(m, directed=False, indices=n, return_predecessors=True)
        if not np.isfinite(dist[n + 1]):
            ours.append(None)
            continue
        chain = [n + 1]
        while chain[-1] != n:
            chain.append(int(pred[chain[-1]]))
        chain.reverse()
        pts = [A if k == n else B if k == n + 1 else tuple(N[k, :3]) for k in chain]
        # pulled straight (the runtime's smoothing, here with the navmesh's own walks)
        total, cur, ii = 0.0, pts[0], 0
        cum = [0.0]
        for k in range(1, len(pts)):
            cum.append(cum[-1] + float(m[chain[k - 1], chain[k]] or m[chain[k], chain[k - 1]]))
        while ii < len(pts) - 1:
            best, bt, lo, hi = ii + 1, cum[ii + 1] - cum[ii], ii + 2, len(pts) - 1
            while lo <= hi:
                mid = (lo + hi) // 2
                ww = nav.arrives(cur, pts[mid])
                if ww["ok"] and ww["seconds"] <= cum[mid] - cum[ii]:
                    best, bt = mid, ww["seconds"]
                    lo = mid + 1
                else:
                    hi = mid - 1
            total += bt
            cur = pts[best]
            ii = best
        ratios.append(total / r["ref"])
        ours.append(total)
        r2 = dict(r)
        r2.update(ratio=round(total / r["ref"], 3), time=round(total, 1), stuck=[],
                  route=[[round(q[0], 1), round(q[1], 1), "graph"] for q in pts])
        shown.append(r2)
    if a.dump:
        with open(a.dump, "w", encoding="utf-8") as fh:
            for r2 in shown:
                fh.write(json.dumps(r2) + "\n")
    none = sum(1 for o in ours if o is None)
    print("graph %d nodes %d links; %d pairs, none %d; time/best median %.3f 90%% %.3f worst %.2f; <=5%% %.0f%% <=15%% %.0f%%"
          % (n, len(L), len(recs), none, pct(ratios, .5), pct(ratios, .9), max(ratios) if ratios else 0,
             100 * sum(1 for x in ratios if x <= 1.05) / max(1, len(ratios)),
             100 * sum(1 for x in ratios if x <= 1.15) / max(1, len(ratios))))


if __name__ == "__main__":
    main()
