"""
Build Media/Textures/CharacterFrame.tga from docs/character-frame.webp: the
1489 x 1056 artwork scaled to 1024 high in the left part of a 2048 x 1024
texture (the Character Panel module reads the left 1444 columns).

The right pane of the art holds five stat plates and two bars with gems. In
the window that whole area is one scrolling list, so the plates and the bar
are lifted out of the picture into sprites in the texture's spare right part
(the module draws them as row backgrounds), the sample text painted on the
plates is dropped, and the area they came from is filled with the plain
stone behind them.

    python Tools\\make_character_frame.py

Prints the sprite coordinates the module needs (SPRITES in CharacterPanel.lua).
"""
import os
from PIL import Image, ImageDraw, ImageFilter
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "character-frame.webp")
OUT = master("Textures", "CharacterFrame.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
TEX_W, TEX_H = 2048, 1024
PLATE = (886, 285, 1327, 332)        # one stat plate on the art (all five are the same shape)
BAR = (890, 573, 1322, 619)          # the bar with the gems
CLEAN = (1060, 1200)                 # x range of plate with nothing painted on it
COVER = [(903, 1045), (1240, 1312)]  # x ranges holding the painted label and value
PANE = (879, 268, 1334, 900)         # the whole right pane below the blue plaque, inner border included
STONE = (879, 640, 1334, 830)        # plain stone inside that pane


def feathered_paste(img, patch, box, feather=6):
    w, h = patch.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, w - feather - 1, h - feather - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    img.paste(patch, box, mask)


art = Image.open(SRC).convert("RGBA")

# 1. a plate with the sample text painted out
x0, y0, x1, y1 = PLATE
clean = art.crop((CLEAN[0], y0, CLEAN[1], y1))
for cx0, cx1 in COVER:
    strip = Image.new("RGBA", (cx1 - cx0, y1 - y0))
    x = 0
    while x < strip.size[0]:
        strip.paste(clean, (x, 0))
        x += clean.size[0]
    feathered_paste(art, strip, (cx0, y0), feather=4)
plate = art.crop(PLATE)
bar = art.crop(BAR)

# 2. the pane filled with plain stone
stone = art.crop(STONE)
px0, py0, px1, py1 = PANE
fill = Image.new("RGBA", (px1 - px0, py1 - py0))
y = 0
while y < fill.size[1]:
    fill.paste(stone, (0, y))
    y += stone.size[1]
feathered_paste(art, fill, (px0, py0), feather=8)

# 2b. the title bar ends short of the frame's corner: slide its end cap and
# close cross right to the body's edge and fill the gap with plain bar
BAR_TAIL = (1200, 0, 1310, 118)      # the last rune, the cross and the end cap
BAR_SHIFT = 49                       # the body's right edge (1353) minus the bar's (1304)
tail = art.crop(BAR_TAIL)
filler = art.crop((1184, 0, 1221, 118))   # plain bar between the last rune and the divider, tiled to the shift
blank = Image.new("RGBA", (BAR_TAIL[2] - BAR_TAIL[0] + BAR_SHIFT, 118), (0, 0, 0, 0))
art.paste(blank, (BAR_TAIL[0], 0))
for x in range(BAR_TAIL[0], BAR_TAIL[0] + BAR_SHIFT, filler.size[0]):
    art.paste(filler, (x, 0))
art.paste(tail, (BAR_TAIL[0] + BAR_SHIFT, 0))

# 2c. a second frame for the other tabs (reputation, skills, ...): the slot
# boxes and the viewport give way to plain stone, one big pane for Blizzard's
# lists, with the same border, bars and right pane
LEFT_PANE = (36, 176, 852, 1010)     # under the name bar and the padlock, down to the bottom border
list_art = art.copy()
stone = art.crop((894, 640, 1318, 830))   # pane interior only, without the pane's border lines
fill = Image.new("RGBA", (LEFT_PANE[2] - LEFT_PANE[0], LEFT_PANE[3] - LEFT_PANE[1]))
# overlapping, feathered stone tiles so no seams show
step_x, step_y = stone.size[0] - 40, stone.size[1] - 40
y = -20
while y < fill.size[1]:
    x = -20
    while x < fill.size[0]:
        feathered_paste(fill, stone, (x, y), feather=12) if (x > -20 or y > -20) else fill.paste(stone, (x, y))
        x += step_x
    y += step_y
feathered_paste(list_art, fill, (LEFT_PANE[0], LEFT_PANE[1]), feather=6)
OUT_LIST = master("Textures", "CharacterFrameList.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
list_scaled = list_art.resize((round(list_art.size[0] * TEX_H / list_art.size[1]), TEX_H), Image.LANCZOS)
list_tex = Image.new("RGBA", (TEX_W, TEX_H), (0, 0, 0, 0))
list_tex.paste(list_scaled, (0, 0))
list_tex.save(OUT_LIST)
print(f"list frame -> {OUT_LIST}")

# 3. the texture: the frame on the left, the sprites on the right
scale = TEX_H / art.size[1]
scaled = art.resize((round(art.size[0] * scale), TEX_H), Image.LANCZOS)
tex = Image.new("RGBA", (TEX_W, TEX_H), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
sprites = {}
sx, sy = 1500, 8
for name, im in (("plate", plate), ("bar", bar)):
    sp = im.resize((round(im.size[0] * scale), round(im.size[1] * scale)), Image.LANCZOS)
    tex.paste(sp, (sx, sy))
    sprites[name] = (sx, sy, sx + sp.size[0], sy + sp.size[1])
    sy += sp.size[1] + 8
tex.save(OUT)
print(f"{scaled.size[0]}x{scaled.size[1]} art in a {TEX_W}x{TEX_H} texture -> {OUT}")
for name, (a, b, c, d) in sprites.items():
    print(f"  {name}: texture px ({a}, {b}) - ({c}, {d}); art size {(c - a) / scale:.1f} x {(d - b) / scale:.1f}")
