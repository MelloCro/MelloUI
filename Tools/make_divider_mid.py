"""
make_divider_mid.py -- the divider line's middle (window/divider_mid) and its right cap's stub repainted from its
left cap's own stub, so the line runs on unbroken where the caps meet it (0.20.1; the user, 2026-10-10: "this
separation line ... its kinda messy and not properly aligned ... the messiness is mostly recognizabe in the Spells
Window").

The caps and the middle were painted as separate plates: the middle in one look (heavier black edges, a darker slate),
each cap's stub in another (light bevels round a fine groove), the right cap's a pixel lower than the left's -- a
visible joint at each end, the larger the line is drawn. Now one rail runs through: the left cap's stub (each row the
median of its plain columns, past the gem's collar) is the middle, repeated, and the right cap's plain stub, faded
into that cap's collar over a few columns. The gems and their collars stay as painted.

Writes the 2x sources (Tools/pack_sources/kit/v2_2x/window/divider_mid.png and divider_cap_r.png, the old ones kept
beside them as *.pre_joints.png), their masters as build_kit.py writes them (masters/Media/Kit/window/*.tga), and the
master KitLayout.lua's entries (the middle's box: the stub's opaque rows). Idempotent: made from the left cap and the
kept originals, never from its own output.

Run:  python Tools/make_divider_mid.py --check   builds nothing: rebuilds TODAY's masters from today's sources the
                                                 way this tool writes them and says whether the bytes match (exit 1
                                                 if not)
      python Tools/make_divider_mid.py           the pieces, then:
      python Tools/kit_palette.py                the looks (Kit<Look>) from Media/Kit
      python Tools/texture_pack.py ship          the masters -> the addon's Media (then a full client restart)
"""
import os
import re
import shutil
import sys

import numpy as np
from PIL import Image

import build_kit as bk
import kit_gems
from paths import master

SRC = os.path.join(bk.SRC, "window")
STUB_L = (38, 51)    # the left cap's plain stub columns (2x px): past the gem's collar (it flares out to ~37), before
#                       the cap's cut edge (52, a column darkened by the cut)
STUB_R = 14          # the right cap's plain stub: columns 0 .. 13; its collar from 14
FADE_R = 4           # ... the new rail faded into that collar over these columns


def emit(name, a):
    """The master file of piece `name` from its 2x array, exactly as build_kit.py's emit writes it (gems toned,
    resized round a tiled axis, at the piece's density, on its power-of-two canvas, a one-axis tile's padding
    repeating its edge rows); and the layout entry's (w, h, uv, box)."""
    a, _ = kit_gems.tone(name, a)
    h, w = a.shape[:2]
    axes = bk.tile_axes(name)
    fw = bk.pot_near(w) if "x" in axes else bk.pot_up(w)
    fh = bk.pot_near(h) if "y" in axes else bk.pot_up(h)
    im = Image.fromarray(a)
    if "x" in axes or "y" in axes:
        im = im.resize((fw if "x" in axes else w, fh if "y" in axes else h), Image.LANCZOS)
    pw, ph = im.size
    d = bk.density(name)
    sw, sh = max(1, round(pw * d)), max(1, round(ph * d))
    if "x" in axes:
        sw = bk.pot_near(sw)
    if "y" in axes:
        sh = bk.pot_near(sh)
    small = im if (sw, sh) == (pw, ph) else im.resize((sw, sh), Image.LANCZOS)
    cw = sw if "x" in axes else bk.pot_up(sw)
    ch = sh if "y" in axes else bk.pot_up(sh)
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.paste(small, (0, 0))
    arr = np.array(canvas)
    if "x" in axes and "y" not in axes and sh < ch:
        half = (sh + ch) // 2
        for r in range(sh, ch):
            arr[r] = arr[sh - 1] if r < half else arr[0]
    if "y" in axes and "x" not in axes and sw < cw:
        half = (sw + cw) // 2
        for c in range(sw, cw):
            arr[:, c] = arr[:, sw - 1] if c < half else arr[:, 0]
    m = np.array(im)[..., 3] > 128
    ys, xs = np.where(m)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1) if len(ys) else (0, 0, pw, ph)
    return Image.fromarray(arr), (pw, ph, (0.0, sw / cw, 0.0, sh / ch), box)


