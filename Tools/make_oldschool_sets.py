"""
Oldschool's three frame sets (2.1.58; the user, 2026-11-17: "im not satisfied with these elements currently: Unitframe,
Personal Resource, Nameplates, Chat Oldschool ... make sure that the new ones are all generated as 1 texture, which are
scalable horizontally and Vertically", then, to the three directions of round 1: "Why not just Make all 3, so that we
have 3 Variations"): the ChatGPT paintings turned into the textures MelloUI_Oldschool draws (Modules/KitSets.lua) and
the numbers it lays them by (Media/FrameSets.lua). Plan: docs/plans/oldschool-redesign.md.

The masters (read only): MelloUI-BuildData/masters/oldschool_redesign/sources -- <D>_sheet.png the direction's sheet
(round 1's pick page: the player frame, two bar frames, the cast bar with its icon socket, the nameplate with its level
socket, the chat frame), <D>_player.png the player frame painted round the green layout guide (the portrait window and
both bars in pure green, the game's geometry), <D>_small.png the small frame (target of target, focus target, pet,
party). D: A Gilded Stone, B Forged Iron, C Carved Wood.
  - the unit frames (the 2.1.0 pipeline, unchanged): the green holes found, the painting fitted onto the game's own
    geometry for its shape (uniform scale + shift, least squares on the holes; GEO from Tools/make_icons.py UF_FRAMES),
    the holes cut clear, drawn at 2 px per 2x texel; the target the player's painting mirrored. Measured on the result:
    each hole, the name plaque, the ring and the art's overhang; its soft shade.
  - every bar ONE texture the client cuts itself (SetTextureSliceMargins, Stretched): the sheet's piece at its own
    pixels, its ends (where its ornament is) kept, its plain middle stretched. The ends are found on the piece: the
    columns whose alpha and light match its middle's are plain, the first and last of them the ends' edges. The bars:
    plate (the Personal Display's health and power), cast (the cast bars: its icon socket at the start), shield (the
    plate stood upright), np (the nameplate: its level socket at the end), chat (the chat window: all four sides
    found the same way, its middle empty for the window's own background).
Every file a 32-bit TGA on a power-of-two canvas (the piece at its top left). Deterministic: the same masters give the
same bytes.

    python Tools/make_oldschool_sets.py            write them (MelloUI_Oldschool/Media/Sets/<Set>/, Media/FrameSets.lua)
    python Tools/make_oldschool_sets.py --check    exit 1 unless every file is up to date
    python Tools/make_oldschool_sets.py --sketch <folder>   also lay each set's check sketch from the built files there
"""
import io
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

from paths import ADDON, MASTERS

SRC = os.path.join(MASTERS, "oldschool_redesign", "sources")
OUT_DIR = os.path.join(ADDON, "MelloUI_Oldschool", "Media", "Sets")
DATA = os.path.join(ADDON, "MelloUI_Oldschool", "Media", "FrameSets.lua")

# (master, folder, id, the name players see) -- the configurator lists them in this order
SETS = (("A", "Stone", "stone", "Gilded Stone"), ("B", "Iron", "iron", "Forged Iron"),
        ("C", "Wood", "wood", "Carved Wood"))

OUT = 2.0          # texture px per 2x texel (UF_FRAMES' units): twice Modern's detail (fit_ornate.OUT)
PX_UNIT = 4.0      # texture px per UI unit (a 2x texel is half a unit)

# the game's geometry per shape, in 2x texels (Tools/make_icons.py UF_FRAMES): the ring (centre, opening radius), the
# health and power bars' insides (l, t, r, b), the frame picture's rect (w, h) -- fit_ornate.GEO
GEO = {
    "player": {"ring": (73, 71, 52), "health": (144, 65, 384, 90), "power": (144, 97, 384, 113), "rect": (396, 142)},
    "target": {"ring": (318.5, 67.5, 49.5), "health": (9, 58, 249, 84), "power": (9, 90, 249, 106), "rect": (388, 136)},
    "small": {"ring": (45, 45.5, 33), "health": (92, 38, 228, 55), "power": (92, 61, 228, 71), "rect": (240, 98)},
}

SHADE_SPREAD = 6   # the shade's reach past the picture (px of its quarter-size file), its blur
SHADE_BLUR = 5.0
END_PAD = 3        # px past the first plain column an end keeps (its ornament wholly in it)
# (the user, 2026-11-17: "outer glow on the nameplates of the targeted mob matching the shape of each nameplate type
# ... same thing with the mouseover and target heighlight on the unitframes") a painting's outer glow: its outline
# (its openings filled) blurred, outside it only -- the unit pictures' reach in px of their 4 px a unit, a bar's a share
# of its piece's height (so it grows with the bar)
GLOW_PAD_UNIT = 40
GLOW_SIGMA_UNIT = 10.0
GLOW_SHARE = 0.4    # (2.1.58, the user in game: "the outer glow is barely noticable": wider, with a bright band at the edge)


