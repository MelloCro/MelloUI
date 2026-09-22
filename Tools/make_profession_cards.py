"""
Build Media/Textures/ProfessionCards.tga, the illustrations the Professions
Panel lays into the body of the book page's profession cards, from
docs/profession-cards.png (a 3 x 2 grid, 1086 x 1448: one column per
profession, row 1 coloured for a learned profession, row 2 grey for one
not learned; thin white dividers between the cells).

Each cell (about 352 x 717) is taller than a card body (300 x 334 art px,
under the skill bar and down to the card's bottom rail): the body's aspect
is cut from the cell's bottom, keeping the subject on its floor and losing
the empty wall above it. A soft shade darkens the bottom third where the
game's spell rings and their labels sit. The cuts are scaled to 252 x 281
(1.46 x their on-screen size at the module's 700 px window) and packed on
a 1024 x 1024 sheet, one column per profession, coloured over grey, with a
2 px extruded gutter round each so linear filtering never bleeds a
neighbour in. The rest of the sheet is free for the primary professions'
illustrations (their stone, bars and crosses are in the page skin).

    python Tools\\make_profession_cards.py

prints the UV table ProfessionsPanel.lua uses.
"""
import os
from PIL import Image
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "profession-cards.png")
OUT = os.path.join(HERE, "..", "Media", "Textures", "ProfessionCards.tga")
PREVIEW = os.path.join(HERE, "output", "profession_cards_sheet.png")

SHEET = 1024
CELL_W, CELL_H = 256, 288              # the pitch of a cell on the sheet
GUTTER = 2                              # extruded edge round each sprite
SPRITE_W, SPRITE_H = CELL_W - 2 * GUTTER, CELL_H - 2 * GUTTER - 3   # 252 x 281, the body's 300 x 334
BODY_W, BODY_H = 300, 334               # a card body in art px
BOTTOM_MARGIN = 12                      # source rows kept under the subject's floor
SHADE_FROM, SHADE_TO = 0.62, 0.55       # the bottom shade: starts at 62 % of the height, 55 % brightness at the edge

# the grid: columns are professions, rows are learned / not learned
COLUMNS = [("cooking", 2, 353), ("fishing", 364, 722), ("firstaid", 733, 1083)]
ROWS = [("learned", 2, 718), ("unlearned", 729, 1445)]


def cut(src, x0, x1, y1):
    """The bottom of a cell at the body's aspect."""
    w = x1 - x0
    h = round(w * BODY_H / BODY_W)
    cy1 = y1 - BOTTOM_MARGIN
    return src.crop((x0, cy1 - h, x1, cy1)).resize((SPRITE_W, SPRITE_H), Image.LANCZOS)


def shade(sprite):
    a = np.array(sprite).astype(float)
    h = a.shape[0]
    t = np.clip((np.arange(h) / (h - 1) - SHADE_FROM) / (1 - SHADE_FROM), 0, 1)
    k = 1 - (1 - SHADE_TO) * t ** 1.4
    a[:, :, :3] *= k[:, None, None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def extrude(sheet, x, y, w, h, g):
    """Fill the gutter round a sprite with its clamped edge pixels."""
    a = np.array(sheet)
    a[y - g:y, x:x + w] = a[y, x:x + w]
    a[y + h:y + h + g, x:x + w] = a[y + h - 1, x:x + w]
    a[y - g:y + h + g, x - g:x] = a[y - g:y + h + g, x][:, None, :]
    a[y - g:y + h + g, x + w:x + w + g] = a[y - g:y + h + g, x + w - 1][:, None, :]
    return Image.fromarray(a)


src = Image.open(SRC).convert("RGBA")
sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
uv = {}
for r, (state, y0, y1) in enumerate(ROWS):
    for c, (name, x0, x1) in enumerate(COLUMNS):
        sprite = shade(cut(src, x0, x1, y1))
        px, py = c * CELL_W + GUTTER, r * CELL_H + GUTTER
        sheet.paste(sprite, (px, py))
        sheet = extrude(sheet, px, py, SPRITE_W, SPRITE_H, GUTTER)
        uv[(name, state)] = (px, py, SPRITE_W, SPRITE_H)

sheet.save(OUT)

os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
preview = Image.new("RGBA", sheet.size, (0, 140, 0, 255))
preview.alpha_composite(sheet)
preview.save(PREVIEW)

print(f"-> {OUT}  ({SHEET} x {SHEET}), sprites {SPRITE_W} x {SPRITE_H}")
print("Sprite table for ProfessionsPanel.lua (sheet px):")
for (name, state), (x, y, w, h) in uv.items():
    print(f"  {name:9s} {state:9s}: Illustration({x}, {y}, {w}, {h})   uv {x / SHEET:.5f} {(x + w) / SHEET:.5f} {y / SHEET:.5f} {(y + h) / SHEET:.5f}")
