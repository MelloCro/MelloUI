"""The swing badge's rings (2.1.42; CurseForge: the ring "is hard to see often times. More width and color options for that
bar would be awesome"; the user's picks of Workspace/BuildData/output/swing_ring_sketch: Thin, Medium and Thick, Thin by
default; a colour wheel; a dark track under the part still to fill).

Three bands on Media/Textures/Icons/ring_gold's profile (measured: opaque from 63 of 128 px from the middle; a dark
outer edge about 4.5 px, the gold about 5, a dark grey inner edge about 4), white and shaded -- lit from the top, the
band's middle brightest -- so the badge's colour tints them (Cooldown:SetSwipeColor, Texture:SetVertexColor): thin's
bright band as wide as ring_gold's (today's ring), medium's and thick's wider (the sketch's 20 and 28 of 128 in all),
the same dark edges.

    python Tools/make_swing_rings.py  ->  Media/Textures/Swing/ring_thin.tga, ring_medium.tga, ring_thick.tga
"""
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Textures", "Swing")
SIZE = 128
SUPER = 4          # drawn this many times larger, then scaled down: smooth edges at the file's size
OUTER = 63         # the ring's outer edge, from the middle (ring_gold's)
DARK_OUT, DARK_IN = 4.5, 3.5   # its dark edges, outside and in (ring_gold's)
OUT_RGB, IN_RGB = (5, 5, 8), (28, 31, 33)
BANDS = {"thin": 5.5, "medium": 12, "thick": 20}   # the bright band between the edges


def ring(band):
    s = SIZE * SUPER
    k = SUPER
    c = s / 2
    ro = OUTER * k
    bo = (OUTER - DARK_OUT) * k            # the bright band's outer edge
    bi = (OUTER - DARK_OUT - band) * k     # its inner edge
    ri = bi - DARK_IN * k                  # the ring's inner edge
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = im.load()
    for y in range(s):
        for x in range(s):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if d < ri or d > ro:
                continue
            if d > bo:
                px[x, y] = OUT_RGB + (255,)
                continue
            if d < bi:
                px[x, y] = IN_RGB + (255,)
                continue
            t = (d - bi) / max(1e-6, bo - bi)
            # (white at its brightest: tinted by the palette's gold it is as bright as ring_gold's)
            light = 1.14 - 0.26 * (y / s)
            mid = 1.0 - 0.22 * abs(t - 0.45) * 2
            v = max(0, min(255, int(255 * light * mid)))
            px[x, y] = (v, v, v, 255)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, band in BANDS.items():
        path = os.path.join(OUT, "ring_" + name + ".tga")
        ring(band).save(path)
        print(path)


if __name__ == "__main__":
    main()
