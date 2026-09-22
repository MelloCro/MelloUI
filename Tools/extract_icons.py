"""
Extract the painted class and faction medallions from docs/class-icons.webp and
docs/faction-icons.webp, crop each tightly, resize to 256 x 256, and write:

    Media/Icons/Class/<CLASSFILE>.tga   for every icon mapped to a class in
                                         Tools/class_icons.json (confirmed or not:
                                         the JSON is the single source of truth,
                                         re-run this script after editing it)
    Media/Icons/Class/unmapped_<n>.tga  for any icon left as class: null
    Media/Icons/Faction/Alliance.tga, Media/Icons/Faction/Horde.tga
    docs/class-icons-contact.png        numbered contact sheet with the proposed
                                         class under each icon, for the user to
                                         confirm or correct in class_icons.json
    Media/ClassIcons.lua                MelloUI_ClassIcons = { classes = {...},
                                         factions = {...} }, paths without an
                                         extension, only for classes actually
                                         mapped (never for unmapped_<n> icons)

class-icons.webp is a 4 x 4 grid (row 4 has one icon, 13 populated cells). The
medallions touch their neighbours through faint alpha bridges (decorative
flourishes at the rim), so a plain connected-components pass merges whole rows
and columns together; slicing the fixed grid and then tight-cropping each cell
to its own alpha bounding box avoids that.

    python Tools\\extract_icons.py
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
CLASS_SRC = os.path.join(ROOT, "docs", "class-icons.webp")
FACTION_SRC = os.path.join(ROOT, "docs", "faction-icons.webp")
MAPPING_PATH = os.path.join(HERE, "class_icons.json")
CLASS_OUT_DIR = os.path.join(ROOT, "Media", "Icons", "Class")
FACTION_OUT_DIR = os.path.join(ROOT, "Media", "Icons", "Faction")
CONTACT_OUT = os.path.join(ROOT, "docs", "class-icons-contact.png")
LUA_DATA_OUT = os.path.join(ROOT, "Media", "ClassIcons.lua")
LUA_PATH_PREFIX = "Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Icons"

CANVAS = 256
GRID_COLS, GRID_ROWS = 4, 4
ALPHA_THRESHOLD = 8


def tight_crop(im):
    """Crop im to the bounding box of its non-transparent pixels."""
    arr = np.asarray(im)
    alpha = arr[:, :, 3]
    ys, xs = np.nonzero(alpha > ALPHA_THRESHOLD)
    if len(xs) == 0:
        return None
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    return im.crop((x0, y0, x1, y1))


def to_canvas(im, size=CANVAS):
    """LANCZOS-resize im onto a square transparent canvas of side `size`,
    preserving aspect ratio and centering."""
    w, h = im.size
    scale = min(size / w, size / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    art = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(art, ((size - nw) // 2, (size - nh) // 2), art)
    return canvas


def circle_cut(im, x0, y0, x1, y1):
    """The medallion in a grid cell as its FULL circle plus the gem under it,
    taken from the whole sheet: the medallions overlap the grid lines (the
    bottom rows' rings run above their cell's top line), and a cell-bound
    crop cut those rings flat (the mage, the paladin and the rogue came out
    13-25 rows short — user, 2026-09-22: "mage one is cut off on the top").
    The circle is read off the cell: its diameter is the widest row of the
    cell's alpha, its centre that row; the crop is the circle's square from
    the sheet with the gem's rows under it; pixels outside the cell that are
    not inside the circle (a neighbour's gem) are cleared."""
    arr = np.asarray(im)
    alpha = arr[:, :, 3]
    cell = alpha[y0:y1, x0:x1]
    ys, xs = np.nonzero(cell > ALPHA_THRESHOLD)
    if len(xs) < 400:
        return None
    left, right = x0 + xs.min(), x0 + xs.max() + 1
    # the ring's diameter: the row widths, the few widest ones left out
    # (those are the rows of the two side gems, which stand ~10 px past the
    # ring and made the circle too big: a neighbour's gem stayed in); the
    # centre line is the widest row
    widths = []
    best_w, best_y = 0, None
    for yy in range(ys.min(), ys.max() + 1):
        row = np.nonzero(cell[yy] > ALPHA_THRESHOLD)[0]
        if len(row):
            w = row.max() - row.min() + 1
            widths.append(w)
            if w > best_w:
                best_w, best_y = w, y0 + yy
    widths.sort(reverse=True)
    diameter = widths[min(len(widths) - 1, int(len(widths) * 0.12))]
    radius = diameter / 2.0
    cx, cy = (left + right) / 2.0, best_y
    top = int(round(cy - radius))
    gem = radius * 0.16                 # the bottom gem stands this far under the ring
    bottom = int(round(cy + radius + gem))
    top = max(0, top)
    bottom = min(im.size[1], bottom)
    crop = im.crop((left, top, right, bottom)).copy()
    # outside the cell, keep the circle only
    px = np.asarray(crop).copy()
    hh, ww = px.shape[0], px.shape[1]
    yy, xx = np.mgrid[0:hh, 0:ww]
    sheet_y = yy + top
    sheet_x = xx + left
    dist = np.sqrt((sheet_x - cx) ** 2 + (sheet_y - cy) ** 2)
    # outside the circle only our own gems stand: the two at the sides (on
    # the centre line) and the one under the ring (on the centre column,
    # taken from the next cell); anything else outside it is a neighbour's
    # (the medallion above reaches down into this cell with its gem, the
    # one below reaches up with its ring) and goes
    outside = dist > radius + 1
    side_gem = (np.abs(sheet_y - cy) < radius * 0.14) & (np.abs(sheet_x - cx) < radius + gem)
    # the bottom gem: a diamond under the ring, 0.34 r wide at the ring
    # tapering to its tip `gem` below it (measured on the mage, the one
    # medallion with nothing under it); the medallion below reaches up
    # into that triangle with its bronze ring, which is neither red nor
    # dark, so a colour test tells the two apart
    below = sheet_y - (cy + radius)
    t = np.clip(below / gem, 0, 1)
    tri = (below > -2) & (below <= gem) & (np.abs(sheet_x - cx) < radius * 0.34 * (1 - t) + 3)
    r_, g_, b_ = px[:, :, 0].astype(int), px[:, :, 1].astype(int), px[:, :, 2].astype(int)
    gem_like = (r_ > g_ + b_ // 2) | (r_ + g_ + b_ < 150)
    bottom_gem = tri & gem_like
    px[(outside & ~side_gem & ~bottom_gem), 3] = 0
    # the medallion above is PAINTED OVER our ring's top in the sheet (its
    # gem's tip): those ring pixels are gone. The ring's texture is even,
    # so the patch (the gem's column over the ring band) is rebuilt from
    # the ring 45 degrees round, where nothing intrudes.
    band = (dist > radius * 0.84) & (dist <= radius + 1)
    patch = band & (np.abs(sheet_x - cx) < radius * 0.32) & (sheet_y < cy - radius * 0.5)
    ang = np.deg2rad(45.0)
    rel_x, rel_y = sheet_x - cx, sheet_y - cy
    src_x = cx + rel_x * np.cos(ang) - rel_y * np.sin(ang)
    src_y = cy + rel_x * np.sin(ang) + rel_y * np.cos(ang)
    sx = np.clip(np.round(src_x - left).astype(int), 0, ww - 1)
    sy = np.clip(np.round(src_y - top).astype(int), 0, hh - 1)
    px[patch] = px[sy[patch], sx[patch]]
    return Image.fromarray(px, "RGBA")


def slice_class_grid(src_path):
    """Return the 13 populated grid cells of class-icons.webp as full
    medallions, in reading order (row by row, left to right), 1-indexed."""
    im = Image.open(src_path).convert("RGBA")
    W, H = im.size
    cell_w, cell_h = W / GRID_COLS, H / GRID_ROWS
    icons = {}
    n = 0
    for r in range(GRID_ROWS):
        for c in range(GRID_COLS):
            x0, x1 = int(round(c * cell_w)), int(round((c + 1) * cell_w))
            y0, y1 = int(round(r * cell_h)), int(round((r + 1) * cell_h))
            cropped = circle_cut(im, x0, y0, x1, y1)
            if cropped is None or cropped.size[0] < 20 or cropped.size[1] < 20:
                continue
            n += 1
            icons[n] = cropped
    return icons


def slice_faction_halves(src_path):
    """Left half = Alliance, right half = Horde (per the art description)."""
    im = Image.open(src_path).convert("RGBA")
    w, h = im.size
    mid = w // 2
    left = tight_crop(im.crop((0, 0, mid, h)))
    right = tight_crop(im.crop((mid, 0, w, h)))
    return left, right


def checker_bg(size, c1=(58, 58, 58, 255), c2=(84, 84, 84, 255), n=10):
    w, h = size
    step = max(1, min(w, h) // n)
    bg = Image.new("RGBA", size, c1)
    px = bg.load()
    for y in range(h):
        for x in range(w):
            if (x // step + y // step) % 2:
                px[x, y] = c2
    return bg


def main():
    with open(MAPPING_PATH, "r", encoding="utf-8") as f:
        mapping = json.load(f)

    os.makedirs(CLASS_OUT_DIR, exist_ok=True)
    os.makedirs(FACTION_OUT_DIR, exist_ok=True)

    # ---- class icons ----
    icons = slice_class_grid(CLASS_SRC)
    entries = mapping["class_icons"]
    if len(icons) != len(entries):
        print(f"WARNING: sliced {len(icons)} icon cells but class_icons.json has "
              f"{len(entries)} entries; numbering may be out of sync.")

    contact_tiles = []  # (number, class_or_None, confirmed, image)
    for num_str, entry in sorted(entries.items(), key=lambda kv: int(kv[0])):
        num = int(num_str)
        cropped = icons.get(num)
        if cropped is None:
            print(f"WARNING: no art found for icon {num} ({entry.get('label')})")
            continue
        final = to_canvas(cropped)
        class_file = entry.get("class")
        if class_file:
            out_path = os.path.join(CLASS_OUT_DIR, f"{class_file}.tga")
        else:
            out_path = os.path.join(CLASS_OUT_DIR, f"unmapped_{num}.tga")
        final.save(out_path)
        print(f"icon {num:2d}: {entry.get('label'):<55} -> {os.path.relpath(out_path, ROOT)}"
              f"{'' if entry.get('confirmed') else '  (unconfirmed)'}")
        contact_tiles.append((num, class_file, bool(entry.get("confirmed")), final))

    # ---- faction icons ----
    left, right = slice_faction_halves(FACTION_SRC)
    alliance = to_canvas(left)
    horde = to_canvas(right)
    alliance.save(os.path.join(FACTION_OUT_DIR, "Alliance.tga"))
    horde.save(os.path.join(FACTION_OUT_DIR, "Horde.tga"))
    print(f"faction: Alliance -> {os.path.relpath(os.path.join(FACTION_OUT_DIR, 'Alliance.tga'), ROOT)}")
    print(f"faction: Horde -> {os.path.relpath(os.path.join(FACTION_OUT_DIR, 'Horde.tga'), ROOT)}")

    # ---- contact sheet ----
    try:
        font = ImageFont.truetype("arial.ttf", 22)
        font_small = ImageFont.truetype("arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default(size=22)
        font_small = ImageFont.load_default(size=16)

    cols = 5
    rows = (len(contact_tiles) + cols - 1) // cols
    tile = CANVAS + 20
    label_h = 56
    sheet = Image.new("RGBA", (cols * tile, rows * (tile + label_h)), (30, 30, 30, 255))
    draw = ImageDraw.Draw(sheet)
    for i, (num, class_file, confirmed, img) in enumerate(contact_tiles):
        cx = (i % cols) * tile
        cy = (i // cols) * (tile + label_h)
        bg = checker_bg((CANVAS, CANVAS))
        bg.alpha_composite(img)
        sheet.paste(bg, (cx + 10, cy + 10))
        label = f"{num}. {class_file or '(unmapped)'}"
        if not confirmed:
            label += " ?"
        colour = (255, 255, 255, 255) if confirmed else (255, 210, 90, 255)
        draw.text((cx + 12, cy + CANVAS + 14), label, fill=colour, font=font)
    sheet = sheet.convert("RGB")
    sheet.save(CONTACT_OUT)
    print(f"contact sheet -> {os.path.relpath(CONTACT_OUT, ROOT)}")

    # ---- Media/ClassIcons.lua ----
    mapped_classes = sorted(
        (e["class"] for e in entries.values() if e.get("class")),
    )
    lines = []
    lines.append("-- Generated by Tools/extract_icons.py from Tools/class_icons.json and")
    lines.append("-- docs/class-icons.webp / docs/faction-icons.webp. Do not edit by hand:")
    lines.append("-- correct a mapping in Tools/class_icons.json and re-run the script.")
    lines.append("")
    lines.append("MelloUI_ClassIcons = {")
    lines.append("\tclasses = {")
    for class_file in mapped_classes:
        lines.append(f'\t\t{class_file} = "{LUA_PATH_PREFIX}\\\\Class\\\\{class_file}",')
    lines.append("\t},")
    lines.append("\tfactions = {")
    for key in ("Alliance", "Horde"):
        lines.append(f'\t\t{key} = "{LUA_PATH_PREFIX}\\\\Faction\\\\{key}",')
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    with open(LUA_DATA_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"data file -> {os.path.relpath(LUA_DATA_OUT, ROOT)}")


if __name__ == "__main__":
    main()
