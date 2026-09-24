"""
Build Media/Textures/TalentsFrame.tga from docs/talents-frame.webp: the
1639 x 960 artwork scaled to 1024 high at the left of a 2048 x 1024 texture.

Everything the game draws is painted out: the title, the tab names, the
search prompt, the unspent talents label and number, the spec names, icons
and counts in the column headers, the talent squares (the column scenes are
blurred under them) and the apply label.

    python Tools\\make_talents_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import numpy as np
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "talents-frame.webp")
OUT = master("Textures", "TalentsFrame.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships


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


def dark_mean(img, box):
    a = np.array(img.crop(box)).astype(int)
    lum = a[:, :, :3].sum(axis=2)
    keep = lum <= np.percentile(lum, 25)
    return tuple(int(v) for v in a[keep].mean(axis=0))


def solid(img, box, colour, feather=2):
    feathered_paste(img, Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), colour), (box[0], box[1]), feather)


def soften(img, box, radius=30, darken=0.7, feather=12):
    """Blur and darken a box (worked on a larger crop so the whole box is blurred)."""
    m = feather + 6
    ext = (box[0] - m, box[1] - m, box[2] + m, box[3] + m)
    patch = img.crop(ext).filter(ImageFilter.GaussianBlur(radius))
    patch = ImageEnhance.Brightness(patch).enhance(darken)
    feathered_paste(img, patch, (ext[0], ext[1]), feather)


def disc(img, cx, cy, r, colour):
    a = np.array(img).astype(float)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    inside = np.clip((r - np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)) / 2, 0, 1)[:, :, None]
    a = a * (1 - inside) + np.array(colour, dtype=float) * inside
    return Image.fromarray(a.astype(np.uint8))


art = Image.open(SRC).convert("RGBA")
t = art
across(t, (640, 50, 1000, 92), 1050, 1180)                    # "TALENTS"
across(t, (180, 114, 322, 152), 180, 188)                     # "Primary" and its arrow: plain plate between the end diamonds
across(t, (384, 114, 552, 152), 384, 390)                     # "Secondary" and its arrow
across(t, (1232, 116, 1335, 146), 1340, 1400)                 # "Search"
across(t, (1338, 176, 1498, 208), 1322, 1338)                 # "Unspent Talents"
solid(t, (1516, 176, 1562, 208), dark_mean(t, (1516, 176, 1562, 208)), 3)   # its number
# the columns: the scenes stay, blurred under the game's talents and under
# its headers (the game draws its own ring, name and count, centred)
for x0, x1 in ((95, 552), (605, 1045), (1100, 1545)):
    soften(t, (x0, 335, x1, 845))
    soften(t, (x0, 226, x1, 330), radius=36)
across(t, (700, 875, 940, 912), 660, 690)                     # "Apply Changes"

k = 1024 / t.size[1]
scaled = t.resize((round(t.size[0] * k), 1024), Image.LANCZOS)
tex = Image.new("RGBA", (2048, 1024), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
tex.save(OUT)
print(f"{scaled.size[0]}x{scaled.size[1]} art in a 2048x1024 texture -> {OUT}")
