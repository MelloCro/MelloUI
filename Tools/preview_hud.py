"""
Render the HUD skins locally, the way Modules/ActionBarPanel.lua composes them
in the client, so the sprite cuts and the placement rules can be checked (and
compared with the painted art) without burning a round of in-game screenshots.

    python Tools\\preview_hud.py                       # this client's defaults
    python Tools\\preview_hud.py --button 45 --pad 2 --cols 12 --rows 1
    python Tools\\preview_hud.py --pad 8               # what a wider Edit Mode
                                                       # icon padding would look like

It reads the SAME numbers the Lua modules read -- Tools/hud_layout_data.py,
from which Media/HudLayout.lua is generated -- and the SAME sprite sheet
(Media/Textures/ActionBarParts.tga), so a mismatch here is a mismatch in the
client. Writes into MelloUI-BuildData/output/:

    preview_actionbar.png   two rows + the XP bar, composed from the sprites
    preview_overlay.png     the painted target art scaled to the same cell
                            pitch, drawn at 50% over that render
    preview_castbar.png     the cast bar skin at the client's bar size
    preview_unitframe.png   the player unit frame skin

Defaults come from the client: ActionButton1 is 45x45 (/huddump), the bar's
icon padding is Blizzard's minimum of 2 (ActionBarMixin:ActionBar_OnLoad), so
the cell pitch is 47; the XP bar's StatusBar is 10 px tall
(StatusTrackingBarTemplate.xml) and as wide as the bar.
"""
import argparse
import os

from PIL import Image, ImageDraw

import hud_layout_data as L
from paths import OUTPUT

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, "..", "docs")
TEX = os.path.join(HERE, "..", "Media", "Textures")
OUT = OUTPUT

BG = (36, 40, 48, 255)


# --------------------------------------------------------------------------
def load_sprites():
    sheet = Image.open(os.path.join(TEX, "ActionBarParts.tga")).convert("RGBA")
    return {name: sheet.crop((x, y, x + w, y + h)) for name, (x, y, w, h) in L.PARTS.items()}


def paste(canvas, sprite, box, flip_h=False, flip_v=False):
    """Draw `sprite` stretched into `box` = (x0, y0, x1, y1) in canvas pixels,
    the way a Texture with SetPoint/SetSize and a (possibly swapped) texcoord
    does in the client."""
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    w, h = max(x1 - x0, 1), max(y1 - y0, 1)
    img = sprite.resize((w, h), Image.LANCZOS)
    if flip_h:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    if flip_v:
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
    canvas.alpha_composite(img, (x0, y0))


def tile_h(canvas, sprite, box, flip_v=False):
    """A rail strip repeated along a box (the Lua side stretches one texture;
    tiling here shows the same art without smearing it at extreme ratios)."""
    if flip_v:
        sprite = sprite.transpose(Image.FLIP_TOP_BOTTOM)
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    h = max(y1 - y0, 1)
    sw = max(1, int(round(sprite.width * h / sprite.height)))
    piece = sprite.resize((sw, h), Image.LANCZOS)
    x = x0
    while x < x1:
        w = min(sw, x1 - x)
        canvas.alpha_composite(piece.crop((0, 0, w, h)), (x, y0))
        x += sw


def tile_v(canvas, sprite, box, flip_h=False):
    if flip_h:
        sprite = sprite.transpose(Image.FLIP_LEFT_RIGHT)
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    w = max(x1 - x0, 1)
    sh = max(1, int(round(sprite.height * w / sprite.width)))
    piece = sprite.resize((w, sh), Image.LANCZOS)
    y = y0
    while y < y1:
        h = min(sh, y1 - y)
        canvas.alpha_composite(piece.crop((0, 0, w, h)), (x0, y))
        y += sh


# --------------------------------------------------------------------------
# The action bar row: exactly the arithmetic Modules/ActionBarPanel.lua does.
# --------------------------------------------------------------------------
def row_geometry(left, top, button, pad, cols, rows):
    """Where the game puts the buttons: a grid of `button`-sized squares with
    `pad` between them (ActionBarMixin:UpdateGridLayout). Returns the button
    rects and the cell pitch (= the distance between two button centres)."""
    pitch = button + pad
    rects = []
    for r in range(rows):
        for c in range(cols):
            x = left + c * pitch
            y = top + r * pitch
            rects.append((x, y, x + button, y + button))
    return rects, pitch


