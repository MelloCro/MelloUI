"""
Build the Legacy Panel textures from the three painted pages:

  docs/legacy-track-frame.webp       (1615 x 974)  the progress track
  docs/legacy-challenges-frame.webp  (1609 x 978)  the legacy challenges
  docs/legacy-tree-frame.webp        (1608 x 978)  the legacy tree

  Media/Textures/LegacyTrack.tga, LegacyChallenges.tga, LegacyTree.tga
                                        2048 x 1024 each, the page scaled to
                                        1024 high at the left
  Media/Textures/LegacyParts.tga        1024 x 512, the sprites the game's
                                        frames wear, in art pixels

Everything the game draws is painted out: titles, points and labels, the
reward cards, the category rows, the search prompts, the tree buttons, the
tree's nodes and labels, the apply button's label. The pictures show six side
tabs where the game has three: the tab column leaves the art and the tabs
get plate sprites.

    python Tools\\make_legacy_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, "..", "docs")
TEX = os.path.join(HERE, "..", "Media", "Textures")

PARTS = {
    "tab": (0, 0),            # 88 x 90   side tab plate (from the tree page's first tab)
    "tab_on": (96, 0),        # 88 x 90   side tab plate, open (the tree page's third)
    "card": (0, 100),         # 340 x 385 reward card, with its diamond and icon frame
    "row": (350, 0),          # 435 x 40  challenge category plate
    "plate": (350, 50),       # 218 x 131 tree selection plate with its ring
    "plate_on": (350, 190),   # 218 x 138 the open one
}
STONE = (1160, 260, 1400, 740)          # plain stone on the tree page, for filling


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


def patch(img, dst, src, feather=4, source=None):
    """Paint dst with a plain box tiled both ways."""
    source = source or img
    feathered_paste(img, sheet_of(source.crop(src), dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def across(img, dst, sx0, sx1, feather=3):
    """Paint dst with a strip of the same rows taken at columns sx0..sx1."""
    piece = img.crop((sx0, dst[1], sx1, dst[3]))
    feathered_paste(img, sheet_of(piece, dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def solid(img, box, colour, feather=2):
    feathered_paste(img, Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), colour), (box[0], box[1]), feather)


def disc(img, cx, cy, r, colour):
    a = np.array(img).astype(float)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    inside = np.clip((r - np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)) / 2, 0, 1)[:, :, None]
    a = a * (1 - inside) + np.array(colour, dtype=float) * inside
    return Image.fromarray(a.astype(np.uint8))


def clear_from(img, x):
    a = np.array(img)
    a[:, x:, 3] = 0
    return Image.fromarray(a)


def hollow_round(sprite, cx, cy, clear_r):
    a = np.array(sprite).astype(float)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    a[:, :, 3] *= np.clip((d - clear_r) / 2.5, 0, 1)
    return Image.fromarray(a.astype(np.uint8))


def dark_mean(img, box):
    """The mean of a box's darker half: the plain colour under a light mark."""
    a = np.array(img.crop(box)).astype(int)
    lum = a[:, :, :3].sum(axis=2)
    keep = lum <= np.percentile(lum, 25)
    return tuple(int(v) for v in a[keep].mean(axis=0))


def border_over_tabs(img, x0, x1, y0, y1, sy0, sy1):
    """The painted tabs overlap the frame's right border: the border from a
    tab-free stretch below is tiled up over them, then the rest of the tab
    column is cleared."""
    piece = img.crop((x0, sy0, x1, sy1))
    sheet = sheet_of(piece, x1 - x0, y1 - y0)
    img.paste(sheet, (x0, y0))
    return clear_from(img, x1)


def save_page(img, name):
    k = 1024 / img.size[1]
    scaled = img.resize((round(img.size[0] * k), 1024), Image.LANCZOS)
    tex = Image.new("RGBA", (2048, 1024), (0, 0, 0, 0))
    tex.paste(scaled, (0, 0))
    out = os.path.join(TEX, name)
    tex.save(out)
    print(f"  {name}: art {scaled.size[0]} x {scaled.size[1]} in 2048 x 1024")


track = Image.open(os.path.join(DOCS, "legacy-track-frame.webp")).convert("RGBA")
chal = Image.open(os.path.join(DOCS, "legacy-challenges-frame.webp")).convert("RGBA")
tree = Image.open(os.path.join(DOCS, "legacy-tree-frame.webp")).convert("RGBA")
parts = Image.new("RGBA", (1024, 512), (0, 0, 0, 0))
stone = tree.crop(STONE)

