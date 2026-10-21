#!/usr/bin/env python3
"""
The lifts and elevators on the continents, which the navmesh does not hold (a moving object is no ground): where each
car rides, its bottom and top landing, and what a ride costs a player who walks up at any time -- for Route's bench
(Tools/route_bench.py: the best way may ride one) and the bake (Tools/nav_bake.py: a timed link between the landings).

Sources: the cars' spawns (cmangos classic-db, gameobject type 11), their animation (the client's TransportAnimation,
build 1.60.1.70338: the cycle, the stops, the rise), the landings' floors (wowsim's navmesh round each shaft).

  LIFTS = [{name, map, x, y, bottom, top, seconds}]   world yards; seconds = the expected wait for a car + the ride
  landings(nav, lift) -> (bottom point, top point)    walkable floor points by the shaft, on each landing's floor
"""
import math

# expected seconds for a player arriving at a random moment: the cars stop STOP seconds at each landing, one at each
# landing every GAP seconds (two cars in a shaft pair, or one car's cycle); boarding during a stop waits out the rest
# of it, else the next car and its whole stop; then the ride
def expected(gap, stop, ride):
    p = stop / gap
    return p * stop / 2 + (1 - p) * ((gap - stop) / 2 + stop) + ride


LIFTS = [
    # Thunder Bluff: two shafts a pair (one car up while the other comes down), 30 s cycle, 5 s stops, 10 s ride
    {"name": "Thunder Bluff west lift", "map": 1, "x": -1297.3, "y": 187.5, "bottom": 68.9, "top": 130.1,
     "seconds": expected(15, 5, 10)},
    {"name": "Thunder Bluff south-east lift", "map": 1, "x": -1032.7, "y": -38.8, "bottom": 69.2, "top": 140.5,
     "seconds": expected(15, 5, 10)},
    # the Great Lift (The Barrens - Thousand Needles) and Freewind Post's: the same cars
    {"name": "the Great Lift", "map": 1, "x": -4668.1, "y": -1838.7, "bottom": -44.0, "top": 85.5,
     "seconds": expected(15, 5, 10)},
    {"name": "Freewind Post lift", "map": 1, "x": -5390.9, "y": -2497.0, "bottom": -40.4, "top": 89.0,
     "seconds": expected(15, 5, 10)},
    # the Undercity: three shafts, a car each, 16.7 s cycle, 5 s stops, 3.5 s ride
    {"name": "Undercity elevator (north)", "map": 0, "x": 1596.2, "y": 291.8, "bottom": -40.8, "top": 55.7,
     "seconds": expected(16.7, 5, 3.5)},
    {"name": "Undercity elevator (south)", "map": 0, "x": 1595.3, "y": 188.6, "bottom": -40.8, "top": 55.7,
     "seconds": expected(16.7, 5, 3.5)},
    {"name": "Undercity elevator (west)", "map": 0, "x": 1544.2, "y": 240.8, "bottom": -40.8, "top": 55.7,
     "seconds": expected(16.7, 5, 3.5)},
    # Gnomeregan's entrance (Dun Morogh): one car, 26.7 s cycle, 6.7 s at the top, 10 s at the bottom, 4.3 s ride
    {"name": "Gnomeregan elevator", "map": 0, "x": -5164.2, "y": 650.4, "bottom": 249.4, "top": 349.5,
     "seconds": expected(26.7, 8.3, 4.3)},
]


def landings(nav, lift, reach=14.0, step=1.0):
    """the walkable floor points by the shaft at each landing's height (within 2.5 yd of it), nearest the shaft first:
    (bottom, top) as (x, y, z), or None where a landing has no floor near"""
    out = []
    for z in (lift["bottom"], lift["top"]):
        best = None
        r = 1.0
        while r <= reach and best is None:
            n = max(8, int(2 * math.pi * r / step))
            for k in range(n):
                a = 2 * math.pi * k / n
                x, y = lift["x"] + r * math.cos(a), lift["y"] + r * math.sin(a)
                g = nav.ground(x, y, z, snap=0.5)
                for fz, area in g["floors"]:
                    if abs(fz - z) <= 2.5:
                        best = (x, y, fz)
                        break
                if best:
                    break
            r += step
        out.append(best)
    return tuple(out)
