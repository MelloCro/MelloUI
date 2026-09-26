"""
Build Textures/SoftShade.tga: the soft band MelloUI lays behind text to make
it readable without an outline (MelloUI.Shade, Core/Shade.lua; the on-screen
notice is its first user, the nameplates' names follow).

The game cannot blur what is behind a frame, so the blur is faked: a white
texture whose alpha falls off smoothly, tinted in game with a dark palette
colour. It is drawn as three slices of this one file, so the ends keep their
shape whatever the band's length:

    left quarter   the left end: alpha rises from 0 to full, left to right
    middle half    full across (stretched to any length in game)
    right quarter  the right end, the mirror of the left

Top and bottom fade softly (full in the middle 30 %, falling off over the
outer 35 % each side), so the band has no hard edge anywhere. The curves are
smootherstep, which starts and ends flat: no visible line where the fade
begins. 2x like the kit: 128 x 64 px.

Writes the TGA master (MelloUI-BuildData/masters/Media/Textures/, Tools/paths.py)
and a byte copy into the addon's Media/Textures/ so it ships at once;
`texture_pack.py ship` may later replace that copy with its own build.
Deterministic: the same script gives the same bytes.

    python Tools/make_soft_shade.py            write both
    python Tools/make_soft_shade.py --check    exit 1 unless both are up to date
"""
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image
from paths import ADDON_MEDIA, master

NAME = ("Textures", "SoftShade.tga")
W, H = 128, 64
CAP = 0.25        # each end's share of the width (the slices' texcoords: 0-0.25, 0.25-0.75, 0.75-1)
FLAT_V = 0.30     # the middle share of the height at full alpha


def smootherstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * t * (t * (t * 6 - 15) + 10)


def build():
    xs = (np.arange(W) + 0.5) / W
    ys = (np.arange(H) + 0.5) / H
    fall = (1 - FLAT_V) / 2
    v = smootherstep(np.minimum(ys, 1 - ys) / fall)
    # the ends reach full exactly at the slice line, so the stretched middle
    # meets them without a seam
    h = smootherstep(np.minimum(xs, 1 - xs) / CAP)
    a = np.outer(v, h)
    img = np.zeros((H, W, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(img, "RGBA").save(buf, format="TGA")
    return buf.getvalue()


def main():
    # an argument it does not know (--help, a typo) writes nothing: without
    # this it fell through to the write mode
    bad = [a for a in sys.argv[1:] if a != "--check"]
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    data = build()
    targets = [master(*NAME), os.path.join(ADDON_MEDIA, *NAME)]
    digest = hashlib.sha256(data).hexdigest()
    if "--check" in sys.argv:
        stale = []
        for path in targets:
            try:
                with open(path, "rb") as f:
                    if f.read() != data:
                        stale.append(path)
            except OSError:
                stale.append(path)
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("sha256", digest, "ok" if not stale else "STALE")
        return 1 if stale else 0
    for path in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        print("->", os.path.normpath(path))
    print("sha256", digest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
