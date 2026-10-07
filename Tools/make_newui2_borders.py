"""
make_newui2_borders.py -- the NewUI2 rims the user picked (2026-10-06, "all as recommended"; docs/plans/border-library.md
section 4, decision 10) as the border library's masters and corner studs, into the kit's sources:

    N4   medium iron with diamond corner studs       borders/n4,  borders/n4_gem
    N4g  thin gold with corner studs                 borders/n4g, borders/n4g_gem
    N5   hairline with corner nubs                   borders/n5,  borders/n5_gem
    N1   heavy bevel with corner studs               borders/n1,  borders/n1_gem
    R1   ring with four diamond studs                rings/r1     (stage 4: Round Border, the portrait ring)
    R3   plain heavy ring                            rings/r3

Made by the sketch's own builder (MelloUI-BuildData/output/newui2_library_sketch/newui2_parts.py: the user's sheets in
Downloads/NewUI2 keyed off the magenta with the kit_v3 tools, cleaned, ONE clean stretch of the top rail swept round
a square with its whole depth profile, ONE clean corner's stud cut out), in the sheets' own colours: the kit's
recolouring (Tools/kit_palette.py) makes each look's from them as from every kit piece. A master is BORDER px square
with a T px rail (the library cuts it at T); a stud is the top left corner's (mirrored for the other three in game),
its centre `off` (a share of its size) from the rails' crossing -- printed here, kept in Modules/KitBorders.lua.

Writes Tools/pack_sources/kit/v2_2x/borders/<name>.png and their manifest entries (pack_sources is git-ignored; the
sheets live in Downloads/NewUI2). Running it again writes the same files.

Run:  python Tools/make_newui2_borders.py
      then build_kit.py, build_nineslice.py, texture_pack.py ship (a full client restart)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

from paths import SIBLING

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
MANIFEST = os.path.join(SRC, "manifest.json")
SKETCH = os.path.join(SIBLING, "output", "newui2_library_sketch")
PICKED = {"N4": "n4", "N4g": "n4g", "N5": "n5", "N1": "n1"}
PICKED_RINGS = {"R1": "r1", "R3": "r3"}


def png(a, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(path)


def main():
    sys.path.insert(0, SKETCH)
    import newui2_parts as P  # noqa: E402  (the sketch's builder: its keying, sweep and stud cut)
    man = json.load(open(MANIFEST, encoding="utf-8"))
    for s in P.styles():
        name = PICKED.get(s.key)
        if not name:
            continue
        master, gem = s.master_raw, s.gem_raw
        png(master, os.path.join(SRC, "borders", name + ".png"))
        man["v2_2x/borders/" + name] = {"w": int(master.shape[1]), "h": int(master.shape[0]), "scale": 1.0,
                                        "src": "NewUI2 %s, its top rail swept round a square (rail %d px)" % (s.key, s.T)}
        line = "%-4s borders/%-4s %dx%d rail %d" % (s.key, name, master.shape[1], master.shape[0], s.T)
        if gem is not None:
            png(gem, os.path.join(SRC, "borders", name + "_gem.png"))
            man["v2_2x/borders/" + name + "_gem"] = {"w": int(gem.shape[1]), "h": int(gem.shape[0]), "scale": 1.0,
                                                     "src": "NewUI2 %s, its top left corner's stud" % s.key}
            line += "   gem %dx%d off (%.3f, %.3f)" % (gem.shape[1], gem.shape[0], s.gem_off[0], s.gem_off[1])
        print(line)
    # the two rings picked (the same decision; border library stage 4, user 2026-10-06 "Do them now"): R1 four
    # diamond studs, R3 plain heavy ring -- each made symmetric from its top left quarter (the sketch's Ring), in the
    # sheet's own colours as the squares are. Their elite / rare / boss twins are the ring itself in the marks'
    # metals (Tools/kit_marks.py: one canvas, so a swap needs no refit; the sheet's own gold ring has other geometry)
    for r in P.rings():
        name = PICKED_RINGS.get(r.key)
        if not name:
            continue
        png(r.raw, os.path.join(SRC, "rings", name + ".png"))
        man["v2_2x/rings/" + name] = {"w": int(r.n), "h": int(r.n), "scale": 1.0,
                                      "src": "NewUI2 %s, its top left quarter mirrored round" % r.key}
        print("%-4s rings/%-3s %dx%d opening r %.1f (asymmetry %.1f)" % (r.key, name, r.n, r.n, r.r_in, r.asym))
    # the two NewUI2 textures picked as background choices (the same decision): the brushed dark metal (8d, the
    # kit_v3 tools' seamless tile, toned per look as the cracked concrete) and the aged parchment (8f, as painted,
    # after a seamless pass: its wrap showed a seam 2.2x its grain); kept as sources/ (build_kit.py lays them as
    # tiles/brushedmetal and tiles/agedparchment, 512 piece px as tiles/concrete, never as pieces of their own)
    for name, path, seam in (("tile8d", os.path.join(SIBLING, "kit_v3", "tools", "tile8d_seamless.png"), 0),
                             ("tile8f", os.path.join(os.path.expanduser("~"), "Downloads", "NewUI2",
                                                     "8f_Seamless Aged Parchment Texture.png"), 48)):
        a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
        if seam:
            a = Seamless(a, seam)
        png(a, os.path.join(SRC, "sources", name + ".png"))
        man["v2_2x/sources/" + name] = {"w": int(a.shape[1]), "h": int(a.shape[0]), "scale": 1.0,
                                        "src": os.path.basename(path) + (" made seamless (%d px)" % seam if seam else "")}
        print("tile %s %dx%d%s" % (name, a.shape[1], a.shape[0], " (seamless pass)" if seam else ""))
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    print("-> %s (+ manifest); next: python Tools/build_kit.py" % os.path.join(SRC, "borders"))


def Seamless(a, b):
    """(kit_v3/tools/seamless.py) the last b rows and columns cross-faded into the first b, the tile shortened by b"""
    for axis in (1, 0):
        m = np.moveaxis(a, axis, 0)
        n = m.shape[0]
        out = m[:n - b].copy()
        t = ((np.arange(b) + 0.5) / b).reshape((b,) + (1,) * (m.ndim - 1))
        out[:b] = m[:b] * t + m[n - b:] * (1 - t)
        a = np.moveaxis(out, 0, axis)
    return a


if __name__ == "__main__":
    main()
