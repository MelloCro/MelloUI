"""
Build the widget column's two textures (0.16.0; Core/Reminders.lua, "The
column": Voice Over and the other widgets, the user's picked look of
2026-09-29, docs/plans/next-update-refs/voiceover_widget_picked.jpg):

    Textures/ProgressRing.tga    the gold ring round a widget's face that
                                 fills clockwise as its time runs (drawn by
                                 a Cooldown frame's swipe, SetSwipeTexture,
                                 so the engine animates it: no Lua per frame)
    Textures/WidgetGlyphs.tga    the small buttons' glyphs (pause, play,
                                 skip, stop, list, lock, unlock, check,
                                 cross, the way, reply), one 32 px cell each

Both are WHITE where they draw, their alpha the picture, so the game tints
them with a palette colour (the ring with selectedTrim, its dim track with
innerPanel; a glyph with text): every palette gets them in its own colours.

The ring (128 x 128): a band from RING_IN to RING_OUT of the half-width.
Its colour channels carry the metal's relief: bright along the band's
middle, falling to EDGE at both sides (the kit art rule: a rail keeps its
dark edge lines, its shadow), so a gold tint reads as a gilt rim with dark
edges. Drawn by the swipe over a frame RING_FRAME times the face's size,
the band lies just outside the face's round rim.

The glyphs (256 x 64: 8 x 2 cells of 32 px, in GLYPHS order, left to right,
top row first): drawn at 8 times the size with PIL and averaged down, so
their edges are smooth at any size.

Writes the TGA masters (MelloUI-BuildData/masters/Media/Textures/,
Tools/paths.py) and byte copies into the addon's Media/Textures/ so they
ship at once; `texture_pack.py ship` keeps them as their masters' bytes
(STAY_TGA: smooth alpha ramps, DXT bands them). Deterministic: the same
script gives the same bytes.

    python Tools/make_widget_art.py            write them
    python Tools/make_widget_art.py --check    exit 1 unless all are up to date
"""
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from paths import ADDON_MEDIA, master

RING_NAME = ("Textures", "ProgressRing.tga")
GLYPH_NAME = ("Textures", "WidgetGlyphs.tga")

RING_SIZE = 128
RING_IN, RING_OUT = 0.870, 0.985   # the band, shares of the half-width
RING_FRAME = 1.16                  # the swipe's frame against the face (Core/Reminders.lua RING_FRAME)
EDGE = 0.30                        # the band's edge brightness (its middle: 1)
SUPER = 4

CELL = 32
BIG = 8                            # drawn at CELL * BIG, averaged down
GLYPHS = ("pause", "play", "skip", "stop", "list", "padlock", "padlockOpen", "check",
          "cross", "way", "reply", "friend", "invite", "ignore", "report")


def smootherstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * t * (t * (t * 6 - 15) + 10)


