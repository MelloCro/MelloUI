"""
make_title_arrows.py -- the title bar's arrow buttons on the close button's steel plate (0.20.1; the user,
2026-10-10: the spell book's maximize button was the red studded plate beside the steel close button -- "Steel, like
close", then pick A of MelloUI-BuildData/output/titlebuttons_sketch: the arrow in the plate's own metal).

window/titlearrow_<up|down>_<normal|hover|pressed>: the close plate in that state (window/close_<state>) with its X
painted out from the slate round it, the NewUI2 arrow glyph of that state (glyphs/arrow_<dir>_<state>) laid in the
X's place at the X's size. In the sources' own colours: the looks are recoloured from them (Tools/kit_palette.py).

Writes the 2x sources (Tools/pack_sources/kit/v2_2x/window/titlearrow_*.png and their manifest entries), their
masters as build_kit.py writes them (masters/Media/Kit/window/titlearrow_*.tga: at the close plate's density, with
no gem toning -- build_kit.DENSITY and kit_gems.KEEP_PIECES name them with the close plate) and the master
KitLayout.lua's entries. Made from the close plates and the glyphs alone: running it again writes the same files.

Run:  python Tools/make_title_arrows.py --check   builds nothing: today's masters against what this tool writes
      python Tools/make_title_arrows.py           the pieces, then:
      python Tools/kit_palette.py                the looks
      python Tools/texture_pack.py ship          the addon's Media (then a full client restart)
"""
import json
import os
import re
import sys

import cv2
import numpy as np
from PIL import Image

import build_kit as bk
from make_divider_mid import emit, num
from paths import master

SRC = bk.SRC
STATES = ("normal", "hover", "pressed")
DIRS = ("up", "down")


def load(name):
    return np.array(Image.open(os.path.join(SRC, name + ".png")).convert("RGBA"))


def x_mask(a):
    """the close button's X: red / orange in the plate's middle, grown a little over its soft edge"""
    rgb = a[..., :3].astype(float) / 255
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    red = (rgb[..., 0] > rgb[..., 1] * 1.35) & (rgb[..., 0] > rgb[..., 2] * 1.35) & (sat > 0.35) & (mx > 0.25)
    h, w = red.shape
    inner = np.zeros_like(red)
    inner[int(h * 0.2):int(h * 0.8), int(w * 0.2):int(w * 0.8)] = True
    return cv2.dilate((red & inner).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=2) > 0


def blank(a):
    """the plate with its X painted out from the slate round it"""
    m = x_mask(a)
    bgr = cv2.cvtColor(np.ascontiguousarray(a[..., :3]), cv2.COLOR_RGB2BGR)
    out = cv2.inpaint(bgr, m.astype(np.uint8) * 255, 4, cv2.INPAINT_TELEA)
    b = a.copy()
    b[..., :3] = cv2.cvtColor(out, cv2.COLOR_BGR2RGB)
    return b, m


def trimmed(a):
    ys, xs = np.nonzero(a[..., 3] > 8)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def compose(plate, glyph, box):
    """the glyph centred in the X's box, as large as the X"""
    ys, xs = np.nonzero(box)
    bw, bh = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    gh, gw = glyph.shape[:2]
    k = min(bw * 0.95 / gw, bh * 0.95 / gh)
    gi = Image.fromarray(glyph).resize((max(1, round(gw * k)), max(1, round(gh * k))), Image.LANCZOS)
    out = Image.fromarray(plate)
    out.alpha_composite(gi, (int(round(cx - gi.width / 2)), int(round(cy - gi.height / 2))))
    return np.array(out)


def pieces():
    out = {}
    for state in STATES:
        plate, box = blank(load("window/close_" + state))
        for d in DIRS:
            out["window/titlearrow_%s_%s" % (d, state)] = compose(plate, trimmed(load("glyphs/arrow_%s_%s" % (d, state))), box)
    return out


def entry_line(name, pw, ph, uv, box):
    return '\t\t["%s"] = { file = "%s", w = %d, h = %d, uv = { %s }, box = { %s } },' % (
        name, name.replace("/", "\\\\"), pw, ph, ", ".join(num(v) for v in uv), ", ".join(str(v) for v in box))


def main():
    made = pieces()
    tga = {name: os.path.join(master("Kit"), name.replace("/", os.sep) + ".tga") for name in made}
    if "--check" in sys.argv[1:]:
        bad = 0
        for name, a in sorted(made.items()):
            img, _ = emit(name, a)
            same = os.path.exists(tga[name]) and np.array_equal(np.array(img), np.array(Image.open(tga[name])))
            bad += 0 if same else 1
            print("%s: %s" % (name, "the same pixels" if same else "DIFFERENT or missing"))
        sys.exit(1 if bad else 0)
    manifest = os.path.join(SRC, "manifest.json")
    man = json.load(open(manifest, encoding="utf-8"))
    lua = master("KitLayout.lua")
    text = open(lua, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in text else "\n"
    for name, a in sorted(made.items()):
        Image.fromarray(a).save(os.path.join(SRC, name + ".png"))
        man["v2_2x/" + name] = {"w": int(a.shape[1]), "h": int(a.shape[0]), "scale": 1.0,
                                "src": "the close plate (X painted out) and glyphs/arrow, Tools/make_title_arrows.py"}
        img, (pw, ph, uv, box) = emit(name, a)
        img.save(tga[name])
        line = entry_line(name, pw, ph, uv, box)
        old = re.compile(r'^\t\t\["%s"\] = \{[^\n]*\},\r?$' % re.escape(name), re.M)
        if old.search(text):
            text = old.sub(line, text)
        else:
            # in the layout's sorted order (build_kit.py writes it sorted by name)
            entries = list(re.finditer(r'^\t\t\["([^"]+)"\] = \{[^\n]*\},\r?$', text, re.M))
            after = [m for m in entries if m.group(1) < name]
            at = after[-1].end() if after else entries[0].start() - 1
            text = text[:at] + nl + line + text[at:]
        print("%s: %d x %d, layout box %s" % (name, pw, ph, box))
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    open(lua, "w", encoding="utf-8", newline="").write(text)
    print("next: python Tools/kit_palette.py, then python Tools/texture_pack.py ship (then a full client restart)")


if __name__ == "__main__":
    main()
