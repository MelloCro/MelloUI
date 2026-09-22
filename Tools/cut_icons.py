"""
cut_icons.py -- the round profession icons for the professions window's
portrait (62 px in the game): icons/profession_<name> and icons/professions
(the crossed pick and hammer for the book page).

  4ea91585  a grid of round icons on transparency, row-major
  4f78b4a9  one big round icon (pick and hammer)

Each icon is cut as an alpha island, squared on its centre and resized to
192 px (the kit's 2x convention: build_kit stores it at 0.5, 96 px, for the
62 px portrait). Writes kit/v2_2x/icons/ and the manifest.
"""
import os, glob, json
import numpy as np
from PIL import Image

SRC = r"C:\Users\mortu\Downloads\UITest"
KIT = os.path.join(SRC, "kit", "v2_2x")
SIZE = 192
GRID = ["alchemy", "herbalism", "blacksmithing",
        "mining", "enchanting", "skinning",
        "engineering", "archaeology", "inscription",
        "jewelcrafting", "firstaid", "cooking",
        "leatherworking", "tailoring", "fishing", "fishing_rod"]


def runs(mask, min_gap=3, min_len=60):
    """(start, end) runs of True, ignoring gaps shorter than min_gap"""
    out = []
    i = 0
    n = len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n:
                if mask[j]:
                    j += 1
                else:
                    k = j
                    while k < n and not mask[k]:
                        k += 1
                    if k - j < min_gap and k < n:
                        j = k
                    else:
                        break
            if j - i >= min_len:
                out.append((i, j))
            i = j
        else:
            i += 1
    return out


def islands(alpha, thresh=160, layout=((4, 3), (1, 4))):
    """the icons' boxes: the sheet's row bands (rows of touching icons merge
    into one band), each band split evenly into its rows and columns per
    `layout` ((rows, columns) per band, top to bottom)"""
    solid = alpha > thresh
    boxes = []
    bands = runs(solid.any(axis=1))
    for (y0, y1), (nrows, ncols) in zip(bands, layout):
        band = solid[y0:y1]
        xs = np.where(band.any(axis=0))[0]
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        rh, cw = (y1 - y0) / nrows, (x1 - x0) / ncols
        for r in range(nrows):
            for c in range(ncols):
                boxes.append((round(x0 + c * cw), round(y0 + r * rh), round(x0 + (c + 1) * cw), round(y0 + (r + 1) * rh)))
    return boxes


def icon_circle(alpha, box, erode=8, thresh=200):
    """the icon's own circle inside its grid cell: the opaque blob under the
    cell's centre after eroding the mask (so touching neighbours' rims fall
    away), grown back by the erosion; returns (cx, cy, radius) in sheet px"""
    from collections import deque
    from scipy.ndimage import minimum_filter
    x0, y0, x1, y1 = box
    cell = alpha[y0:y1, x0:x1] > thresh
    er = minimum_filter(cell, size=2 * erode + 1)
    h, w = er.shape
    sy, sx = h // 2, w // 2
    if not er[sy, sx]:
        ys, xs = np.where(er)
        k = np.argmin((ys - sy) ** 2 + (xs - sx) ** 2)
        sy, sx = int(ys[k]), int(xs[k])
    seen = np.zeros_like(er); q = deque([(sy, sx)]); seen[sy, sx] = True
    bx0 = bx1 = sx; by0 = by1 = sy
    while q:
        cy, cx = q.popleft()
        bx0, bx1, by0, by1 = min(bx0, cx), max(bx1, cx), min(by0, cy), max(by1, cy)
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and er[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; q.append((ny, nx))
    bx0, bx1, by0, by1 = bx0 - erode, bx1 + erode, by0 - erode, by1 + erode
    cx, cy = x0 + (bx0 + bx1) / 2, y0 + (by0 + by1) / 2
    r = max(bx1 - bx0, by1 - by0) / 2
    return cx, cy, r


def square(im, box):
    """the icon's circle (found inside its cell) squared on ITS centre,
    resized so every icon fills the same 192 px disc, clipped to the disc"""
    cx, cy, r = icon_circle(np.array(im)[..., 3], box)
    pad = r * 0.02
    out = im.crop((round(cx - r - pad), round(cy - r - pad), round(cx + r + pad), round(cy + r + pad))).resize((SIZE, SIZE), Image.LANCZOS)
    a = np.array(out).astype(float)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    radius = r / (r + pad) * SIZE / 2
    d = np.hypot(xx - (SIZE - 1) / 2, yy - (SIZE - 1) / 2)
    a[..., 3] *= np.clip(radius + 1 - d, 0, 1)
    return Image.fromarray(a.astype(np.uint8))


def main():
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))
    os.makedirs(os.path.join(KIT, "icons"), exist_ok=True)

    im = Image.open(glob.glob(os.path.join(SRC, "4ea91585*.png"))[0]).convert("RGBA")
    boxes = islands(np.array(im)[..., 3])
    print(len(boxes), "icons found")
    for name, box in zip(GRID, boxes):
        out = square(im, box)
        out.save(os.path.join(KIT, "icons", f"profession_{name}.png"))
        man[f"v2_2x/icons/profession_{name}"] = { "w": SIZE, "h": SIZE, "scale": 1.0, "src": f"4ea91585 {box}" }
        print(f"icons/profession_{name}: {box}")

    im = Image.open(glob.glob(os.path.join(SRC, "4f78b4a9*.png"))[0]).convert("RGBA")
    box = islands(np.array(im)[..., 3], layout=((1, 1),))[0]
    out = square(im, box)
    out.save(os.path.join(KIT, "icons", "professions.png"))
    man["v2_2x/icons/professions"] = { "w": SIZE, "h": SIZE, "scale": 1.0, "src": f"4f78b4a9 {box}" }
    print("icons/professions:", box)
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)
    # preview at the game's size: the 62 px portrait inside the 95 px ring
    ring = Image.open(os.path.join(KIT, "window", "portrait_ring.png")).convert("RGBA").resize((95, 95), Image.LANCZOS)
    names = sorted(n for n in os.listdir(os.path.join(KIT, "icons")))
    sheet = Image.new("RGBA", (len(names) * 105, 110), (60, 60, 60, 255))
    for i, n in enumerate(names):
        ic = Image.open(os.path.join(KIT, "icons", n)).convert("RGBA").resize((62, 62), Image.LANCZOS)
        x = i * 105 + 5
        sheet.alpha_composite(ic, (x + (95 - 62) // 2, 7 + (95 - 62) // 2))
        sheet.alpha_composite(ring, (x, 7))
    sheet.save(os.path.join(SRC, "kit_raw", "icons_in_ring.png"))


if __name__ == "__main__":
    main()
