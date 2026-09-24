"""
Build the Professions Panel textures from docs/professions-book-frame.webp
(the professions book page, 1218 x 1292); the crafting page is composed
from the same picture, so both pages share one frame and one style:

  Media/Textures/ProfessionsFrame.tga   2048 x 1024, the book page scaled to
                                        1024 high on the left, the crafting
                                        page (the book page's frame with the
                                        rank bar in the band, a card-style
                                        list box and schematic box, plates
                                        for the buttons) the same on the right
  Media/Textures/ProfessionsParts.tga   512 x 512, the sprites the game's
                                        frames wear, in art pixels

The art was painted from a character with Blacksmithing and Mining. All
that the game draws is painted out: names, ranks and spell labels, the
title, the search prompt, the recipe rows, the schematic's texts and
frames, the buttons' labels, the tab icons. The painted portraits stay: the game's own are hidden. The two primary
cards' illustrations go too, as they belong to those two professions only;
the parchment keeps its faint anvil as decoration. The class tab row of the
book page has no counterpart in the game and leaves as well. The band
under the title is painted with the repeatable dark stone of
docs/stone-dark-tile.png at the scale the shared StoneDarkTile.tga has on
screen; the two primary cards' insides and the crafting page's list box
with the cracked stone of docs/profession-primary-bg.png, cover-cropped;
the schematic's sheet with docs/parchment-tile.png. The CRAFT table holds
the crafting page's layout. The three secondary cards' bodies are painted plain: the module
lays the coloured or grey illustrations from ProfessionCards.tga
(make_profession_cards.py) there.

Painting out samples a plain strip next to each box on the same rows (or
columns) and tiles it across, so the art's gradients carry through.

    python Tools\\make_professions_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import numpy as np
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
BOOK_SRC = os.path.join(HERE, "..", "docs", "professions-book-frame.webp")
OUT = master("Textures", "ProfessionsFrame.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
PARTS_OUT = master("Textures", "ProfessionsParts.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships

DISC = (108, 80, 58)                    # the portrait disc: centre and radius
TAB_COLUMN_X = 1112                     # the tab plates start here; they leave the art
BAR_DARK = (28, 28, 32, 255)            # the bars' empty inside; the game's fill draws over it

# ---- sprite positions in the parts sheet (art pixels, unscaled) ----------------
PARTS = {
    "square": (0, 0),        # 86 x 86  primary card spell frame
    "ring": (96, 0),         # 90 x 90  secondary card spell ring
    "tab": (192, 0),         # 88 x 92  side tab plate
    "tab_on": (296, 0),      # 88 x 92  side tab plate, open
    "output": (400, 0),      # 110 x 110 schematic output ring
    "reagent": (0, 120),     # 88 x 88  reagent frame
    "arrow": (96, 120),      # 45 x 45  count arrow
    "category": (0, 220),    # 406 x 50 recipe category plate
}


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


def across(img, dst, sx0, sx1, feather=3, source=None):
    """Paint dst with a strip of the same rows taken at columns sx0..sx1, tiled sideways."""
    source = source or img
    piece = source.crop((sx0, dst[1], sx1, dst[3]))
    feathered_paste(img, sheet_of(piece, dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def down(img, dst, sy0, sy1, feather=3, source=None):
    """Paint dst with a strip of the same columns taken at rows sy0..sy1, tiled downwards."""
    source = source or img
    piece = source.crop((dst[0], sy0, dst[2], sy1))
    feathered_paste(img, sheet_of(piece, dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def patch(img, dst, src, feather=3):
    """Paint dst with a plain box tiled both ways (for flat areas)."""
    feathered_paste(img, sheet_of(img.crop(src), dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def soften(img, box, feather=16):
    """Blur and darken a box: a soft dark patch for the game's text over an
    illustration. The work is done on a larger crop so the feathered edge
    falls outside the box and everything inside it is blurred."""
    m = feather + 6
    ext = (box[0] - m, box[1] - m, box[2] + m, box[3] + m)
    patch = img.crop(ext).filter(ImageFilter.GaussianBlur(28))
    patch = ImageEnhance.Brightness(patch).enhance(0.7)
    feathered_paste(img, patch, (ext[0], ext[1]), feather)


def inpaint(img, box, grain=None, margin=6):
    """Fill a box by blending its four edges inward (a smooth continuation of
    what surrounds it), plus the fine grain of a clean sample when given."""
    x0, y0, x1, y1 = box
    a = np.array(img).astype(float)
    w, h = x1 - x0, y1 - y0
    left = a[y0:y1, x0 - margin:x0].mean(axis=1)          # per row
    right = a[y0:y1, x1:x1 + margin].mean(axis=1)
    top = a[y0 - margin:y0, x0:x1].mean(axis=0)            # per column
    bottom = a[y1:y1 + margin, x0:x1].mean(axis=0)
    tx = (np.arange(w) + 0.5) / w
    ty = (np.arange(h) + 0.5) / h
    horiz = left[:, None, :] * (1 - tx)[None, :, None] + right[:, None, :] * tx[None, :, None]
    vert = top[None, :, :] * (1 - ty)[:, None, None] + bottom[None, :, :] * ty[:, None, None]
    fill = (horiz + vert) / 2
    if grain is not None:
        g = np.array(sheet_of(grain, w, h)).astype(float)
        g = g - np.array(sheet_of(grain, w, h).filter(ImageFilter.GaussianBlur(3))).astype(float)
        fill[:, :, :3] += g[:, :, :3] * 0.9
    fill[:, :, 3] = 255
    patch_img = Image.fromarray(np.clip(fill, 0, 255).astype(np.uint8))
    feathered_paste(img, patch_img, (x0, y0), 3)


def parchment(img, box, sample, edge=70, darken=0.22, feather=8):
    """Refill a parchment box: the sample's mean colour and grain everywhere,
    shaded darker towards the box's edges like the original page."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    piece = img.crop(sample)
    base = np.array(piece).astype(float)
    grain = base - np.array(piece.filter(ImageFilter.GaussianBlur(6))).astype(float)
    grain_img = Image.fromarray(np.clip(grain + 128, 0, 255).astype(np.uint8))
    sheet = np.array(sheet_of(grain_img, w, h)).astype(float) - 128
    mean = base.reshape(-1, 4).mean(axis=0)
    fill = np.empty((h, w, 4), dtype=float)
    fill[:, :, :] = mean
    fill += sheet
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(float)
    shade = 1 - darken * np.clip(1 - dist / edge, 0, 1) ** 1.5
    fill[:, :, :3] *= shade[:, :, None]
    fill[:, :, 3] = 255
    feathered_paste(img, Image.fromarray(np.clip(fill, 0, 255).astype(np.uint8)), (x0, y0), feather)


