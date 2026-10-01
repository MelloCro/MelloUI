#!/usr/bin/env python3
"""
The ground graph and the walk grid for Route (docs/plans/route-terrain.md, option A), from Tools/trace_terrain.py's
walkable grid (MelloUI-BuildData/cache/terrain/walk_<map>.npz). Used by Tools/trace_roads.py's bake.

  cells     the vertex grid (4.17 yd) folded into CELL-yard cells (4 x 4 vertices: 16.67 yd): wall when half its
            vertex cells are steep, swim when half are deep water, none when half have no ground, else walk; small
            specks cleaned (a lone wall cell in a field, a lone walk cell in a cliff)
  nodes     ground nodes on walk cells: a lattice every NEAR_STEP cells within NEAR_RANGE cells of a wall (where a
            route has to turn), every OPEN_STEP cells elsewhere
  links     between two nodes within LINK_RANGE yards whose straight segment crosses no wall cell (swim cells cost
            SWIM_COST); each node keeps its MAX_LINKS shortest; costs in seconds at WALK yards a second times
            GROUND_COST (a road always wins a like way)
  roads     each road node linked to the ground nodes within ROAD_REACH yards it sees (the same rule)
  grid      the walk grid for the runtime's straight legs: one string per row, runs of a letter (w walk, s swim,
            x wall, n none) and a count

Continent yards are Route's: east = (the continent's world y1) - world y, south = (its world x1) - world x.
"""
import math

import numpy as np

UNIT = 100.0 / 24.0                # 4.1667 yd: the terrain's vertex spacing
FOLD = 4                           # vertices per cell side
CELL = UNIT * FOLD                 # 16.67 yd
WALK = 7.0                         # yards a second, as Route.lua
GROUND_COST = 1.25                 # a ground link against a road's 1
SWIM_COST = 2.5                    # a swum stretch
NEAR_RANGE = 4                     # cells (67 yd): "near a wall"
NEAR_STEP = 3                      # cells (50 yd) between nodes near walls
OPEN_STEP = 9                      # cells (150 yd) between nodes in the open
LINK_RANGE = 220                   # yards
MAX_LINKS = 8
ROAD_REACH = 90                    # yards
WALK_V, SWIM_V, WALL_V, NONE_V = 1, 2, 0, 3
LETTERS = {WALK_V: "w", SWIM_V: "s", WALL_V: "x", NONE_V: "n"}


def fold(grid):
    """the vertex-cell grid (1 walk, 2 swim, 0 wall, 255 none) -> CELL-yard cells"""
    H, W = grid.shape
    h, w = H // FOLD, W // FOLD
    g = grid[:h * FOLD, :w * FOLD].reshape(h, FOLD, w, FOLD)
    n = FOLD * FOLD
    wall = (g == 0).sum(axis=(1, 3))
    swim = (g == 2).sum(axis=(1, 3))
    none = (g == 255).sum(axis=(1, 3))
    out = np.full((h, w), WALK_V, dtype=np.uint8)
    out[swim * 2 >= n] = SWIM_V
    out[wall * 2 >= n] = WALL_V
    out[none * 2 >= n] = NONE_V
    return clean(out)


def clean(c):
    """a lone wall cell among walk cells walks; a lone walk cell among walls is a wall"""
    from scipy.ndimage import convolve
    k = np.ones((3, 3), dtype=np.int32)
    k[1, 1] = 0
    walls = convolve((c == WALL_V).astype(np.int32), k, mode="constant", cval=0)
    walks = convolve((c == WALK_V).astype(np.int32), k, mode="constant", cval=0)
    out = c.copy()
    out[(c == WALL_V) & (walks >= 7)] = WALK_V
    out[(c == WALK_V) & (walls >= 7)] = WALL_V
    return out


def clear(c, r0, c0, r1, c1):
    """the cells a straight segment crosses (cell coordinates as floats): None when a wall or no ground is crossed,
    else the share of it swum"""
    d = max(abs(r1 - r0), abs(c1 - c0))
    steps = max(1, int(math.ceil(d * 2)))
    swum = 0
    H, W = c.shape
    for i in range(steps + 1):
        t = i / steps
        r = int(r0 + (r1 - r0) * t)
        q = int(c0 + (c1 - c0) * t)
        if r < 0 or q < 0 or r >= H or q >= W:
            return None
        v = c[r, q]
        if v == WALL_V or v == NONE_V:
            return None
        if v == SWIM_V:
            swum += 1
    return swum / (steps + 1)


def nodes_of(c):
    """the ground nodes: (row, col) cell centres"""
    from scipy.ndimage import distance_transform_cdt
    walk = c == WALK_V
    to_wall = distance_transform_cdt(walk, metric="chessboard")
    out = []
    H, W = c.shape
    for r in range(0, H, NEAR_STEP):
        for q in range(0, W, NEAR_STEP):
            if not walk[r, q]:
                continue
            near = to_wall[r, q] <= NEAR_RANGE
            if near or (r % OPEN_STEP == 0 and q % OPEN_STEP == 0):
                out.append((r, q))
    return out


def link(c, pts, e0, s0):
    """{ i: { j: seconds } } between the nodes (cell coordinates), their yards (east, south) from the cell grid's
    origin e0, s0"""
    from scipy.spatial import cKDTree
    xy = np.array([(e0 + (q + 0.5) * CELL, s0 + (r + 0.5) * CELL) for r, q in pts])
    tree = cKDTree(xy)
    links = {i: {} for i in range(len(pts))}
    for i, (r, q) in enumerate(pts):
        cand = tree.query_ball_point(xy[i], LINK_RANGE)
        cand = sorted((j for j in cand if j != i), key=lambda j: (xy[j][0] - xy[i][0]) ** 2 + (xy[j][1] - xy[i][1]) ** 2)
        kept = 0
        for j in cand:
            if kept >= MAX_LINKS:
                break
            if j in links[i]:
                kept += 1
                continue
            r2, q2 = pts[j]
            swum = clear(c, r + 0.5, q + 0.5, r2 + 0.5, q2 + 0.5)
            if swum is None:
                continue
            d = float(np.hypot(*(xy[j] - xy[i])))
            cost = d / WALK * (GROUND_COST * (1 - swum) + SWIM_COST * swum)
            links[i][j] = round(cost, 1)
            links[j][i] = round(cost, 1)
            kept += 1
    return xy, links


def grid_rows(c):
    """the walk grid as one run-length string per row"""
    rows = []
    for r in range(c.shape[0]):
        row = c[r]
        parts = []
        start = 0
        n = len(row)
        while start < n:
            v = row[start]
            end = start + 1
            while end < n and row[end] == v:
                end += 1
            run = end - start
            parts.append(LETTERS[int(v)] + (str(run) if run > 1 else ""))
            start = end
        rows.append("".join(parts))
    return rows


def origin(tx0, ty0, cont_x1, cont_y1):
    """the cell grid's north-west corner in continent yards (east, south)"""
    zero = 32.0 * 1600.0 / 3.0
    # vertex column 0 is world y = zero - tx0 * 533.33 (the tile's west edge... y decreases eastward)
    e0 = cont_y1 - (zero - tx0 * 128 * UNIT)
    s0 = cont_x1 - (zero - ty0 * 128 * UNIT)
    return e0, s0