# ---- ported: ornate_sets.dechecker -----------------------------------------------------------------------------
def dechecker(img):
    """a sheet painted with a fake transparency checkerboard (ChatGPT does that): every patch of pale, unsaturated
    checker pixels bigger than a speck keyed clear (outside the pieces and inside their hollows), edges feathered"""
    a = np.asarray(img.convert("RGBA")).astype(np.float64)
    if (a[..., 3] < 250).mean() > 0.05:
        return img   # (real transparency already)
    rgb = a[..., :3]
    pale = (rgb.min(2) > 175) & (rgb.max(2) - rgb.min(2) < 22)
    lab, n = ndimage.label(pale)
    sizes = ndimage.sum(pale, lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes > 300
    clear = keep[lab]
    clear = ndimage.binary_closing(clear, iterations=1)
    soft = ndimage.gaussian_filter(clear.astype(float), 0.7)
    a[..., 3] = 255 * (1 - np.clip(soft * 1.4, 0, 1))
    a[:4, :, 3] = a[-4:, :, 3] = a[:, :4, 3] = a[:, -4:, 3] = 0   # (the sheet's own edge line)
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")


# ---- ported: fit_ornate (holes, fit, key_out, frame) -----------------------------------------------------------
def green_mask(a):
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (g > 150) & (g - np.maximum(r, b) > 80) & (a[..., 3] > 100)


def find_holes(img):
    a = np.asarray(img.convert("RGBA"))
    m = ndimage.binary_opening(green_mask(a), iterations=2)
    lab, _ = ndimage.label(m)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = sl
        area = int((lab[sl] == i).sum())
        if area > 2000:
            comps.append({"box": (xs.start, ys.start, xs.stop, ys.stop), "area": area,
                          "w": xs.stop - xs.start, "h": ys.stop - ys.start})
    ring = max(comps, key=lambda c: min(c["w"], c["h"]) / max(c["w"], c["h"]) * c["area"])
    bars = sorted([c for c in comps if c is not ring and c["w"] > 3 * c["h"]], key=lambda c: c["box"][1])
    if len(bars) < 2:
        raise SystemExit("found %d bar holes" % len(bars))
    l, t, r, b = ring["box"]
    return {"ring": ((l + r) / 2, (t + b) / 2, (r - l + b - t) / 4), "health": bars[0]["box"],
            "power": bars[1]["box"], "mask": m}


def fit(found, geo):
    """uniform scale s and shift mapping the result's px onto the shape's 2x texels (least squares on the holes)"""
    src, dst = [], []
    (cx, cy, r), (gx, gy, gr) = found["ring"], geo["ring"]
    src += [(cx, cy), (cx - r, cy), (cx + r, cy), (cx, cy - r), (cx, cy + r)]
    dst += [(gx, gy), (gx - gr, gy), (gx + gr, gy), (gx, gy - gr), (gx, gy + gr)]
    for k in ("health", "power"):
        l, t, rr, b = found[k]
        g = geo[k]
        src += [(l, t), (rr, t), (l, b), (rr, b)]
        dst += [(g[0], g[1]), (g[2], g[1]), (g[0], g[3]), (g[2], g[3])]
    S, D = np.array(src, float), np.array(dst, float)
    sm, dm = S.mean(0), D.mean(0)
    s = ((S - sm) * (D - dm)).sum() / ((S - sm) ** 2).sum()
    shift = dm - s * sm
    return s, shift, float(np.abs(S * s + shift - D).max())


def key_out(img, mask):
    a = np.asarray(img.convert("RGBA")).astype(np.float64)
    near = ndimage.binary_dilation(mask, iterations=3)
    a[near, 3] = 0
    rim = ndimage.binary_dilation(near, iterations=3) & ~near
    g = a[..., 1]
    over = np.clip(g - np.maximum(a[..., 0], a[..., 2]), 0, None)
    a[rim, 1] = g[rim] - over[rim]
    grey = (np.abs(a[..., 0] - 127) < 6) & (np.abs(a[..., 1] - 127) < 6) & (np.abs(a[..., 2] - 127) < 6)
    a[grey, 3] = 0
    a[a[..., 3] <= 8, 3] = 0
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")


def fitted(src, shape):
    """fit_ornate.frame: the art at OUT px per 2x texel, cropped to its pixels; `at` its top left against the game
    rect's top left (px)"""
    geo = GEO[shape]
    src = dechecker(src)
    found = find_holes(src)
    s, shift, err = fit(found, geo)
    art = key_out(src, found["mask"])
    k = s * OUT
    big = art.convert("RGBa").resize((round(art.width * k), round(art.height * k)), Image.LANCZOS).convert("RGBA")
    al = np.asarray(big)[..., 3]
    big = Image.fromarray(np.dstack([np.asarray(big)[..., :3], np.where(al > 8, al, 0)]).astype(np.uint8), "RGBA")
    bbox = big.getbbox()
    crop = big.crop(bbox)
    at = (bbox[0] + shift[0] * OUT, bbox[1] + shift[1] * OUT)
    return crop, at, s, err


def no_green(img):
    """a leftover speck of the guide's green (outside the keyed holes) put back to the metal's own hue"""
    a = np.asarray(img).astype(np.int32).copy()
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = (g - np.maximum(r, b) > 40) & (g > 90) & (a[..., 3] > 0)
    a[..., 1] = np.where(green, np.maximum(r, b), g)
    return Image.fromarray(a.astype(np.uint8), "RGBA"), int(green.sum())


# ---- ported: build_themes (interior) -------------------------------------------------------------
def interior(piece):
    """a hollow frame's inside: the clear pixels joined to its middle"""
    a = np.asarray(piece)[..., 3] < 128
    lab, _ = ndimage.label(a)
    mid = lab[a.shape[0] // 2, a.shape[1] // 2]
    return (lab == mid) if mid else np.zeros_like(a)


def box_of(mask):
    ys, xs = np.nonzero(mask)
    if not len(xs):
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


# ---- the files ---------------------------------------------------------------------------------------------------
def pot(n):
    p = 1
    while p < n:
        p *= 2
    return p


def scaled(img, w, h):
    """premultiplied Lanczos (no dark fringe), alpha specks under 8 cleared"""
    out = img.convert("RGBa").resize((max(1, round(w)), max(1, round(h))), Image.LANCZOS).convert("RGBA")
    a = np.asarray(out).copy()
    a[a[..., 3] <= 8] = 0
    return Image.fromarray(a, "RGBA")


def canvas(img):
    """the picture at the top left of a power-of-two canvas: (canvas, its share across, its share down)"""
    w, h = img.size
    c = Image.new("RGBA", (pot(w), pot(h)), (0, 0, 0, 0))
    c.paste(img, (0, 0))
    return c, w / c.width, h / c.height


def tga(img):
    buf = io.BytesIO()
    img.save(buf, format="TGA")
    return buf.getvalue()


def r1(v):
    return round(float(v), 2)


# ---- the outer glow (2.1.58) -----------------------------------------------------------------------------------------
def glow_of(img, pad, sigma):
    """a painting's outer glow: white, on a canvas `pad` px larger on every side; the outline (alpha, its openings
    filled) glowing -- a bright band hugging the edge over a wide soft halo -- nothing inside it (drawn additively in
    the game: it lights the ground round the frame, bright or dark)"""
    a = np.asarray(img)[..., 3] > 40
    h, w = a.shape
    sil = np.zeros((h + 2 * pad, w + 2 * pad), bool)
    sil[pad:pad + h, pad:pad + w] = ndimage.binary_fill_holes(a)
    band = ndimage.binary_dilation(sil, iterations=max(2, pad // 8))
    core = np.clip(ndimage.gaussian_filter(band.astype(np.float64), sigma * 0.3) * 2.2, 0, 1)
    halo = np.clip(ndimage.gaussian_filter(band.astype(np.float64), sigma) * 2.4, 0, 1) ** 0.6
    inside = ndimage.gaussian_filter(sil.astype(np.float64), 0.8)
    g = np.maximum(core, 0.8 * halo) * (1 - inside)
    out = np.zeros(g.shape + (4,), np.uint8)
    out[..., :3] = 255
    out[..., 3] = (g * 255).round().astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def glow_rect(size=96, pad=24, sigma=7.0):
    """the raid cells' glow: a rounded box's outer glow, sliced by the client round any cell (pad px each side)"""
    inner = Image.new("RGBA", (size - 2 * pad, size - 2 * pad), (255, 255, 255, 255))
    return glow_of(inner, pad, sigma)


def plate_box(alpha, rcx, ro, shape):
    """the bars' part of a unit picture -- the columns past the ring's outer edge, on the bars' side -- as px (l, t, r,
    b): the rim the frame effects light (Unit Frames' PlateOf)"""
    h, w = alpha.shape
    solid = alpha > 40
    if shape == "target":
        cols = np.arange(w) < rcx - ro * 0.98
    else:
        cols = np.arange(w) > rcx + ro * 0.98
    part = solid[:, cols]
    ys = np.nonzero(part.any(axis=1))[0]
    xs = np.nonzero(cols)[0][np.nonzero(part.any(axis=0))[0]]
    if not len(ys) or not len(xs):
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


# ---- the unit frames --------------------------------------------------------------------------------------------
def clear_box(alpha, x, y):
    """the clear component of the picture's alpha that holds px (x, y): its box (l, t, r, b), px"""
    clear = alpha < 128
    lab, _ = ndimage.label(clear)
    i = lab[int(round(y)), int(round(x))]
    return box_of(lab == i) if i else None


PLAQUE_DARK = 78   # the plaque's slate (its luminance, smoothed over its grain) is under this; its bevels far over


def ring_outer(alpha, cx, cy, ropen, shape):
    """the painted ring's outer edge (px from its centre): along each ray over the half away from the bars, the first
    radius past the opening where the art goes clear for 3 px; the median (the combo points hang past it)"""
    h, w = alpha.shape
    side = 1 if shape == "target" else -1   # (the ring's free side: the target's right, the others' left)
    found = []
    for deg in range(-80, 81, 4):
        a = np.radians(deg)
        dx, dy = side * np.cos(a), -np.sin(a)
        clear, rad = 0, ropen + 2
        while rad < ropen * 3:
            x, y = int(round(cx + dx * rad)), int(round(cy + dy * rad))
            if not (0 <= x < w and 0 <= y < h) or alpha[y, x] < 40:
                clear += 1
                if clear >= 3:
                    found.append(rad - 2)
                    break
            else:
                clear = 0
            rad += 1
    return float(np.median(found)) if found else ropen * 1.25


def otsu(values):
    """the split between two classes of values that leaves each tightest (Otsu): the dark rows' and the light ones'"""
    v = np.sort(np.asarray(values, np.float64))
    if len(v) < 4:
        return PLAQUE_DARK
    best, split = -1.0, PLAQUE_DARK
    for i in range(2, len(v) - 1):
        a, b = v[:i], v[i:]
        between = len(a) * len(b) * (a.mean() - b.mean()) ** 2
        if between > best:
            best, split = between, (v[i - 1] + v[i]) / 2
    return split


def plaque(art, health):
    """the name plaque: the dark slate over the health hole -- the longest run of dark rows above the bar's own top rim
    (each row's median light over the hole's middle 70 %, so a painted crack or scratch never splits it), then its
    width: the dark run each way from the middle along those rows' median light (px box)"""
    a = np.asarray(art).astype(np.float64)
    alpha = a[..., 3]
    l, t, r, _ = health
    lum = ndimage.gaussian_filter((a[..., 0] * 3 + a[..., 1] * 6 + a[..., 2]) / 10, 1.5)
    x0, x1 = int(l + 0.15 * (r - l)), int(r - 0.15 * (r - l))
    med = np.full(t, 999.0)
    for y in range(t):
        op = alpha[y, x0:x1] > 200
        if op.mean() > 0.9:
            med[y] = np.median(lum[y, x0:x1][op])
    # (dark from light by the rows' own two classes -- Otsu's split of their medians: the slate, its shade and grain on
    # one side, the rims' metal or inlay on the other -- never over PLAQUE_DARK)
    limit = min(PLAQUE_DARK, otsu(med[med < 999]))
    dark = med < limit
    best, run, start = None, 0, None
    for y in range(t + 1):
        on = y < t and dark[y]
        if on and start is None:
            start = y
        elif not on and start is not None:
            if y - start > run and y < t - 2:   # (a run ending on the hole is the bar's own rim's shade)
                best, run = (start, y), y - start
            start = None
    if best is None or run < 6:
        return None
    y0, y1 = best
    band = np.median(np.where(alpha[y0:y1] > 200, lum[y0:y1], 999.0), axis=0)
    cx = (l + r) // 2
    xa = cx
    while xa > l and band[xa - 1] < limit:
        xa -= 1
    xb = cx
    while xb < r and band[xb] < limit:
        xb += 1
    return xa, y0, xb, y1


def shade_of(art):
    """the soft shade under the picture: its alpha spread and blurred, at a quarter of its size, black"""
    q = 4
    w, h = art.size
    m = SHADE_SPREAD * 2
    small = art.split()[3].resize((max(1, round(w / q)), max(1, round(h / q))), Image.BILINEAR)
    a = np.zeros((small.height + 2 * m, small.width + 2 * m))
    a[m:m + small.height, m:m + small.width] = np.asarray(small) / 255.0
    a = ndimage.grey_dilation(a, size=(3, 3))
    a = ndimage.gaussian_filter(a, SHADE_BLUR)
    a = np.clip(a / max(a.max(), 1e-6), 0, 1)
    out = np.zeros(a.shape + (4,), np.uint8)
    out[..., 3] = (a * 255).round().astype(np.uint8)
    return Image.fromarray(out, "RGBA"), m * q, q


def unit(src, shape, files, log):
    geo = GEO[shape]
    art, at, s, err = fitted(src, shape)
    art, specks = no_green(art)
    alpha = np.asarray(art)[..., 3]
    ox, oy = at
    rw, rh = geo["rect"][0] / 2, geo["rect"][1] / 2   # the game picture in UI units
    data = {"w": r1(art.width / PX_UNIT), "h": r1(art.height / PX_UNIT), "x": r1(ox / PX_UNIT), "y": r1(oy / PX_UNIT),
            "rw": rw, "rh": rh}
    # (each hole as the painting has it, in UI units from the game picture's top left)
    holes = {}
    for k in ("health", "power"):
        l, t, r, b = geo[k]
        box = clear_box(alpha, (l + r) / 2 * OUT - ox, (t + b) / 2 * OUT - oy)
        if not box:
            raise SystemExit("%s: no %s hole" % (shape, k))
        holes[k] = box
        data[k] = [r1((box[0] + ox) / PX_UNIT), r1((box[1] + oy) / PX_UNIT), r1((box[2] + ox) / PX_UNIT),
                   r1((box[3] + oy) / PX_UNIT)]
        # the game bar's own rect past the hole lies under the painted rim: it must be solid there
        gl, gt, gr, gb = (round(v * OUT - o) for v, o in zip(geo[k], (ox, oy, ox, oy)))
        under = alpha[max(gt, 0):gb, max(gl, 0):gr].astype(np.int32)
        inside = np.zeros_like(alpha, bool)
        inside[box[1]:box[3], box[0]:box[2]] = True
        rim = ~inside[max(gt, 0):gb, max(gl, 0):gr]
        thin = int(((under < 230) & rim).sum())
        log.append("    %s hole %s units (game %s); under the rim, %d px not solid" % (
            k, data[k], [v / 2 for v in geo[k]], thin))
    cx, cy, rr = geo["ring"]
    rbox = clear_box(alpha, cx * OUT - ox, cy * OUT - oy)
    rcx, rcy = (rbox[0] + rbox[2]) / 2, (rbox[1] + rbox[3]) / 2
    ropen = min(rbox[2] - rbox[0], rbox[3] - rbox[1]) / 2
    data["ring"] = [r1((rcx + ox) / PX_UNIT), r1((rcy + oy) / PX_UNIT), r1(ropen / PX_UNIT),
                    r1(ring_outer(alpha, rcx, rcy, ropen, shape) / PX_UNIT)]
    pl = plaque(art, holes["health"])
    if pl:
        inset = 2   # (px: the plaque's own bevel)
        data["plaque"] = [r1((pl[0] + inset + ox) / PX_UNIT), r1((pl[1] + inset + oy) / PX_UNIT),
                          r1((pl[2] - inset + ox) / PX_UNIT), r1((pl[3] - inset + oy) / PX_UNIT)]
    c, u, v = canvas(art)
    data["u"], data["v"] = r1(u * 10000) / 10000, r1(v * 10000) / 10000
    files[shape] = c
    sh, pad, q = shade_of(art)
    sc, su, sv = canvas(sh)
    files[shape + "_shade"] = sc
    data["shade"] = {"x": r1((ox - pad) / PX_UNIT), "y": r1((oy - pad) / PX_UNIT), "w": r1(sh.width * q / PX_UNIT),
                     "h": r1(sh.height * q / PX_UNIT), "u": r1(su * 10000) / 10000, "v": r1(sv * 10000) / 10000}
    # (2.1.58) its outer glow (target and mouseover), laid as the shade is; the bars' rim (the frame effects' plate)
    gl = glow_of(art, GLOW_PAD_UNIT, GLOW_SIGMA_UNIT)
    gc, gu, gv = canvas(gl)
    files[shape + "_glow"] = gc
    data["glow"] = {"x": r1((ox - GLOW_PAD_UNIT) / PX_UNIT), "y": r1((oy - GLOW_PAD_UNIT) / PX_UNIT),
                    "w": r1(gl.width / PX_UNIT), "h": r1(gl.height / PX_UNIT),
                    "u": r1(gu * 10000) / 10000, "v": r1(gv * 10000) / 10000}
    pb = plate_box(alpha, rcx, ring_outer(alpha, rcx, rcy, ropen, shape), shape)
    if pb:
        data["plate"] = [r1(pb[0] / art.width * 1000) / 1000, r1(pb[1] / art.height * 1000) / 1000,
                         r1(pb[2] / art.width * 1000) / 1000, r1(pb[3] / art.height * 1000) / 1000]
    log.append("  %s: scale %.3f, worst hole miss %.1f texels, art %dx%d at %s px, canvas %dx%d, %d green px" % (
        shape, s, err, art.width, art.height, tuple(round(v) for v in at), c.width, c.height, specks))
    return data, art, at


# ---- the bars: one texture each, cut by the client -------------------------------------------------------------------
def sheet_pieces(sheet):
    """round 1's sheet: the player frame (top left), the two bar frames and the cast bar (top right, from the top),
    the nameplate (bottom left), the chat frame (bottom right) -- each cropped to its pixels"""
    a = np.asarray(sheet)[..., 3] > 90
    lab, _ = ndimage.label(ndimage.binary_dilation(a, iterations=2))
    W, H = sheet.size
    quads = {"tl": [], "tr": [], "bl": [], "br": []}
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = sl
        if (lab[sl] == i).sum() < 2000:
            continue
        cx, cy = (xs.start + xs.stop) / 2, (ys.start + ys.stop) / 2
        quads[("t" if cy < H * 0.45 else "b") + ("l" if cx < W / 2 else "r")].append((xs.start, ys.start, xs.stop, ys.stop))
    bars = sorted(quads["tr"], key=lambda c: c[1])
    if len(bars) != 3 or not quads["bl"] or not quads["br"]:
        raise SystemExit("sheet: %d bar pieces (3 wanted), %d nameplate, %d chat" % (len(bars), len(quads["bl"]),
                                                                                    len(quads["br"])))
    area = lambda c: (c[2] - c[0]) * (c[3] - c[1])

    def crop(box):
        img = sheet.crop(box)
        return img.crop(img.getbbox())
    return {"plate": crop(bars[0]), "cast": crop(bars[2]), "np": crop(max(quads["bl"], key=area)),
            "chat": crop(max(quads["br"], key=area))}


def plain_span(p, axis=0):
    """the plain middle along the piece's length (axis 0: across its columns; 1: down its rows): the columns whose
    alpha and light down them match the middle fifth's within twice that fifth's own spread -- (first, last) px"""
    a = np.asarray(p).astype(np.float64)
    if axis == 1:
        a = a.transpose(1, 0, 2)
    alpha = a[..., 3] / 255.0
    lum = (a[..., 0] * 3 + a[..., 1] * 6 + a[..., 2]) / 2550.0 * alpha
    prof = np.concatenate([alpha, lum], axis=0)
    w = prof.shape[1]
    m0, m1 = w * 2 // 5, w * 3 // 5
    ref = np.median(prof[:, m0:m1], axis=1)
    d = ndimage.uniform_filter1d(np.abs(prof - ref[:, None]).mean(0), 5)
    ok = d <= max(np.percentile(d[m0:m1], 95) * 2.0, 0.015)
    lo = hi = w // 2
    while lo > 0 and ok[lo - 1]:
        lo -= 1
    while hi < w - 1 and ok[hi + 1]:
        hi += 1
    return lo, hi


def enclosed(p):
    """the clear patches of a piece that touch none of its edges: boxes (l, t, r, b px) with their areas"""
    a = np.asarray(p)[..., 3] < 128
    lab, _ = ndimage.label(a)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])).tolist())
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        if sl is None or i in edge:
            continue
        ys, xs = sl
        out.append(((xs.start, ys.start, xs.stop, ys.stop), int((lab[sl] == i).sum())))
    return out


