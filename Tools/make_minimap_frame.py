"""
Build the minimap cluster and objective tracker textures from
docs/minimap-frame.webp (964 x 1631): the zone bar, the ring with its runes,
gems and sun disc, the scaffold with its ten icon slots, and the tracker panel
that hangs under the scaffold's feet.

  Media/Textures/MinimapStand.tga   1024 x 1024, the zone bar down to the
                                    scaffold's feet (art x 124..840, y 0..782)
                                    centred on the canvas, the map disc cut out
  Media/Textures/TrackerFrame.tga   1024 x 512, the tracker panel in pieces:
                                    top cap, a middle strip that tiles down,
                                    bottom cap, the module header plate and the
                                    two quest medallions

Everything the game prints is painted out: the zone name, the clock, the
calendar day, the ten painted service icons, "All Objectives", "Quests", both
minimize boxes, every quest title and objective line, and the "!" and "?"
glyphs in the medallions.

    python Tools\\make_minimap_frame.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "minimap-frame.webp")
TEX = os.path.join(HERE, "..", "Media", "Textures")
OUT = os.path.join(HERE, "output")

# ---- measured on the art (pixels of the 964 x 1631 picture) -------------------
RING = (482.70, 356.85, 213.58)      # map disc centre and inner radius
SUN = (622.48, 145.85, 42.0)         # sun disc centre and the inside of its silver rim
SLOT_X0, SLOT_PITCH = 316.50, 83.8125    # centre of the first slot, step
SLOT_Y = (654.0, 739.0)              # the two row centres
SLOT_HALF = 28                       # half the painted opening

STAND_BOX = (124, 0, 840, 782)       # zone bar down to the feet
CANVAS = 1024

PANEL_X0, PANEL_X1 = 124, 840        # the tracker panel with its corner gems
BODY_X0, BODY_X1 = 157, 807          # the dark body between the side rails
TOP_CAP = (785, 872)                 # "All Objectives" plate
MOD_HEAD = (872, 940)                # "Quests" plate
MIDDLE = (1140, 1230)                # a clean stretch of the body
BOTTOM_CAP = (1578, 1624)
MED_RED = (174, 939, 234, 999)       # the red "!" medallion
MED_GOLD = (173, 1359, 233, 1419)    # the gold "?" medallion


# ---- painting helpers (same shapes as Tools/make_map_frame.py) ---------------
def feathered_paste(img, patch, box, feather=3):
    w, h = patch.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, w - feather - 1, h - feather - 1), fill=255)
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    img.paste(patch, box, mask)


def sheet_of(piece, w, h):
    sheet = Image.new("RGBA", (w, h))
    y, row = 0, 0
    while y < h:
        x, col = 0, 0
        while x < w:
            p = piece
            if col % 2 == 1:
                p = p.transpose(Image.FLIP_LEFT_RIGHT)
            if row % 2 == 1:
                p = p.transpose(Image.FLIP_TOP_BOTTOM)
            sheet.paste(p, (x, y))
            x += piece.size[0]
            col += 1
        y += piece.size[1]
        row += 1
    return sheet


def across(img, dst, sx0, sx1, feather=3):
    """Fill dst with a piece taken from the same rows, columns sx0..sx1."""
    piece = img.crop((sx0, dst[1], sx1, dst[3]))
    feathered_paste(img, sheet_of(piece, dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def solid(img, box, colour, feather=2):
    feathered_paste(img, Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), colour), (box[0], box[1]), feather)


def dark_mean(img, box):
    """The plain colour of the darker part of a sample, fully opaque: the art
    is painted at alpha 252 and a fill at that alpha lets the paint underneath
    ghost through."""
    a = np.array(img.crop(box)).astype(int)
    lum = a[:, :, :3].sum(axis=2)
    keep = lum <= np.percentile(lum, 40)
    mean = a[keep].mean(axis=0)
    return (int(mean[0]), int(mean[1]), int(mean[2]), 255)


def flat(img, box, sample, feather=3):
    solid(img, box, dark_mean(img, sample), feather)


def clear_circle(img, cx, cy, radius, feather=2.0):
    """Cut a soft edged hole; the art behind it is the game's own drawing."""
    a = np.array(img).astype(float)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx - cx, yy - cy)
    keep = np.clip((d - radius) / max(feather, 0.01), 0.0, 1.0)
    a[:, :, 3] = a[:, :, 3] * keep
    return Image.fromarray(a.astype(np.uint8))


