"""
make_rpg_gradient.py -- the dark gradient background (0.20.1; the user, 2026-10-10: "there is this gradient background
in the RPG user interface folder, i want that background ... scaleable and reusable"; the pack used with its
creator's permission). The pack's character panel (Paperdoll.psd, its big sprite_ContainerBase) is a flat dark fill
under a Photoshop gradient effect: measured on the merged image, it runs top to bottom only (every row one colour),
darkest at the top and bottom edges, lightest at the middle, easing between. Drawn here from those measurements:

    backdrops/gradient_dark   64 x 512   the profile down the panel, the same in every column
    backdrops/gradient_radial 256 x 256  the slot boxes' round gradient (the user: "add the slot box gradient too"):
                                         lightest in the middle, the same at equal distances every way (measured on
                                         the axes and the diagonal of a 260 px box), and its inner shadow (the user:
                                         "add the inner shadow too"): darkest just inside the edge, gone 30 px in on
                                         the 260 px box, the two sides' multiplied in a corner -- part of the picture,
                                         so it scales with the background (its share of the side as on the box)

Not a tile: a background choice laid over the whole rect it covers, so it scales to any panel (a pure gradient loses
nothing stretched; Kit:Retile leaves a piece that is no tile as applied). The pack's own colours in every look
(backdrops/ are uncoloured: kit_palette.py SKIP, Kit.lua UNCOLOURED).

Run:  python Tools/make_rpg_gradient.py
      then python Tools/build_kit.py, python Tools/texture_pack.py ship (a full client restart)
"""
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
MANIFEST = os.path.join(SRC, "manifest.json")
W, H = 64, 512

# the panel's colour by distance from its middle (0) to its top or bottom edge (1), measured on the merged image
# (columns clear of the silhouette and the slots; the lower half mirrors the upper within a level)
PROFILE = [
    (0.000, (54, 52, 44)),
    (0.118, (53, 50, 43)),
    (0.242, (51, 48, 42)),
    (0.367, (48, 46, 40)),
    (0.492, (45, 43, 38)),
    (0.617, (42, 40, 36)),
    (0.742, (38.5, 37, 31)),
    (1.000, (32, 31, 26)),
]


# the slot box's colour by distance from its middle, over half its side (1: the middle of an edge; 1.41 a corner)
RADIAL = [
    (0.00, (55, 53, 46)),
    (0.26, (53, 51, 45)),
    (0.44, (51, 49, 43)),
    (0.61, (48, 47, 42)),
    (0.78, (46, 44, 40)),
    (0.87, (45, 43, 39)),
    (1.05, (42, 41, 38)),
    (1.13, (40, 39, 36)),
    (1.42, (36, 35, 32)),
]
RW = 256
# the inner shadow: the colour over the gradient's by depth from the box's edge, in px of the 260 px box (its 1 px
# border line left out), the same on all four sides
SHADOW = [(0, 0.46), (2, 0.48), (4, 0.55), (6, 0.61), (8, 0.68), (10, 0.73), (12, 0.77), (14, 0.80), (16, 0.84),
          (18, 0.89), (20, 0.91), (22, 0.93), (24, 0.95), (26, 0.98), (30, 1.0)]


def radial():
    c = (RW - 1) / 2.0
    y, x = np.mgrid[0:RW, 0:RW]
    r = np.hypot(x - c, y - c) / (RW / 2.0)
    xs = [p[0] for p in RADIAL]
    rgb = np.stack([np.interp(r, xs, [p[1][k] for p in RADIAL]) for k in range(3)], axis=2)
    box = 260.0 / RW
    dx, dy = np.minimum(x, RW - 1 - x) * box, np.minimum(y, RW - 1 - y) * box
    sd, sm = [p[0] for p in SHADOW], [p[1] for p in SHADOW]
    rgb = rgb * (np.interp(dx, sd, sm) * np.interp(dy, sd, sm))[..., None]
    a = np.full((RW, RW, 1), 255.0)
    return np.clip(np.concatenate([rgb, a], axis=2).round(), 0, 255).astype(np.uint8)


def gradient():
    d = np.abs(np.linspace(-1, 1, H))
    xs = [p[0] for p in PROFILE]
    rows = np.stack([np.interp(d, xs, [p[1][c] for p in PROFILE]) for c in range(3)], axis=1)
    rgb = np.repeat(rows[:, None, :], W, axis=1)
    a = np.full((H, W, 1), 255.0)
    return np.clip(np.concatenate([rgb, a], axis=2).round(), 0, 255).astype(np.uint8)


def main():
    os.makedirs(os.path.join(SRC, "backdrops"), exist_ok=True)
    Image.fromarray(gradient(), "RGBA").save(os.path.join(SRC, "backdrops", "gradient_dark.png"))
    Image.fromarray(radial(), "RGBA").save(os.path.join(SRC, "backdrops", "gradient_radial.png"))
    man = json.load(open(MANIFEST, encoding="utf-8"))
    man["v2_2x/backdrops/gradient_radial"] = {"w": RW, "h": RW, "scale": 1.0,
                                              "src": "Tools/make_rpg_gradient.py: the RPG UI pack's slot box gradient "
                                                     "(used with its creator's permission), from its measured profile"}
    man["v2_2x/backdrops/gradient_dark"] = {"w": W, "h": H, "scale": 1.0,
                                            "src": "Tools/make_rpg_gradient.py: the RPG UI pack's dark panel gradient "
                                                   "(used with its creator's permission), from its measured profile"}
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    print("backdrops/gradient_dark %dx%d, gradient_radial %dx%d -> %s" % (W, H, RW, RW, os.path.join(SRC, "backdrops")))


if __name__ == "__main__":
    main()
