"""
Build Textures/Masks/BarEnd.tga and BarEndR.tga: the masks of a bar's soft ends (Modules/BarTextures.lua's soft ends; the user,
2026-10-16: "this texture that you made on the Party Unitframe Health and Mana bar, can you reflect that change to
every texture in the UI i really low the dimmed edges").

The party bars' dimmed ends were a plain white mask clamped to black, stretched over the bar: the game's bilinear
filter falls from full to half alpha over the last half texel at each end. That length grows with the bar (a 16th
of its width), so the look is rebuilt with a fixed length: this file is one end of it -- white, its alpha rising in a
straight line from half at its left edge to full at its right -- laid over a bar's first SOFT_END units, its far side
clamped (the edge texel, full) so the rest of the bar passes; BarEndR is its mirror, for the right end.

Writes the TGA master (MelloUI-BuildData/masters/Media/Textures/Masks/, Tools/paths.py) and a byte copy into the
addon's Media/Textures/Masks/ so it ships at once. Deterministic: the same script gives the same bytes.

    python Tools/make_bar_end.py            write both
    python Tools/make_bar_end.py --check    exit 1 unless both are up to date
"""
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image
from paths import ADDON_MEDIA, master

NAMES = (("Textures", "Masks", "BarEnd.tga"), ("Textures", "Masks", "BarEndR.tga"))
W, H = 32, 4
LOW = 0.5   # the alpha at the bar's very edge (the half texel's)


def build(mirror=False):
    xs = np.arange(W) / (W - 1)
    a = LOW + (1 - LOW) * (xs[::-1] if mirror else xs)
    img = np.zeros((H, W, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = np.clip(np.tile(a, (H, 1)) * 255 + 0.5, 0, 255).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(img, "RGBA").save(buf, format="TGA")
    return buf.getvalue()


def main():
    bad = [a for a in sys.argv[1:] if a != "--check"]
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    stale = []
    for i, name in enumerate(NAMES):
        data = build(mirror=i == 1)
        targets = [master(*name), os.path.join(ADDON_MEDIA, *name)]
        digest = hashlib.sha256(data).hexdigest()
        if "--check" in sys.argv:
            for path in targets:
                try:
                    with open(path, "rb") as f:
                        if f.read() != data:
                            stale.append(path)
                except OSError:
                    stale.append(path)
            print(name[-1], "sha256", digest)
            continue
        for path in targets:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            print("->", os.path.normpath(path))
        print("sha256", digest)
    if "--check" in sys.argv:
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("ok" if not stale else "STALE")
        return 1 if stale else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