def radial_repaint(img, cx, cy, radius, box, bright):
    """Repaint a disc with the median colour of each radius, ignoring the
    bright glyph painted on it. Leaves the rim and the shading intact."""
    a = np.array(img).astype(int)
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.hypot(xx - cx, yy - cy)
    lum = sub[:, :, :3].mean(axis=2)
    glyph = lum > bright
    inside = d < radius
    out = sub.copy()
    bands, colours = [], []
    for r in range(0, int(radius) + 1):
        band = inside & (d >= r) & (d < r + 1)
        clean = band & ~glyph
        bands.append(band)
        colours.append(np.median(sub[clean], axis=0) if clean.sum() >= 6 else None)
    # the innermost rings are all glyph: they take the colour of the first ring
    # that had enough plain pixels, so no bright dot is left in the middle
    last = None
    for i in range(len(colours) - 1, -1, -1):
        if colours[i] is None:
            colours[i] = last
        else:
            last = colours[i]
    for band, colour in zip(bands, colours):
        if colour is not None and band.any():
            out[band] = colour
    a[y0:y1, x0:x1] = out
    return Image.fromarray(a.astype(np.uint8))


art = Image.open(SRC).convert("RGBA")
os.makedirs(OUT, exist_ok=True)

# =============================================================================
# 1. The stand: zone bar, ring, sun disc, scaffold with ten empty slots
# =============================================================================
stand = art.copy()

# the zone name and the clock: tiled from the plain stretch of the bar between them
across(stand, (310, 21, 564, 58), 464, 584)      # "Goldshire"
across(stand, (586, 21, 676, 58), 464, 560)      # "10:28"
flat(stand, (694, 20, 740, 61), (698, 24, 736, 31), 3)   # the calendar day "19"

# the ten painted service icons: the slots keep their rims and go empty
for cy in SLOT_Y:
    for col in range(5):
        cx = SLOT_X0 + col * SLOT_PITCH
        box = (round(cx - SLOT_HALF), round(cy - SLOT_HALF), round(cx + SLOT_HALF), round(cy + SLOT_HALF))
        solid(stand, box, dark_mean(stand, box), 2)

# the sun disc: the painted compass rose goes, the silver rim stays and the
# game's day/night indicator (MinimapCluster.DielFrame) is laid in the socket
a = np.array(stand).astype(int)
yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
d = np.hypot(xx - SUN[0], yy - SUN[1])
rim = (d >= SUN[2] - 4) & (d < SUN[2])
sun_fill = np.median(a[rim], axis=0)
soft = np.clip((SUN[2] - d) / 1.5, 0.0, 1.0)[:, :, None]
inside = d < SUN[2] + 1
a[inside] = (a[inside] * (1 - soft[inside]) + sun_fill * soft[inside])
stand = Image.fromarray(a.astype(np.uint8))

# the map itself
stand = clear_circle(stand, RING[0], RING[1], RING[2] + 1.0, 2.0)

crop = stand.crop(STAND_BOX)
ox, oy = (CANVAS - crop.size[0]) // 2, (CANVAS - crop.size[1]) // 2
canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
canvas.paste(crop, (ox, oy))
canvas.save(os.path.join(TEX, "MinimapStand.tga"))


def cv(x, y):
    return x - STAND_BOX[0] + ox, y - STAND_BOX[1] + oy


cx, cy = cv(RING[0], RING[1])
print(f"  MinimapStand.tga {CANVAS} x {CANVAS}   art {crop.size[0]} x {crop.size[1]} at ({ox}, {oy})")
print(f"    STAND_CX, STAND_CY = {cx:.2f}, {cy:.2f}    STAND_INNER_R = {RING[2]:.2f}")
sx, sy = cv(*SUN[:2])
print(f"    SUN centre ({sx:.2f}, {sy:.2f}) r {SUN[2]:.1f}   offset from the ring ({sx - cx:.2f}, {sy - cy:.2f})")
print(f"    SLOT first centre x {cv(SLOT_X0, 0)[0]:.2f}  pitch {SLOT_PITCH:.4f}  rows y "
      f"{cv(0, SLOT_Y[0])[1]:.2f} / {cv(0, SLOT_Y[1])[1]:.2f}  opening {SLOT_HALF * 2}")
print(f"    SLOT offsets from the ring centre: dx "
      f"{', '.join(f'{cv(SLOT_X0 + i * SLOT_PITCH, 0)[0] - cx:.2f}' for i in range(5))}  dy "
      f"{', '.join(f'{cv(0, v)[1] - cy:.2f}' for v in SLOT_Y)}")