STONE_SRC = os.path.join(HERE, "..", "docs", "stone-dark-tile.png")
FRAME_W, ART_W = 700, 1218               # the module's window width for this art
TILE_PX_PER_FRAME_PX = 0.75              # the shared stone tile's scale on screen (StoneDarkTile.tga, 1024 x 512)
_stone = None


def stone_tile(img, box, offset=(0, 0), feather=2):
    """Fill a box with the repeatable dark stone of docs/stone-dark-tile.png
    (the source of Media/Textures/StoneDarkTile.tga), wrapped without
    mirroring at the scale the shared tile has on screen: 1024 tile px span
    1024 / 0.75 frame px, i.e. 2376 art px here. `offset` (art px) shifts
    the tile so two surfaces do not repeat each other."""
    global _stone
    if _stone is None:
        src = Image.open(STONE_SRC).convert("RGBA")
        k = ART_W / FRAME_W / TILE_PX_PER_FRAME_PX          # art px per tile px
        _stone = src.resize((round(1024 * k), round(512 * k)), Image.LANCZOS)   # 2376 x 1188
    tw, th = _stone.size
    w, h = box[2] - box[0], box[3] - box[1]
    piece = Image.new("RGBA", (w, h))
    ox, oy = offset[0] % tw, offset[1] % th
    y = -oy
    while y < h:
        x = -ox
        while x < w:
            piece.paste(_stone, (x, y))
            x += tw
        y += th
    feathered_paste(img, piece, (box[0], box[1]), feather)


CRACKED_SRC = os.path.join(HERE, "..", "docs", "profession-primary-bg.png")