def ring():
    n = RING_SIZE * SUPER
    c = (np.arange(n) + 0.5) / n * 2.0 - 1.0
    r = np.sqrt(c[None, :] ** 2 + c[:, None] ** 2)
    aa = 1.5 / RING_SIZE   # a texel and a half of soft edge
    a = smootherstep((r - RING_IN) / aa + 0.5) * (1.0 - smootherstep((r - RING_OUT) / aa + 0.5))
    mid = (RING_IN + RING_OUT) / 2
    half = (RING_OUT - RING_IN) / 2
    t = np.clip(np.abs(r - mid) / half, 0.0, 1.0)
    # the relief: a soft round top, dark lines at both edges
    light = EDGE + (1.0 - EDGE) * (1.0 - smootherstep((t - 0.25) / 0.75))
    a = a.reshape(RING_SIZE, SUPER, RING_SIZE, SUPER).mean(axis=(1, 3))
    light = light.reshape(RING_SIZE, SUPER, RING_SIZE, SUPER).mean(axis=(1, 3))
    img = np.zeros((RING_SIZE, RING_SIZE, 4), np.uint8)
    v = np.clip(light * 255 + 0.5, 0, 255).astype(np.uint8)
    img[..., 0] = v
    img[..., 1] = v
    img[..., 2] = v
    img[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    return img


def glyph(name):
    s = CELL * BIG
    im = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(im)
    k = s / 32.0   # glyph units: a 32-unit cell

    def P(*pts):
        return [(x * k, y * k) for x, y in pts]

    def box(x0, y0, x1, y1, r=0):
        d.rounded_rectangle((x0 * k, y0 * k, x1 * k, y1 * k), radius=r * k, fill=255)

    def line(pts, w):
        d.line(P(*pts), fill=255, width=int(w * k), joint="curve")
        for x, y in pts:   # round caps
            d.ellipse(((x - w / 2) * k, (y - w / 2) * k, (x + w / 2) * k, (y + w / 2) * k), fill=255)

    if name == "pause":
        box(9, 7, 14, 25, 1.2)
        box(18, 7, 23, 25, 1.2)
    elif name == "play":
        d.polygon(P((10, 6.5), (25.5, 16), (10, 25.5)), fill=255)
    elif name == "skip":
        d.polygon(P((7.5, 7), (19.5, 16), (7.5, 25)), fill=255)
        box(20.5, 7, 24.5, 25, 1)
    elif name == "stop":
        box(8, 8, 24, 24, 2.5)
    elif name == "list":
        for y in (9, 16, 23):
            d.ellipse(((6.5) * k, (y - 2) * k, (10.5) * k, (y + 2) * k), fill=255)
            box(13, y - 1.7, 26, y + 1.7, 1.5)
    elif name in ("padlock", "padlockOpen"):
        box(8, 14, 24, 27, 2.5)
        # the shackle: a thick arch, open (lifted to the right) when unlocked
        w = 3.2
        x0, x1 = (11, 21) if name == "padlock" else (15, 25)
        top = 5 if name == "padlock" else 3
        d.arc((x0 * k, top * k, x1 * k, (top + 11) * k), 180, 360, fill=255, width=int(w * k))
        box(x0, top + 5, x0 + w, 15, 0)
        # (open: the lifted leg stops short of the body)
        box(x1 - w, top + 5, x1, 15 if name == "padlock" else 11, 0)
        # the keyhole
        d.ellipse((14.2 * k, 17.5 * k, 17.8 * k, 21.1 * k), fill=0)
        d.polygon(P((15.2, 20), (16.8, 20), (17.3, 24), (14.7, 24)), fill=0)
    elif name == "check":
        line([(7.5, 16.5), (13.5, 22.5), (24.5, 9.5)], 3.6)
    elif name == "cross":
        line([(9, 9), (23, 23)], 3.6)
        line([(23, 9), (9, 23)], 3.6)
    elif name == "way":
        # a map pin: a round head over a point, a hole in the head
        d.ellipse((8 * k, 4.5 * k, 24 * k, 20.5 * k), fill=255)
        d.polygon(P((9.3, 16), (22.7, 16), (16, 28)), fill=255)
        d.ellipse((12.8 * k, 9.3 * k, 19.2 * k, 15.7 * k), fill=0)
    elif name == "reply":
        box(5, 7, 27, 21, 4.5)
        d.polygon(P((9, 19), (15, 19), (8, 27)), fill=255)
    # (0.16.0, the whisper window's header, user 2026-09-30: add friend, invite, ignore, report)
    elif name in ("friend", "ignore"):
        # a person: the head and the shoulders
        d.ellipse((7 * k, 5 * k, 15 * k, 13 * k), fill=255)
        d.pieslice((4 * k, 14 * k, 18 * k, 30 * k), 180, 360, fill=255)
        if name == "friend":
            line([(23.5, 10), (23.5, 20)], 3.4)
            line([(18.5, 15), (28.5, 15)], 3.4)
        else:
            # a "no" sign over the shoulder
            d.ellipse((16 * k, 14 * k, 29 * k, 27 * k), fill=0)
            d.ellipse((17 * k, 15 * k, 28 * k, 26 * k), outline=255, width=int(2.6 * k))
            line([(19.3, 23.7), (25.7, 17.3)], 2.6)
    elif name == "invite":
        # two people and a plus: a group
        for ox in (0, 8):
            d.ellipse(((5 + ox) * k, 7 * k, (11 + ox) * k, 13 * k), fill=255)
            d.pieslice(((3 + ox) * k, 14 * k, (13 + ox) * k, 27 * k), 180, 360, fill=255)
        line([(25.5, 14), (25.5, 24)], 3.2)
        line([(20.5, 19), (30.5, 19)], 3.2)
    elif name == "report":
        # a flag on its pole
        line([(9, 5), (9, 27)], 3.2)
        d.polygon(P((10, 5.5), (25, 10), (10, 15.5)), fill=255)
    else:
        raise ValueError(name)
    return im.resize((CELL, CELL), Image.BOX)


def glyph_sheet():
    cols, rows = 8, 2
    sheet = np.zeros((rows * CELL, cols * CELL, 4), np.uint8)
    sheet[..., :3] = 255
    for i, name in enumerate(GLYPHS):
        x, y = (i % cols) * CELL, (i // cols) * CELL
        sheet[y:y + CELL, x:x + CELL, 3] = np.asarray(glyph(name), np.uint8)
    return sheet


def tga(img):
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
    files = [(RING_NAME, tga(ring())), (GLYPH_NAME, tga(glyph_sheet()))]
    stale = []
    for name, data in files:
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
            continue
        for path in targets:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            print("->", os.path.normpath(path))
        print(name[-1], "sha256", digest)
    if "--check" in sys.argv:
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("ok" if not stale else "STALE")
        return 1 if stale else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
