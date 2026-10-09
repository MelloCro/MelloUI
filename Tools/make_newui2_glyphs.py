"""
make_newui2_glyphs.py -- the NewUI2 glyph sheet, and the parts sheet's close button and portrait border (user,
2026-10-08: "replacing existing ones that we already use in the UI with these ones ... specifically the Portrait
Border and the Close Button"; plan docs/plans/newui2-glyphs-close-portrait.md), cut into kit-sized pieces. The twin of
Tools/make_newui2_borders.py: the same keying and cleaning (the sketch builder
MelloUI-BuildData/output/newui2_library_sketch/newui2_parts.py: the kit_v3 magenta key, every pixel under full alpha
taking the nearest solid one's colour, the dust round a piece dropped), in the sheets' own colours (the kit's
recolouring makes each look's from them, Tools/kit_palette.py).

The glyph sheet (C:/Users/mortu/Downloads/NewUI2/a4de1ef6...png): square plates with gold corner studs, each glyph in
its states left to right (steel = normal, gold = hover, dim = pressed):
    row 1  arrow up x 3, arrow down x 3          row 3  check box off, on, hover (gold empty); cog x 3
    row 2  arrow left x 3, arrow right x 3       row 4  plus normal, hover; minus normal, hover
The parts sheet (55600330...png): the close button x 3 (steel, gold, dark red = pressed) and the portrait border (a
round steel ring with a gold inner line and two winged side brackets; nothing else on that sheet is taken).

The cells are FOUND (the plates' connected parts on the keyed sheet, in rows by their centres), not measured by
hand. Each family (a glyph's states; the four arrows together) is laid at ONE scale on the canvas of the piece it
replaces (CANVAS: the v2_2x pieces' painted 2x sizes), centred, so a state swap never moves it. The plates keep their
own black outline and bevel shadow (kit-art-edge-shadows). Beside each arrow and + / - plate: its glyph alone, cut out
of the plate's ground with a soft dark shadow of its own (the sketch's small-size choice; every state takes the steel
one's shape). buttons/checkbox_onhover: a ticked box under the mouse (the sheet paints none: the gold plate with the
tick laid on it). buttons/iconplate_<state>: the cog plate with its cog painted out, every icon button's plate (the
user's pick A, 2026-10-09). The portrait border: made symmetric left to right about its opening's centre (the sheet's two wings
differ), its bottom point kept, on a SQUARE canvas with the opening in its middle (the ring code lays rings square),
at the scale of a ring style (its opening as rings/r1's).

The user's picks (2026-10-08, "0A 1A 2B 3B 4c 5A"; the sketch MelloUI-BuildData/output/newui2_glyphs_sketch): the
plates are THE control style (the flat controls draw them, Core/Widgets.lua); under 20 UI px an arrow or a + / -
is its glyph alone (glyphs/<name>, one scale for all of them, each glyph's states on one canvas so a state swap never
moves it); the border is rings/r5 (it was R5 in the NewUI2 rims' sketch): the window corners' ring and a Portrait
Ring choice.

Run:  python Tools/make_newui2_glyphs.py [--out DIR]
      the pieces as PNG under DIR (default MelloUI-BuildData/output/newui2_glyphs_sketch/pieces, the sketch's):
      <group>/<name>.png (the plate on its canvas), glyph/<name>.png (the glyph alone), rings/winged.png, and
      pieces.json (each piece's size, the family scale, the border's opening)
      python Tools/make_newui2_glyphs.py --kit
      the same into the kit's sources (Tools/pack_sources/kit/v2_2x, git-ignored): buttons/<name>, window/close_*,
      glyphs/<name>, rings/r5, and their manifest entries; running it again writes the same files. Then
      build_kit.py and texture_pack.py ship (a full client restart).
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

from paths import SIBLING

SKETCH_BUILDER = os.path.join(SIBLING, "output", "newui2_library_sketch")
OUT = os.path.join(SIBLING, "output", "newui2_glyphs_sketch", "pieces")
GLYPH_SHEET = "a4de1ef6-5b33-4b10-a437-45d6334530bb"     # registered as newui2_parts' sheet "G"
PARTS_SHEET = "D"                                         # newui2_parts' 55600330...: the parts sheet

# the glyph sheet's plates, row by row, left to right
GLYPH_ROWS = (
    ("arrow_up_normal", "arrow_up_hover", "arrow_up_pressed", "arrow_down_normal", "arrow_down_hover", "arrow_down_pressed"),
    ("arrow_left_normal", "arrow_left_hover", "arrow_left_pressed", "arrow_right_normal", "arrow_right_hover", "arrow_right_pressed"),
    ("checkbox_off", "checkbox_on", "checkbox_hover", "cog_normal", "cog_hover", "cog_pressed"),
    ("plus_normal", "plus_hover", "minus_normal", "minus_hover"),
)
CLOSE = ("close_normal", "close_hover", "close_pressed")
# each piece's canvas: the painted (2x) size of the v2_2x piece it replaces (Tools/pack_sources/kit/v2_2x/manifest.json)
CANVAS = {
    "buttons/arrow_up": (44, 41), "buttons/arrow_down": (43, 42), "buttons/arrow_left": (43, 43),
    "buttons/arrow_right": (43, 41), "buttons/checkbox": (43, 43), "buttons/cog": (50, 49),
    "buttons/plus": (37, 37), "buttons/minus": (37, 37), "window/close": (64, 58), "buttons/iconplate": (50, 49),
}
# families laid at one scale: the four arrows share one plate; + and - one
FAMILY = {"buttons/arrow_up": "arrow", "buttons/arrow_down": "arrow", "buttons/arrow_left": "arrow",
          "buttons/arrow_right": "arrow", "buttons/plus": "plusminus", "buttons/minus": "plusminus",
          "buttons/cog": "cog", "buttons/iconplate": "cog"}
GLYPH_ALONE = ("arrow_", "plus_", "minus_")
RING_OPENING = 152          # the border's opening as rings/r1's (Media/KitLayout.lua: open 41..193)
GLYPH_SIDE = 48             # the glyphs alone: the largest one's larger side (2x px; shown at 11 to 17 UI units)
KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pack_sources", "kit", "v2_2x")


def png(a, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(np.round(a), 0, 255).astype(np.uint8), "RGBA").save(path)


def plates(P, sheet_id, min_px=5000):
    """the sheet's plates: (x, y, w, h) of each connected part of the keyed sheet, in rows top down, each row left to
    right"""
    al = P.sheet(sheet_id)[..., 3] > 100
    lab, n = ndimage.label(al)
    sizes = ndimage.sum(np.ones_like(al), lab, range(1, n + 1))
    boxes = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sizes[i] >= min_px:
            boxes.append((sl[1].start, sl[0].start, sl[1].stop - sl[1].start, sl[0].stop - sl[0].start))
    boxes.sort(key=lambda b: b[1] + b[3] / 2)
    rows, last = [], None
    for b in boxes:
        cy = b[1] + b[3] / 2
        if last is None or cy - last > 60:
            rows.append([])
        rows[-1].append(b)
        last = cy
    return [sorted(r) for r in rows]


def trim(a, t=8):
    ys, xs = np.nonzero(a[..., 3] > t)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def resized(a, k):
    h, w = a.shape[:2]
    im = Image.fromarray(np.clip(np.round(a), 0, 255).astype(np.uint8), "RGBA")
    return np.asarray(im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)).astype(np.float32)


def on_canvas(a, W, H):
    """`a` centred on a W x H canvas by its solid part's box"""
    ys, xs = np.nonzero(a[..., 3] > 100)
    cx, cy = (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2
    out = np.zeros((H, W, 4), np.float32)
    ox, oy = int(round(W / 2 - cx)), int(round(H / 2 - cy))
    h, w = a.shape[:2]
    sx0, sy0 = max(0, -ox), max(0, -oy)
    sx1, sy1 = min(w, W - ox), min(h, H - oy)
    out[oy + sy0:oy + sy1, ox + sx0:ox + sx1] = a[sy0:sy1, sx0:sx1]
    return out


def _hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1e-6)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    return hue, sat, mx


