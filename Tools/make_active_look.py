"""
Build Textures/ActiveLook.tga: the active look MelloUI lays round every button,
tab and row the game or MelloUI shows as active, checked or selected
(Kit:SetActive, Modules/Kit.lua; 0.15.0, user 2026-09-28: "people cant see in
which stance they are as a warrior ... dont just make the stance bar, do it
across the board"; option C of the sketch: a thick gold ring lit additively,
a soft halo just outside it and a soft glow inside its edge).

Four cells of 128 x 128 px in a 256 x 256 file, every one WHITE, its alpha the
picture, so the game tints it with a palette colour:

    top left      the LIGHT round a square or oblong rect: the ring, the halo
                  outside it, the glow inside it. Tinted with the palette's
                  selectedTrim and added as light (ADD blend). Cut into nine
                  in game: its corners CORNER units square, its edges uniform
                  along their length, its middle never drawn
    top right     the ring's two dark EDGE lines (the kit art rule: a rail
                  keeps its dark edge lines, its shadow), one just outside
                  the ring and a heavier one inside it. Tinted with the
                  palette's innerPanel and blended over the light
    bottom left   the light round a ROUND rect (a round rim): one texture
    bottom right  its edge lines

The picture is drawn round a HOST-unit square (the look at scale 1, on a
45-unit action button), D texels a unit: the cell is that square with HALO
units round it. Across the rect's edge, from the outside in:

    HALO     units of soft light outside the rect (to the texture's edge)
    ring     RING_H units deep along the top and bottom, RING_V along the
             sides (the kit's horizontal rails are heavier than its vertical
             ones), full light
    GAP      a unit of no light under the inner dark line
    GLOW     units of soft light fading inward
The outer dark line lies OUT_W units just outside the ring, over the halo's
start. INNER = the ring's depth + GAP + GLOW, CORNER = HALO + INNER: what
Kit.lua's ACTIVE geometry must say (the tests check it).

The square cell draws the HOST square from HALO units in, its corners
rounded by CORNER_R units. In game it is drawn WHOLE round a square button
(the texture reaching HALO / HOST of the button's size past each side, one
texture a layer), or cut into nine round an oblong rect (a tab, a row): every
feature of one edge stays CORNER units from the rect's corner, so the strip
between two corners is the same all along (CUT: the corner's share of the
cell). The round cell draws a circle HOST units across, drawn whole round a
round rim the same way. The curves are smootherstep, flat where they start
and end, and each texel is the mean of SUPER x SUPER samples.

Writes the TGA master (MelloUI-BuildData/masters/Media/Textures/,
Tools/paths.py) and a byte copy into the addon's Media/Textures/ so it ships
at once; `texture_pack.py ship` keeps it as its master's bytes (STAY_TGA: a
smooth alpha ramp, DXT bands it). Deterministic: the same script gives the
same bytes. `--preview <picture> <out.png> x0 y0 x1 y1 [...]` draws the look
at those button boxes of a screenshot, as the game adds it (for the eye; the
preview never ships).

    python Tools/make_active_look.py            write both
    python Tools/make_active_look.py --check    exit 1 unless both are up to date
"""
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image
from paths import ADDON_MEDIA, master

NAME = ("Textures", "ActiveLook.tga")
CELL = 128          # px, each cell square
HOST = 45.0         # units: the square the cells are drawn round (an action button at scale 1)
HALO = 8.0          # units of light outside the rect
RING_H = 3.4        # the ring's depth along the top and bottom edges
RING_V = 3.0        # ... along the sides
GAP = 1.0           # no light under the inner dark line
GLOW = 8.0          # units of glow fading inward
OUT_W = 0.9         # the outer dark line, just outside the ring
CORNER_R = 1.5      # the rect's corner radius (units)
HALO_PEAK, HALO_POW = 0.85, 1.3
GLOW_PEAK, GLOW_POW = 0.6, 1.3
LINE_OUT, LINE_IN = 0.5, 0.78   # the dark lines' strength
SUPER = 4           # samples per texel, each way

