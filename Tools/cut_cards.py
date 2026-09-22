"""
cut_cards.py -- the profession pictures for the professions window's cards.

  cards/<profession>          wide banner (still-life at the right on stone),
                              for the primary profession cards (664 x 142)
  backdrops/profession_<p>    tall colour panel (the same subject), for a
                              tall area (the crafting page's schematic)

Sheets (ids = the first 8 chars of ChatGPT's file names):
  6d785f85  2 x 4 grid of wide banners on black, row-major
  e16eb841  one wide banner (mining), no gaps
  841a7d25  3 x 3 grid of tall colour panels with thin light seams
  3d259005  three tall strips (cooking, fishing, first aid) for the schematic:
            the band with the most colour at the schematic's aspect is kept
Panels keep their native size (build_kit pads to a power of two and records
the uv); the picture kind crops them to the card's aspect in the client.
"""
import os, glob, json
import numpy as np
from PIL import Image

SRC = r"C:\Users\mortu\Downloads\UITest"
KIT = os.path.join(SRC, "kit", "v2_2x")

WIDE = ["alchemy", "blacksmithing", "enchanting", "engineering", "herbalism", "leatherworking", "skinning", "tailoring"]
TALL = ["blacksmithing", "alchemy", "mining", "enchanting", "engineering", "herbalism", "leatherworking", "skinning", "tailoring"]
SECONDARY_TALL = ["cooking", "fishing", "firstaid"]      # 3d259005: three tall strips, the objects in the lower half
SCHEMATIC_ASPECT = 360 / 484                                # the schematic form's rect


def sheet(sid):
    files = glob.glob(os.path.join(SRC, sid + "*.png"))
    return Image.open(files[0]).convert("RGBA") if files else None


def runs(mask):
    """(start, end) runs of True in a 1-D mask."""
    out = []
    for i, v in enumerate(mask):
        if v and out and out[-1][1] == i:
            out[-1][1] = i + 1
        elif v:
            out.append([i, i + 1])
    return out


def islands(a, thresh=12, min_size=100):
    """rows and columns of a sheet whose panels sit on near-black: the panel
    bands are the runs of not-dark lines."""
    lum = a[..., :3].mean(axis=2)
    rows = runs(lum.mean(axis=1) > thresh)
    cols = runs(lum.mean(axis=0) > thresh)
    return [r for r in rows if r[1] - r[0] >= min_size], [c for c in cols if c[1] - c[0] >= min_size]


def save(im, name, man, src):
    out = os.path.join(KIT, name + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out)
    man[f"v2_2x/{name}"] = { "w": im.width, "h": im.height, "scale": 1.0, "src": src }
    print(f"{name}: {im.width}x{im.height}  ({src})")


def main():
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))

    im = sheet("6d785f85")
    a = np.array(im)
    rows, cols = islands(a)
    assert len(rows) == 4 and len(cols) == 2, (rows, cols)
    i = 0
    for r in rows:
        for c in cols:
            save(im.crop((c[0], r[0], c[1], r[1])), "cards/" + WIDE[i], man, f"6d785f85 {c[0]}-{c[1]} x {r[0]}-{r[1]}")
            i += 1

    im = sheet("e16eb841")
    # the mining banner was painted taller than the others (2046 x 768): the
    # band with the same aspect as the grid's banners, keeping the pick's head
    band = round(im.width * 215 / 804)
    y0 = 100
    mining = im.crop((0, y0, im.width, y0 + band))
    mining = mining.resize((1024, round(band * 1024 / im.width)), Image.LANCZOS)   # the others are ~804 wide: no need for 2046
    save(mining, "cards/mining", man, f"e16eb841 rows {y0}-{y0 + band}, resized")

    im = sheet("841a7d25")
    W, H = im.size
    inset = 5                                  # the seam lines between the panels
    i = 0
    for ry in range(3):
        for cx in range(3):
            x0, x1 = round(cx * W / 3) + inset, round((cx + 1) * W / 3) - inset
            y0, y1 = round(ry * H / 3) + inset, round((ry + 1) * H / 3) - inset
            save(im.crop((x0, y0, x1, y1)), "backdrops/profession_" + TALL[i], man, f"841a7d25 cell {cx},{ry}")
            i += 1
    # the secondary professions' schematic panels: three 362 x 1448 strips;
    # the band with the most colour (the still-life) at the schematic's aspect
    im = sheet("3d259005")
    if im is not None:
        W, H = im.size
        inset = 4
        for i, name in enumerate(SECONDARY_TALL):
            x0, x1 = round(i * W / 3) + inset, round((i + 1) * W / 3) - inset
            strip = im.crop((x0, 0, x1, H))
            a = np.array(strip.convert("RGB")).astype(float)
            sat = (a.max(axis=2) - a.min(axis=2)).mean(axis=1)          # colour per row: stone is grey, the objects are not
            band = round((x1 - x0) / SCHEMATIC_ASPECT)
            best = max(range(0, H - band + 1, 4), key=lambda y: sat[y:y + band].sum())
            save(strip.crop((0, best, x1 - x0, best + band)), "backdrops/schematic_" + name, man, f"3d259005 strip {i}, rows {best}-{best + band}")
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
