"""Media/Textures/Masks/portrait_corner.tga: the mask Kit:CutGameCorner lays over the game's portrait corner
(UI-Frame-PortraitMetal-CornerTopLeft) on a dressed window (white = shown, as the other masks). The game's ring and
its soft dark halo stay whole; the stubs of the game's metal rails beside the ring (the title bar's bar to the right,
the left rail below) are cut away at the ring's rim, so the kit's rail runs into the ring (the user, 2026-10-10).

The numbers were measured on the corner's art at its 2x size (190 px for its 95 units; a local study, the art itself
never read here nor shipped): the ring's centre at 76, 76; its gold rim ends at 60, the dark outline at 62, the soft
halo at 68; the bar's rows 22..84 right of the ring, the rail's columns 21..39 below it (each widened by its shadow).
Laid with SetAllPoints on the corner, so the mask's square is the corner's."""
import os

import numpy as np
from PIL import Image

from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

ART = 190.0                 # the corner's art, px (2x of its 95 units)
SIZE = 256                  # the mask's px
CX = CY = 76.0              # the ring's centre in the art
R_RIM = 61.5                # the cut where a stub joins: past the gold rim, half its dark outline
R_HALO = 67.0               # the cut elsewhere: the ring's whole soft halo
BAR_ROWS = (14.0, 92.0)     # the title bar's stub, right of the centre (rows 22..84 and its shadow)
RAIL_COLS = (14.0, 46.0)    # the left rail's stub, below the centre (columns 21..39 and its shadow)
SOFT = 1.5                  # art px of soft edge

out = master("Textures", "Masks", "portrait_corner.tga")  # `texture_pack.py ship` makes what Media ships
k = ART / SIZE
y, x = (np.mgrid[0:SIZE, 0:SIZE] + 0.5) * k
r = np.hypot(x - CX, y - CY)


def inside(v, lo, hi):
    """1 inside [lo, hi], 0 outside, soft over SOFT at both ends."""
    return np.clip((v - lo) / SOFT + 0.5, 0, 1) * np.clip((hi - v) / SOFT + 0.5, 0, 1)


def disc(radius):
    return np.clip((radius - r) / SOFT + 0.5, 0, 1)


bar = inside(y, *BAR_ROWS) * np.clip((x - CX) / SOFT + 0.5, 0, 1)
rail = inside(x, *RAIL_COLS) * np.clip((y - CY) / SOFT + 0.5, 0, 1)
stub = np.maximum(bar, rail)
v = disc(R_HALO) * (1 - stub) + disc(R_RIM) * stub
a = (v * 255).round().astype(np.uint8)
os.makedirs(os.path.dirname(out), exist_ok=True)
Image.fromarray(np.dstack([a, a, a, a]), "RGBA").save(out)
print("wrote", os.path.normpath(out))
