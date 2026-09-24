"""
Build Media/Textures/GameMenuFrame.tga from docs/gamemenu-frame.webp: the
910 x 1728 artwork in the top-left of a 1024 x 2048 texture (the Game Menu
module reads 910 x 1728 of it). The button names painted on the nine plates
are painted out (the game writes its own), by tiling a clean strip of each
plate across it.

    python Tools\\make_gamemenu_frame.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "gamemenu-frame.webp")
OUT = master("Textures", "GameMenuFrame.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
PLATES = [(258, 326), (394, 461), (523, 590), (653, 720), (782, 849), (977, 1043), (1154, 1220), (1281, 1347), (1452, 1525)]
CLEAN = (165, 255)      # x range of plate with no lettering on any row
COVER = (255, 745)      # x range that may hold lettering


def feathered_paste(img, patch, box, feather=6):
    w, h = patch.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, 0, w - feather - 1, h - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    img.paste(patch, box, mask)


art = Image.open(SRC).convert("RGBA")
for y0, y1 in PLATES:
    clean = art.crop((CLEAN[0], y0, CLEAN[1], y1))
    strip = Image.new("RGBA", (COVER[1] - COVER[0], y1 - y0))
    x = 0
    while x < strip.size[0]:
        strip.paste(clean, (x, 0))
        x += clean.size[0]
    feathered_paste(art, strip, (COVER[0], y0))
tex = Image.new("RGBA", (1024, 2048), (0, 0, 0, 0))
tex.paste(art, (0, 0))
tex.save(OUT)
print(f"{art.size[0]}x{art.size[1]} art in a {tex.size[0]}x{tex.size[1]} texture -> {OUT}")

# the Kit Colours looks (GameMenuFrame_warm / _bronze beside it)
import sys  # noqa: E402
sys.path.insert(0, HERE)
from kit_palette import build_textures  # noqa: E402
for dst in build_textures():
    print("->", dst)