def sliced(piece, name, files, both=False):
    """a piece as one sliced texture: its ends (the margins, px) round its plain middle, its hole (the clear patch
    joined to its middle) and its canvas share. `both`: margins on all four sides (the chat window)"""
    lo, hi = plain_span(piece, 0)
    w, h = piece.size
    left, right = min(lo + END_PAD, w // 2 - 1), min(w - 1 - hi + END_PAD, w // 2 - 1)
    top = bottom = 0
    if both:
        vlo, vhi = plain_span(piece, 1)
        top, bottom = min(vlo + END_PAD, h // 2 - 1), min(h - 1 - vhi + END_PAD, h // 2 - 1)
    hole = box_of(interior(piece))
    if not hole:
        raise SystemExit("%s: no hole" % name)
    c, u, v = canvas(piece)
    files[name] = c
    return {"w": w, "h": h, "margins": [left, top, right, bottom], "hole": list(hole),
            "u": r1(u * 10000) / 10000, "v": r1(v * 10000) / 10000}


def socket(piece, hole, side):
    """the clear patch beside the hole -- the cast bar's icon socket (its start) or the nameplate's level socket (its
    end): the biggest enclosed patch wholly on that side of the hole (px box), or None"""
    best, area = None, 0
    for box, n in enclosed(piece):
        if (side == "start" and box[2] <= hole[0] + 2) or (side == "end" and box[0] >= hole[2] - 2):
            if n > area:
                best, area = list(box), n
    return best


def bars(src, files, log):
    with Image.open(src) as im:
        b = sheet_pieces(dechecker(im.convert("RGBA")))
    data = {}
    data["plate"] = sliced(b["plate"], "plate", files)
    data["cast"] = sliced(b["cast"], "cast", files)
    data["cast"]["icon"] = socket(b["cast"], data["cast"]["hole"], "start")
    data["np"] = sliced(b["np"], "np", files)
    data["np"]["badge"] = socket(b["np"], data["np"]["hole"], "end")
    if data["np"]["badge"]:
        bl, bt, br, bb = data["np"]["badge"]
        na = np.asarray(b["np"])[..., 3]
        bcx, bcy = (bl + br) / 2, (bt + bb) / 2
        rad = (br - bl) / 2 + 1
        while bcx + rad < na.shape[1] - 1 and na[int(bcy), int(bcx + rad)] > 60:
            rad += 1
        data["np"]["socketOuter"] = r1(rad)
    # (the shield column: the plate stood upright -- turned clockwise, its start at the top, its top rail on the right)
    up = b["plate"].rotate(-90, expand=True)
    lo, hi = plain_span(up, 1)
    w, h = up.size
    files["shield"], u, v = canvas(up)
    data["shield"] = {"w": w, "h": h, "hole": list(box_of(interior(up))),
                      "margins": [0, min(lo + END_PAD, h // 2 - 1), 0, min(h - 1 - hi + END_PAD, h // 2 - 1)],
                      "u": r1(u * 10000) / 10000, "v": r1(v * 10000) / 10000}
    data["chat"] = sliced(b["chat"], "chat", files, both=True)
    # (2.1.58) the nameplate's outer glow (the target's): the piece's outline glowing, cut by the client as the piece
    # is -- its ends (the piece's, `pad` further out) kept, its plain middle stretched -- at the piece's scale
    np_p = b["np"]
    pad = max(6, round(np_p.height * GLOW_SHARE))
    gl = glow_of(np_p, pad, pad / 3.2)
    gc, gu, gv = canvas(gl)
    files["np_glow"] = gc
    m = data["np"]["margins"]
    data["np"]["glow"] = {"w": gl.width, "h": gl.height, "pad": pad, "margins": [m[0] + pad, 0, m[2] + pad, 0],
                          "u": r1(gu * 10000) / 10000, "v": r1(gv * 10000) / 10000}
    for k in ("plate", "cast", "np", "shield", "chat"):
        d = data[k]
        extra = ", icon %s" % d["icon"] if d.get("icon") else (", badge %s" % d["badge"] if d.get("badge") else "")
        log.append("  %s: %dx%d px, margins %s, hole %s%s" % (k, d["w"], d["h"], d["margins"], d["hole"], extra))
        if k == "cast" and not d.get("icon"):
            raise SystemExit("cast: no icon socket found")
        if k == "np" and not d.get("badge"):
            raise SystemExit("np: no level socket found")
    return data, b


# ---- the level badge (2.1.58; the user: "the level ring on the new Unitframes dont match anymore, they need to match
# their style") -- its own painting per set, <D>_level.png: cut to its pixels, its round opening (the clear patch at
# its middle) the number's place; drawn on a unit frame's level circle, its opening on the circle
def level(src, files, log):
    if not os.path.exists(src):
        log.append("  level: no %s yet (the kit's orb stays)" % os.path.basename(src))
        return None
    with Image.open(src) as im:
        img = dechecker(im.convert("RGBA"))
    a = np.asarray(img).copy()
    a[a[..., 3] <= 8] = 0   # (ChatGPT's near-clear specks all over the canvas: never the badge's own box)
    img = Image.fromarray(a, "RGBA")
    img = img.crop(img.getbbox())
    hole = box_of(interior(img))
    if not hole:
        raise SystemExit("%s: no opening found" % src)
    side = 256
    k = side / max(img.size)
    img = scaled(img, img.width * k, img.height * k)
    hole = box_of(interior(img))
    c, u, v = canvas(img)
    files["level"] = c
    log.append("  level: %dx%d px, opening %s" % (img.width, img.height, hole))
    return {"w": img.width, "h": img.height, "hole": list(hole), "u": r1(u * 10000) / 10000,
            "v": r1(v * 10000) / 10000}


# ---- the rank pieces (2.1.58; the user, 2026-11-17: "We also need Nameplates and Unitframes for Rare, Elite, Rare Elite
# and Boss enemies", then "Yes, build them") -- <D>_ranks.png: the top row four portrait rings, each wearing its rank's
# ornament (elite, rare elite, rare, boss, left to right), the bottom row the same on four small level sockets. Each
# piece cut to its pixels at its own size: its round opening (centre, radius) and its ring's outer edge (along rays
# through its lower half: the ornament stands on the top) measured -- the game lays the ring's outer edge on the frame
# ring's (Modules/KitSets.lua Sets.Rank) or on the plate socket's (StripMixin:Rank)
RANK_KINDS = ("elite", "rareelite", "rare", "boss")


def rank_opening(img):
    a = np.asarray(img)[..., 3] < 90
    lab, _ = ndimage.label(a)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])).tolist())
    best = None
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        if sl is None or i in edge:
            continue
        n = int((lab[sl] == i).sum())
        if not best or n > best[0]:
            ys, xs = sl
            best = (n, (xs.start + xs.stop) / 2, (ys.start + ys.stop) / 2,
                    ((xs.stop - xs.start) + (ys.stop - ys.start)) / 4)
    if not best:
        raise SystemExit("rank piece: no opening")
    return best[1:]


