"""
Build the Appearances (transmog wardrobe) textures from docs/appearances-frame.webp
(1387 x 1134): the rune title bar, one "Items" tab, a search box and a filter
plate, a class dropdown plate, a row of slot-ring buttons with one square
"selected" gem frame, a weapon-category dropdown plate, one painted item card
(gem-cornered, a sword painted in it) over the cracked-stone grid area, and a
page counter with two arrow plates.

Every painted text, number and item icon is painted out: the title, the tab
name, the search prompt, the filter/class/weapon labels, the row's slot
icons and its selected frame, the sword in the card, the page count. The
prev/next arrows and the search magnifier and the dropdown arrows are kept
(they are plain chrome, not dynamic game text) -- see AppearancesPanel.lua's
comment header for how the game's own frames are laid over what is left.

  Media/Textures/AppearancesFrame.tga   2048 x 1024, the whole window scaled
                                         to 1024 high, every text/icon erased
  Media/Textures/AppearancesParts.tga   512 x 512, sprites: the slot ring
                                         (plain), the selected square gem
                                         frame, the item card (interior
                                         cleared), the tab plate (for a
                                         second "Sets" tab, if the client
                                         shows one)

    python Tools\\make_appearances_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "appearances-frame.webp")
TEX = master("Textures")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships

ART_W, ART_H = 1387, 1134


def feathered_paste(img, patch_img, box, feather=3):
    w, h = patch_img.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, w - feather - 1, h - feather - 1), fill=255)
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    img.paste(patch_img, box, mask)


def sheet_of(piece, w, h):
    sheet = Image.new("RGBA", (w, h))
    y = 0
    while y < h:
        x = 0
        while x < w:
            sheet.paste(piece, (x, y))
            x += piece.size[0]
        y += piece.size[1]
    return sheet


def across(img, dst, sx0, sx1, feather=3):
    """Erase dst by tiling a vertical strip (sx0..sx1, dst's own y range)
    across its width: keeps whatever horizontal border runs through dst."""
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
    solid(img, box, dark_mean(img, sample), feather)


def key_metal(crop, lum_thresh=270, feather=1.5, clear_rect=None):
    """Isolate bright metal / red-gem ornament from a dark background: alpha
    stays only where the pixel is bright (the iron/gold ring or frame) or a
    saturated red (a gem), so the sprite drops onto any dark background.
    `clear_rect` (x0, y0, x1, y1), if given, is forced fully transparent
    before the feather blur regardless of pixel colour -- for a card's
    interior, where a bright painted item would otherwise survive the
    brightness key."""
    a = np.array(crop.convert("RGBA")).astype(int)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    lum = r + g + b
    bright = lum >= lum_thresh
    red = (r > 95) & ((r - g) > 35) & ((r - b) > 35)
    keep = bright | red
    if clear_rect:
        x0, y0, x1, y1 = clear_rect
        keep[y0:y1, x0:x1] = False
    out = a.copy()
    out[:, :, 3] = np.where(keep, 255, 0)
    img = Image.fromarray(out.astype(np.uint8), "RGBA")
    if feather:
        a_ch = img.split()[3].filter(ImageFilter.GaussianBlur(feather))
        img.putalpha(a_ch)
    if clear_rect:
        # the blur can bleed a little brightness back into the hole's edge:
        # cut the interior dead flat once more, after feathering the outside
        x0, y0, x1, y1 = clear_rect
        a2 = np.array(img)
        a2[y0:y1, x0:x1, 3] = 0
        img = Image.fromarray(a2)
    return img


art = Image.open(SRC).convert("RGBA")
assert art.size == (ART_W, ART_H), art.size

parts = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
PARTS = {}

# ---- sprites, cut from the pristine art before anything is painted out ----

# the slot ring: one clean ring from the row (the head slot)
ring_src = art.crop((350, 199, 426, 274))
ring = key_metal(ring_src)
PARTS["ring"] = (0, 0)
parts.paste(ring, PARTS["ring"], ring)

# the selected slot's square gem frame
sel_src = art.crop((1099, 192, 1209, 284))
sel = key_metal(sel_src)
PARTS["selected"] = (90, 0)
parts.paste(sel, PARTS["selected"], sel)

# the item card: gem-cornered frame, interior (and the painted sword) cleared
# to full transparency regardless of colour -- a brightness key alone keeps
# the sword, since it is light-on-black exactly like the frame's own metal
card_src = art.crop((86, 331, 316, 557))
card = key_metal(card_src, lum_thresh=250, clear_rect=(38, 44, 193, 202))
PARTS["card"] = (0, 100)
parts.paste(card, PARTS["card"], card)

# ---- paint the text and icons out of the main art --------------------------

# the rune bar's title: replaced with more of its own rune pattern (a gap
# between two glyph clusters, so no stray dot or letter gets tiled in)
across(art, (598, 34, 799, 72), 415, 470, 2)

# the "Items" tab: erase only the word, keep the tab's pointed border
flat(art, (184, 116, 300, 158), (296, 120, 308, 150), 2)
tab_plate = art.crop((159, 105, 322, 167))
PARTS["tab"] = (220, 0)
parts.paste(tab_plate, PARTS["tab"])

# the search box: erase "Search", keep the border and the magnifier
flat(art, (927, 116, 1068, 155), (1075, 120, 1100, 150), 2)

# the Filter plate: erase the word, keep the border and the arrow
flat(art, (1186, 116, 1298, 155), (1291, 122, 1299, 148), 2)

# the class dropdown "Warrior": erase the word, keep the border and the arrow
flat(art, (84, 210, 283, 260), (285, 221, 296, 249), 2)

# the weapon dropdown "Two-Handed Swords": erase the words, keep border+arrow
flat(art, (1010, 294, 1293, 344), (1291, 122, 1299, 148), 2)

# the slot row: erase every painted ring, icon and the selected square at once
flat(art, (348, 196, 1349, 276), (1332, 210, 1345, 265), 4)

# the one example item card: erase the whole thing off the stone
flat(art, (86, 331, 316, 557), (700, 650, 900, 800), 4)

# "Page 1/1": erase against the cracked stone (copy the patch just above it)
patch(art, (533, 970, 692, 1020), (533, 920, 692, 970), 2)

# ---- scale and save the main texture ---------------------------------------
TEX_W, TEX_H = 2048, 1024
k = TEX_H / ART_H
scaled = art.resize((round(ART_W * k), TEX_H), Image.LANCZOS)
tex = Image.new("RGBA", (TEX_W, TEX_H), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
tex.save(os.path.join(TEX, "AppearancesFrame.tga"))
print(f"AppearancesFrame.tga: art {scaled.size[0]} x {TEX_H} in {TEX_W} x {TEX_H}")

parts.save(os.path.join(TEX, "AppearancesParts.tga"))
print("AppearancesParts.tga:", ", ".join(f"{k2} at {v}" for k2, v in PARTS.items()))
print("ring", ring.size, "selected", sel.size, "card", card.size, "tab", tab_plate.size)
