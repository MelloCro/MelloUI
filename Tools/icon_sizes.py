"""
icon_sizes.py -- MelloUI's icons made for the size they are drawn at (2026-10-21).

The user, 2026-10-21: "all icons and its borders should always stay smooth", "i want this rule to be for all the icons
in the UI". The set's files are 64 px (some 32 or 128) TGA, which carry no mipmaps: the client draws a TGA with its
plain bilinear filter (it mips one only when told TRILINEAR, and that made thin lines a soft, dim ring in game,
docs/plans/chat-redesign.md stage 0), so a 64 px icon drawn at 14 screen px reads one texel in five -- jagged edges,
and a 2 px gold ring sampled into dots or lost. So each icon also ships SMALL COPIES, one per size of LADDER under its
own, packed on one sheet (Media/Textures/Icons/Sizes/<name>.tga), and MelloUI.Icons (Core/Icons.lua) draws the copy
made for the icon's size on screen: never shrunk by more than a ladder step (about 1.33x), which bilinear filtering
draws whole.

A copy is made for its size (made_for):
  - its border kept: a compact icon's (a disc, a rounded box) dark outline and its light ring, read from the icon's
    profile by depth from its edge (structure), are made at least MIN_OUT and MIN_RING copy px wide -- the ring
    widened inward over the disc's edge, the outline likewise (as Tools/kit_sharp.py did for the kit's round rims,
    2026-10-14: a line ~1.2 px wide on screen was solid and crisp in game, a thinner one dotted);
  - the inside squeezed toward the middle to make room for the wider border (a flag or a gear stays whole);
  - then scaled down in one step (Lanczos, premultiplied: no dark fringe), so no texel is skipped and every edge is
    anti-aliased; the small copies (SHARPEN_UPTO) lightly sharpened (the user's look B of
    MelloUI-BuildData/output/icon_sizes_sketch; A: no sharpening).
A thin shape (a "!", footprints: no deep middle) has no border plan: only the scaling.

SHEETS: one sheet per file size (SHEET[size] = (w, h, {copy size: (x, y)})), every copy GUTTER px from the next;
the layouts are fixed here and written into Media/IconSizes.lua for the game (Tools/make_icons.py writes both).
"""
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

LADDER = (12, 16, 20, 24, 32, 40, 48, 64, 96)
MIN_OUT = 0.7       # copy px: the outline's least width
MIN_RING = 1.1      # copy px: the ring's least width (drawn up to one ladder step smaller: still near 1 px)
SHARPEN_UPTO = 24   # copies this size and under get a light unsharp mask (look B; 0: none, look A)
SHARPEN = (0.7, 70, 0)   # its radius (copy px), percent, threshold
CONTRAST = 40       # luminance steps (alpha-weighted, 0..255) between a border's dark and its light, at least
COMPACT = 0.3       # a shape whose deepest point is this share of its size from its edge has a border (a disc, a box)
GUTTER = 2          # px between two copies on a sheet (bilinear filtering never reads the next one)

# the sheets' layouts by the file's size -- a square file's side, or "WxH" for an oblong one (its copies keep its
# shape: a copy `s` wide is s * H / W high) -- (sheet width, height, {copy width: (x, y) of its top left}); a file
# has a copy for every LADDER size under its width
SHEET = {
    32: (64, 32, {24: (0, 0), 20: (26, 0), 16: (48, 0), 12: (48, 18)}),
    64: (128, 64, {48: (0, 0), 40: (50, 0), 32: (92, 0), 24: (92, 34), 20: (50, 42), 16: (72, 42), 12: (0, 50)}),
    128: (256, 128, {96: (0, 0), 64: (98, 0), 48: (164, 0), 40: (214, 0), 32: (98, 66), 24: (132, 66),
                     20: (164, 50), 16: (186, 50), 12: (214, 42)}),
    # (the minimap's goal chevron, edge_arrow)
    "64x32": (128, 64, {48: (0, 0), 40: (50, 0), 32: (92, 0), 24: (0, 26), 20: (26, 26), 16: (48, 26), 12: (66, 26)}),
}


def dims(key):
    """a sheet key's file size: (width, height)"""
    if isinstance(key, str):
        w, h = key.split("x")
        return int(w), int(h)
    return key, key