def stone_crop(img, box, anchor=0.0, feather=2, upright=False):
    """Fill a box with the cracked dark stone of docs/profession-primary-bg.png
    (2000 x 750, wider than any card): cover-cropped to the box's aspect,
    `anchor` picking the slice (0 = the image's top or left, 1 = its bottom
    or right) so two boxes can show different parts of it; `upright` turns
    the image on its side first for a tall box."""
    stone = Image.open(CRACKED_SRC).convert("RGBA")
    if upright:
        stone = stone.transpose(Image.ROTATE_90)
    sw, sh = stone.size
    w, h = box[2] - box[0], box[3] - box[1]
    if sw / sh > w / h:
        cw, ch = round(sh * w / h), sh
    else:
        cw, ch = sw, round(sw * h / w)
    cx, cy = round((sw - cw) * anchor), round((sh - ch) * anchor)
    piece = stone.crop((cx, cy, cx + cw, cy + ch)).resize((w, h), Image.LANCZOS)
    feathered_paste(img, piece, (box[0], box[1]), feather)


def solid(img, box, colour, feather=2):
    patch = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), colour)
    feathered_paste(img, patch, (box[0], box[1]), feather)


def clear_disc(img, cx, cy, r):
    """The portrait disc goes dark: the game draws its own portrait there."""
    a = np.array(img)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    inside = np.clip((r - d) / 2, 0, 1)[:, :, None]
    dark = np.array([26, 26, 30, 255], dtype=float)
    a = (a * (1 - inside) + dark * inside).astype(np.uint8)
    return Image.fromarray(a)


def clear_tabs(img):
    """The painted tab plates leave (the game's tabs wear sprites); the
    frame's outer edge, the top-right corner and the bottom-right gem,
    which reach past the plates' column, stay."""
    a = np.array(img)
    a[95:840, TAB_COLUMN_X:, 3] = 0
    a[:, 1150:, 3] = 0
    return Image.fromarray(a)



def hollow(sprite, inset):
    """Clear a sprite's middle (the game draws the icon there), with a soft edge."""
    a = np.array(sprite).astype(float)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    a[:, :, 3] *= np.clip((inset - dist) / 2, 0, 1)
    return Image.fromarray(a.astype(np.uint8))


def hollow_round(sprite, clear_r):
    a = np.array(sprite).astype(float)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt((xx - (w - 1) / 2) ** 2 + (yy - (h - 1) / 2) ** 2)
    a[:, :, 3] *= np.clip((d - clear_r) / 2.5, 0, 1)
    a[:, :, 3] *= np.clip(((w - 1) / 2 + 0.5 - d) / 1.5, 0, 1)
    return Image.fromarray(a.astype(np.uint8))


def plainest_band(img, x0, x1, y0, y1, height):
    """The rows in y0..y1 whose pixels vary least: the cleanest sample for a list."""
    a = np.array(img.crop((x0, y0, x1, y1)).convert("L")).astype(float)
    best, best_y = None, y0
    for y in range(0, a.shape[0] - height):
        v = a[y:y + height].std()
        if best is None or v < best:
            best, best_y = v, y0 + y
    return best_y, best_y + height


book = Image.open(BOOK_SRC).convert("RGBA")
original = book.copy()                       # untouched, for the pieces the crafting page is built from
parts = Image.new("RGBA", (512, 512), (0, 0, 0, 0))

# ---- pieces of the book page's art ----------------------------------------------
SQUARE_SRC = (138, 252, 224, 338)            # a primary card's spell frame, 86 x 86
RING_SRC = (138, 1030, 228, 1120)            # a secondary card's spell ring, 90 x 90
BAR_SRC = (440, 274, 985, 320)               # the first primary bar's frame, 545 x 46
BAR_CAP = 30                                 # the bar frame's end caps
SEC_CARD = (750, 674, 1073, 1153)            # the third secondary card's frame, arches in its corners
SEC_RAIL = (10, 17, 9, 13)                   # its rail bands: left, top, right, bottom (to just past the bevel)
SEC_CORNER = (64, 70)                        # a corner cell holding the arch
GOLD = (222, 176, 62, 255)