# ---- sprites, cut before anything is painted out --------------------------------
for key, box in (("tab", (1515, 154, 1603, 244)), ("tab_on", (1515, 344, 1603, 434))):
    plate = tree.crop(box)
    # the inside is an octagon: the rim is thicker on the right and the
    # top-right corner is cut diagonally
    ImageDraw.Draw(plate).polygon([(8, 8), (68, 8), (78, 18), (78, 82), (8, 82)], fill=(24, 24, 28, 255))
    parts.paste(plate, PARTS[key])
card = track.crop((417, 497, 757, 882))                       # the second card, diamond included
patch(card, (116, 98, 238, 224), (950, 150, 1300, 440), source=track)    # inside the icon frame
patch(card, (20, 232, 320, 332), (950, 150, 1300, 440), source=track)    # the name
solid(card, (144, 10, 200, 64), dark_mean(card, (144, 10, 200, 64)), 4)  # the level number in the diamond
parts.paste(card, PARTS["card"])
row = chal.crop((80, 245, 515, 285))
across(row, (10, 5, 300, 35), 310, 380)                        # "CLASSES"
across(row, (385, 5, 430, 35), 310, 380)                       # the glyph
parts.paste(row, PARTS["row"])
for key, box in (("plate", (60, 472, 278, 603)), ("plate_on", (60, 333, 278, 471))):
    plate = tree.crop(box)
    w, h = plate.size
    plate = hollow_round(plate, 105, h / 2, 50)               # the icon shows through the ring
    parts.paste(plate, PARTS[key])

# ---- the progress track ------------------------------------------------------------
t = track
across(t, (640, 46, 930, 92), 940, 1180)                      # "Progress Track"
solid(t, (745, 255, 836, 342), dark_mean(t, (745, 255, 836, 342)), 3)   # the points in the shield
patch(t, (640, 380, 940, 446), (950, 330, 1300, 440))         # "Legacy Points" and its glow
patch(t, (62, 502, 1458, 896), (950, 150, 1300, 440), 6)     # the four cards (sprites now)
for cx in (245, 588, 931, 1275):
    across(t, (cx - 52, 484, cx + 52, 506), 300, 420)         # the diamonds' tips over the track line
t = clear_from(t, 1497)
save_page(t, "LegacyTrack.tga")

# ---- the legacy challenges ----------------------------------------------------------
c = chal
across(c, (660, 44, 950, 86), 960, 1230)                      # "Legacy Challenges"
c = disc(c, 458, 127, 19, (30, 30, 34, 255))                  # the shield's points
across(c, (700, 112, 1100, 146), 560, 690)                    # "Legacy Points 0 / 65"
across(c, (112, 196, 335, 228), 340, 382)                     # "Search"
across(c, (415, 196, 512, 228), 400, 414)                     # "FILTER"
patch(c, (56, 234, 524, 554), (90, 600, 500, 800), 3)         # the category rows (sprites now)
c = border_over_tabs(c, 1490, 1520, 120, 720, 712, 790)
save_page(c, "LegacyChallenges.tga")

# ---- the legacy tree -----------------------------------------------------------------
r = tree
across(r, (660, 42, 950, 88), 960, 1250)                      # "Legacy Tree"
r = disc(r, 316, 127, 19, (30, 30, 34, 255))                  # the shield's points
solid(r, (362, 116, 604, 144), dark_mean(r, (362, 116, 604, 144)), 3)   # "Available points: 0"
patch(r, (55, 172, 282, 762), (65, 180, 270, 330), 8)        # the tree plates (sprites now)
r = disc(r, 470, 480, 76, (22, 24, 30, 255))                  # the big ring's inside
patch(r, (345, 280, 600, 328), STONE)                         # "Professions"
r = disc(r, 465, 578, 22, (22, 24, 30, 255))                  # the spent points circle's inside
patch(r, (612, 242, 1148, 764), STONE, 8)                     # the nodes (the game draws its own)
across(r, (688, 842, 952, 900), 654, 688)                     # "Apply Changes" and its glow
r = border_over_tabs(r, 1490, 1526, 130, 460, 480, 640)
save_page(r, "LegacyTree.tga")

parts.save(os.path.join(TEX, "LegacyParts.tga"))
print("  LegacyParts.tga:", ", ".join(f"{k} at {v}" for k, v in PARTS.items()))