def sizes_for(key):
    return [s for s in LADDER if s < dims(key)[0]]


def copy_dims(key, s):
    """the copy `s` wide of a file of `key`: (width, height)"""
    w, h = dims(key)
    return s, s * h // w


def _lum(a):
    return (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) * a[..., 3] / 255.0


def structure(a):
    """a's border by depth from its edge (master px), or None: (outline end, ring) -- ring (start, end) or None.
    a: HxWx4 float (0..255)."""
    m = min(a.shape[:2])
    inside = a[..., 3] > 127
    if not inside.any():
        return None
    d = ndimage.distance_transform_edt(inside)
    if d.max() < COMPACT * m:
        return None
    lum = _lum(a)
    n = max(4, int(0.25 * m))
    prof = []
    for k in range(n):
        sel = (d > k) & (d <= k + 1)
        prof.append(float(lum[sel].mean()) if sel.any() else 0.0)
    prof = np.array(prof)
    dark, top = float(np.median(prof[:3])), float(prof.max())
    if top - dark < CONTRAST:
        return None
    mid = (dark + top) / 2
    light = np.nonzero(prof >= mid)[0]
    if not len(light) or light[0] > 0.1 * m:
        return None
    o1 = int(light[0])
    ring = None
    for k in range(o1 + 1, n - 2):
        if prof[k] < mid and prof[k + 1] < mid and prof[k + 2] < mid:
            if k - o1 <= 0.1 * m:
                ring = (o1, k)
            break
    return o1, ring


def _sample(pm, sy, sx):
    """pm (premultiplied HxWx4) read bilinear at (sy, sx)"""
    h, w = pm.shape[:2]
    x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = (sx - x0)[:, None], (sy - y0)[:, None]

    def px(x, y):
        return pm[np.clip(y, 0, h - 1), np.clip(x, 0, w - 1)]
    return (px(x0, y0) * (1 - fx) * (1 - fy) + px(x0 + 1, y0) * fx * (1 - fy)
            + px(x0, y0 + 1) * (1 - fx) * fy + px(x0 + 1, y0 + 1) * fx * fy)


def _remap(a, plan, k):
    """the border's lines at least MIN_OUT / MIN_RING copy px (k master px a copy px), each border pixel read along
    its way to the nearest edge; the inside squeezed toward the shape's middle to make room (whole, a little smaller:
    a flag or a gear is never cut by the wider ring)"""
    o1, ring = plan
    out1 = max(o1, MIN_OUT * k)
    if ring:
        r0, r1 = ring
        ring_w = max(r1 - r0, MIN_RING * k)
        band, old_band = out1 + ring_w, r1
    else:
        band, old_band = out1, o1
    if band <= old_band + 1e-6:
        return a
    inside = a[..., 3] > 127
    d, ind = ndimage.distance_transform_edt(inside, return_indices=True)
    deep = float(d.max())
    if deep <= band + 1:
        return a
    pm = a.copy()
    pm[..., :3] *= pm[..., 3:4] / 255.0
    out = pm.copy()
    # the border
    sel = inside & (d < band)
    dd = d[sel]
    s = np.where(dd < out1, dd * o1 / out1, 0.0)
    if ring:
        s = np.where(dd >= out1, r0 + (dd - out1) * (r1 - r0) / ring_w, s)
    yy, xx = np.nonzero(sel)
    qy, qx = ind[0][sel].astype(np.float64), ind[1][sel].astype(np.float64)
    f = s / np.maximum(dd, 1e-6)
    out[yy, xx] = _sample(pm, qy + (yy - qy) * f, qx + (xx - qx) * f)
    # the inside, scaled about the shape's middle: its edge (band deep) reads the old one (old_band deep)
    sel = inside & (d >= band)
    yy, xx = np.nonzero(sel)
    cy, cx = ndimage.center_of_mass(inside)
    g = (deep - old_band) / (deep - band)
    out[yy, xx] = _sample(pm, cy + (yy - cy) * g, cx + (xx - cx) * g)
    al = out[..., 3:4]
    out[..., :3] = np.where(al > 0, out[..., :3] * 255.0 / np.maximum(al, 1e-6), 0)
    return out


