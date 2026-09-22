"""
Build the bag-slot column box from docs/bottombar-vision-4k.png (the user's
higher quality re-export of the mockup; prefer it over the more compressed
docs/bottombar-vision.webp whenever it is at least as large). The mockup
shows the backpack's borrowed bag slot buttons in a vertical column of
rune-bordered boxes on the frame's LEFT side, instead of the row of boxes
BackpackPanel.lua used to hang under the frame.

Every box in the column shares the same border art (a carved wood-and-iron
frame with a small red gem at each corner); the mockup's own icons painted
inside five of them are the game's bag icons rendered at mockup time, not
part of the art, so the one EMPTY box (the sixth, no bag slot in that
character's setup) is the clean template: same border, no icon to paint out.

  Media/Textures/BackpackColumn.tga   128 x 128, one square box tile at (0, 0)

    python Tools\\make_backpack_column.py
"""
import os

from PIL import Image
from paths import OUTPUT

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "bottombar-vision-4k.png")
TEX = os.path.join(HERE, "..", "Media", "Textures")
OUT = OUTPUT

# ---- measured on the art (pixels of the 1935 x 812 picture) -----------------
# the column runs from about y 387 to y 738 in six boxes; the sixth (bottom)
# one is empty in this character's mockup, so it is the clean box template
BOX = (1289, 681, 1358, 739)   # x0, y0, x1, y1 -- 69 x 58

SHEET = 128

art = Image.open(SRC).convert("RGBA")
os.makedirs(OUT, exist_ok=True)

box = art.crop(BOX)
w, h = box.size
assert w <= SHEET and h <= SHEET, f"box {w}x{h} does not fit a {SHEET} sheet"

sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
sheet.paste(box, (0, 0))
sheet.save(os.path.join(TEX, "BackpackColumn.tga"))

u0, u1 = 0 / SHEET, w / SHEET
v0, v1 = 0 / SHEET, h / SHEET
print(f"BackpackColumn.tga {SHEET} x {SHEET}   box {w} x {h} at (0, 0)")
print(f"  COLUMN_BOX = {{ {u0:.6f}, {u1:.6f}, {v0:.6f}, {v1:.6f} }}")
print(f"  box art aspect {w / h:.4f} (w/h) -- use to keep the sprite from stretching oddly")

# ---- preview over green so nothing painted can hide --------------------------
im = Image.open(os.path.join(TEX, "BackpackColumn.tga")).convert("RGBA")
bg = Image.new("RGBA", im.size, (0, 140, 0, 255))
bg.alpha_composite(im)
bg.convert("RGB").save(os.path.join(OUT, "backpackcolumn-preview.png"))
print("  preview in MelloUI-BuildData/output/backpackcolumn-preview.png")