def compose_row(canvas, rects, pitch, cols, rows, sprites, title=False, marks=None, join_bottom_to=None, gems=None):
    """`join_bottom_to`: this row sits on top of another skinned row whose
    block starts at that y. The divider is then drawn once, by the LOWER row,
    so this row drops its bottom rail and bottom gems and only runs its side
    rails down to meet the other block. Same rule as LayoutRow in
    Modules/ActionBarPanel.lua."""
    rules = L.actionbar_rules()
    cell = pitch
    half = cell / 2.0
    b0 = rects[0]
    cx0, cy0 = (b0[0] + b0[2]) / 2.0, (b0[1] + b0[3]) / 2.0

    # Grid lines: cols+1 vertical, rows+1 horizontal, through the cell edges.
    xs = [cx0 - half + i * pitch for i in range(cols + 1)]
    ys = [cy0 - half + j * pitch for j in range(rows + 1)]
    block = (xs[0], ys[0], xs[-1], ys[-1])
    rail = rules["rail"] * cell
    side_bottom = join_bottom_to if join_bottom_to is not None else block[3]

    # 1) the outer rail: top and bottom run the full width (they cover the
    #    corners), left and right fill between them.
    tile_h(canvas, sprites["RAIL_H"], (block[0] - rail, block[1] - rail, block[2] + rail, block[1]))
    if join_bottom_to is None:
        tile_h(canvas, sprites["RAIL_H"], (block[0] - rail, block[3], block[2] + rail, block[3] + rail), flip_v=True)
    tile_v(canvas, sprites["RAIL_V"], (block[0] - rail, block[1], block[0], side_bottom))
    tile_v(canvas, sprites["RAIL_V"], (block[2], block[1], block[2] + rail, side_bottom), flip_h=True)

    # 2) one slot cell per button, centred on the button, exactly `pitch`
    #    across -- so neighbouring cells butt edge to edge with no overlap.
    for (x0, y0, x1, y1) in rects:
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        paste(canvas, sprites["SLOT"], (cx - half, cy - half, cx + half, cy + half))
        if marks is not None:
            marks.append(("slot", (cx - half, cy - half, cx + half, cy + half)))

    # 3) one gem per grid crossing -- never two, which is what a per-button
    #    sprite carrying its own corner gems produced.
    gem = rules["gem"] * cell
    big = rules["cornerGem"] * cell
    for i, gx in enumerate(xs):
        for j, gy in enumerate(ys):
            if join_bottom_to is not None and j == rows:
                continue   # the row below draws this divider's gems
            corner = (i in (0, cols)) and (j in (0, rows))
            s = (big if corner else gem) / 2.0
            box = (gx - s, gy - s, gx + s, gy + s)
            # gems go on last so a neighbouring row's rail cannot cover them
            gems.append(("GEMBIG" if corner else "GEM", box))
            if marks is not None:
                marks.append(("gem", box))

    # 4) the rune title plate, centred over the block, hanging into the rail;
    #    it lies over the rail and its gems, so it is deferred past them too.
    if title:
        tw = rules["titleBlockW"] * (block[2] - block[0])
        th = rules["titleH"] * cell
        mid = (block[0] + block[2]) / 2.0
        bottom = block[1] - rail + rules["titleDrop"] * cell
        box = (mid - tw / 2.0, bottom - th, mid + tw / 2.0, bottom)
        gems.append(("TITLE", box))
        if marks is not None:
            marks.append(("title", box))

    # 5) where the game's icons end up: filling the cell from rail to rail
    #    (rules["icon"]), over the painted bevel and the dark slot plate.
    half_icon = (0.5 - rules["icon"]) * cell
    icons = []
    for (x0, y0, x1, y1) in rects:
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        icons.append((cx - half_icon, cy - half_icon, cx + half_icon, cy + half_icon))
    return block, icons