def _hull(m, ss=4):
    """the convex hull of a mask's pixels, drawn ss x over and brought back down (soft edges)"""
    from PIL import ImageDraw
    from scipy.spatial import ConvexHull
    ys, xs = np.nonzero(m)
    pts = np.stack((xs + 0.5, ys + 0.5), 1)
    hull = pts[ConvexHull(pts).vertices]
    h, w = m.shape
    im = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(im).polygon([tuple(p * ss) for p in hull], fill=255)
    return np.asarray(im.resize((w, h), Image.LANCZOS)).astype(np.float32) / 255


def _shifted(m, dx, dy, shape):
    """m moved by (dx, dy) onto a canvas of `shape`"""
    out = np.zeros(shape, m.dtype)
    h, w = m.shape
    H, W = shape
    sx0, sy0 = max(0, -dx), max(0, -dy)
    sx1, sy1 = min(w, W - dx), min(h, H - dy)
    if sx1 > sx0 and sy1 > sy0:
        out[sy0 + dy:sy1 + dy, sx0 + dx:sx1 + dx] = m[sy0:sy1, sx0:sx1]
    return out


def glyph_alone(a, state, convex, ref=None, inset=0.19):
    """the glyph of a plate cut out of its maroon ground: in the plate's middle (inside its frame) the steel (normal)
    or dim (pressed) glyph is the unsaturated part, the gold one (hover) the bright gold hue (its orange glow on the
    ground left out); the shape completed (an arrow and a minus are convex: their hull; a plus closed). A state given
    `ref` (its steel twin's shape, the same glyph painted in the same place) takes that shape, moved onto its own
    pixels (the shift that covers most of them). With a soft dark shadow of its own. Returns the glyph and its shape."""
    h, w = a.shape[:2]
    x0, x1, y0, y1 = int(w * inset), int(w * (1 - inset)), int(h * inset), int(h * (1 - inset))
    inner = np.zeros((h, w), bool)
    inner[y0:y1, x0:x1] = True
    band = inner & ~ndimage.binary_erosion(inner, iterations=max(2, int(min(w, h) * 0.04)))
    ground = np.median(a[band][:, :3], axis=0)
    hue, sat, val = _hsv(a[..., :3] / 255.0)
    if state == "hover":
        m = (hue >= 28) & (hue <= 62) & (val > 0.45) & (sat > 0.2)
    else:
        m = (sat < 0.55) & (val > 0.16)
    m &= inner & (a[..., 3] > 200)
    m = ndimage.binary_opening(m, iterations=1)
    lab, n = ndimage.label(m)
    if n:
        sizes = ndimage.sum(np.ones(m.shape), lab, range(1, n + 1))
        m = np.isin(lab, 1 + np.flatnonzero(sizes >= sizes.max() * 0.05))
    if ref is not None:
        best = None
        for dy in range(-10, 11):
            for dx in range(-10, 11):
                r = _shifted(ref, dx, dy, m.shape)
                score = (r * m).sum() - 0.5 * (r * (~m & inner)).sum()
                if best is None or score > best[0]:
                    best = (score, dx, dy)
        soft = _shifted(ref, best[1], best[2], m.shape)
    elif convex:
        soft = _hull(m)
    else:
        m = ndimage.binary_fill_holes(ndimage.binary_closing(m, iterations=2))
        soft = ndimage.gaussian_filter(m.astype(np.float32), 0.7)
    shape = soft
    m = soft > 0.5
    g = a.copy()
    g[..., 3] = soft * 255
    # its own shadow: the shape grown, blurred, dark, a little down
    sh = ndimage.gaussian_filter(ndimage.binary_dilation(m, iterations=2).astype(np.float32), 2.0)
    sh = np.roll(np.roll(sh, 2, axis=0), 1, axis=1) * 0.85
    out = np.zeros_like(a)
    out[..., 3] = sh * 255
    ga = g[..., 3:4] / 255
    out_a = ga + out[..., 3:4] / 255 * (1 - ga)
    out[..., :3] = np.where(out_a > 0, g[..., :3] * ga / np.maximum(out_a, 1e-6), 0)
    out[..., 3:4] = out_a * 255
    return trim(out, 4), ground, shape


