"""
Build Media/Textures/BackpackFrame.tga (a 2048 x 1024 atlas) from the
1484 x 1060 painting docs/backpack-frame.webp, and write Media/BackpackLayout.lua
with every number Modules/BackpackPanel.lua needs. The numbers live in
Tools/backpack_layout_data.py; Tools/preview_backpack.py composes the window
from the same atlas and numbers for a local check.

Pieces (all at the painting's own resolution, nothing downscaled):
  TOP     the ring, title bar, search bar and sort button (fixed height)
  BAND    one row of slots' worth of rails with plain stone between (repeats per row)
  BOTTOM  the money bar, bottom rail and corner gems (fixed height)
  SLOT    one carved slot with its rune rim and corner gems (laid once per item slot)
  RUNES   the rune text of the art's top row (shown in the top row's free cells)
  GOLD    the gold-edged bag box (the bag column's hover glow)

The painting was made from a full bag: the title and the money numbers are
painted out with plain bar; the slot sprite is cut from the one empty slot;
the bag-box row under the frame is dropped (the bag column has its own sheet).

    python Tools\\make_backpack_frame.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import backpack_layout_data as D
from paths import OUTPUT
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "backpack-frame.webp")
OUT_TGA = master("Textures", "BackpackFrame.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
OUT_LUA = os.path.join(HERE, "..", "Media", "BackpackLayout.lua")
OUT_DIR = OUTPUT


def feathered_paste(img, patch, box, feather=4):
    w, h = patch.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, w - feather - 1, h - feather - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    img.paste(patch, box, mask)


def tile(img, src_box, dst_box):
    """Repeat a plain strip (scaled to the destination's height) across a box."""
    w, h = dst_box[2] - dst_box[0], dst_box[3] - dst_box[1]
    src = img.crop(src_box)
    src = src.resize((max(1, round(src.size[0] * h / src.size[1])), h))
    strip = Image.new("RGBA", (w, h))
    x = 0
    while x < w:
        strip.paste(src, (x, 0))
        x += src.size[0]
    feathered_paste(img, strip, (dst_box[0], dst_box[1]))


def mirror_tile_vertical(strip, height):
    """Stack a strip, flipping every other copy, so the joins are seamless."""
    w, h = strip.size
    out = Image.new("RGBA", (w, height))
    y, flip = 0, False
    while y < height:
        piece = strip.transpose(Image.FLIP_TOP_BOTTOM) if flip else strip
        out.paste(piece, (0, y))
        y += h
        flip = not flip
    return out


def feather_alpha(img, feather):
    """Fade the outer `feather` px of an RGBA image to transparent."""
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((feather, feather, w - feather - 1, h - feather - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    arr = np.array(img).astype(np.float32)
    arr[..., 3] *= np.array(mask, dtype=np.float32) / 255.0
    return Image.fromarray(arr.astype(np.uint8))


def main():
    art = Image.open(SRC).convert("RGBA")
    assert art.size == (D.ART_W, 1060), art.size

    # the picture's own text goes: the game draws the title and the money
    tile(art, D.TITLE_PLAIN, D.TITLE_TEXT)
    tile(art, D.MONEY_PLAIN, D.MONEY_TEXT)

    # the gold box sprite comes from the bag row before that row is dropped
    gold = art.crop(D.GOLD_BOX)

    # drop the bag boxes under the frame: everything below the bottom rail
    # except the two corner rings, which reach a little lower
    px = art.load()
    for y in range(913, art.size[1]):
        for x in range(art.size[0]):
            keep = False
            for cx, cy in D.CORNER_GEMS:
                if (x - cx) ** 2 + (y - cy) ** 2 <= D.CORNER_R ** 2:
                    keep = True
                    break
            if not keep:
                px[x, y] = (0, 0, 0, 0)

    # --- pieces ---------------------------------------------------------------
    top = art.crop((0, 0, D.ART_W, D.TOP_H))
    bottom = art.crop((0, D.BOTTOM_START, D.ART_W, D.ART_FRAME_H))

    band = art.crop((0, D.BAND_REF_Y, D.ART_W, D.BAND_REF_Y + D.ROW_PITCH))
    stone = art.crop(D.STONE_STRIP)
    interior = mirror_tile_vertical(stone, D.ROW_PITCH)
    band.paste(interior, (D.STONE_STRIP[0], 0))

    sx, sy = D.SLOT_REF
    m = D.SLOT_MARGIN
    slot = art.crop((sx - m, sy - m, sx + D.SLOT_W + m, sy + D.SLOT_H + m))
    slot = feather_alpha(slot, m - 2)

    runes = art.crop(D.RUNES)
    runes = feather_alpha(runes, 10)

    # --- the atlas ------------------------------------------------------------
    atlas = Image.new("RGBA", (D.ATLAS_W, D.ATLAS_H), (0, 0, 0, 0))
    pieces = {"TOP": top, "BAND": band, "BOTTOM": bottom, "SLOT": slot, "RUNES": runes, "GOLD": gold}
    rects = {}
    for name, im in pieces.items():
        x, y = D.ATLAS[name]
        assert x + im.size[0] <= D.ATLAS_W and y + im.size[1] <= D.ATLAS_H, (name, im.size)
        atlas.paste(im, (x, y))
        rects[name] = (x, y, x + im.size[0], y + im.size[1])
    # no two pieces may overlap
    names = list(rects)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            ra, rb = rects[a], rects[b]
            assert ra[2] <= rb[0] or rb[2] <= ra[0] or ra[3] <= rb[1] or rb[3] <= ra[1], (a, b)
    atlas.save(OUT_TGA)

    # --- the Lua table --------------------------------------------------------
    def box(t):
        return "{ %s }" % ", ".join("%g" % v for v in t)

    lines = [
        "-- Generated by Tools/make_backpack_frame.py from docs/backpack-frame.webp.",
        "-- Do not edit by hand: change Tools/backpack_layout_data.py and re-run the",
        "-- script (Tools/preview_backpack.py renders the same numbers locally).",
        "--",
        "-- Every number is in art pixels of the 1484 x 1060 painting; rects are",
        "-- { x0, y0, x1, y1 } and atlas rects are pixels of the 2048 x 1024 texture.",
        "",
        "MelloUI_BackpackLayout = {",
        '\ttexture = "Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Textures\\\\BackpackFrame",',
        "\tatlasW = %d, atlasH = %d," % (D.ATLAS_W, D.ATLAS_H),
        "\tartW = %d, topH = %d, rowPitch = %d, bottomH = %d," % (D.ART_W, D.TOP_H, D.ROW_PITCH, D.BOTTOM_H),
        "\tcapLeft = %d, capRight = %d, bandRailL = %d, bandRailR = %d," % (D.CAP_LEFT, D.CAP_RIGHT, D.BAND_RAIL_L, D.BAND_RAIL_R),
        "\tcolumns = %d," % D.COLUMNS,
        "\tslot = { x0 = %g, y0 = %g, pitchX = %g, w = %g, h = %g, margin = %g, inset = %g }," % (
            D.SLOT_X0, D.SLOT_Y0, D.SLOT_PITCH_X, D.SLOT_W, D.SLOT_H, D.SLOT_MARGIN, D.SLOT_INSET),
        "\trunes = { x = %g, y = %g, w = %g, h = %g, minEmpty = %d }," % (
            D.RUNES[0], D.RUNES[1] - D.TOP_H, D.RUNES[2] - D.RUNES[0], D.RUNES[3] - D.RUNES[1], D.RUNES_MIN_EMPTY),
        "\tatlas = {",
    ]
    for name in ("TOP", "BAND", "BOTTOM", "SLOT", "RUNES", "GOLD"):
        lines.append("\t\t%s = %s," % (name, box(rects[name])))
    lines += [
        "\t},",
        "\tboxes = {",
        "\t\tRING = %s," % box(D.RING),
        "\t\tTITLE = %s," % box(D.TITLE),
        "\t\tCROSS = %s," % box(D.CROSS),
        "\t\tSEARCH = %s," % box(D.SEARCH),
        "\t\tSORT = %s," % box(D.SORT),
        "\t\tMONEY = %s,   -- relative to the BOTTOM piece's top" % box(D.MONEY),
        "\t},",
        "}",
        "",
    ]
    with open(OUT_LUA, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    # --- preview over green: nothing painted may hide -------------------------
    os.makedirs(OUT_DIR, exist_ok=True)
    bg = Image.new("RGBA", atlas.size, (0, 140, 0, 255))
    bg.alpha_composite(atlas)
    bg.crop((0, 0, D.ART_W, D.ATLAS["SLOT"][1] + 160)).convert("RGB").save(os.path.join(OUT_DIR, "backpackframe-atlas.png"))

    for name, r in rects.items():
        print("  %-7s atlas px %s  (%d x %d)" % (name, r, r[2] - r[0], r[3] - r[1]))
    print("-> %s\n-> %s\n   preview MelloUI-BuildData/output/backpackframe-atlas.png" % (OUT_TGA, OUT_LUA))


if __name__ == "__main__":
    main()