def draw_icons(canvas, icons):
    """Stand-ins for the game's spell icons, so the hole can be judged."""
    d = ImageDraw.Draw(canvas)
    for i, (x0, y0, x1, y1) in enumerate(icons):
        d.rectangle((x0, y0, x1 - 1, y1 - 1), fill=(90 + (i * 13) % 90, 70, 120, 255))
        d.rectangle((x0, y0, x1 - 1, y1 - 1), outline=(200, 190, 160, 255))


# --------------------------------------------------------------------------
# The XP / reputation / honor bar: scaled from the status bar's own height.
# --------------------------------------------------------------------------
def compose_xpbar(canvas, bar_rect, sprites, marks=None):
    rules = L.xpbar_rules()
    x0, y0, x1, y1 = bar_rect
    h = float(y1 - y0)
    capw, caph = rules["capW"] * h, rules["capH"] * h
    ix, iy = rules["capInsetX"] * h, rules["capInsetY"] * h
    left = (x0 - ix, y0 - iy, x0 - ix + capw, y0 - iy + caph)
    right = (x1 + ix - capw, y0 - iy, x1 + ix, y0 - iy + caph)
    # middle, stretched between the two caps
    paste(canvas, sprites["XP_MID"], (left[2], left[1], right[0], left[3]))
    paste(canvas, sprites["XP_L"], left)
    paste(canvas, sprites["XP_R"], right)
    # the painted segment dividers, over the game's fill
    seg = rules["segment"] * h
    tw, th = rules["tickW"] * h, rules["tickH"] * h
    top = y0 + rules["tickTop"] * h
    x = x0 + seg
    while x < x1 - seg * 0.25:
        paste(canvas, sprites["XP_TICK"], (x - tw / 2.0, top, x + tw / 2.0, top + th))
        x += seg
    if marks is not None:
        marks.append(("xp-bar", bar_rect))
        marks.append(("xp-capL", left))
        marks.append(("xp-capR", right))
    return left, right


# --------------------------------------------------------------------------
def render_actionbar(args, sprites):
    button, pad, cols, rows = args.button, args.pad, args.cols, args.rows
    pitch = button + pad
    margin = int(pitch * 1.2)
    row_w = cols * pitch
    width = row_w + 2 * margin
    height = int(margin * 2 + rows * pitch * 2 + pitch * 1.6)

    canvas = Image.new("RGBA", (width, height), BG)
    marks = []

    rules = L.actionbar_rules()
    rail = rules["rail"] * pitch
    left = margin + pad / 2.0
    top = margin + pitch * 0.6
    rects1, _ = row_geometry(left, top, button, pad, cols, rows)
    # the second row is an independent Edit Mode system with its own frame;
    # here it is stacked directly under the first, the way the client does.
    bottom1 = (rects1[-1][1] + rects1[-1][3]) / 2.0 + pitch / 2.0
    top2 = bottom1 + args.row_gap
    rects2, _ = row_geometry(left, top2 + (pitch - button) / 2.0, button, pad, cols, rows)
    top2_block = (rects2[0][1] + rects2[0][3]) / 2.0 - pitch / 2.0

    # Rows Edit Mode has left touching share one divider: their two rails are
    # already the art's 28 px, but only one row of gems belongs on it.
    gap = top2_block - bottom1
    joined = -1 <= gap <= rail * rules["joinGap"]

    gems = []
    block1, icons1 = compose_row(canvas, rects1, pitch, cols, rows, sprites, title=True, marks=marks,
                                 join_bottom_to=top2_block if joined else None, gems=gems)
    block2, icons2 = compose_row(canvas, rects2, pitch, cols, rows, sprites, title=False, marks=marks,
                                 gems=gems)
    for name, box in sorted(gems, key=lambda g: g[0] == "TITLE"):
        paste(canvas, sprites[name], box)
    draw_icons(canvas, icons1)
    draw_icons(canvas, icons2)
    print(f"  rows {'joined' if joined else 'separate'} (gap {gap:.1f} px, threshold {rail * rules['joinGap']:.1f})")

    # the XP bar under the rows, at the client's 10 px status bar height, with
    # the game's own fill and a dark trough drawn under the painted frame
    bar_h = args.xp_height
    bar_y = block2[3] + pitch * 0.55
    d = ImageDraw.Draw(canvas)
    d.rectangle((block1[0], bar_y, block1[2], bar_y + bar_h - 1), fill=(0, 0, 0, 160))
    d.rectangle((block1[0], bar_y, block1[0] + (block1[2] - block1[0]) * 0.61, bar_y + bar_h - 1),
                fill=(48, 84, 210, 255))
    compose_xpbar(canvas, (block1[0], bar_y, block1[2], bar_y + bar_h), sprites, marks)

    os.makedirs(OUT, exist_ok=True)
    out = canvas.resize((canvas.width * args.zoom, canvas.height * args.zoom), Image.NEAREST)
    out.convert("RGB").save(os.path.join(OUT, "preview_actionbar.png"))
    print(f"preview_actionbar.png  {out.size[0]}x{out.size[1]}  button={button} pad={pad} pitch={pitch} "
          f"cols={cols} rows={rows} zoom={args.zoom}")
    iw = icons1[0][2] - icons1[0][0]
    print(f"  icon {iw:.1f} px in a {pitch} px cell ({iw / pitch:.3f} of it) against a {button} px button "
          f"({'grows' if iw > button else 'shrinks'} by {abs(iw - button) / 2:.1f} px per side); "
          f"painted hole {(1 - 2 * L.actionbar_rules()['hole']) * pitch:.1f} px")
    print(f"  rail {L.actionbar_rules()['rail'] * pitch:.1f} px, seam gem "
          f"{L.actionbar_rules()['gem'] * pitch:.1f} px, corner gem {L.actionbar_rules()['cornerGem'] * pitch:.1f} px")
    return canvas, block1, block2


