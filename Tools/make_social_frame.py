"""
Build the Social Panel textures from docs/social-frame.webp (1158 x 1359):
the Contacts window (the friends list, and the raid list on the same frame)
with the two bottom tabs painted under it.

  Media/Textures/SocialFrame.tga   1024 x 1024, the window (art 1158 x 1250,
                                   the bottom tabs left out) scaled to
                                   1024 high at the left
  Media/Textures/SocialParts.tga   512 x 512, the sprites the game's frames
                                   wear, in art pixels: the two bottom tab
                                   plates, the two sub tab plates and the two
                                   bottom button plates

Everything the game writes is painted out: the window title, the BattleTag,
the sub tab names, the bottom tab names, the button labels, the status gem
(the game draws the real status there) and the scroll thumb.  The runes are
ornament and stay.

    python Tools\\make_social_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "social-frame.webp")
TEX = master("Textures")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships

ART_W, ART_H = 1158, 1250          # the window, without the tabs under it
SHEET = 512

# sprite name -> (x, y) on the sheet, and the art box it is cut from
PARTS = {
    "tab":        ((0, 0),     (252, 1249, 466, 1345)),   # 214 x 96  a bottom tab
    "tab_on":     ((220, 0),   (36, 1249, 250, 1345)),    # 214 x 96  the open one
    "subtab":     ((0, 100),   (364, 209, 638, 277)),     # 274 x 68  a sub tab
    "subtab_on":  ((0, 176),   (75, 205, 349, 277)),      # 274 x 72  the open one
    "plate_red":  ((0, 252),   (78, 1165, 409, 1222)),    # 331 x 57  the red button plate
    "plate_dark": ((0, 314),   (744, 1165, 1032, 1222)),  # 288 x 57  the dark button plate
}
# the plain stone that covers the status row on the pages that have none:
# the strip behind the plates, tiled from the bare stone beside them and
# given that strip's own top-to-bottom shading, stored at half size
COVER_AT = (0, 390)
COVER_BOX = (185, 106, 1118, 266)
COVER_TILE = (190, 112, 290, 190)
COVER_SIZE = (466, 80)


def feathered_paste(img, piece, box, feather=3):
    w, h = piece.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, w - feather - 1, h - feather - 1), fill=255)
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    img.paste(piece, box, mask)


def sheet_of(piece, w, h):
    out = Image.new("RGBA", (w, h))
    y, row = 0, 0
    while y < h:
        x, col = 0, 0
        while x < w:
            p = piece
            if col % 2 == 1:
                p = p.transpose(Image.FLIP_LEFT_RIGHT)
            if row % 2 == 1:
                p = p.transpose(Image.FLIP_TOP_BOTTOM)
            out.paste(p, (x, y))
            x += piece.size[0]
            col += 1
        y += piece.size[1]
        row += 1
    return out


def across(img, dst, sx0, sx1, feather=3):
    """Paint dst with a strip of the same rows taken at columns sx0..sx1."""
    piece = img.crop((sx0, dst[1], sx1, dst[3]))
    feathered_paste(img, sheet_of(piece, dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def patch(img, dst, src, feather=3, source=None):
    """Paint dst with a box tiled both ways."""
    source = source or img
    feathered_paste(img, sheet_of(source.crop(src), dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def bridge(img, box, gap=2, feather=2):
    """Paint dst by fading the column just left of it into the column just
    right of it, row by row.  The plates are lit top to bottom and end to end,
    so a tiled strip bands them; this keeps both gradients."""
    x0, y0, x1, y1 = box
    a = np.array(img).astype(float)
    left = a[y0:y1, x0 - gap][:, None, :]
    right = a[y0:y1, x1 + gap - 1][:, None, :]
    t = np.linspace(0, 1, x1 - x0)[None, :, None]
    piece = Image.fromarray((left * (1 - t) + right * t).astype(np.uint8), "RGBA")
    feathered_paste(img, piece, (x0, y0), feather)


def solid(img, box, colour, feather=2):
    feathered_paste(img, Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), colour), (box[0], box[1]), feather)


def shaded_stone(img, box, tile, size):
    """A patch of plain stone the size of box: the tile repeated over it, each
    row then scaled to the brightness the strip really has there (measured on
    the bare stone columns the tile was cut from)."""
    x0, y0, x1, y1 = box
    base = np.array(sheet_of(img.crop(tile), x1 - x0, y1 - y0)).astype(float)
    src = np.array(img).astype(float)
    want = src[y0:y1, tile[0]:tile[2], :3].mean(axis=(1, 2))
    have = np.maximum(base[:, :, :3].mean(axis=(1, 2)), 1)
    base[:, :, :3] = np.clip(base[:, :, :3] * (want / have)[:, None, None], 0, 255)
    base[:, :, 3] = 255
    return Image.fromarray(base.astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)


def dark_mean(img, box):
    """The mean of a box's darker part: the plain colour under a light mark."""
    a = np.array(img.crop(box)).astype(int)
    lum = a[:, :, :3].sum(axis=2)
    keep = lum <= np.percentile(lum, 40)
    return tuple(int(v) for v in a[keep].mean(axis=0))