RING = RING_V                     # the depth the inner features are measured in
INNER = RING + GAP + GLOW         # 12 units inside the rect
CORNER = HALO + INNER             # 20 units: the nine-slice's corner
D = CELL / (HOST + 2 * HALO)      # texels per unit (128 px for 61 units)
CUT = CORNER / (HOST + 2 * HALO)  # the corner as a share of the cell
PAD = HALO / HOST                 # a whole cell reaches this share of its square past each side


def smootherstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * t * (t * (t * 6 - 15) + 10)


def samples():
    """sample centres of one cell in units from its top-left corner (y down)"""
    n = CELL * SUPER
    c = (np.arange(n) + 0.5) / SUPER / D
    return c[None, :], c[:, None]


def profiles(outside, inner):
    """light and edge alpha from the distance outside the rect (units, 0 inside it)
    and the depth inside it (units, measured in RING's scale; 0 outside it)"""
    ins = outside <= 0
    light = np.zeros(np.broadcast(outside, inner).shape)
    edge = np.zeros_like(light)
    # outside: the halo, and the outer dark line on its start
    halo = HALO_PEAK * (1.0 - smootherstep(outside / HALO)) ** HALO_POW
    light = np.where(~ins, halo, light)
    edge = np.where(~ins & (outside < OUT_W), LINE_OUT, edge)
    # inside: the ring, the inner line (no light under it), the glow
    glow = GLOW_PEAK * (1.0 - smootherstep((inner - RING - GAP) / GLOW)) ** GLOW_POW
    light = np.where(ins & (inner < RING), 1.0, light)
    light = np.where(ins & (inner >= RING + GAP), glow, light)
    edge = np.where(ins & (inner >= RING) & (inner < RING + GAP), LINE_IN, edge)
    return light, edge


def depth(d, ring):
    """a depth from an edge whose ring is `ring` units deep, in RING's scale:
    [0, ring] -> [0, RING], [ring, INNER] -> [RING, INNER]"""
    return np.where(d < ring, d * (RING / ring), RING + (d - ring) * ((INNER - RING) / (INNER - ring)))


def square_cell():
    x, y = samples()
    lo, hi = HALO, HALO + HOST                      # the rect's edges, units
    # outside: the distance to the rect with rounded corners
    cx, cy = (lo + hi) / 2, (lo + hi) / 2
    half = (hi - lo) / 2 - CORNER_R
    qx, qy = np.abs(x - cx) - half, np.abs(y - cy) - half
    outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - CORNER_R
    outside = np.maximum(outside, 0)
    # inside: the depth from the nearest edge, the top and bottom ones
    # measured in their heavier ring's scale (the ring RING_H deep, the rest
    # of the INNER units shared out after it, so every edge's features end
    # INNER units in: the strips between the corners stay uniform)
    dx = depth(np.minimum(x - lo, hi - x), RING_V)
    dy = depth(np.minimum(y - lo, hi - y), RING_H)
    inner = np.maximum(np.minimum(dx, dy), 0)
    return profiles(outside, inner)


def round_cell():
    x, y = samples()
    c = CELL / D / 2
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2)
    radius = HOST / 2
    outside = np.maximum(r - radius, 0)
    inner = np.maximum(radius - r, 0)
    return profiles(outside, inner)


def mean(a):
    return a.reshape(CELL, SUPER, CELL, SUPER).mean(axis=(1, 3))


def alpha():
    """the file's alpha, 0..1, 256 x 256 (rows top down)"""
    out = np.zeros((2 * CELL, 2 * CELL))
    for row, cell in ((0, square_cell()), (1, round_cell())):
        light, edge = cell
        out[row * CELL:(row + 1) * CELL, :CELL] = mean(light)
        out[row * CELL:(row + 1) * CELL, CELL:] = mean(edge)
    return out


