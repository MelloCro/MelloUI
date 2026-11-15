"""The Quest Moments count rings (Core/QuestMoments.lua; the user, 2026-11-14, of the first build's ring of dots:
"not as smooth as i expected them to be, and have very sharp edges").

One ring for each count needed, 1 to 20, and a ring with no gaps for more: an arc for each needed item from the top
clockwise, round ends, a small gap between them -- the sketch's (BuildData/output/quest_moments_sketch) -- drawn from a
signed distance with a one-pixel soft edge, so it stays smooth at any size. Two pictures each, white for the palette:
  ring_<n>.tga        the arcs (the track tinted, and the gold through the Cooldown's swipe)
  ring_<n>_edge.tga   the same arcs wider: the dark edge under them
128 x 128, drawn at the ring's 64 x 64 units (two pixels a unit at the game's scale: never shown larger than its file).

    python Tools/make_quest_rings.py
"""
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Textures", "QuestMoments")
SIZE = 128                 # the file
UNITS = 64.0               # the ring's frame in game units (Core/QuestMoments.lua: Q.RING_FRAME)
RING = 28.0                # the arcs' middle line, units (Q.RING)
WIDTH = 4.2                # an arc's width, units
EDGE = 6.6                 # the dark edge's width, units
GAP = 1.6                  # the room left between two arcs, units (past their round ends)
COUNTS = list(range(1, 21))


def ring(n, width):
    k = SIZE / UNITS
    r0, half, gap = RING * k, width * k / 2, GAP * k
    c = (SIZE - 1) / 2
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    dx, dy = x - c, c - y                         # up is +y
    r = np.hypot(dx, dy)
    theta = np.mod(np.arctan2(dx, dy), 2 * math.pi)   # 0 at the top, clockwise
    if n is None or n == 1:
        d = np.abs(r - r0) - half                    # one whole ring: no ends
    else:
        slot = 2 * math.pi / n
        # each arc's half span: the slot less the gap and the two round ends, as angles on the middle line
        span = slot - (gap + 2 * (WIDTH * k / 2)) / r0
        span = max(span, 0.02)
        local = np.mod(theta, slot) - slot / 2       # the angle from this slot's middle
        inside = np.abs(local) <= span / 2
        d_arc = np.abs(r - r0)
        # past an end: the distance to that end's point on the middle line
        end = np.sign(local) * span / 2
        mid = (np.floor(theta / slot) + 0.5) * slot
        ex, ey = r0 * np.sin(mid + end), r0 * np.cos(mid + end)
        d_end = np.hypot(dx - ex, dy - ey)
        d = np.where(inside, d_arc, d_end) - half
    alpha = np.clip(0.5 - d, 0, 1)                   # a one-pixel soft edge
    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for n in COUNTS + [None]:
        name = "ring_%s" % (n if n else "all")
        for suffix, width in (("", WIDTH), ("_edge", EDGE)):
            path = os.path.join(OUT, name + suffix + ".tga")
            ring(n, width).save(path, compression="tga_rle")
            total += os.path.getsize(path)
    print("wrote %d rings to %s (%d KB)" % (len(COUNTS) + 1, OUT, total // 1024))


if __name__ == "__main__":
    main()