art = Image.open(SRC).convert("RGBA")
print(f"  source {SRC}: {art.size[0]} x {art.size[1]}")
parts = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))

# ---- sprites, cut before anything is painted out --------------------------------
# The plates are small and lit end to end, so their labels are bridged out
# rather than tiled over.  Boxes are in sprite pixels.
# a bottom tab, from "Raid"
tab = art.crop(PARTS["tab"][1])
bridge(tab, (60, 12, 156, 56))                               # "Raid"
parts.paste(tab, PARTS["tab"][0])
# the open bottom tab, from "Contacts"
tab_on = art.crop(PARTS["tab_on"][1])
bridge(tab_on, (34, 18, 180, 60))                            # "Contacts"
parts.paste(tab_on, PARTS["tab_on"][0])
# a sub tab, from "Recent Allies"
subtab = art.crop(PARTS["subtab"][1])
bridge(subtab, (38, 10, 242, 56))                            # "Recent Allies"
parts.paste(subtab, PARTS["subtab"][0])
# the open sub tab, from "Friends"
subtab_on = art.crop(PARTS["subtab_on"][1])
bridge(subtab_on, (78, 12, 202, 60))                         # "Friends"
parts.paste(subtab_on, PARTS["subtab_on"][0])
# the red button plate, from "Add Friend"
plate_red = art.crop(PARTS["plate_red"][1])
bridge(plate_red, (60, 5, 260, 51))                          # "Add Friend"
parts.paste(plate_red, PARTS["plate_red"][0])
# the dark button plate, from "Send Message"
plate_dark = art.crop(PARTS["plate_dark"][1])
bridge(plate_dark, (52, 4, 284, 52))                         # "Send Message"
parts.paste(plate_dark, PARTS["plate_dark"][0])

# ---- the window -----------------------------------------------------------------
w = art.crop((0, 0, ART_W, ART_H))
across(w, (500, 34, 730, 92), 700, 790)                      # the title "Contacts"
across(w, (615, 124, 865, 174), 880, 960)                    # the BattleTag "Mello#21650"
across(w, (68, 198, 665, 288), 690, 900, 4)                  # the two sub tabs (sprites now)
across(w, (313, 123, 363, 175), 364, 376, 3)                 # the green status gem
patch(w, (1062, 324, 1106, 368), (1062, 560, 1106, 604), 2)  # the scroll thumb
bridge(w, (138, 1170, 338, 1212))                            # "Add Friend"
bridge(w, (796, 1169, 1028, 1215))                           # "Send Message"

# the status row's stone cover, cut from the window once its plates' row and
# the sub tab strip are already plain
parts.paste(shaded_stone(w, COVER_BOX, COVER_TILE, COVER_SIZE), COVER_AT)

k = 1024 / ART_H
scaled = w.resize((round(ART_W * k), 1024), Image.LANCZOS)
tex = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
tex.save(os.path.join(TEX, "SocialFrame.tga"))
print(f"  SocialFrame.tga: art {ART_W} x {ART_H} scaled to {scaled.size[0]} x 1024 in 1024 x 1024")

parts.save(os.path.join(TEX, "SocialParts.tga"))
print("  SocialParts.tga:")
for name, (at, box) in PARTS.items():
    wid, hei = box[2] - box[0], box[3] - box[1]
    print(f"    {name:11s} {wid:3d} x {hei:3d} at {at}  (cut from {box})")
print(f"    {'cover':11s} {COVER_SIZE[0]:3d} x {COVER_SIZE[1]:3d} at {COVER_AT}"
      f"  (plain stone for art {COVER_BOX}, tiled from {COVER_TILE})")
