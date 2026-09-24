"""
Build the damage meter window's painted parts (Media/Textures/DamageMeter.tga)
as a NINE-SLICE from the user's standalone frame art docs/dpsmeter-frame.png
(1564 x 1006): a bronze rune frame with a red diamond gem at each corner, a
dark header band between two bronze rails across the top, and a cracked
dark-stone body. Falls back to cutting the same kind of parts from the
mockup docs/topbar-vision.png when the standalone file is missing.

The standalone file is RGB with a BAKED CHECKERBOARD behind the frame (white
253/254/255 and light grey 208 squares), not real alpha. The alpha is built
here: checker-coloured pixels (low saturation, bright) that connect to the
picture's border are background; everything the frame encloses is kept
whatever its colour; the frame's outer edge is then eroded by a pixel and
feathered. If the file is ever re-saved with real transparency (any pixel
with alpha < 255) the keying is skipped.

Measured with PIL on the standalone file:
    gems         ~68 x 72 px, centred (95,166) (1454,166) (90,884) (1454,884)
    top rail     rows 114..119, header band's lower rail rows 209..215
    bottom rail  rows 881..884; side rails x 75..88 and 1450..1464
    header band  the dark strip between the two top rails, y 120..208
    body         cracked stone, x 89..1449, y 216..880
  so the TOP corners sit on the header band (the gems are centred on it) and
  the top edge piece IS the band with both rails; the bottom corners sit on
  the bottom rail.

Nothing here is text, a button or a row: the game draws all of that. The
three header widgets get small square plates generated from the band's own
dark strip with a thin bronze rim (there are none in the art).

  Media/Textures/DamageMeter.tga   1024 x 512

    python Tools\\make_dpsmeter_frame.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from paths import OUTPUT
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
STANDALONE = os.path.join(HERE, "..", "docs", "dpsmeter-frame.png")
MOCKUP = os.path.join(HERE, "..", "docs", "topbar-vision.png")
TEX = master("Textures")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
OUT = OUTPUT

SHEET_W, SHEET_H = 1024, 512

# ---- the cuts on the STANDALONE file (file px) -------------------------------
STANDALONE_CUTS = {
    "CORNER_TL": (30, 95, 175, 240),      # gem + both rail junctions + band end
    "CORNER_TR": (1375, 95, 1520, 240),
    "CORNER_BL": (30, 815, 175, 950),     # gem + bottom rail junction
    "CORNER_BR": (1375, 815, 1520, 950),
    "EDGE_T": (500, 95, 620, 240),        # the header band with both rails
    "EDGE_B": (500, 815, 620, 950),       # the bottom rail
    "EDGE_L": (30, 400, 175, 520),        # the left rail (+ margin, matches the corners' width)
    "EDGE_R": (1375, 400, 1520, 520),
    "BODY": (250, 300, 1290, 820),        # a large clean stretch of stone (no period: stretched, never tiled)
}
STANDALONE_BAND = (120, 208)              # the header band's dark strip rows (for the plates)
STANDALONE_BAND_SAMPLE = (700, 900)       # a plain stretch of it
STANDALONE_RIM = (1000, 116)              # a bronze rail pixel, for the plates' rim
BODY_SHEET = (512, 256)                   # the body's size on the sheet

# ---- the same parts, cut from the mockup window (window px) ------------------
WIN = (7, 40, 372, 261)


def key_checkerboard(img):
    """RGBA with the baked checkerboard turned transparent (see the docstring)."""
    a = np.array(img.convert("RGBA")).astype(int)
    if a[:, :, 3].min() < 255:
        return img.convert("RGBA"), "real alpha found, keying skipped"
    mx = a[:, :, :3].max(axis=2)
    mn = a[:, :, :3].min(axis=2)
    checker = (mx - mn < 14) & (mn > 185)
    labels, _ = ndimage.label(checker)
    border = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    border.discard(0)
    background = np.isin(labels, list(border))
    fg = ~background
    # keep only the frame itself: the largest solid component
    fl, n = ndimage.label(fg)
    if n > 1:
        sizes = ndimage.sum(fg, fl, range(1, n + 1))
        fg = fl == (int(np.argmax(sizes)) + 1)
    fg = ndimage.binary_erosion(fg, iterations=1)
    alpha = ndimage.gaussian_filter(fg.astype(float), 0.7)
    a[:, :, 3] = np.clip(alpha * 255, 0, 255).astype(int)
    return Image.fromarray(a.astype(np.uint8)), "checkerboard keyed"


def make_plate(band, rim_colour, size=48):
    """A small square button plate: the band's own dark stone with a thin
    bronze rim, for the three header widgets the art has no plates for."""
    fill = band.resize((size, size), Image.LANCZOS)
    d = ImageDraw.Draw(fill)
    for i in range(2):
        d.rectangle((i, i, size - 1 - i, size - 1 - i), outline=rim_colour)
    d.rectangle((2, 2, size - 3, size - 3), outline=(0, 0, 0, 160))
    return fill


def load_standalone():
    src = Image.open(STANDALONE)
    keyed, how = key_checkerboard(src)
    pieces = {name: keyed.crop(box) for name, box in STANDALONE_CUTS.items()}
    pieces["BODY"] = pieces["BODY"].resize(BODY_SHEET, Image.LANCZOS)
    band = keyed.crop((STANDALONE_BAND_SAMPLE[0], STANDALONE_BAND[0], STANDALONE_BAND_SAMPLE[1], STANDALONE_BAND[1]))
    rim = tuple(int(v) for v in np.array(keyed)[STANDALONE_RIM[1], STANDALONE_RIM[0]])
    pieces["PLATE"] = make_plate(band, rim)
    layout = {
        "corner": 145, "corner_t": 145, "corner_b": 135, "edge_t": 145, "edge_b": 135, "edge_side": 145,
        "band": (STANDALONE_BAND[0] - 95, STANDALONE_BAND[1] - 95),   # the dark strip inside EDGE_T
        "art_to_old": 365.0 / 1525.0,   # this file is ~4x the mockup cut; the module scales it back
    }
    return pieces, layout, "docs/dpsmeter-frame.png (standalone, %s)" % how


def load_mockup():
    art = Image.open(MOCKUP).convert("RGB")
    win = art.crop(WIN).convert("RGBA")
    a = np.array(win).astype(int)
    dark = a[:, :, :3].max(axis=2) <= 14
    labels, _ = ndimage.label(dark)
    border = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    border.discard(0)
    a[:, :, 3] = np.where(np.isin(labels, list(border)), 0, 255)
    a[0:12, 14:60, 3] = 0
    win = Image.fromarray(a.astype(np.uint8))
    cuts = {
        "CORNER_TR": (330, 0, 365, 35), "CORNER_BR": (330, 186, 365, 221), "CORNER_BL": (0, 186, 35, 221),
        "EDGE_T": (240, 0, 300, 17), "EDGE_B": (240, 204, 300, 221), "EDGE_L": (0, 60, 17, 120),
        "EDGE_R": (348, 60, 365, 120), "PLATE": (285, 22, 310, 43),
    }
    pieces = {name: win.crop(box) for name, box in cuts.items()}
    pieces["CORNER_TL"] = pieces["CORNER_TR"].transpose(Image.FLIP_LEFT_RIGHT)
    body = win.crop((60, 95, 300, 180)).resize(BODY_SHEET, Image.LANCZOS).filter(ImageFilter.GaussianBlur(3))
    pieces["BODY"] = body
    layout = {"corner": 35, "corner_t": 35, "corner_b": 35, "edge_t": 17, "edge_b": 17, "edge_side": 17,
              "band": (3, 14), "art_to_old": 1.0}
    return pieces, layout, "docs/topbar-vision.png (mockup cut)"


# ---- the shared stone tile: Media/Textures/StoneTile.tga ------------------------
# The user's docs/stone-tile.png (1536 x 1024) is the body fill for this and
# for every later window. It is its own file because the body is drawn with
# texture WRAP (SetHorizTile / SetVertTile), which needs the file itself to be
# the tile -- so it repeats at native size at any window size, neither
# stretched nor showing a period. As delivered it is not seamless (the
# cracks break at the seams), so a seamless tile is made from it: a square
# centre crop mirrored into a 2 x 2 (its outer edges then match themselves by
# construction), downscaled to 512 x 512. A seamless export (edge difference
# no worse than 1.5 x the typical neighbour difference) is used as-is.
STONE_SRC = os.path.join(HERE, "..", "docs", "stone-tile.png")
STONE_TILE = 512


def build_stone_tile():
    if not os.path.exists(STONE_SRC):
        return None, "docs/stone-tile.png missing, body uses the frame's own stone"
    src = Image.open(STONE_SRC).convert("RGB")
    a = np.array(src).astype(float)
    edge = (np.abs(a[:, 0, :] - a[:, -1, :]).mean() + np.abs(a[0, :, :] - a[-1, :, :]).mean()) / 2
    neighbour = (np.abs(a[:, 1, :] - a[:, 2, :]).mean() + np.abs(a[1, :, :] - a[2, :, :]).mean()) / 2
    if edge <= 1.5 * neighbour:
        tile = src.resize((STONE_TILE, STONE_TILE), Image.LANCZOS)
        how = f"seamless export used as-is (edge {edge:.1f} vs neighbour {neighbour:.1f})"
    else:
        side = min(src.size)
        x0 = (src.width - side) // 2
        y0 = (src.height - side) // 2
        base = src.crop((x0, y0, x0 + side, y0 + side))
        quad = Image.new("RGB", (side * 2, side * 2))
        quad.paste(base, (0, 0))
        quad.paste(base.transpose(Image.FLIP_LEFT_RIGHT), (side, 0))
        quad.paste(base.transpose(Image.FLIP_TOP_BOTTOM), (0, side))
        quad.paste(base.transpose(Image.FLIP_LEFT_RIGHT).transpose(Image.FLIP_TOP_BOTTOM), (side, side))
        tile = quad.resize((STONE_TILE, STONE_TILE), Image.LANCZOS)
        how = f"mirror-tiled to seamless (edge {edge:.1f} vs neighbour {neighbour:.1f})"
    tile = tile.convert("RGBA")
    tile.save(os.path.join(TEX, "StoneTile.tga"))
    # a 2 x 2 repeat, to check the seams by eye
    check = Image.new("RGB", (STONE_TILE * 2, STONE_TILE * 2))
    for ix in range(2):
        for iy in range(2):
            check.paste(tile.convert("RGB"), (ix * STONE_TILE, iy * STONE_TILE))
    check.save(os.path.join(OUT, "stone-tile-repeat.png"))
    return tile, how


os.makedirs(OUT, exist_ok=True)
stone, stone_how = build_stone_tile()
if os.path.exists(STANDALONE):
    pieces, layout, source = load_standalone()
else:
    pieces, layout, source = load_mockup()

# ---- pack ---------------------------------------------------------------------
sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
PARTS = {}
x, y, rowh = 0, 0, 0
for name in ("CORNER_TL", "CORNER_TR", "CORNER_BL", "CORNER_BR", "EDGE_T", "EDGE_B",
             "EDGE_L", "EDGE_R", "PLATE", "BODY"):
    piece = pieces[name]
    w, h = piece.size
    if x + w > SHEET_W:
        x, y, rowh = 0, y + rowh + 2, 0
    assert y + h <= SHEET_H, f"{name} does not fit the sheet"
    sheet.paste(piece, (x, y))
    PARTS[name] = (x, y, w, h)
    x += w + 2
    rowh = max(rowh, h)
sheet.save(os.path.join(TEX, "DamageMeter.tga"))

bg = Image.new("RGBA", sheet.size, (20, 120, 20, 255))
bg.alpha_composite(sheet)
bg.convert("RGB").save(os.path.join(OUT, "dpsmeter-preview.png"))


# ---- composed previews, the way the module lays the window out ----------------
def compose(W, H, name):
    C, ET, EB, ES = layout["corner"], layout["edge_t"], layout["edge_b"], layout["edge_side"]
    c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    if stone is not None:
        # repeated at the tile's own size (the module wraps the texture the same way)
        body = Image.new("RGBA", (W - 2 * ES + 40, H - ET - EB + 40))
        ty = 0
        while ty < body.height:
            tx = 0
            while tx < body.width:
                body.paste(stone, (tx, ty))
                tx += STONE_TILE
            ty += STONE_TILE
        c.alpha_composite(body, (ES - 20, ET - 20))
    else:
        c.alpha_composite(pieces["BODY"].resize((W - 2 * ES + 40, H - ET - EB + 40), Image.BILINEAR), (ES - 20, ET - 20))
    c.alpha_composite(pieces["EDGE_T"].resize((max(W - 2 * C, 1), ET), Image.BILINEAR), (C, 0))
    c.alpha_composite(pieces["EDGE_B"].resize((max(W - 2 * C, 1), EB), Image.BILINEAR), (C, H - EB))
    ch_t = pieces["CORNER_TL"].height
    ch_b = pieces["CORNER_BL"].height
    c.alpha_composite(pieces["EDGE_L"].resize((ES, max(H - ch_t - ch_b, 1)), Image.BILINEAR), (0, ch_t))
    c.alpha_composite(pieces["EDGE_R"].resize((ES, max(H - ch_t - ch_b, 1)), Image.BILINEAR), (W - ES, ch_t))
    c.alpha_composite(pieces["CORNER_TL"], (0, 0))
    c.alpha_composite(pieces["CORNER_TR"], (W - C, 0))
    c.alpha_composite(pieces["CORNER_BL"], (0, H - ch_b))
    c.alpha_composite(pieces["CORNER_BR"], (W - C, H - ch_b))
    # the three plates at the band's right end, and the widgets' boxes
    b0, b1 = layout["band"]
    ph = b1 - b0 - 8
    d = ImageDraw.Draw(c)
    px = W - C - 10
    for _ in range(3):
        px -= ph
        c.alpha_composite(pieces["PLATE"].resize((ph, ph), Image.LANCZOS), (px, b0 + 4))
        d.rectangle((px, b0 + 4, px + ph, b0 + 4 + ph), outline=(0, 255, 0, 255))
        px -= 6
    d.rectangle((C + 6, b0 + 4, px - 6, b1 - 4), outline=(0, 200, 255, 255))      # the type selector / title
    d.rectangle((ES + 8, ET + 8, W - ES - 8, H - EB - 8), outline=(255, 0, 255, 255))   # the rows box
    d.rectangle((ES + 10, ET + 10, W - ES - 10, ET + 10 + 24), fill=(120, 90, 40, 255))  # a row's bar
    out = Image.new("RGBA", c.size, (20, 120, 20, 255))
    out.alpha_composite(c)
    out.convert("RGB").save(os.path.join(OUT, name))
    print(f"  composed {name}: {W} x {H} (art px)  chT={ch_t} chB={ch_b}")


scale_hint = 365.0 / 1525.0 if "standalone" in source else 1.0
compose(int(365 / scale_hint), int(230 / scale_hint), "dpsmeter-composed.png")
compose(int(548 / scale_hint), int(200 / scale_hint), "dpsmeter-composed-wide.png")

print(f"DamageMeter.tga {SHEET_W} x {SHEET_H}   source: {source}")
print(f"StoneTile.tga {STONE_TILE} x {STONE_TILE}   {stone_how}")
for name, (px, py, pw, ph) in PARTS.items():
    print(f"  {name:10s} {pw:4d} x {ph:3d}  uv = {{ {px / SHEET_W:.6f}, {(px + pw) / SHEET_W:.6f}, "
          f"{py / SHEET_H:.6f}, {(py + ph) / SHEET_H:.6f} }}")
print("  layout (art px):", layout)