def bar_plate(w, h, dark=True):
    """A bar frame at any size: the book bar's end caps kept, its middle
    stretched, the whole scaled to the height; the inside dark."""
    bar = original.crop(BAR_SRC)
    s = h / bar.size[1]
    cap = round(BAR_CAP * s)
    left = bar.crop((0, 0, BAR_CAP, bar.size[1])).resize((cap, h), Image.LANCZOS)
    right = bar.crop((bar.size[0] - BAR_CAP, 0, bar.size[0], bar.size[1])).resize((cap, h), Image.LANCZOS)
    mid = bar.crop((BAR_CAP, 0, bar.size[0] - BAR_CAP, bar.size[1])).resize((max(1, w - 2 * cap), h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.paste(left, (0, 0))
    out.paste(mid, (cap, 0))
    out.paste(right, (w - cap, 0))
    if dark:
        inset = round(7 * s)
        ImageDraw.Draw(out).rectangle((inset, inset, w - inset - 1, h - inset - 1), fill=BAR_DARK)
    return out


def square_plate(w, h, inset=9):
    """The spell square frame at any size, its inside dark."""
    plate = original.crop(SQUARE_SRC).resize((w, h), Image.LANCZOS)
    ImageDraw.Draw(plate).rectangle((inset, inset, w - inset - 1, h - inset - 1), fill=BAR_DARK)
    return plate


def triangle(img, cx, cy, size, direction):
    d = ImageDraw.Draw(img)
    h = size / 2
    if direction == "right":
        pts = [(cx - h * 0.8, cy - h), (cx + h * 0.8, cy), (cx - h * 0.8, cy + h)]
    elif direction == "left":
        pts = [(cx + h * 0.8, cy - h), (cx - h * 0.8, cy), (cx + h * 0.8, cy + h)]
    elif direction == "up":
        pts = [(cx - h, cy + h * 0.8), (cx, cy - h * 0.8), (cx + h, cy + h * 0.8)]
    else:
        pts = [(cx - h, cy - h * 0.8), (cx, cy + h * 0.8), (cx + h, cy - h * 0.8)]
    d.polygon(pts, fill=GOLD)


def card_frame(w, h):
    """A card frame at any size from the secondary card's: the rails
    stretched, the arches in the top corners, plain corners below; the
    inside transparent."""
    x0, y0, x1, y1 = SEC_CARD
    src = original.crop(SEC_CARD)
    sw, sh = src.size
    rl, rt, rr, rb = SEC_RAIL
    cw, ch = SEC_CORNER
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # the rails: a mid stretch of each edge band
    left = src.crop((0, ch, rl, sh - ch)).resize((rl, h), Image.LANCZOS)
    right = src.crop((sw - rr, ch, sw, sh - ch)).resize((rr, h), Image.LANCZOS)
    top = src.crop((cw, 0, sw - cw, rt)).resize((w, rt), Image.LANCZOS)
    bottom = src.crop((cw, sh - rb, sw - cw, sh)).resize((w, rb), Image.LANCZOS)
    out.paste(left, (0, 0))
    out.paste(right, (w - rr, 0))
    out.paste(top, (0, 0))
    out.paste(bottom, (0, h - rb))
    # the top corners: the rail bands opaque, the arch inside them kept by its light
    for cell, at in ((src.crop((0, 0, cw, ch)), (0, 0)), (src.crop((sw - cw, 0, sw, ch)), (w - cw, 0))):
        c = np.array(cell).astype(float)
        l = c[:, :, :3].max(axis=2)
        yy, xx = np.mgrid[0:ch, 0:cw]
        if at[0] == 0:
            band = (xx < rl) | (yy < rt)
        else:
            band = (xx >= cw - rr) | (yy < rt)
        keep = np.clip((l - 34) / 36, 0, 1)
        keep[band] = 1
        c[:, :, 3] = 255 * keep
        out.alpha_composite(Image.fromarray(c.astype(np.uint8)), at)
    # the bottom corners are plain: the bottom rail laid over the side rails
    out.paste(bottom, (0, h - rb))
    return out


def parchment_fill(img, box, feather=2):
    """docs/parchment-tile.png cover-cropped to the box (no repeat needed)."""
    tile = Image.open(os.path.join(HERE, "..", "docs", "parchment-tile.png")).convert("RGBA")
    sw, sh = tile.size
    w, h = box[2] - box[0], box[3] - box[1]
    if sw / sh > w / h:
        cw, ch = round(sh * w / h), sh
    else:
        cw, ch = sw, round(sw * h / w)
    cx, cy = (sw - cw) // 2, (sh - ch) // 2
    piece = tile.crop((cx, cy, cx + cw, cy + ch)).resize((w, h), Image.LANCZOS)
    feathered_paste(img, piece, (box[0], box[1]), feather)


# ---- sprites, cut before anything is painted out --------------------------------
parts.paste(hollow(original.crop(SQUARE_SRC), 9), PARTS["square"])
parts.paste(hollow_round(original.crop(RING_SRC), 34), PARTS["ring"])
# the plate proper is 88 x 92 of the 97 x 101 column cell (a shadow fills the rest)
for key, box in (("tab", (1111, 294, 1199, 386)), ("tab_on", (1111, 184, 1199, 276))):
    plate = original.crop(box)
    ImageDraw.Draw(plate).rectangle((5, 5, plate.size[0] - 6, plate.size[1] - 6), fill=(24, 24, 28, 255))
    parts.paste(plate, PARTS[key])
# the crafting page's parts in the book's style: the output ring is the
# spell ring grown, the reagent frame the spell square, the count arrow a
# small square plate with a gold triangle, the category plate a short bar
parts.paste(hollow_round(original.crop(RING_SRC).resize((110, 110), Image.LANCZOS), 48), PARTS["output"])
parts.paste(hollow(original.crop(SQUARE_SRC).resize((88, 88), Image.LANCZOS), 10), PARTS["reagent"])
arrow = square_plate(45, 45, inset=6)
triangle(arrow, 23, 22, 18, "right")
parts.paste(arrow, PARTS["arrow"])
parts.paste(bar_plate(406, 50), PARTS["category"])

# ---- the book page -----------------------------------------------------------------
b = book
across(b, (520, 38, 700, 92), 700, 820)              # "Professions"
# the band under the title (the class tabs and the search box) goes to
# the repeatable stone, from the portrait disc to the right rail
stone_tile(b, (180, 89, 1091, 159), offset=(0, 0))
across(b, (195, 150, 530, 173), 540, 630, feather=2)  # the class tabs' feet on the rail under it
b = clear_tabs(b)
page = b.copy()                              # the frame, title bar, portrait, band and rails: both pages start here
# the primary cards' insides go to the cracked stone (their anvil and ore,
# names, spell labels and frames with them), the first card the image's
# top, the second its bottom; the bars and their crosses are cut out first
# and laid back on top
PRIMARY_INSIDES = ((125, 189, 1047, 397), (125, 418, 1047, 658))
bars = [b.crop((440, 274, 985, 320)).copy(), b.crop((440, 516, 985, 562)).copy()]
crosses = [b.crop((995, 280, 1032, 318)).copy(), b.crop((995, 520, 1032, 558)).copy()]
for i, box in enumerate(PRIMARY_INSIDES):
    stone_crop(b, box, anchor=float(i))
    b.paste(bars[i], (440, 274 if i == 0 else 516))
    b.paste(crosses[i], (995, 280 if i == 0 else 520))
for box in ((447, 279, 978, 315), (447, 521, 978, 557)):
    solid(b, box, BAR_DARK)                                              # the bars' fill and rank
for x0, x1 in ((118, 432), (437, 750), (755, 1070)):
    patch(b, (x0 + 24, 700, x1 - 24, 754), (x0 + 40, 812, x1 - 40, 836))  # the card names
    solid(b, (x0 + 30, 764, x1 - 30, 802), BAR_DARK)                     # the bars
# the card bodies (under the bar, down to the bottom rail) go plain: the
# module lays the illustrations from ProfessionCards.tga there, coloured
# or grey by whether the profession is learned (Tools/make_profession_cards.py)
SECONDARY_BODIES = ((125, 807, 424, 1141), (441, 807, 741, 1141), (758, 807, 1063, 1141))
for (x0, y0, x1, y1), (cx0, cx1) in zip(SECONDARY_BODIES, ((118, 432), (437, 750), (755, 1070))):
    patch(b, (x0, y0, x1, y1), (cx0 + 40, 706, cx1 - 40, 750), feather=2)
book = b

# ---- the crafting page: the book page's frame, its inside composed anew --------------
# Boxes in the book page's art px; ProfessionsPanel.lua carries the same
# numbers (CBox). The rank bar and the link button stand in the band under
# the title; two card-style boxes fill the page, the recipe list on the
# left (search and filter plates under the arches, the list and its scroll
# track below) and the schematic on the right (the parchment sheet under
# the arches); the create buttons and the count box sit under them.
CRAFT = {
    "inside": (114, 170, 1073, 1160),        # the page between the rune rails: dark stone
    "rank": (236, 99, 965, 149),
    "link": (975, 100, 1027, 148),
    "list_box": (118, 178, 605, 1080),
    "search": (134, 252, 424, 298),
    "filter": (436, 252, 590, 298),
    "list": (134, 308, 560, 1064),
    "scroll": (566, 308, 590, 1064),
    "schem_box": (618, 178, 1070, 1080),
    "parch": (628, 193, 1060, 1068),         # the whole inside under the rails; the arches lie over it
    "out": (646, 208, 756, 318),
    "create_all": (150, 1094, 382, 1150),
    "count_down": (525, 1100, 570, 1145),
    "count": (575, 1100, 668, 1145),
    "count_up": (680, 1100, 725, 1145),
    "create": (830, 1094, 1035, 1150),
}


def paste_at(img, piece, box):
    img.alpha_composite(piece, (box[0], box[1]))


def size_of(box):
    return box[2] - box[0], box[3] - box[1]


c = page
stone_tile(c, CRAFT["inside"], offset=(600, 300))
paste_at(c, bar_plate(*size_of(CRAFT["rank"])), CRAFT["rank"])
paste_at(c, square_plate(*size_of(CRAFT["link"]), inset=7), CRAFT["link"])
for key in ("list_box", "schem_box"):
    box = CRAFT[key]
    rl, rt, rr, rb = SEC_RAIL
    stone_crop(c, (box[0] + rl - 2, box[1] + rt - 2, box[2] - rr + 2, box[3] - rb + 2), anchor=0.5 if key == "list_box" else 0.0)
    paste_at(c, card_frame(*size_of(box)), box)
paste_at(c, bar_plate(*size_of(CRAFT["search"])), CRAFT["search"])
filt = bar_plate(*size_of(CRAFT["filter"]))
triangle(filt, filt.size[0] - 24, filt.size[1] // 2, 16, "right")
paste_at(c, filt, CRAFT["filter"])
# the scroll track: the bar frame on its side, narrowed
SCROLL_CAP = 16                              # the track's end caps (art px), the scroll buttons' plates
track = bar_plate(size_of(CRAFT["scroll"])[1], 46).transpose(Image.ROTATE_270).resize(size_of(CRAFT["scroll"]), Image.LANCZOS)
tw, th = track.size
triangle(track, tw / 2, SCROLL_CAP / 2 + 1, 9, "up")
triangle(track, tw / 2, th - SCROLL_CAP / 2 - 1, 9, "down")
paste_at(c, track, CRAFT["scroll"])
parchment_fill(c, CRAFT["parch"])
for key in ("create_all", "create", "count"):
    paste_at(c, bar_plate(*size_of(CRAFT[key])), CRAFT[key])
down_plate = square_plate(*size_of(CRAFT["count_down"]), inset=6)
triangle(down_plate, 22, 22, 18, "left")
paste_at(c, down_plate, CRAFT["count_down"])
paste_at(c, arrow, CRAFT["count_up"])


def restore_ornament(img, box, grow=6):
    """Lay the original art's gem ornament in `box` back over the page:
    its red and bronze pixels, grown a little to take the silver frame
    round the gem with them, everything else (the old card rails under the
    wing) left as the page has it now."""
    src = np.array(original.crop(box)).astype(int)
    r, g, b = src[:, :, 0], src[:, :, 1], src[:, :, 2]
    mark = ((r > 140) & (g < 90) & (b < 90)) | ((r > b + 25) & (r > 70))
    mask = Image.fromarray((mark * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * grow + 1))
    mask = mask.filter(ImageFilter.GaussianBlur(1))
    img.paste(original.crop(box), (box[0], box[1]), mask)


for box in ((26, 1112, 165, 1250), (995, 1112, 1140, 1250)):
    restore_ornament(c, box)
craft = c

# ---- the textures --------------------------------------------------------------------
k = 1024 / book.size[1]
tex = Image.new("RGBA", (2048, 1024), (0, 0, 0, 0))
placed = {}
for name, im, x in (("book", book, 0), ("craft", craft, 980)):
    scaled = im.resize((round(im.size[0] * k), 1024), Image.LANCZOS)
    tex.paste(scaled, (x, 0))
    placed[name] = (x, 0, x + scaled.size[0], 1024)
tex.save(OUT)
parts.save(PARTS_OUT)
for name, box in placed.items():
    print(f"  {name} page: texture px {box}")
print(f"-> {OUT}\n-> {PARTS_OUT}")
print("  crafting page boxes (art px, for ProfessionsPanel.lua):")
for key, box in CRAFT.items():
    print(f"    {key:11s} {box}")