def load(path):
    return np.array(Image.open(path).convert("RGBA"))


def rail(cap):
    """The left cap's stub as one column: each row its plain columns' median (float RGBA)."""
    col = np.median(cap[:, STUB_L[0]:STUB_L[1] + 1].astype(float), axis=1)
    col[col[:, 3] < 8] = 0           # (rows the stub does not paint stay clear)
    return col


def new_mid(cap, width):
    return np.repeat(np.round(rail(cap)).astype(np.uint8)[:, None, :], width, axis=1)


def new_cap_r(cap, old):
    """The right cap with its plain stub the left cap's rail, faded into its collar."""
    col = rail(cap)
    out = old.astype(float).copy()
    for x in range(STUB_R + FADE_R):
        t = 1.0 if x < STUB_R else 1.0 - (x - STUB_R + 1) / (FADE_R + 1)
        out[:, x] = col * t + out[:, x] * (1 - t)
    return np.round(out).astype(np.uint8)


def num(v):
    return ("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def set_entry(text, name, pw, ph, uv, box):
    line = re.compile(r'(\["%s"\] = \{ file = "[^"]+", )w = \d+, h = \d+, uv = \{ [^}]* \}(, tile = "\w+")?, box = \{ [^}]* \}'
                      % re.escape(name))
    assert len(line.findall(text)) == 1, "the master layout's %s entry" % name
    return line.sub(lambda m: '%sw = %d, h = %d, uv = { %s }%s, box = { %s }' % (
        m.group(1), pw, ph, ", ".join(num(v) for v in uv), m.group(2) or "", ", ".join(str(v) for v in box)), text)


def kept(png):
    """The original 2x source of a piece this tool rewrites (kept beside it on the first run)."""
    keep = png[:-4] + ".pre_joints.png"
    if not os.path.exists(keep):
        shutil.copyfile(png, keep)
    return load(keep)


def main():
    pieces = (("window/divider_mid", "divider_mid"), ("window/divider_cap_r", "divider_cap_r"))
    if "--check" in sys.argv[1:]:
        bad = 0
        for name, file in pieces + (("window/divider_cap_l", "divider_cap_l"),):
            img, entry = emit(name, load(os.path.join(SRC, file + ".png")))
            same = np.array_equal(np.array(img), load(os.path.join(master("Kit"), "window", file + ".tga")))
            bad += 0 if same else 1
            print("%s: today's master from today's source, as this tool writes it: %s (w %d h %d box %s)" % (
                name, "the same pixels" if same else "DIFFERENT", entry[0], entry[1], entry[3]))
        sys.exit(1 if bad else 0)
    cap = load(os.path.join(SRC, "divider_cap_l.png"))
    made = {}
    mid_png = os.path.join(SRC, "divider_mid.png")
    old_mid = kept(mid_png)
    assert cap.shape[0] == old_mid.shape[0], "the cap and the middle must be one height (%d, %d)" % (
        cap.shape[0], old_mid.shape[0])
    made["window/divider_mid"] = (mid_png, new_mid(cap, old_mid.shape[1]))
    capr_png = os.path.join(SRC, "divider_cap_r.png")
    made["window/divider_cap_r"] = (capr_png, new_cap_r(cap, kept(capr_png)))
    lua = master("KitLayout.lua")
    text = open(lua, encoding="utf-8", newline="").read()
    for name, (png, a) in made.items():
        Image.fromarray(a).save(png)
        img, (pw, ph, uv, box) = emit(name, a)
        img.save(os.path.join(master("Kit"), name.replace("/", os.sep) + ".tga"))
        text = set_entry(text, name, pw, ph, uv, box)
        print("%s: %d x %d, layout w %d h %d box %s" % (name, a.shape[1], a.shape[0], pw, ph, box))
    open(lua, "w", encoding="utf-8", newline="").write(text)
    print("next: python Tools/kit_palette.py, then python Tools/texture_pack.py ship (then a full client restart)")


if __name__ == "__main__":
    main()
