"""
Build Textures/SoftGlowRound.tga: the round soft glow MelloUI lays around a
round button (MelloUI.Shade:Glow, Core/Shade.lua; the Reminder widget is its
first user: "make sure that widget has a nice glow around it", user,
2026-09-26 -- round and baked, never a square).

A white texture whose alpha is a ring of light, tinted in game with a palette
colour (selectedTrim, gold, by default) and added as light (ADD blend):

    0 .. INNER    clear: the button's own face shows, never lit over
    INNER .. PEAK rises smoothly to full, just past the ring's edge (RING)
    PEAK .. 1     falls smoothly to nothing at the texture's edge

The distances are shares of the texture's half-width. The ring the glow lies
around has its edge at RING, so in game the texture reaches
(1 / RING - 1) / 2 of the ring's size past each side of it: Core/Shade.lua's
GLOW_RING must equal RING (the tests check it). The curves are smootherstep,
flat where they start and end: no visible line anywhere; the fall is raised
to FALL_POWER, so the light is bright near the ring and trails off softly.
Each texel is the mean of SUPER x SUPER samples, so the ring's inner rise is
smooth at any size. 128 x 128 px (a 36-unit ring's glow is 50 units wide).
The ring at 0.72 (2026-10-04, the user: the widgets' glow "kind of too big";
it was 0.60, reaching a third of the ring's size past each side, now about a
fifth), the clear middle and the peak moved out with it.

Writes the TGA master (MelloUI-BuildData/masters/Media/Textures/, Tools/paths.py)
and a byte copy into the addon's Media/Textures/ so it ships at once;
`texture_pack.py ship` keeps it as its master's bytes once STAY_TGA lists it
(a smooth alpha ramp: DXT bands it). Deterministic: the same script gives
the same bytes.

    python Tools/make_soft_glow.py            write both
    python Tools/make_soft_glow.py --check    exit 1 unless both are up to date
"""
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image
from paths import ADDON_MEDIA, master

NAME = ("Textures", "SoftGlowRound.tga")
SIZE = 128        # px, square
RING = 0.72       # the ring's edge (Core/Shade.lua GLOW_RING; 0.60 until 2026-10-04)
INNER = 0.62      # clear inside this (0.50)
PEAK = 0.77       # full here: just outside the ring's edge (0.66)
FALL_POWER = 1.8  # the fall's shape: above 1, brighter near the ring, a longer soft tail
SUPER = 4         # samples per texel, each way


def smootherstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * t * (t * (t * 6 - 15) + 10)


def profile(r):
    """The glow's alpha (0..1) at r, a share of the half-width."""
    rise = smootherstep((r - INNER) / (PEAK - INNER))
    fall = (1.0 - smootherstep((r - PEAK) / (1.0 - PEAK))) ** FALL_POWER
    return np.where(r < PEAK, rise, fall) * (r < 1.0)


def alpha():
    """The texture's alpha, 0..1, SIZE x SIZE (the mean of the samples)."""
    n = SIZE * SUPER
    c = (np.arange(n) + 0.5) / n * 2.0 - 1.0          # sample centres, -1..1
    r = np.sqrt(c[None, :] ** 2 + c[:, None] ** 2)
    a = profile(r)
    return a.reshape(SIZE, SUPER, SIZE, SUPER).mean(axis=(1, 3))


def build():
    img = np.zeros((SIZE, SIZE, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = np.clip(alpha() * 255 + 0.5, 0, 255).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(img, "RGBA").save(buf, format="TGA")
    return buf.getvalue()


def main():
    # an argument it does not know (--help, a typo) writes nothing
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