def build():
    img = np.zeros((2 * CELL, 2 * CELL, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = np.clip(alpha() * 255 + 0.5, 0, 255).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(img, "RGBA").save(buf, format="TGA")
    return buf.getvalue()


# ------------------------------------------------------------------ the preview
GOLD = (174, 133, 70)        # Ember's selectedTrim (the game paints the palette's own)
INK = (17, 16, 13)           # Ember's innerPanel


def nine(cell, w, h, k):
    """a cell cut into nine and laid round a w x h rect at scale k, as Kit.lua lays it:
    the picture (alpha), (w + 2 * HALO * k) x (h + 2 * HALO * k) px"""
    c = int(round(CORNER * k))
    ow, oh = int(round(w + 2 * HALO * k)), int(round(h + 2 * HALO * k))
    src = Image.fromarray(np.clip(cell * 255, 0, 255).astype(np.uint8))
    cut = int(round(CUT * CELL))
    out = Image.new("L", (ow, oh), 0)
    if abs(w - h) < 0.5:
        # a square: the whole cell, as the game draws a square button's
        return np.asarray(src.resize((ow, oh), Image.BICUBIC), np.float64) / 255
    xs = [(0, cut, 0, c), (cut, CELL - cut, c, ow - c), (CELL - cut, CELL, ow - c, ow)]
    ys = [(0, cut, 0, c), (cut, CELL - cut, c, oh - c), (CELL - cut, CELL, oh - c, oh)]
    for i, (sy0, sy1, dy0, dy1) in enumerate(ys):
        for j, (sx0, sx1, dx0, dx1) in enumerate(xs):
            if i == 1 and j == 1 or dx1 <= dx0 or dy1 <= dy0:
                continue
            out.paste(src.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.BICUBIC), (dx0, dy0))
    return np.asarray(out, np.float64) / 255


def preview(picture, target, boxes):
    """the look (and the icon lifted 1.2 x) at each box of a screenshot, the light
    added and the lines blended, as in game (k: the box's short side / 45)"""
    im = np.asarray(Image.open(picture).convert("RGB"), np.float64)
    a = alpha()
    light, edge = a[:CELL, :CELL], a[:CELL, CELL:]
    gold, ink = np.array(GOLD, np.float64), np.array(INK, np.float64)
    for x0, y0, x1, y1 in boxes:
        w, h = x1 - x0, y1 - y0
        k = min(w, h) / 45.0
        face = im[y0 + 3:y1 - 3, x0 + 3:x1 - 3]
        im[y0 + 3:y1 - 3, x0 + 3:x1 - 3] = np.minimum(face * 1.2, 255)
        lt, ed = nine(light, w, h, k), nine(edge, w, h, k)
        pad = int(round(HALO * k))
        X0, Y0 = x0 - pad, y0 - pad
        region = im[Y0:Y0 + lt.shape[0], X0:X0 + lt.shape[1]]
        region += lt[..., None] * gold
        np.minimum(region, 255, out=region)
        region[:] = region * (1 - ed[..., None]) + ink * ed[..., None]
    Image.fromarray(np.clip(im, 0, 255).astype(np.uint8)).save(target)
    print("->", target)


def main():
    args = sys.argv[1:]
    if args[:1] == ["--preview"] and len(args) >= 7 and (len(args) - 3) % 4 == 0:
        nums = [int(v) for v in args[3:]]
        preview(args[1], args[2], [tuple(nums[i:i + 4]) for i in range(0, len(nums), 4)])
        return 0
    # an argument it does not know (--help, a typo) writes nothing
    bad = [a for a in args if a != "--check"]
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    data = build()
    targets = [master(*NAME), os.path.join(ADDON_MEDIA, *NAME)]
    digest = hashlib.sha256(data).hexdigest()
    if "--check" in args:
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
    print("geometry: HOST %.1f HALO %.1f INNER %.1f CORNER %.1f -> CUT %.6f, PAD %.6f (Kit.lua's active look)" % (
        HOST, HALO, INNER, CORNER, CUT, PAD))
    return 0


if __name__ == "__main__":
    sys.exit(main())
