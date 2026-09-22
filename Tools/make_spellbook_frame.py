"""
Build Media/Textures/SpellBookFrame.tga from docs/spellbook-frame.webp: the
1218 x 1291 artwork scaled to 1024 high in the left part of a 2048 x 1024
texture (the Spell Book module reads the left 966 columns).

The art was painted from a full page: a title, four tab icons, a search
prompt, a "General" heading with its rule, twelve spells with their rings
and names, a page count. All of that is the game's to draw, so it is painted
out: the title bar and the search box get their plain fill, the page gets
plain parchment. The pieces the game's frames wear are kept aside as sprites
in the texture's spare right part: the ring around a spell icon (with its
middle cleared for the icon), a tab square (plain and gold-rimmed for the
open tab), and the search box (cut in two so it can be drawn shorter when
there are more tabs than the art has squares).

    python Tools\\make_spellbook_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "spellbook-frame.webp")
OUT = os.path.join(HERE, "..", "Media", "Textures", "SpellBookFrame.tga")

TITLE_TEXT = (532, 36, 700, 94)         # "Spellbook" in gold
TITLE_CLEAN = (700, 36, 820, 94)        # plain bar right of it
SEARCH = (648, 106, 1093, 158)          # the search box, outline included
SEARCH_TEXT_FROM = 704                  # the prompt starts here; the magnifier is left of it
SEARCH_FILL = (1000, 114, 1080, 150)    # plain box interior
HEADER_WORD = (150, 332, 430, 408)      # "General" (left of the ornament's lowest tips)
HEADER_RULE = (420, 376, 1050, 414)     # its rule
CELLS = (148, 408, 1085, 972)           # the twelve spells
PAGE_TEXT = (760, 1094, 902, 1156)      # "Page 1/1"
PARCH_STRIP = (148, 972, 1085, 1078)    # clean parchment under the spells, full width
TABS_AREA = (218, 96, 548, 182)         # the four tab squares (drawn as sprites on the tabs)
FRAME_BG = (545, 96, 645, 182)          # plain frame background next to them
RING_CENTER = (550.5, 760.5)            # the ring of the third row's middle spell
RING_R = 58                             # its outer radius (57 measured, one more for the shadow)
RING_CLEAR = 36                         # the icon shows through inside this radius
TAB = (226, 105, 295, 172)              # the first tab square
TAB_ICON_INSET = 4


def feathered_paste(img, patch, box, feather=4):
    w, h = patch.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, w - feather - 1, h - feather - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    img.paste(patch, box, mask)


def tile_h(img, src_box, dst_box):
    """Tile a strip sideways over a box (same height)."""
    w, h = dst_box[2] - dst_box[0], dst_box[3] - dst_box[1]
    src = img.crop(src_box).resize((src_box[2] - src_box[0], h))
    strip = Image.new("RGBA", (w, h))
    x = 0
    while x < w:
        strip.paste(src, (x, 0))
        x += src.size[0]
    feathered_paste(img, strip, (dst_box[0], dst_box[1]))


def tile_v(img, src_box, dst_box, feather=6):
    """Tile a wide strip downwards over a box (the strip is cut to the box's width)."""
    w, h = dst_box[2] - dst_box[0], dst_box[3] - dst_box[1]
    src = img.crop(src_box)
    if src.size[0] > w:
        src = src.crop((0, 0, w, src.size[1]))
    elif src.size[0] < w:
        src = src.resize((w, src.size[1]))
    sheet = Image.new("RGBA", (w, h))
    y = 0
    while y < h:
        # alternate the strip's direction so the seams do not repeat a gradient
        piece = src if (y // src.size[1]) % 2 == 0 else src.transpose(Image.FLIP_TOP_BOTTOM)
        sheet.paste(piece, (0, y))
        y += src.size[1]
    feathered_paste(img, sheet, (dst_box[0], dst_box[1]), feather)


art = Image.open(SRC).convert("RGBA")
clean = art.copy()   # sprites are cut before anything is painted out

# ---- sprites -----------------------------------------------------------------
cx, cy = RING_CENTER
ring = clean.crop((int(cx - RING_R), int(cy - RING_R), int(cx + RING_R) + 1, int(cy + RING_R) + 1))
rw, rh = ring.size
yy, xx = np.mgrid[0:rh, 0:rw]
d = np.sqrt((xx - (cx - int(cx - RING_R))) ** 2 + (yy - (cy - int(cy - RING_R))) ** 2)
alpha = np.array(ring)[:, :, 3].astype(float)
alpha *= np.clip((d - RING_CLEAR) / 2.5, 0, 1)          # clear the middle, soft edge
alpha *= np.clip((RING_R + 0.5 - d) / 1.5, 0, 1)        # round the outside
ring_arr = np.array(ring)
ring_arr[:, :, 3] = alpha.astype(np.uint8)
ring = Image.fromarray(ring_arr)

tab = clean.crop(TAB)
tw, th = tab.size
# the plain square gets the icon area filled with the square's own dark inside
inside = np.array(tab)
inner = inside[TAB_ICON_INSET + 2:th - TAB_ICON_INSET - 2, TAB_ICON_INSET + 2:tw - TAB_ICON_INSET - 2]
dark = np.array([22, 22, 26, 255], dtype=np.uint8)
inner[:, :, :] = dark
tab_plain = Image.fromarray(inside)
# the open tab: a gold rim just inside the square's outline
tab_on = tab_plain.copy()
draw = ImageDraw.Draw(tab_on)
for i, colour in enumerate(((255, 214, 110, 255), (232, 180, 70, 255), (150, 105, 30, 255))):
    draw.rectangle((1 + i, 1 + i, tw - 2 - i, th - 2 - i), outline=colour)

search = clean.crop(SEARCH)
# the prompt is painted out of the sprite, the magnifier stays
sw, sh = search.size
fill = clean.crop(SEARCH_FILL).resize((sw, SEARCH_FILL[3] - SEARCH_FILL[1]))
text_left = SEARCH_TEXT_FROM - SEARCH[0]
fill_box = (text_left, 114 - SEARCH[1], sw - 12, 150 - SEARCH[1])
patch = fill.crop((0, 0, fill_box[2] - fill_box[0], fill_box[3] - fill_box[1]))
feathered_paste(search, patch, (fill_box[0], fill_box[1]), 3)

# ---- paint the art out ---------------------------------------------------------
tile_h(art, TITLE_CLEAN, TITLE_TEXT)
tile_v(art, PARCH_STRIP, HEADER_WORD)
tile_v(art, PARCH_STRIP, HEADER_RULE)
tile_v(art, PARCH_STRIP, CELLS)
tile_v(art, PARCH_STRIP, PAGE_TEXT)
# the tab squares and the search box leave the art (both are drawn as sprites,
# one square per tab however many there are); the frame's plain background
# takes their place
tile_h(art, FRAME_BG, TABS_AREA)
tile_h(art, FRAME_BG, (SEARCH[0] - 4, SEARCH[1] - 2, SEARCH[2] + 4, SEARCH[3] + 2))

# ---- the texture ----------------------------------------------------------------
k = 1024 / art.size[1]
scaled = art.resize((round(art.size[0] * k), 1024), Image.LANCZOS)
tex = Image.new("RGBA", (2048, 1024), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
sprites = {}
x, y = 1000, 8
row_h = 0
for name, im in (("ring", ring), ("tab", tab_plain), ("tab_on", tab_on), ("search", search)):
    sp = im.resize((round(im.size[0] * k), round(im.size[1] * k)), Image.LANCZOS)
    if x + sp.size[0] > 2040:
        x, y = 1000, y + row_h + 8
        row_h = 0
    tex.paste(sp, (x, y))
    sprites[name] = (x, y, x + sp.size[0], y + sp.size[1])
    x += sp.size[0] + 8
    row_h = max(row_h, sp.size[1])
tex.save(OUT)
for name, box in sprites.items():
    print(f"  {name} sprite: texture px {box}")
print(f"{scaled.size[0]}x{scaled.size[1]} art in a {tex.size[0]}x{tex.size[1]} texture -> {OUT}")
