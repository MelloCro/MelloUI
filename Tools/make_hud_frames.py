"""
Build the HUD textures from the painted art in docs/ (all RGBA webp), and
write the shared layout table Media/HudLayout.lua that both the Lua modules
and Tools/preview_hud.py read.

  Media/Textures/ActionBarParts.tga  2048 x 512   docs/actionbar-frame.webp
      The action bar art cut into re-usable pieces (see Tools/hud_layout_data.py
      for the measurements and why): ONE square slot cell with no gems, the
      seam gem and the bigger corner gem on transparent, a tileable horizontal
      and vertical outer rail strip, the rune title plate, and the XP bar's
      two end caps + a stretchable middle + one segment divider. The module
      composes a row out of these, so every slot is identical and every gem is
      drawn exactly once, at a grid crossing.
  Media/Textures/UnitFrame.tga       2048 x 1024  docs/unitframe-frame.webp
      the ring (portrait disc cut to a transparent hole), the level badge
      (number blurred into its own gloss shading), the name plate (blurred
      out) and both bar interiors (cleared; the game's health and power bars
      draw through, see Modules/BarTextures.lua).
  Media/Textures/CastBarFrame.tga    2048 x 512   docs/castbar-frame.webp
      the fill interior cleared (the middle gem ornament kept) and the name
      plate blurred out.

    python Tools\\make_hud_frames.py

No painted text, number, icon or face survives in any of them: the game draws
all of that live over the art.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

import hud_layout_data as L
from paths import OUTPUT

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, "..", "docs")
TEX = os.path.join(HERE, "..", "Media", "Textures")
MEDIA = os.path.join(HERE, "..", "Media")
CANVAS_W = 2048


# --------------------------------------------------------------------------
# helpers (pattern from make_map_frame.py / make_legacy_frame.py)
# --------------------------------------------------------------------------
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
    """Tile a same-height strip (sx0:sx1 at dst's own y-range) horizontally
    across dst: safe for text on an opaque plate, the sample never leaves the
    plate's own row."""
    piece = img.crop((sx0, dst[1], sx1, dst[3]))
    feathered_paste(img, sheet_of(piece, dst[2] - dst[0], dst[3] - dst[1]), (dst[0], dst[1]), feather)


def soften(img, box, radius=22, darken=1.0, feather=10):
    """Blur a box heavily so painted text dissolves into its own surrounding
    shading instead of being flattened to one sampled colour."""
    m = feather + 6
    ext = (box[0] - m, box[1] - m, box[2] + m, box[3] + m)
    p = img.crop(ext).filter(ImageFilter.GaussianBlur(radius))
    if darken != 1.0:
        p = ImageEnhance.Brightness(p).enhance(darken)
    feathered_paste(img, p, (ext[0], ext[1]), feather)


def clear_box(img, box, keep_center=None):
    """Clear a rectangle to transparent (alpha 0); a game frame draws there.
    keep_center=(cx,cy,reach) preserves a diamond ornament sitting on top of
    the box (a Chebyshev-diamond mask, like the painted gem shapes)."""
    a = np.array(img)
    a[box[1]:box[3], box[0]:box[2], 3] = 0
    if keep_center:
        cx, cy, reach = keep_center
        src = np.array(img)
        c = (max(box[0], cx - reach), max(box[1], cy - reach), min(box[2], cx + reach), min(box[3], cy + reach))
        sub = src[c[1]:c[3], c[0]:c[2]]
        yy, xx = np.mgrid[c[1]:c[3], c[0]:c[2]]
        near = (np.abs(xx - cx) + np.abs(yy - cy)) <= reach
        a[c[1]:c[3], c[0]:c[2], 3] = np.where(near, sub[:, :, 3], 0)
    return Image.fromarray(a)


def clear_blue(img, box):
    """Clear every remaining blue pixel inside `box`. The painted bar fills
    have a soft edge that reaches a row or a column past the interior boxes,
    and the kept gem ornament drags a ring of fill with it; both showed in the
    client as a blue hairline / halo. The frames are grey metal and the gems
    red, so nothing else in these bands is blue."""
    a = np.array(img).astype(int)
    sub = a[box[1]:box[3], box[0]:box[2]]
    blue = (sub[:, :, 2] - sub[:, :, 0] > 18) & (sub[:, :, 2] > 45)
    sub[:, :, 3] = np.where(blue, 0, sub[:, :, 3])
    a[box[1]:box[3], box[0]:box[2]] = sub
    return Image.fromarray(a.astype(np.uint8))


def clear_circle(img, cx, cy, r, keep=None):
    """Clear a disc to transparent. `keep` = (kx, ky, kr): a second disc that
    is never cleared, for art that overlaps the hole and has to stay opaque
    (the level badge lies partly inside the portrait hole)."""
    a = np.array(img)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    inside = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    if keep:
        kx, ky, kr = keep
        inside &= (xx - kx) ** 2 + (yy - ky) ** 2 > kr * kr
    a[:, :, 3] = np.where(inside, 0, a[:, :, 3])
    return Image.fromarray(a)


def corner_cut(img, reach):
    """Clear a Chebyshev diamond at each of the four corners: that is where
    the art's seam gems overlap a slot cell, and where the module draws a gem
    sprite of its own."""
    a = np.array(img).astype(float)
    h, w = a.shape[0], a.shape[1]
    yy, xx = np.mgrid[0:h, 0:w]
    keep = np.ones((h, w), dtype=bool)
    for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        keep &= (np.abs(xx - cx) + np.abs(yy - cy)) > reach
    a[:, :, 3] = np.where(keep, a[:, :, 3], 0)
    return Image.fromarray(a.astype(np.uint8))


def diamond_cut(img, reach, feather=1.5):
    """Keep only the Chebyshev diamond of the given reach around the crop's
    centre; everything outside goes transparent, so the gem can be laid over
    whatever rail the module composed underneath it."""
    a = np.array(img).astype(float)
    h, w = a.shape[0], a.shape[1]
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.abs(xx - cx) + np.abs(yy - cy)
    k = np.clip((reach - d) / max(feather, 0.001), 0.0, 1.0)
    a[:, :, 3] = a[:, :, 3] * k
    return Image.fromarray(a.astype(np.uint8))


def fit_to_canvas(art, canvas_w, canvas_h):
    scale = min(canvas_w / art.size[0], canvas_h / art.size[1])
    scaled = art.resize((round(art.size[0] * scale), round(art.size[1] * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    canvas.paste(scaled, (0, 0))
    return canvas, scaled.size


def preview(img, name):
    out = OUTPUT
    os.makedirs(out, exist_ok=True)
    bg = Image.new("RGBA", img.size, (20, 120, 20, 255))
    bg.alpha_composite(img)
    bg.convert("RGB").save(os.path.join(out, name))


# ==========================================================================
# 1) Action bar parts sheet
# ==========================================================================
raw = Image.open(os.path.join(DOCS, L.AB_ART)).convert("RGBA")

# --- the slot cell: rim only, gems excluded by the cut, icon hole cleared ---
cell = raw.crop(L.AB_CELL_SRC).resize((L.AB_SLOT_SIZE, L.AB_SLOT_SIZE), Image.LANCZOS)
m = int(round(L.AB_HOLE * L.AB_SLOT_SIZE))
cell = clear_box(cell, (m, m, L.AB_SLOT_SIZE - m, L.AB_SLOT_SIZE - m))
cell = corner_cut(cell, L.AB_CORNER_CUT)

gem = diamond_cut(raw.crop(L.AB_GEM_SRC), L.AB_GEM_REACH)
gem_big = diamond_cut(raw.crop(L.AB_GEMBIG_SRC), L.AB_GEMBIG_REACH)
rail_h = raw.crop(L.AB_RAIL_H_SRC)
rail_v = raw.crop(L.AB_RAIL_V_SRC)
title = raw.crop(L.AB_TITLE_SRC).copy()
across(title, L.AB_TITLE_X_BOX, L.AB_TITLE_X_SRC[0], L.AB_TITLE_X_SRC[1], feather=5)   # the painted red X

# --- the XP bar pieces: interiors cleared so the game's fill shows through ---
CY0, CY1 = L.XP_CLEAR_Y[0] - L.XP_Y0, L.XP_CLEAR_Y[1] - L.XP_Y0
xp_l = raw.crop(L.XP_CAP_L_SRC)
xp_l = clear_box(xp_l, (L.XP_CLEAR_X0 - L.XP_CAP_L_SRC[0], CY0,
                        L.XP_CAP_L_SRC[2] - L.XP_CAP_L_SRC[0], CY1))
xp_r = raw.crop(L.XP_CAP_R_SRC)
xp_r = clear_box(xp_r, (0, CY0, L.XP_CLEAR_X1 - L.XP_CAP_R_SRC[0], CY1))
xp_mid = raw.crop(L.XP_MID_SRC)
xp_mid = clear_box(xp_mid, (0, CY0, L.XP_MID_SRC[2] - L.XP_MID_SRC[0], CY1))
xp_tick = raw.crop(L.XP_TICK_SRC)

SPRITES = {
    "SLOT": cell, "GEM": gem, "GEMBIG": gem_big, "RAIL_H": rail_h, "RAIL_V": rail_v,
    "TITLE": title, "XP_L": xp_l, "XP_R": xp_r, "XP_MID": xp_mid, "XP_TICK": xp_tick,
}

parts = Image.new("RGBA", (L.PARTS_W, L.PARTS_H), (0, 0, 0, 0))
for name, img in SPRITES.items():
    x, y, w, h = L.PARTS[name]
    assert img.size == (w, h), f"{name}: sprite {img.size} != declared {(w, h)}"
    parts.paste(img, (x, y))
parts.save(os.path.join(TEX, "ActionBarParts.tga"))
preview(parts, "actionbar-parts-preview.png")
print(f"ActionBarParts.tga: {L.PARTS_W}x{L.PARTS_H}")
for name in SPRITES:
    x, y, w, h = L.PARTS[name]
    print(f"  {name:8s} sheet=({x},{y}) {w}x{h}  uv={tuple(round(v, 5) for v in L.uv(name))}")
print("  action bar rules (x cell pitch):", {k: round(v, 5) for k, v in L.actionbar_rules().items()})
print("  xp bar rules (x status bar height):", {k: round(v, 5) for k, v in L.xpbar_rules().items()})

# The old whole-row picture is gone: a single stretched image cannot give
# every row identical slots at whatever size Edit Mode makes the buttons.
_old = os.path.join(TEX, "ActionBarFrame.tga")
if os.path.exists(_old):
    os.remove(_old)
    print("  removed the superseded ActionBarFrame.tga")

# ==========================================================================
# 2) Unit frame (player layout; target mirrors it at runtime)
# ==========================================================================
art = Image.open(os.path.join(DOCS, "unitframe-frame.webp")).convert("RGBA").crop(L.UF_CROP)
ART_W, ART_H = art.size

RING_CX, RING_CY, RING_R_OUT, RING_R_IN = L.UF_RING
LEVEL_CX, LEVEL_CY, LEVEL_R = L.UF_LEVEL

soften(art, (LEVEL_CX - 55, LEVEL_CY - 55, LEVEL_CX + 55, LEVEL_CY + 55), radius=16, feather=10)   # the "14"
across(art, L.UF_NAME_BOX, L.UF_NAME_SRC[0], L.UF_NAME_SRC[1], feather=6)                          # "Warr Mello"
across(art, L.UF_CROSS_BOX, L.UF_CROSS_SRC[0], L.UF_CROSS_SRC[1], feather=6)                      # the painted red X
_m = L.UF_CLEAR_MARGIN
for _box in (L.UF_HEALTH_BOX, L.UF_POWER_BOX):
    # the painted "438" / "0" go with the fill; the game's bars draw through
    art = clear_box(art, (_box[0] - _m, _box[1] - _m, _box[2] + _m, _box[3] + _m))
art = clear_circle(art, RING_CX, RING_CY, RING_R_IN,
                   keep=(LEVEL_CX, LEVEL_CY, L.UF_LEVEL_KEEP_R))   # the face, but never the level badge

tex, art_size = fit_to_canvas(art, CANVAS_W, 1024)
tex.save(os.path.join(TEX, "UnitFrame.tga"))
preview(tex, "unitframe-frame-preview.png")
print(f"\nUnitFrame.tga: art {ART_W}x{ART_H} -> {art_size[0]}x{art_size[1]} in {CANVAS_W}x1024")
print("  RING", L.UF_RING, "LEVEL", L.UF_LEVEL)
print("  HEALTH_BOX", L.UF_HEALTH_BOX, "POWER_BOX", L.UF_POWER_BOX)
print("  NAME_BOX", L.UF_NAME_BOX, "CROSS_BOX", L.UF_CROSS_BOX)
UF_SIZE = (ART_W, ART_H)

# ==========================================================================
# 3) Cast bar (player; the target spell bar reuses the same texture, smaller)
# ==========================================================================
art = Image.open(os.path.join(DOCS, "castbar-frame.webp")).convert("RGBA").crop(L.CB_CROP)
CB_W, CB_H = art.size

art = clear_box(art, L.CB_FILL_BOX, keep_center=L.CB_MID_GEM)   # the game's status bar fill shows through
art = clear_blue(art, L.CB_FILL_BAND)                           # ... and no painted fill survives around it
across(art, L.CB_NAME_BOX, 635, 685, feather=6)                 # "Hearthstone", tiled from the rune deco beside it

CASTBAR_CANVAS_H = 512
tex, art_size = fit_to_canvas(art, CANVAS_W, CASTBAR_CANVAS_H)
tex.save(os.path.join(TEX, "CastBarFrame.tga"))
preview(tex, "castbar-frame-preview.png")
print(f"\nCastBarFrame.tga: art {CB_W}x{CB_H} -> {art_size[0]}x{art_size[1]} in {CANVAS_W}x{CASTBAR_CANVAS_H}")
print("  FILL_BOX", L.CB_FILL_BOX, "MID_GEM", L.CB_MID_GEM, "NAME_BOX", L.CB_NAME_BOX)


# ==========================================================================
# 4) Media/HudLayout.lua -- the one table the three modules read
# ==========================================================================
def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return f"{v:.6g}"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(fmt(x) for x in v) + " }"
    return str(v)


def table(pairs, indent):
    pad = "\t" * indent
    return "\n".join(f"{pad}{k} = {fmt(v)}," for k, v in pairs)


ab = L.actionbar_rules()
xp = L.xpbar_rules()
sprite_lines = []
for name in sorted(L.PARTS):
    u0, u1, v0, v1 = L.uv(name)
    w, h = L.part_size(name)
    sprite_lines.append(f"\t\t{name} = {{ uv = {{ {u0:.6g}, {u1:.6g}, {v0:.6g}, {v1:.6g} }}, w = {w}, h = {h} }},")

lua = f"""-- Generated by Tools/make_hud_frames.py from the painted art in docs/.
-- Do not edit by hand: change Tools/hud_layout_data.py and re-run the script
-- (Tools/preview_hud.py renders the same numbers locally for checking).
--
-- actionbar.* are fractions of the button CELL PITCH (button size + the bar's
-- icon padding). xpbar.* are fractions of the status bar's own HEIGHT.
-- unitframe.* / castbar.* are art pixels on each texture's own crop.

MelloUI_HudLayout = {{
\tparts = "Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Textures\\\\ActionBarParts",
\tsprites = {{
{chr(10).join(sprite_lines)}
\t}},
\tactionbar = {{
{table(sorted(ab.items()), 2)}
\t}},
\txpbar = {{
{table(sorted(xp.items()), 2)}
\t}},
\tunitframe = {{
\t\ttexture = "Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Textures\\\\UnitFrame",
\t\tcanvas = {{ 2048, 1024 }},
\t\tart = {{ {UF_SIZE[0]}, {UF_SIZE[1]} }},
\t\tring = {fmt(L.UF_RING)},
		portrait = {fmt(L.UF_PORTRAIT_R)},
\t\tlevel = {fmt(L.UF_LEVEL)},
\t\thealth = {fmt(L.UF_HEALTH_BOX)},
\t\tpower = {fmt(L.UF_POWER_BOX)},
\t\tname = {fmt(L.UF_NAME_BOX)},
\t\tcross = {fmt(L.UF_CROSS_BOX)},
\t}},
\tcastbar = {{
\t\ttexture = "Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Textures\\\\CastBarFrame",
\t\tcanvas = {{ 2048, {CASTBAR_CANVAS_H} }},
\t\tart = {{ {CB_W}, {CB_H} }},
\t\tfill = {fmt(L.CB_FILL_BOX)},
\t\tmidgem = {fmt(L.CB_MIDGEM_BOX)},
\t\tname = {fmt(L.CB_NAME_BOX)},
\t}},
\t-- the dark trough every module draws under the game's fill
\ttrough = {fmt(L.TROUGH)},
}}
"""
with open(os.path.join(MEDIA, "HudLayout.lua"), "w", encoding="utf-8", newline="\r\n") as fh:
    fh.write(lua)
print("\nwrote Media/HudLayout.lua")