def rank_outer(img, cx, cy, r0):
    a = np.asarray(img)[..., 3]
    h, w = a.shape
    found = []
    for deg in range(20, 161, 10):
        t = np.radians(deg)
        dx, dy = np.cos(t), np.sin(t)
        rad = r0 + 2
        while rad < r0 * 3:
            x, y = int(round(cx + dx * rad)), int(round(cy + dy * rad))
            if not (0 <= x < w and 0 <= y < h) or a[y, x] < 60:
                found.append(rad)
                break
            rad += 1
    return float(np.median(found)) if found else r0 * 1.3


def ranks(src, files, log):
    if not os.path.exists(src):
        log.append("  ranks: no %s yet" % os.path.basename(src))
        return None, None
    with Image.open(src) as im:
        sheet = dechecker(im.convert("RGBA"))
    a = np.asarray(sheet).copy()
    a[a[..., 3] <= 8] = 0
    sheet = Image.fromarray(a, "RGBA")
    mask = np.asarray(sheet)[..., 3] > 60
    lab, _ = ndimage.label(ndimage.binary_dilation(mask, iterations=3))
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = sl
        if (lab[sl] == i).sum() >= 1500:
            comps.append((xs.start, ys.start, xs.stop, ys.stop))
    if len(comps) < 8:
        raise SystemExit("%s: %d pieces (8 wanted)" % (src, len(comps)))
    comps.sort(key=lambda c: (c[2] - c[0]) * (c[3] - c[1]), reverse=True)
    big, small = sorted(comps[:4], key=lambda c: c[0]), sorted(comps[4:8], key=lambda c: c[0])
    out = {}
    for prefix, row in (("rank", big), ("np_rank", small)):
        out[prefix] = {}
        for kind, box in zip(RANK_KINDS, row):
            img = sheet.crop(box)
            img = img.crop(img.getbbox())
            cx, cy, r0 = rank_opening(img)
            ro = rank_outer(img, cx, cy, r0)
            c, u, v = canvas(img)
            files["%s_%s" % (prefix, kind)] = c
            out[prefix][kind] = {"w": img.width, "h": img.height, "cx": r1(cx), "cy": r1(cy), "open": r1(r0),
                                 "outer": r1(ro), "u": r1(u * 10000) / 10000, "v": r1(v * 10000) / 10000}
            log.append("  %s %s: %dx%d px, opening %.0f, outer %.0f" % (prefix, kind, img.width, img.height, r0, ro))
    return out["rank"], out["np_rank"]


