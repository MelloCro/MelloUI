"""
Build the Map Panel textures from docs/map-frame.webp (2000 x 768): the map
window (art x 0..1493) and the Quests window (x 1493..1994), each 762 high.

  Media/Textures/MapFrame.tga      2048 x 1024, the map window scaled to
                                   1024 high at the left, the map canvas cut
                                   out (the game draws the map there)
  Media/Textures/QuestsFrame.tga   1024 x 1024, the Quests window the same
  Media/Textures/MapParts.tga      512 x 128, the sprites: the two list
                                   header plates and the filter plates

Everything the game (or MelloUI) draws is painted out: the titles, the
search prompts, both lists, the quest count, the filter labels, the hide
completed label and its check, the scroll thumb.

    python Tools\\make_map_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "map-frame.webp")
TEX = master("Textures")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
SPLIT = 1493
CANVAS = (46, 126, 996, 740)     # the frame's inner edge
ORNAMENT_CORNERS = ((37, 740, 23),)     # the bottom-left diamond: centre and reach, it pokes into the hole

PARTS = {
    "log_header": (0, 0),      # 418 x 34  the map's quest log header plate
    "list_header": (0, 40),    # 410 x 30  the Quests window's header plate
    "filter": (0, 80),         # 102 x 30  a filter plate
    "filter_on": (110, 80),    # 102 x 30  the chosen one
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


def across(img, dst, sx0, sx1, feather=3):
    piece = img.crop((sx0, dst[1], sx1, dst[3]))
    feathered_paste(img, sheet_of(piece, dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def patch(img, dst, src, feather=3, source=None):
    source = source or img
    feathered_paste(img, sheet_of(source.crop(src), dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def solid(img, box, colour, feather=2):
    feathered_paste(img, Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), colour), (box[0], box[1]), feather)


def dark_mean(img, box):
    a = np.array(img.crop(box)).astype(int)
    lum = a[:, :, :3].sum(axis=2)
    keep = lum <= np.percentile(lum, 40)
    return tuple(int(v) for v in a[keep].mean(axis=0))


def flat(img, box, sample, feather=3):
    """Fill a box with the plain colour of a sample (the darker part of it)."""
    solid(img, box, dark_mean(img, sample), feather)


def clear_box(img, box, keep_corners=()):
    """Clear the box to transparent; in the given corner squares the frame's
    ornament pixels (dark iron and red gems) stay."""
    a = np.array(img)
    a[box[1]:box[3], box[0]:box[2], 3] = 0
    src = np.array(img).astype(int)
    for cx, cy, reach in keep_corners:
        c = (max(box[0], cx - reach), max(box[1], cy - reach), min(box[2], cx + reach), min(box[3], cy + reach))
        sub = src[c[1]:c[3], c[0]:c[2]]
        r, g, b = sub[:, :, 0], sub[:, :, 1], sub[:, :, 2]
        lum = r + g + b
        yy, xx = np.mgrid[c[1]:c[3], c[0]:c[2]]
        near = (np.abs(xx - cx) + np.abs(yy - cy)) <= reach     # a diamond, like the ornament
        ornament = near & ((lum < 150) | ((r > 110) & (g < 80) & (b < 80)))
        a[c[1]:c[3], c[0]:c[2], 3] = np.where(ornament, sub[:, :, 3], 0)
    return Image.fromarray(a)


art = Image.open(SRC).convert("RGBA")
parts = Image.new("RGBA", (512, 128), (0, 0, 0, 0))

# ---- sprites, cut before anything is painted out --------------------------------
log_header = art.crop((1022, 138, 1440, 172))
across(log_header, (4, 2, 150, 32), 160, 360, 1)             # "Westfall"
across(log_header, (360, 2, 414, 32), 160, 360, 1)           # the glyph
parts.paste(log_header, PARTS["log_header"])
list_header = art.crop((1528, 308, 1938, 338))
across(list_header, (4, 2, 250, 28), 255, 345, 1)            # "Blackrock Depths"
across(list_header, (345, 2, 406, 28), 255, 345, 1)          # the count and the glyph
parts.paste(list_header, PARTS["list_header"])
filt = art.crop((1750, 192, 1852, 222))
across(filt, (10, 3, 92, 27), 12, 26, 1)                     # "Zone"
parts.paste(filt, PARTS["filter"])
filt_on = art.crop((1528, 192, 1630, 222))
across(filt_on, (10, 3, 92, 27), 12, 36, 1)                  # "All"
parts.paste(filt_on, PARTS["filter_on"])

# ---- the map window ---------------------------------------------------------------
m = art.crop((0, 0, SPLIT, 762))
across(m, (690, 33, 940, 66), 960, 1100)                     # "Map & Quest Log"
across(m, (1050, 86, 1210, 112), 1250, 1400)                 # "Search Quest Log"
flat(m, (1016, 130, 1450, 745), (1030, 660, 1440, 740), 4)   # the quest log's list
m = clear_box(m, CANVAS, ORNAMENT_CORNERS)                   # the game's map
k = 1024 / m.size[1]
scaled = m.resize((round(m.size[0] * k), 1024), Image.LANCZOS)
tex = Image.new("RGBA", (2048, 1024), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
tex.save(os.path.join(TEX, "MapFrame.tga"))
print(f"  MapFrame.tga: art {scaled.size[0]} x 1024 in 2048 x 1024")

# ---- the Quests window ---------------------------------------------------------------
q = art.crop((SPLIT, 0, 1994, 762))
X = -SPLIT
across(q, (1680 + X, 33, 1800 + X, 66), 1560 + X, 1650 + X)          # "Quests"
flat(q, (1525 + X, 80, 1720 + X, 132), (1720 + X, 84, 1950 + X, 128))   # "All quests", the count
across(q, (1555 + X, 154, 1720 + X, 178), 1720 + X, 1900 + X)        # "Search quests"
flat(q, (1524 + X, 186, 1962 + X, 268), (1530 + X, 224, 1950 + X, 230))    # the filter plates (sprites now)
flat(q, (1552 + X, 269, 1720 + X, 299), (1720 + X, 272, 1900 + X, 296))   # "Hide completed"
solid(q, (1531 + X, 276, 1547 + X, 291), (24, 24, 28, 255), 1)       # the check in its box
solid(q, (1524 + X, 305, 1942 + X, 745), dark_mean(art, (1030, 660, 1440, 740)), 4)   # the list
patch(q, (1949 + X, 328, 1967 + X, 366), (1950 + X, 400, 1966 + X, 600), 2)       # the scroll thumb
scaled = q.resize((round(q.size[0] * k), 1024), Image.LANCZOS)
tex = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
tex.save(os.path.join(TEX, "QuestsFrame.tga"))
print(f"  QuestsFrame.tga: art {scaled.size[0]} x 1024 in 1024 x 1024")

parts.save(os.path.join(TEX, "MapParts.tga"))
print("  MapParts.tga:", ", ".join(f"{k} at {v}" for k, v in PARTS.items()))