def scale(img, w, h=None):
    """img scaled to w x h (h: w), Lanczos, premultiplied (no dark fringe)"""
    return img.convert("RGBa").resize((w, h or w), Image.LANCZOS).convert("RGBA")


def sharpen(img):
    """a light unsharp mask on the colour (the alpha, the shape's edge, as scaled)"""
    r, g, b, a = img.convert("RGBa").split()
    rgb = Image.merge("RGB", (r, g, b)).filter(ImageFilter.UnsharpMask(*SHARPEN))
    return Image.merge("RGBa", (*rgb.split(), a)).convert("RGBA")


def made_for(master, size, border=True, height=None):
    """the copy of `master` (an RGBA image, wider than `size`) made for `size` px across (`height` px down: the same
    shape as the master's when left out)"""
    a = np.asarray(master.convert("RGBA")).astype(np.float64)
    height = height or round(size * a.shape[0] / a.shape[1])
    plan = structure(a) if border else None
    if plan:
        a = _remap(a, plan, a.shape[1] / size)
    img = scale(Image.fromarray(np.clip(np.rint(a), 0, 255).astype(np.uint8), "RGBA"), size, height)
    return sharpen(img) if size <= SHARPEN_UPTO else img


def sheet(master, key):
    """every copy of an icon whose file is of `key` (SHEET's), on its sheet"""
    w, h, at = SHEET[key]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for s in sizes_for(key):
        out.paste(made_for(master, *copy_dims(key, s)), at[s])
    return out


def check_layouts():
    """every sheet's copies inside it, GUTTER px apart; the sizes LADDER's under the file's; the sheets powers of two"""
    bad = []
    for key, (w, h, at) in SHEET.items():
        if sorted(at) != sizes_for(key):
            bad.append("%s: sizes %s" % (key, sorted(at)))
        if w & (w - 1) or h & (h - 1):
            bad.append("%s: sheet %d x %d" % (key, w, h))
        boxes = []
        for s, (x, y) in at.items():
            cw, ch = copy_dims(key, s)
            boxes.append((x, y, x + cw, y + ch))
        for i, b in enumerate(boxes):
            if b[0] < 0 or b[1] < 0 or b[2] > w or b[3] > h:
                bad.append("%s: %s outside" % (key, b))
            for c in boxes[i + 1:]:
                if not (b[2] + GUTTER <= c[0] or c[2] + GUTTER <= b[0] or b[3] + GUTTER <= c[1] or c[3] + GUTTER <= b[1]):
                    bad.append("%s: %s and %s touch" % (key, b, c))
    return bad


def lua_key(key):
    return '"%s"' % key if isinstance(key, str) else "%d" % key


def lua_layout(names):
    """Media/IconSizes.lua: the sheets' layouts and each icon's file size"""
    lines = ["-- Generated by Tools/make_icon_sizes.py (Tools/icon_sizes.py): the sheets of MelloUI's icons made for the",
             "-- sizes they are drawn at, read by Core/Icons.lua. Do not edit by hand.",
             "--   sheets[file size] = { w, h, r, { copy width, x, y } ... }  (px on the sheet, from its top left; a copy",
             "--     is r of its width high: a square file's 1, an oblong one's, \"WxH\", its own)",
             "--   files[path under Media, no extension] = the file's size; its sheet: Media\\IconSizes\\<that path>",
             "local _, ns = ...",
             "ns.MelloUI.IconSizes = {",
             "\tsheets = {"]
    for key in sorted(SHEET, key=lambda k: (isinstance(k, str), str(k).zfill(8))):
        w, h, at = SHEET[key]
        fw, fh = dims(key)
        copies = ", ".join("{ %d, %d, %d }" % (s, at[s][0], at[s][1]) for s in sorted(at))
        lines.append("\t\t[%s] = { w = %d, h = %d, r = %s, %s }," % (lua_key(key), w, h, ("%g" % (fh / fw)), copies))
    lines.append("\t},")
    lines.append("\tfiles = {")
    for name in sorted(names):
        lines.append('\t\t["%s"] = %s,' % (name.replace("\\", "\\\\"), lua_key(names[name])))
    lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"