# ---- the data file ---------------------------------------------------------------------------------------------------
def lua(v, ind=""):
    if isinstance(v, dict):
        inner = ind + "\t"
        parts = []
        for k in sorted(v, key=lambda x: (not isinstance(v[x], (int, float, str)), str(x))):
            key = k if k.isidentifier() else '["%s"]' % k
            parts.append("%s%s = %s," % (inner, key, lua(v[k], inner)))
        return "{\n" + "\n".join(parts) + "\n" + ind + "}"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x, ind) for x in v) + " }"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        s = ("%.4f" % v).rstrip("0").rstrip(".")
        return s if s not in ("-0", "") else "0"
    return str(v)


HEADER = """--------------------------------------------------------------------------------
-- MelloUI Oldschool - the three frame sets' numbers (2.1.58). Made by Tools/make_oldschool_sets.py from the
-- paintings (docs/plans/oldschool-redesign.md): do not edit by hand, run the tool again.
--   unit.<player|target|small>: the picture (Sets/<dir>/<shape>.tga) laid from the game picture's top left -- x, y
--     (down) and w, h in UI units for a game picture of rw x rh (u, v its share of the file); its holes as the
--     painting has them (health, power: l, t, r, b; ring: x, y, radius, outer edge), the name plaque, the soft shade
--   plate, cast, shield, np, chat: ONE texture each (Sets/<dir>/<kind>.tga), cut by the client
--     (SetTextureSliceMargins, Stretched) -- w, h the piece (px), margins (left, top, right, bottom px: its ends,
--     kept), hole (l, t, r, b px: the bar's or the window's inside), u, v its share of the file; cast.icon its icon
--     socket, np.badge its level socket (px boxes); the shield's piece upright (its start at the top)
--   unit.<shape>.glow: the picture's outer glow (Sets/<dir>/<shape>_glow.tga), laid as the shade; unit.<shape>.plate:
--     the bars' rim as shares of the picture (l, t, r, b: Unit Frames' PlateOf for the frame effects)
--   np.glow: the nameplate's outer glow, cut by the client as the piece (w, h px, pad px past the piece each side,
--     margins); level: the set's level badge (Sets/<dir>/level.tga: w, h, its opening's box px, u, v)
--   rect: the raid cells' glow (Sets/glow_rect.tga: size px, pad px past the cell)
--   rank.<elite|rareelite|rare|boss>: a portrait ring wearing the rank's ornament (Sets/<dir>/rank_<kind>.tga: w, h,
--     its opening's centre cx, cy and radius `open`, its ring's outer radius `outer`, px); np_rank.<kind> the same on a
--     small level socket (np_rank_<kind>.tga); np.socketOuter: the plate socket ring's outer radius (px of np)
--------------------------------------------------------------------------------
local _, ns = ...
"""


