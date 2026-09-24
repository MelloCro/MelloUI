"""
Build the top bar texture from docs/bottombar-frame.png (1939 x 811 RGBA),
FLIPPED VERTICALLY: the same painted rail and the same red orbs in bronze
rings, but hung from the top edge of the screen instead of standing on the
bottom one. The user's mockup shows exactly that -- the bottom bar's art
mirrored -- so there is no separate source file to cut.

If dedicated top bar art ever lands (docs/topbar-frame.png), point SRC at it
and set FLIP = False; nothing else changes.

Measured on the bottom bar art (alpha > 8) and re-stated here for the flip:
the bar occupies rows 743..810 (68 px tall, orbs included); the plain rail
body is rows 774..809; the left orb's red gem is x 23..64, y 755..795. After
the flip, inside the 68 px band and measured from its TOP:

    rail body   rows  1..36        (it now hugs the screen's top edge)
    orbs        rows 15..55        (they hang down past the rail)
    orb centre  row  34.5          (gem centre 43.5 / 43.0 px from each end)

  Media/Textures/TopBar.tga   2048 x 128, three pieces on one row:
    LEFT   art x 0..150      (orb + ring + ornament, until the rail is plain)
    RIGHT  art x 1789..1939  (mirrored: ornament, then the ring + orb)
    MID    art x 400..1400   (a plain 1000 px slice of the rail, stretched)

Nothing painted here is text or a number, so the pieces are plain crops.

    python Tools\\make_topbar_frame.py
"""
import os

from PIL import Image
from paths import OUTPUT
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "bottombar-frame.png")
TEX = master("Textures")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
OUT = OUTPUT
FLIP = True

# ---- measured on the art (pixels of the 1939 x 811 picture) -----------------
BAR_TOP, BAR_BOTTOM = 743, 810          # the whole bar, orbs included (68 tall)
LEFT_X0, LEFT_X1 = 0, 150               # left cap: orb, ring and ornament
RIGHT_X0, RIGHT_X1 = 1789, 1939         # right cap: mirrored
MID_X0, MID_X1 = 400, 1400              # a clean 1000 px slice of the plain rail
GAP = 2                                 # padding between sheet pieces (no filter bleed)

BODY_TOP, BODY_BOTTOM = 774, 809        # the plain rail body, in unflipped art rows
GEM_LEFT = (23, 755, 64, 796)           # the red gem inside the left orb
GEM_RIGHT = (1875, 755, 1917, 796)

art = Image.open(SRC).convert("RGBA")
assert art.size == (1939, 811), f"unexpected art size {art.size}"
os.makedirs(OUT, exist_ok=True)

BAR_H = BAR_BOTTOM - BAR_TOP + 1
LEFT_W = LEFT_X1 - LEFT_X0
RIGHT_W = RIGHT_X1 - RIGHT_X0
MID_W = MID_X1 - MID_X0

SHEET_W, SHEET_H = 2048, 128
sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))


def band(x0, x1):
    piece = art.crop((x0, BAR_TOP, x1, BAR_BOTTOM + 1))
    return piece.transpose(Image.FLIP_TOP_BOTTOM) if FLIP else piece


PARTS = {}
x = 0
for name, piece, w in (
    ("LEFT", band(LEFT_X0, LEFT_X1), LEFT_W),
    ("RIGHT", band(RIGHT_X0, RIGHT_X1), RIGHT_W),
    ("MID", band(MID_X0, MID_X1), MID_W),
):
    sheet.paste(piece, (x, 0))
    PARTS[name] = (x, 0, w, BAR_H)
    x += w + GAP

sheet.save(os.path.join(TEX, "TopBar.tga"))

# a preview over green, so the transparent parts are obvious
bg = Image.new("RGBA", sheet.size, (20, 120, 20, 255))
bg.alpha_composite(sheet)
bg.convert("RGB").save(os.path.join(OUT, "topbar-preview.png"))


def flip_row(row):
    """An unflipped art row, expressed from the TOP of the flipped band."""
    return (BAR_H - 1) - (row - BAR_TOP) if FLIP else row - BAR_TOP


print(f"TopBar.tga {SHEET_W} x {SHEET_H}   bar art {BAR_H} tall (rows {BAR_TOP}..{BAR_BOTTOM}, flipped={FLIP})")
for name, (px, py, pw, ph) in PARTS.items():
    x0f, x1f = px / SHEET_W, (px + pw) / SHEET_W
    y0f, y1f = py / SHEET_H, (py + ph) / SHEET_H
    print(f"  {name:6s} {pw:4d} x {ph:3d}   uv = {{ {x0f:.6f}, {x1f:.6f}, {y0f:.6f}, {y1f:.6f} }}")

print("  measured from the bar's TOP edge, in art px:")
print(f"    rail body      {flip_row(BODY_BOTTOM):.1f} .. {flip_row(BODY_TOP):.1f}")
print(f"    orb gem rows   {flip_row(GEM_LEFT[3] - 1):.1f} .. {flip_row(GEM_LEFT[1]):.1f}")
print(f"    orb centre y   {(flip_row(GEM_LEFT[1]) + flip_row(GEM_LEFT[3] - 1)) / 2:.1f}")
print(f"    left orb x     {(GEM_LEFT[0] + GEM_LEFT[2]) / 2:.1f} from the bar's left")
print(f"    right orb x    {1939 - (GEM_RIGHT[0] + GEM_RIGHT[2]) / 2:.1f} from the bar's right")
print(f"    orb diameter   {GEM_LEFT[2] - GEM_LEFT[0]:.1f}")