def render_overlay(canvas, block1, block2, args):
    """The painted target art, scaled so its own 145 px cell pitch matches the
    render's, drawn at 50% over the render: anything out of place shows as a
    doubled edge."""
    art = Image.open(os.path.join(DOCS, L.AB_ART)).convert("RGBA")
    s = (args.button + args.pad) / L.AB_CELL_PITCH
    art = art.resize((max(1, round(art.width * s)), max(1, round(art.height * s))), Image.LANCZOS)
    over = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    # line the art's own block top-left (AB_BLOCK) up with the render's
    ox = block1[0] - L.AB_BLOCK[0] * s
    oy = block1[1] - L.AB_BLOCK[1] * s
    over.alpha_composite(art, (int(round(ox)), int(round(oy))))
    faded = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    faded.paste(over, (0, 0), Image.eval(over.split()[3], lambda a: a // 2))
    shot = canvas.copy()
    shot.alpha_composite(faded)
    out = shot.resize((shot.width * args.zoom, shot.height * args.zoom), Image.NEAREST)
    out.convert("RGB").save(os.path.join(OUT, "preview_overlay.png"))
    print("preview_overlay.png    target art at 50% over the render "
          f"(art scaled x{s:.4f}; block2 top {block2[1]:.0f})")


# --------------------------------------------------------------------------
def render_castbar(args, width=208, height=11):
    """Modules/CastBarPanel.lua: one uniform scale from the status bar's width
    against the painted fill interior."""
    art = Image.open(os.path.join(TEX, "CastBarFrame.tga")).convert("RGBA")
    cw, ch = L.CB_CROP[2] - L.CB_CROP[0], L.CB_CROP[3] - L.CB_CROP[1]
    art = art.crop((0, 0, 2048, round(2048 * ch / cw)))
    fill = L.CB_FILL_BOX
    s = width / float(fill[2] - fill[0])
    aw, ah = round(cw * s), round(ch * s)
    skin = art.resize((aw, ah), Image.LANCZOS)

    pad = 30
    canvas = Image.new("RGBA", (aw + 2 * pad, ah + 2 * pad), BG)
    d = ImageDraw.Draw(canvas)
    # the game's status bar (fill + 50% black trough) under the painted frame
    bx0, by0 = pad + fill[0] * s, pad + fill[1] * s
    d.rectangle((bx0, by0, bx0 + width - 1, by0 + height - 1), fill=(0, 0, 0, 128))
    d.rectangle((bx0, by0, bx0 + width * 0.62, by0 + height - 1), fill=(60, 110, 220, 255))
    canvas.alpha_composite(skin, (pad, pad))
    os.makedirs(OUT, exist_ok=True)
    out = canvas.resize((canvas.width * args.zoom, canvas.height * args.zoom), Image.NEAREST)
    out.convert("RGB").save(os.path.join(OUT, "preview_castbar.png"))
    print(f"preview_castbar.png    status bar {width}x{height} -> skin {aw}x{ah} (scale {s:.4f}); "
          f"painted interior {(fill[3] - fill[1]) * s:.1f} px tall vs a {height} px bar")


def render_unitframe(args, width=232):
    """Modules/UnitFramePanel.lua: one uniform scale from the frame's width."""
    art = Image.open(os.path.join(TEX, "UnitFrame.tga")).convert("RGBA")
    aw, ah = L.UF_CROP[2] - L.UF_CROP[0], L.UF_CROP[3] - L.UF_CROP[1]
    art = art.crop((0, 0, 2048, round(2048 * ah / aw)))
    s = width / float(aw)
    skin = art.resize((round(aw * s), round(ah * s)), Image.LANCZOS)

    pad = 20
    canvas = Image.new("RGBA", (skin.width + 2 * pad, skin.height + 2 * pad), BG)
    d = ImageDraw.Draw(canvas)
    for box, colour in ((L.UF_HEALTH_BOX, (60, 190, 70, 255)), (L.UF_POWER_BOX, (60, 110, 220, 255))):
        x0, y0 = pad + box[0] * s, pad + box[1] * s
        x1, y1 = pad + box[2] * s, pad + box[3] * s
        d.rectangle((x0, y0, x1, y1), fill=(0, 0, 0, 128))
        d.rectangle((x0, y0, x0 + (x1 - x0) * 0.7, y1), fill=colour)
    # the portrait at its own (larger) radius, drawn BEFORE the skin so the
    # painted ring covers its rim -- the same order the module produces by
    # putting the portrait on a draw layer below the skin's art
    cx, cy = L.UF_RING[0], L.UF_RING[1]
    pr = L.UF_PORTRAIT_R
    d.ellipse((pad + (cx - pr) * s, pad + (cy - pr) * s, pad + (cx + pr) * s, pad + (cy + pr) * s),
              fill=(120, 100, 80, 255))
    canvas.alpha_composite(skin, (pad, pad))
    os.makedirs(OUT, exist_ok=True)
    out = canvas.resize((canvas.width * args.zoom, canvas.height * args.zoom), Image.NEAREST)
    out.convert("RGB").save(os.path.join(OUT, "preview_unitframe.png"))
    print(f"preview_unitframe.png  frame {width} wide -> skin {skin.width}x{skin.height} (scale {s:.4f}); "
          f"health bar {(L.UF_HEALTH_BOX[3] - L.UF_HEALTH_BOX[1]) * s:.1f} px tall")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--button", type=int, default=45, help="action button size (this client: 45)")
    p.add_argument("--pad", type=int, default=2, help="the bar's icon padding (Blizzard minimum: 2)")
    p.add_argument("--cols", type=int, default=12)
    p.add_argument("--rows", type=int, default=1, help="rows per bar (Edit Mode can stack a bar)")
    p.add_argument("--xp-height", type=int, default=10, help="the XP status bar's height (template: 10)")
    p.add_argument("--row-gap", type=float, default=2.0,
                   help="pixels Edit Mode leaves between the two rows' cell blocks "
                        "(above ~3x the rail the two rows stop sharing a divider)")
    p.add_argument("--castbar", type=int, nargs=2, default=(208, 11), metavar=("W", "H"))
    p.add_argument("--unitframe", type=int, default=232, help="PlayerFrame width")
    p.add_argument("--zoom", type=int, default=3)
    args = p.parse_args()

    sprites = load_sprites()
    canvas, block1, block2 = render_actionbar(args, sprites)
    render_overlay(canvas, block1, block2, args)
    render_castbar(args, *args.castbar)
    render_unitframe(args, args.unitframe)


if __name__ == "__main__":
    main()