for name, box in (("BADGE", (233, 9, 292, 74)), ("BAR", (292, 9, 682, 74)), ("BAR_INNER", (302, 21, 674, 57)),
                  ("ZONE", (310, 21, 566, 57)), ("CLOCK", (586, 21, 676, 57)),
                  ("DAY", (684, 9, 744, 74)), ("DAY_INNER", (694, 20, 738, 60))):
    p0, p1 = cv(box[0], box[1]), cv(box[2], box[3])
    print(f"    {name:10s} canvas {p0[0]}, {p0[1]}, {p1[0]}, {p1[1]}   from the ring centre "
          f"({p0[0] - cx:.1f}, {p0[1] - cy:.1f}) .. ({p1[0] - cx:.1f}, {p1[1] - cy:.1f})")
print(f"    feet end at canvas y {cv(0, 778)[1]}  = {cv(0, 778)[1] - cy:.2f} below the ring centre")

# =============================================================================
# 2. The tracker panel
# =============================================================================
panel = art.copy()

# the medallions are cut first, before the body is painted over
medallions = {}
for name, box, bright in (("MED_RED", MED_RED, 120), ("MED_GOLD", MED_GOLD, 105)):
    piece = panel.crop(box)
    w, h = piece.size
    medallions[name] = radial_repaint(piece, (w - 1) / 2, (h - 1) / 2, 21, (0, 0, w, h), bright)

# "All Objectives" and its red minimize box, tiled from the plain plate between them
across(panel, (188, 798, 736, 854), 490, 700)
across(panel, (730, 798, 788, 854), 490, 700)
# "Quests" and its yellow minimize box
across(panel, (190, 884, 738, 928), 400, 700)
across(panel, (734, 884, 792, 928), 400, 700)

# every quest title and objective line: the body goes back to plain stone
body_colour = dark_mean(panel, (600, 1150, 795, 1230))
solid(panel, (BODY_X0 + 18, 940, BODY_X1 - 14, 1560), body_colour, 4)
solid(panel, (BODY_X0 + 21, 1556, BODY_X1 - 19, 1597), body_colour, 3)

W = PANEL_X1 - PANEL_X0
sheet = Image.new("RGBA", (1024, 512), (0, 0, 0, 0))
PARTS = {}
y = 0
for name, (a0, a1) in (("TOP", TOP_CAP), ("MIDDLE", MIDDLE), ("BOTTOM", BOTTOM_CAP), ("MODHEAD", MOD_HEAD)):
    sheet.paste(panel.crop((PANEL_X0, a0, PANEL_X1, a1)), (0, y))
    PARTS[name] = (0, y, W, a1 - a0)
    y += (a1 - a0) + 2
for i, (name, piece) in enumerate(medallions.items()):
    x = i * 64
    sheet.paste(piece, (x, y))
    PARTS[name] = (x, y, piece.size[0], piece.size[1])
sheet.save(os.path.join(TEX, "TrackerFrame.tga"))

print("  TrackerFrame.tga 1024 x 512")
for name, (px, py, pw, ph) in PARTS.items():
    print(f"    {name:9s} {px}, {py}, {pw} x {ph}   "
          f"texcoords {px / 1024:.6f}, {(px + pw) / 1024:.6f}, {py / 512:.6f}, {(py + ph) / 512:.6f}")
print(f"    panel art {W} wide, body {BODY_X0}..{BODY_X1} ({BODY_X1 - BODY_X0}), "
      f"overhang {BODY_X0 - PANEL_X0} each side")
print(f"    header plate centre y in the top cap: {(785 + 868) / 2 - TOP_CAP[0]:.1f} of {TOP_CAP[1] - TOP_CAP[0]}")
print(f"    minimize box centre in the top cap: x {(738 + 782) / 2 - PANEL_X0:.1f}, "
      f"y {(802 + 852) / 2 - TOP_CAP[0]:.1f}")
print(f"    module plate: text left {202 - PANEL_X0}, minimize box centre x {(738 + 786) / 2 - PANEL_X0:.1f}, "
      f"y {(890 + 926) / 2 - MOD_HEAD[0]:.1f}")

# ---- previews over green so nothing painted can hide -------------------------
for name in ("MinimapStand", "TrackerFrame"):
    im = Image.open(os.path.join(TEX, name + ".tga")).convert("RGBA")
    bg = Image.new("RGBA", im.size, (0, 140, 0, 255))
    bg.alpha_composite(im)
    bg.convert("RGB").save(os.path.join(OUT, name.lower() + "-preview.png"))
print("  previews in Tools/output")
