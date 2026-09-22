"""
Compose the painted backpack window locally, from the same atlas and numbers
Modules/BackpackPanel.lua uses (Media/Textures/BackpackFrame.tga and
Tools/backpack_layout_data.py), for any slot count and column count:

    python Tools\\preview_backpack.py --slots 36
    python Tools\\preview_backpack.py --slots 46 --columns 10

Writes Tools/output/backpack-preview-<slots>.png (over a green background, at
the art's own resolution) with the game's item buttons drawn as translucent
boxes numbered in the game's order (1 = bottom right), the controls' boxes
outlined, so the composed frame can be checked against docs/backpack-frame.webp.
"""
import argparse
import math
import os

from PIL import Image, ImageDraw

import backpack_layout_data as D

HERE = os.path.dirname(os.path.abspath(__file__))
TGA = os.path.join(HERE, "..", "Media", "Textures", "BackpackFrame.tga")
OUT = os.path.join(HERE, "output")


def piece(atlas, name):
    x, y = D.ATLAS[name]
    sizes = {
        "TOP": (D.ART_W, D.TOP_H),
        "BAND": (D.ART_W, D.ROW_PITCH),
        "BOTTOM": (D.ART_W, D.BOTTOM_H),
        "SLOT": D.slot_sprite_size(),
        "RUNES": (D.RUNES[2] - D.RUNES[0], D.RUNES[3] - D.RUNES[1]),
    }
    w, h = sizes[name]
    return atlas.crop((x, y, x + w, y + h))


def stretch_h(im, width):
    """Left cap, stretched middle, right cap: the same split the module uses."""
    if width == im.size[0]:
        return im
    left = im.crop((0, 0, D.CAP_LEFT, im.size[1]))
    right = im.crop((D.CAP_RIGHT, 0, im.size[0], im.size[1]))
    mid_w = int(round(width - left.size[0] - right.size[0]))
    mid = im.crop((D.CAP_LEFT, 0, D.CAP_RIGHT, im.size[1])).resize((max(1, mid_w), im.size[1]))
    out = Image.new("RGBA", (int(round(width)), im.size[1]))
    out.paste(left, (0, 0))
    out.paste(mid, (left.size[0], 0))
    out.paste(right, (left.size[0] + mid.size[0], 0))
    return out


def compose(slots, columns, flip_bands=True):
    atlas = Image.open(TGA).convert("RGBA")
    rows = max(1, math.ceil(slots / columns))
    width = int(round(D.art_width(columns)))
    height = D.art_height(rows)
    frame = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    frame.alpha_composite(stretch_h(piece(atlas, "TOP"), width), (0, 0))
    band = stretch_h(piece(atlas, "BAND"), width)
    for r in range(rows):
        b = band.transpose(Image.FLIP_TOP_BOTTOM) if (flip_bands and r % 2) else band
        frame.alpha_composite(b, (0, D.TOP_H + r * D.ROW_PITCH))
    frame.alpha_composite(stretch_h(piece(atlas, "BOTTOM"), width), (0, height - D.BOTTOM_H))

    slot = piece(atlas, "SLOT")
    used = set()
    cells = {}
    for i in range(1, slots + 1):
        r, c = D.cell_of(i, slots, columns)
        cells[i] = (r, c)
        used.add((r, c))
        x0, y0, _, _ = D.rim_box(r, c)
        frame.alpha_composite(slot, (int(round(x0 - D.SLOT_MARGIN)), int(round(y0 - D.SLOT_MARGIN))))

    free_top = columns - (slots % columns) if slots % columns else 0
    if free_top >= D.RUNES_MIN_EMPTY:
        runes = piece(atlas, "RUNES")
        frame.alpha_composite(runes, (D.RUNES[0], D.TOP_H + (D.RUNES[1] - D.TOP_H)))

    # over green, then the game's boxes
    out = Image.new("RGBA", (width + 40, height + 40), (0, 140, 0, 255))
    out.alpha_composite(frame, (20, 20))
    overlay = Image.new("RGBA", out.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for i, (r, c) in cells.items():
        x0, y0, x1, y1 = D.rim_box(r, c)
        k = D.SLOT_INSET
        box = (20 + x0 + k, 20 + y0 + k, 20 + x1 - k, 20 + y1 - k)
        draw.rectangle(box, outline=(255, 255, 0, 200), fill=(255, 255, 0, 40))
        draw.text((box[0] + 6, box[1] + 4), str(i), fill=(255, 255, 255, 255))
    for name, b in (("RING", D.RING), ("TITLE", D.TITLE), ("CROSS", D.CROSS), ("SEARCH", D.SEARCH), ("SORT", D.SORT)):
        draw.rectangle((20 + b[0], 20 + b[1], 20 + b[2], 20 + b[3]), outline=(0, 255, 255, 220))
        draw.text((22 + b[0], 22 + b[1]), name, fill=(0, 255, 255, 255))
    m = D.MONEY
    by = height - D.BOTTOM_H
    draw.rectangle((20 + m[0], 20 + by + m[1], 20 + m[2], 20 + by + m[3]), outline=(0, 255, 255, 220))
    draw.text((22 + m[0], 22 + by + m[1]), "MONEY", fill=(0, 255, 255, 255))
    out.alpha_composite(overlay)
    return out, rows, width, height


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--slots", type=int, default=36)
    ap.add_argument("--columns", type=int, default=D.COLUMNS)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    out, rows, width, height = compose(args.slots, args.columns)
    path = os.path.join(OUT, "backpack-preview-%d.png" % args.slots)
    out.convert("RGB").save(path)
    print("%d slots in %d x %d cells -> %d x %d art px -> %s" % (args.slots, args.columns, rows, width, height, path))


if __name__ == "__main__":
    main()