def build(sketch_dir=None):
    files, data, log = {}, {"order": [s[2] for s in SETS]}, []
    for d, folder, sid, label in SETS:
        log.append("%s (%s)" % (label, d))
        sfiles = {}
        with Image.open(os.path.join(SRC, d + "_player.png")) as im:
            player = im.convert("RGBA")
        with Image.open(os.path.join(SRC, d + "_small.png")) as im:
            small = im.convert("RGBA")
        units, made = {}, {}
        for shape, src in (("player", player), ("target", player.transpose(Image.FLIP_LEFT_RIGHT)), ("small", small)):
            units[shape], art, at = unit(src, shape, sfiles, log)
            made[shape] = (art, at)
        bd, pieces = bars(os.path.join(SRC, d + "_sheet.png"), sfiles, log)
        entry = {"label": label, "dir": folder, "unit": units}
        entry.update(bd)
        lv = level(os.path.join(SRC, d + "_level.png"), sfiles, log)
        if lv:
            entry["level"] = lv
        rk, nrk = ranks(os.path.join(SRC, d + "_ranks.png"), sfiles, log)
        if rk:
            entry["rank"], entry["np_rank"] = rk, nrk
        data[sid] = entry
        for name, img in sfiles.items():
            files[os.path.join(OUT_DIR, folder, name + ".tga")] = tga(img)
        if sketch_dir:
            os.makedirs(sketch_dir, exist_ok=True)
            sketch(entry, sfiles, made).convert("RGB").save(os.path.join(sketch_dir, "%s_built.png" % d))
    files[os.path.join(OUT_DIR, "glow_rect.tga")] = tga(canvas(glow_rect())[0])
    data["rect"] = {"size": 96, "pad": 24}
    body = HEADER + "ns.FrameSetsData = " + lua(data) + "\n"
    files[DATA] = body.replace("\r\n", "\n").encode("utf-8")
    return files, log


