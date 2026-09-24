"""Painted-edge masks for the kit (user's pick B of kit_raw/edge_mask_catalog.png,
2026-09-23: "dry brush", on the spell book's parchment pages; softened the same
day to pick B2 of a second catalogue -- "its too spikey": longer, evener strokes
whose ends ease into the next, no bristle streaks, a softer edge).

A corner mask is opaque except along its LEFT and TOP sides, where bristle
strokes of uneven length reach in from the edge. In the game two of them sit on
one texture -- this one at its top-left, its 180-degree twin at its
bottom-right -- so all four sides of a page get the rough edge at any size up
to the mask's own (512 UI units). Drawn procedurally, seeded, so a rebuild
gives the same edge.

Writes Media/Textures/Masks/edge_brush_tl.tga and edge_brush_br.tga
(32-bit, white where the page shows, the mask in both the colour and the alpha),
and the FINE pair edge_brush_fine_tl / _br: the same strokes a third as deep,
for a wide panel whose text runs close to its edge (user, 2026-09-23: "lets
make the chat fit onto the parchment"), and the WIDE pair edge_brush_wide_tl /
_br: deep strokes on the left and right, shallow ones top and bottom (the chat
windows, whose backdrop can grow sideways but not into the tabs above and the
input box below).

    python Tools/make_edge_mask.py
"""
import os
import random

from PIL import Image
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

OUT = master("Textures", "Masks")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
DRAW = 1024      # drawn at twice the file's size, then halved: smoother bristles
FILE = 512       # the file: 512 x 512, shown 1:1 (512 UI units)
EDGE = 36        # how deep the strokes reach at DRAW size (18 UI units on screen)
FINE_EDGE = 12   # the fine pair: a third as deep (6 units at 512)
SEED = 1235


def fbm(n, octaves, seed, rough=0.55):
    """1-D fractal noise, n samples in -1..1."""
    rnd = random.Random(seed)
    out = [0.0] * n
    amp, total, step = 1.0, 0.0, n / 4
    for _ in range(octaves):
        pts = max(2, int(n / step) + 2)
        knots = [rnd.uniform(-1, 1) for _ in range(pts)]
        for i in range(n):
            x = i / step
            k = int(x)
            f = x - k
            f = f * f * (3 - 2 * f)
            out[i] += amp * (knots[k] * (1 - f) + knots[k + 1] * f)
        total += amp
        amp *= rough
        step = max(1.0, step / 2)
    return [v / total for v in out]


def profile(seed, depth=EDGE):
    """How far into the mask the paint starts, per row: strokes of fairly
    even length and reach, a slow wander, soft stroke ends."""
    n = DRAW
    slow = fbm(n, 3, seed, 0.5)
    rnd = random.Random(seed + 7)
    raw, stroke, length = [], 0, 0.0
    for i in range(n):
        if stroke <= 0:
            stroke = rnd.randint(10, 26)
            length = rnd.betavariate(2, 2)
        stroke -= 1
        raw.append(depth * (0.25 + 0.45 * length) + depth * 0.12 * slow[i])
    # each stroke's end eased into the next over a few rows (a soft bite,
    # not a tooth), then the whole line smoothed
    out, i = raw[:], 0
    while i < n:
        j = i
        while j + 1 < n and raw[j + 1] == raw[i]:
            j += 1
        if j + 1 < n:
            a, b, w = raw[j], raw[j + 1], 6
            for k in range(-w, w + 1):
                t = (k + w) / (2 * w)
                t = t * t * (3 - 2 * t)
                if 0 <= j + k < n:
                    out[j + k] = a + (b - a) * t
        i = j + 1
    raw = out
    for _ in range(8):
        raw = [(raw[max(0, i - 1)] + 2 * raw[i] + raw[min(n - 1, i + 1)]) / 4 for i in range(n)]
    return raw


def corner_mask(depth=EDGE, top_depth=None):
    top_depth = depth if top_depth is None else top_depth
    left, top = profile(SEED, depth), profile(SEED + 101, top_depth)
    feather = 3.5
    img = Image.new("L", (DRAW, DRAW), 255)
    px = img.load()
    for y in range(DRAW):
        for x in range(depth * 2):
            px[x, y] = int(255 * max(0.0, min(1.0, 0.5 + (x - left[y]) / feather)))
    for x in range(DRAW):
        for y in range(max(depth, top_depth) * 2):
            v = int(255 * max(0.0, min(1.0, 0.5 + (y - top[x]) / feather)))
            px[x, y] = min(px[x, y], v)
    return img.resize((FILE, FILE), Image.LANCZOS)


def save(mask, name):
    rgba = Image.merge("RGBA", (mask, mask, mask, mask))
    path = os.path.join(OUT, name + ".tga")
    rgba.save(path)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    # wide: deep strokes on the sides, shallow ones top and bottom -- a chat
    # window can grow its backdrop sideways but not into its tabs and input
    # box (user, 2026-09-23: "grow the backdrop")
    for name, depth, top_depth in (("edge_brush", EDGE, EDGE), ("edge_brush_fine", FINE_EDGE, FINE_EDGE),
                                   ("edge_brush_wide", EDGE, FINE_EDGE)):
        mask = corner_mask(depth, top_depth)
        for path in (save(mask, name + "_tl"), save(mask.rotate(180), name + "_br")):
            print(path)


if __name__ == "__main__":
    main()