def square_border(a):
    """the border made symmetric left to right about its opening's centre (its left half mirrored: the sheet's two
    wings differ), on a SQUARE canvas with the opening's centre in its middle -- the ring code lays every ring
    square and centred (Modules/Kit.lua's square / opening rules, Kit:LayPortraitRing), so the wings need no code of
    their own; its opening (x0, y0, x1, y1) measured on that canvas"""
    al = a[..., 3] > 128
    lab, _ = ndimage.label(~al)
    h, w = al.shape
    hole = lab == lab[h // 2, w // 2]
    ys, xs = np.nonzero(hole)
    cx, cy = (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2
    asym = float(np.abs(a[..., 3] - a[:, ::-1, 3]).mean())
    ix, iy = int(round(cx)), int(round(cy))
    n = 2 * max(ix, w - ix, iy, h - iy) + 2
    out = np.zeros((n, n, 4), np.float32)
    ox, oy = n // 2 - ix, n // 2 - iy
    out[oy:oy + h, ox:ox + ix] = a[:, :ix]
    out[:, n // 2:] = out[:, :n // 2][:, ::-1]
    lab2, _ = ndimage.label(~(out[..., 3] > 128))
    ys, xs = np.nonzero(lab2 == lab2[n // 2, n // 2])
    return out, (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1), asym


def blank_plate(a, inset=0.2):
    """the cog plate with its cog painted out (0.19.9, the user's pick A 2026-10-09: the plate of every icon button --
    the bag window's bin and sort, the chat column's, the tracker's filter -- the NewUI2 cog plate's own, so the bag's
    three buttons match): the cog (the middle's pixels brighter than its ground, or gold) filled in from the ground
    round it"""
    import cv2
    h, w = a.shape[:2]
    hue, sat, val = _hsv(a[..., :3] / 255.0)
    inner = np.zeros((h, w), bool)
    inner[int(h * inset):int(h * (1 - inset)), int(w * inset):int(w * (1 - inset))] = True
    band = inner & ~ndimage.binary_erosion(inner, iterations=6)
    gv = np.median(val[band])
    m = inner & ((val > gv + 0.07) | ((sat > 0.3) & (hue > 15) & (hue < 70)))
    m = ndimage.binary_opening(m, iterations=1)
    lab, n = ndimage.label(m)
    if n:
        sizes = ndimage.sum(np.ones(m.shape), lab, range(1, n + 1))
        m = np.isin(lab, 1 + np.flatnonzero(sizes >= sizes.max() * 0.05))
    m = ndimage.binary_dilation(ndimage.binary_fill_holes(m), iterations=4)
    out = a.copy()
    out[..., :3] = cv2.inpaint(np.clip(np.round(a[..., :3]), 0, 255).astype(np.uint8), (m * 255).astype(np.uint8), 9,
                               cv2.INPAINT_TELEA)
    return out


def tick_on(on, plate, inset=0.2):
    """the tick of the ticked plate `on` (its gold, glow and all, inside the frame) laid on `plate`"""
    h, w = on.shape[:2]
    # the tick: the bright part of the plate's middle (its faces run from gold to near white; the ground is dark)
    _, _, val = _hsv(on[..., :3] / 255.0)
    m = val > 0.45
    inner = np.zeros((h, w), bool)
    inner[int(h * inset):int(h * (1 - inset)), int(w * inset):int(w * (1 - inset))] = True
    m = ndimage.binary_opening(m & inner, iterations=1)
    lab, n = ndimage.label(m)
    if n:
        sizes = ndimage.sum(np.ones(m.shape), lab, range(1, n + 1))
        m = lab == 1 + int(np.argmax(sizes))
    m = ndimage.binary_fill_holes(ndimage.binary_closing(m, iterations=2))
    soft = ndimage.gaussian_filter(ndimage.binary_dilation(m, iterations=2).astype(np.float32), 1.0)
    # (on the bright gold plate the gold tick needs its own dark edge to read: a soft shadow under it)
    shade = np.clip(ndimage.gaussian_filter(ndimage.binary_dilation(m, iterations=5).astype(np.float32), 3.0) * 1.4,
                    0, 1) * 0.85
    shade = np.roll(shade, 3, axis=0)
    out = plate.copy()
    ph, pw = plate.shape[:2]
    oy, ox = (ph - h) // 2, (pw - w) // 2
    for y in range(h):
        ty = y + oy
        if 0 <= ty < ph:
            xs = np.arange(w) + ox
            ok = (xs >= 0) & (xs < pw)
            sh = shade[y, ok][:, None]
            out[ty, xs[ok], :3] = out[ty, xs[ok], :3] * (1 - sh)
            al = soft[y, ok][:, None]
            out[ty, xs[ok], :3] = on[y, ok, :3] * al + out[ty, xs[ok], :3] * (1 - al)
    return out


def main():
    out_dir = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else OUT
    kit = "--kit" in sys.argv
    made = {}           # (the kit's) piece name -> (RGBA, its manifest note)
    sys.path.insert(0, SKETCH_BUILDER)
    import newui2_parts as P  # noqa: E402  (the sketch builder: its keying and cleaning)
    P.SHEETS.setdefault("G", GLYPH_SHEET)

    # every cell, keyed and cleaned
    cells = {}
    rows = plates(P, "G")
    if [len(r) for r in rows] != [len(r) for r in GLYPH_ROWS]:
        raise SystemExit("the glyph sheet's plates: rows of %s, expected %s" % ([len(r) for r in rows],
                                                                              [len(r) for r in GLYPH_ROWS]))
    for names, boxes in zip(GLYPH_ROWS, rows):
        for name, box in zip(names, boxes):
            cells["buttons/" + name] = (trim(P.cut("G", *box)), box)
    parts = [b for r in plates(P, PARTS_SHEET) for b in r]
    close = sorted(b for b in parts if 140 < b[2] < 200 and 140 < b[3] < 200 and b[0] > 880 and 420 < b[1] < 480)
    border = [b for b in parts if b[2] > 480 and b[3] > 350]
    if len(close) != 3 or len(border) != 1:
        raise SystemExit("the parts sheet: %d close buttons, %d portrait borders found (expected 3, 1)" % (len(close), len(border)))
    for name, box in zip(CLOSE, close):
        cells["window/" + name] = (trim(P.cut(PARTS_SHEET, *box)), box)

    # (a candidate for the user's states pick) a ticked box under the mouse: the sheet paints none, so the gold
    # (hover) plate with the ticked plate's tick laid on it, their boxes' centres matched
    # (the user's pick A, 2026-10-09) every icon button's plate: the cog plate blank, in its three states
    for state in ("normal", "hover", "pressed"):
        cog_cell, cog_box = cells["buttons/cog_" + state]
        cells["buttons/iconplate_" + state] = (blank_plate(cog_cell), cog_box)
    cells["buttons/checkbox_onhover"] = (tick_on(cells["buttons/checkbox_on"][0], cells["buttons/checkbox_hover"][0]),
                                         cells["buttons/checkbox_hover"][1])

    # one scale per family: the largest plate of the family fits the smallest canvas of it
    def base_of(name):
        return name.rsplit("_", 1)[0]
    fam_k = {}
    for name, (a, _) in cells.items():
        base = base_of(name)
        fam = FAMILY.get(base, base)
        W, H = CANVAS[base]
        h, w = a.shape[:2]
        k = min(W / w, H / h)
        fam_k[fam] = min(fam_k.get(fam, k), k)
    info = {"pieces": {}, "families": {f: round(k, 4) for f, k in fam_k.items()}}
    shapes = {}
    # (the steel state first: the others take its glyph's shape)
    for name, (a, box) in sorted(cells.items(), key=lambda kv: (kv[0].rsplit("_", 1)[0], not kv[0].endswith("_normal"), kv[0])):
        base = base_of(name)
        k = fam_k[FAMILY.get(base, base)]
        W, H = CANVAS[base]
        piece = on_canvas(resized(a, k), W, H)
        png(piece, os.path.join(out_dir, name + ".png"))
        made[name] = (piece, "NewUI2 %s, x %d y %d %dx%d" % ((("glyphs",) if name.startswith("buttons/") else ("parts",))
                                                              + tuple(box)))
        e = {"w": W, "h": H, "scale": round(k, 4), "src": "%s %s" % ("NewUI2 glyphs" if name.startswith("buttons/")
                                                                   else "NewUI2 parts", "x %d y %d %dx%d" % box)}
        if name.split("/")[1].startswith(GLYPH_ALONE):
            base, state = name.rsplit("_", 1)
            g, ground, shapes[name] = glyph_alone(a, state, not name.split("/")[1].startswith("plus_"),
                                                  shapes.get(base + "_normal"))
            png(g, os.path.join(out_dir, "glyph", name.split("/")[1] + ".png"))
            made["glyphs/" + name.split("/")[1]] = (g, "NewUI2 glyphs, the glyph of buttons/%s alone" % name.split("/")[1])
            e["glyph"] = [int(g.shape[1]), int(g.shape[0])]
            e["ground"] = [int(v) for v in ground]
        info["pieces"][name] = e
        print("%-28s %dx%d  scale %.3f  (plate %dx%d at x %d y %d)%s" % (
            name, W, H, k, a.shape[1], a.shape[0], box[0], box[1],
            "  glyph alone %dx%d" % tuple(e["glyph"]) if "glyph" in e else ""))

    # the portrait border, symmetric, square, at a ring style's scale (its opening as rings/r1's)
    a = trim(P.cut(PARTS_SHEET, *border[0]))
    sq, op, asym = square_border(a)
    k = RING_OPENING / (op[2] - op[0])
    n = int(round(sq.shape[1] * k))
    ring = np.asarray(Image.fromarray(np.clip(np.round(sq), 0, 255).astype(np.uint8), "RGBA").resize(
        (n, n), Image.LANCZOS)).astype(np.float32)
    png(sq, os.path.join(out_dir, "rings", "winged_src.png"))
    png(ring, os.path.join(out_dir, "rings", "winged.png"))
    made["rings/r5"] = (ring, "NewUI2 R5 (the parts sheet's portrait border), its left half mirrored, square, opening centred")
    info["border"] = {"src": [int(v) for v in border[0]], "size_src": int(sq.shape[1]), "opening_src": list(op),
                      "asymmetry": round(asym, 1), "scale": round(k, 4), "size": n,
                      "opening": [round(v * k, 1) for v in op]}
    print("portrait border  %dx%d square -> %dx%d, opening %s (%d px across as rings/r1; the sheet's halves differed by %.1f)" % (
        sq.shape[1], sq.shape[0], n, n, info["border"]["opening"], RING_OPENING, asym))
    with open(os.path.join(out_dir, "pieces.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1, sort_keys=True)
    print("-> %s" % out_dir)
    if kit:
        to_kit(made)


def to_kit(made):
    """the pieces into the kit's sources: the glyphs alone at one scale (GLYPH_SIDE), each glyph's states centred on
    one canvas; the rest as made; their manifest entries"""
    manifest = os.path.join(KIT, "manifest.json")
    man = json.load(open(manifest, encoding="utf-8"))
    glyphs = {n: a for n, (a, _) in made.items() if n.startswith("glyphs/")}
    k = GLYPH_SIDE / max(max(a.shape[:2]) for a in glyphs.values())
    canvas = {}
    for n, a in glyphs.items():
        base = n.rsplit("_", 1)[0]
        h, w = a.shape[:2]
        cw, ch = canvas.get(base, (0, 0))
        canvas[base] = (max(cw, int(np.ceil(w * k)) + 2), max(ch, int(np.ceil(h * k)) + 2))
    for name, (a, note) in sorted(made.items()):
        if name.startswith("glyphs/"):
            W, H = canvas[name.rsplit("_", 1)[0]]
            a = on_canvas(resized(a, k), W, H)
            note += ", at %.3f" % k
        png(a, os.path.join(KIT, name + ".png"))
        man["v2_2x/" + name] = {"w": int(a.shape[1]), "h": int(a.shape[0]), "scale": 1.0, "src": note}
        print("kit  %-28s %dx%d" % (name, a.shape[1], a.shape[0]))
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    print("-> %s (+ manifest); next: python Tools/build_kit.py" % KIT)


if __name__ == "__main__":
    main()