# ---- a check sketch from the built files: the unit frames at the game's 2 px a unit, each bar laid as the client cuts
# it (its ends kept, its middle stretched) at a long and a short length
def nine(img, d, w, k):
    """the client's cut, drawn here: the piece (its canvas share) at scale k (its ends and margins scaled with it, as
    the texture's scale does) stretched to w px along -- or, for an upright piece (d["w"] < d["h"]), w px down"""
    p = img.crop((0, 0, d["w"], d["h"]))
    l, t, r, b = (round(v * k) for v in d["margins"])
    pw, ph = round(d["w"] * k), round(d["h"] * k)
    p = scaled(p, pw, ph)
    W, H = (pw, w) if d["w"] < d["h"] else (w, ph)
    if d.get("both"):
        W, H = w
    xs = [(0, l, 0, l), (l, pw - r, l, W - r), (pw - r, pw, W - r, W)]
    ys = [(0, t, 0, t), (t, ph - b, t, H - b), (ph - b, ph, H - b, H)]
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            if sx1 > sx0 and sy1 > sy0 and dx1 > dx0 and dy1 > dy0:
                out.alpha_composite(scaled(p.crop((sx0, sy0, sx1, sy1)), dx1 - dx0, dy1 - dy0), (dx0, dy0))
    return out


def sketch(entry, sfiles, made):
    W, H = 1700, 900
    img = Image.new("RGBA", (W, H), (120, 116, 108, 255))
    d = ImageDraw.Draw(img)
    for shape, (px, py) in {"player": (30, 40), "target": (560, 40), "small": (1100, 60)}.items():
        u = entry["unit"][shape]
        art, at = made[shape]
        x0, y0 = px - min(0, u["x"]) * 2, py - min(0, u["y"]) * 2
        for k, col in (("health", (40, 170, 60)), ("power", (40, 90, 210))):
            l, t, r, b = u[k]
            d.rectangle((x0 + l * 2, y0 + t * 2, x0 + r * 2, y0 + b * 2), fill=(14, 12, 10, 255))
            d.rectangle((x0 + l * 2, y0 + t * 2, x0 + (l + (r - l) * 0.8) * 2, y0 + b * 2), fill=col + (255,))
        half = scaled(art, art.width * 0.5, art.height * 0.5)
        img.alpha_composite(half, (round(x0 + u["x"] * 2), round(y0 + u["y"] * 2)))
        if u.get("plaque"):
            l, t, r, b = u["plaque"]
            d.rectangle((x0 + l * 2, y0 + t * 2, x0 + r * 2, y0 + b * 2), outline=(255, 60, 60, 255))
    y = 300
    for kind, lengths in (("plate", (520, 260)), ("cast", (520, 260)), ("np", (300, 170))):
        dd = entry[kind]
        x = 30
        for L in lengths:
            piece = nine(sfiles[kind], dd, L, 0.6)
            img.alpha_composite(piece, (x, y))
            x += L + 40
        y += round(dd["h"] * 0.6) + 20
    img.alpha_composite(nine(sfiles["shield"], entry["shield"], 300, 0.6), (1000, 300))
    cd = dict(entry["chat"], both=True)
    img.alpha_composite(nine(sfiles["chat"], cd, (560, 300), 0.6), (1100, 300))
    img.alpha_composite(nine(sfiles["chat"], cd, (420, 200), 0.6), (1100, 640))
    return img


def main():
    args = sys.argv[1:]
    check = "--check" in args
    sketch_dir = None
    if "--sketch" in args:
        i = args.index("--sketch")
        sketch_dir = args[i + 1] if i + 1 < len(args) else None
    bad = [a for a in args if a not in ("--check", "--sketch", sketch_dir)]
    if bad or ("--sketch" in args and not sketch_dir):
        print("unknown argument: %s (nothing written)\n" % " ".join(bad or ["--sketch"]))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    files, log = build(sketch_dir)
    stale = []
    for path, data in sorted(files.items()):
        old = None
        if os.path.exists(path):
            with open(path, "rb") as f:
                old = f.read()
        if old != data:
            stale.append(path)
            if not check:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(data)
    if check:
        if stale:
            print("%d of %d files out of date:" % (len(stale), len(files)))
            for p in stale:
                print("  " + os.path.relpath(p, ADDON))
            return 1
        print("all %d files up to date" % len(files))
        return 0
    print("\n".join(log))
    print("%d files, %d written" % (len(files), len(stale)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
