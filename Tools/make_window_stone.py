"""
make_window_stone.py -- the thin stone window look (2026-10-10: a lighter, thinner window "in the style" of two RPG UI
packs the user owns, drawn as MelloUI's OWN art). Nothing is copied, traced, sampled or cropped from the packs: every
pixel here is painted in code, its grain, mottling and cracks generated noise (seeded, so a run is repeatable).

    window/stone_tl, _tr, _bl, _br   24 x 24   the rail's rounded outer corners (radius ~6), the profile swept round
    window/stone_t, _b               128 x 24  the rail's edges, tile seamlessly along x
    window/stone_l, _r               24 x 128  ... along y
    window/ribbon_cap_l, _cap_r      48 x 56   the red ribbon title strip's ends: its iron frame round the end, an iron
                                               chevron pointing inward over the ribbon's end
    window/ribbon_mid                128 x 56  ... its middle (tiles along x), clean for the title
    window/band_cap_l, _cap_r        24 x 56   the plain header band's ends: its rail line ended round
    window/band_mid                  128 x 56  ... its middle: the window's ground (#1F1B16), a half-thickness rail line
                                               along its bottom (tiles along x)

Painted at 2x (the kit's convention), transparent outside the art. The rail's profile, from its outer edge inward:
a 2 px near-black outline; a 15 px band of dark grey-green stone (fine grain, faint strata along the rail, a few
hairline cracks) whose outer pixel is a 1 px bevel, lit from the top left (top and left a little lighter, bottom and
right a little darker); a 2 px dark inner line; a soft inner shadow over ~4 px fading to transparent. The corners
sweep that profile round a radius-6 outer corner (the inner side stays square, as a rounded rectangle's offset does);
the stone's grain runs on through the joins (each side's noise is periodic over the edge's 128 px, and a corner reads
the end of its two edges' period), the light turning round the corner with a soft mitre.

The ribbon: a deep red cloth (#5a1a16 at the top to #4e1812 at the bottom, a faint sheen, fine horizontal fibres) in a
thin iron frame (1 px outline, 3 px of the rail's stone, 1 px dark line); the caps bend that frame round the end
(radius 10) and raise an iron chevron from it over the ribbon's end, with its soft shadow on the cloth. The band: a
flat fill of MelloUI.Palette.mainWindow with the rail's profile at about half thickness (10 px line + 2 px shadow)
along its bottom; its caps round the line off.

Writes Tools/pack_sources/kit/v2_2x/window/<name>.png and their manifest entries (pack_sources is git-ignored).
The kit's tools treat them as every window piece (build_kit.py: DENSITY 1.0 for the family, the header caps whole
pieces, not stood-up edges; texture_pack.py: shown at 1x, half the painted size; kit_gems.py finds no gem in them,
the ribbon's red is a fill; kit_palette.py recolours them per look, the red on the palette's selectedTab ramp;
build_nineslice.py lays window/stone as a one-texture nine-slice).

Run:  python Tools/make_window_stone.py [--preview]
      then python Tools/build_kit.py, python Tools/build_nineslice.py, python Tools/texture_pack.py ship
      (a full client restart). --preview also writes
      MelloUI-BuildData/output/charwin_sketch/stone_preview.png (the pieces at 1x, a rail frame, the two strips).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

from paths import SIBLING

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
MANIFEST = os.path.join(SRC, "manifest.json")
PREVIEW = os.path.join(SIBLING, "output", "charwin_sketch", "stone_preview.png")
SEED = 20261010

# ---- the rail (2x px)
S = 24                          # the rail's depth: corners S x S, edges EDGE x S
EDGE = 128                      # an edge's length (one period of its grain)
R_CORNER = 6.0                  # the outer corners' radius
OUTLINE, BEVEL, BAND, INNER, SHADOW = 2.0, 1.0, 14.0, 2.0, 5.0
P_BEVEL = OUTLINE               # where each layer starts, px in from the outer edge
P_BAND = P_BEVEL + BEVEL
P_INNER = P_BAND + BAND
P_SHADOW = P_INNER + INNER
P_END = P_SHADOW + SHADOW       # = S
SHADOW_ALPHA = 0.55             # the inner shadow's strength at its start
MITRE = 0.8                     # px: the softness of the light's turn where two sides meet

# ---- the header strips (2x px)
H_STRIP = 56
RIB_CAP = 48
RIB_RADIUS = 10.0               # the ribbon frame's rounded end
RIB_FRAME = (1.0, 1.0, 2.0, 1.0)   # outline, bevel, iron, dark line: 5 px
RIB_IN = sum(RIB_FRAME)
BAND_CAP = 24
LINE_TOP, LINE_BOT = 44.0, 54.0     # the band's rail line (10 px) ...
LINE_R = (LINE_BOT - LINE_TOP) / 2  # ... its rounded ends' radius
LINE_C = (LINE_TOP + LINE_BOT) / 2
LINE_END = 6.0                  # px from the cap's outer side to the round end's centre (its tip 1 px in)

# ---- colours (0..255 sRGB)
C_OUTLINE = np.array((12, 13, 10), float)
C_STONE = np.array((70, 74, 61), float)        # dark grey-green
C_INNER = np.array((16, 17, 13), float)
C_LIGHT = np.array((168, 174, 150), float)     # what a lit bevel leans toward
C_DARK = np.array((20, 21, 17), float)         # ... and a shaded one
C_GROUND = np.array((0x1F, 0x1B, 0x16), float)  # MelloUI.Palette.mainWindow
C_RIB_TOP = np.array((0x5A, 0x1A, 0x16), float)
C_RIB_BOT = np.array((0x4E, 0x18, 0x12), float)

# light from the top left: K = the outward normal . the direction toward the light (y down)
_L = np.array((-0.6, -1.0)) / math.hypot(0.6, 1.0)
K = {side: float(np.dot(n, _L)) for side, n in (("top", (0, -1)), ("bottom", (0, 1)), ("left", (-1, 0)),
                                                 ("right", (1, 0)))}


# ------------------------------------------------------------------ helpers

def periodic_noise(rng, shape, sy, sx):
    """White noise smoothed by a gaussian (sy, sx px), periodic on both axes (made in the frequency domain), unit
    standard deviation."""
    n = rng.standard_normal(shape)
    fy = np.fft.fftfreq(shape[0])[:, None]
    fx = np.fft.fftfreq(shape[1])[None, :]
    g = np.exp(-2 * math.pi ** 2 * ((fy * sy) ** 2 + (fx * sx) ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(n) * g))
    return (out - out.mean()) / (out.std() + 1e-9)


def cracks(rng, rows, count, lo, hi, inward):
    """Hairline cracks on a rows x EDGE strip (depth x along), wrapped along: (coverage, lit lip), each 0..1. They
    stay between depths lo and hi; `inward` is +1 or -1, the depth step toward the bottom right (where an incised
    crack's far wall catches the light)."""
    ss = 4
    im = Image.new("L", (EDGE * ss, rows * ss), 0)
    dr = ImageDraw.Draw(im)

    def walk(u, d, course, length, jag):
        pts, gone = [(u, d)], 0.0
        while gone < length:
            step = rng.uniform(0.9, 1.7)
            a = course + rng.uniform(-jag, jag)          # jagged about a straight course
            u, d = u + step * math.cos(a), d + step * math.sin(a)
            if not (lo + 0.5 <= d <= hi - 0.5):
                break
            pts.append((u, d))
            gone += step
        return pts

    def draw(pts, strength):
        n = len(pts) - 1
        for i in range(n):                               # fading toward its tip
            f = int(255 * strength * (1 - 0.65 * i / max(1, n)))
            for off in (-EDGE, 0, EDGE):
                dr.line([((pts[i][0] + off) * ss, pts[i][1] * ss), ((pts[i + 1][0] + off) * ss, pts[i + 1][1] * ss)],
                        fill=f, width=ss)

    for _ in range(count):
        u = rng.uniform(0, EDGE)
        if rng.random() < 0.75:                          # from one edge of the band, part way across
            d = lo + 0.6 if rng.random() < 0.5 else hi - 0.6
            course = (math.pi / 2 if d < (lo + hi) / 2 else -math.pi / 2) + rng.uniform(-0.5, 0.5)
            length = rng.uniform(0.4, 0.85) * (hi - lo)
        else:                                            # a short split along the band
            d = rng.uniform(lo + 3, hi - 3)
            course = (0.0 if rng.random() < 0.5 else math.pi) + rng.uniform(-0.3, 0.3)
            length = rng.uniform(4, 8)
        pts = walk(u, d, course, length, 0.55)
        if len(pts) < 3:
            continue
        draw(pts, 1.0)
        if rng.random() < 0.45:                          # a hair of a branch
            j = int(rng.integers(1, len(pts) - 1))
            br = walk(*pts[j], course + rng.choice((-1, 1)) * rng.uniform(0.6, 1.0), rng.uniform(2, 4), 0.4)
            if len(br) > 1:
                draw(br, 0.6)
    a = np.asarray(im, float).reshape(rows, ss, EDGE, ss).mean(axis=(1, 3)) / 255
    lip = np.clip(np.roll(a, (inward, 1), axis=(0, 1)) - a, 0, 1)
    return a, lip


def stone_field(rng, rows, n_cracks, lo, hi, inward):
    """One side's stone: (grain multiplier, crack, lit lip), rows x EDGE, periodic along."""
    n = max(32, rows + 8)
    mottle = periodic_noise(rng, (n, EDGE), 3.5, 7.0)[:rows]
    strata = periodic_noise(rng, (n, EDGE), 0.7, 6.0)[:rows]
    grain = periodic_noise(rng, (n, EDGE), 0.55, 0.55)[:rows]
    mult = 1 + 0.055 * mottle + 0.035 * strata + 0.028 * grain
    crack, lip = cracks(rng, rows, n_cracks, lo, hi, inward) if n_cracks else (np.zeros((rows, EDGE)),) * 2
    return mult, crack, lip


def cov(d, a, b):
    """The share of a pixel (centre depth d, one px wide across) inside the layer [a, b)."""
    return np.clip(np.minimum(b, d + 0.5) - np.maximum(a, d - 0.5), 0.0, 1.0)


def stack(d, layers):
    """Layers (a, b, rgb, alpha) by depth d: premultiplied rgb (H, W, 3) and alpha (H, W)."""
    h, w = d.shape
    P, A = np.zeros((h, w, 3)), np.zeros((h, w))
    for a, b, rgb, al in layers:
        c = cov(d, a, b) * al
        P += c[..., None] * np.broadcast_to(rgb, (h, w, 3))
        A += c
    return P, A


def over(top, bottom):
    (Pt, At), (Pb, Ab) = top, bottom
    return Pt + Pb * (1 - At)[..., None], At + Ab * (1 - At)


def rgba(PA, empty=C_OUTLINE):
    P, A = PA
    A = np.clip(A, 0, 1)
    rgb = np.where(A[..., None] > 1e-6, P / np.maximum(A, 1e-6)[..., None], empty)
    return np.clip(np.round(np.dstack([rgb, A * 255])), 0, 255).astype(np.uint8)


def lean(c, a):
    """A colour leaned toward the light (a > 0) or the dark (a < 0) by |a|."""
    a = a[..., None]
    return np.where(a >= 0, c + (C_LIGHT - c) * a, c + (C_DARK - c) * -a)


def softmin_weights(ds):
    """Each side's share of a pixel's light: the nearest side's, eased over MITRE px where two meet."""
    m = np.minimum.reduce(ds)
    e = [np.exp(-(d - m) / MITRE) for d in ds]
    s = sum(e)
    return [x / s for x in e]


def grid(w, h):
    y, x = np.mgrid[0:h, 0:w]
    return x, y, x + 0.5, y + 0.5


# ------------------------------------------------------------------ the rail

def rail(d, k, mult, crack, lip):
    """The rail's pixels from their depth d, light k and stone (grain, crack, lip)."""
    lift = (1 + 0.05 * k)[..., None]
    base = C_STONE * mult[..., None] * lift
    t = np.clip((d - P_BAND) / BAND, 0, 1)[..., None]
    stone = base * (1.03 - 0.10 * t * t)
    stone = stone * (1 - 0.42 * crack[..., None]) + 20 * lip[..., None]
    bevel = lean(base * 1.03, 0.14 + 0.30 * k)
    s = np.clip((np.clip(d, P_SHADOW, P_END) - P_SHADOW) / SHADOW, 0, 1)
    shadow = SHADOW_ALPHA * (1 - s) ** 1.8
    return stack(d, [(0, P_BEVEL, C_OUTLINE, 1.0),
                     (P_BEVEL, P_BAND, bevel, 1.0),
                     (P_BAND, P_INNER, stone, 1.0),
                     (P_INNER, P_SHADOW, C_INNER, 1.0),
                     (P_SHADOW, P_END, np.zeros(3), shadow)])


def rail_edge(field, side):
    """window/stone_<t|b|l|r>: the rail along one side, its outer edge on that side."""
    mult, crack, lip = field
    if side in ("top", "bottom"):
        x, y, px, py = grid(EDGE, S)
        d = py if side == "top" else S - py
        u = x
    else:
        x, y, px, py = grid(S, EDGE)
        d = px if side == "left" else S - px
        u = y
    row = np.clip(np.floor(d).astype(int), 0, S - 1)
    k = np.full(d.shape, K[side])
    return rgba(rail(d, k, mult[row, u], crack[row, u], lip[row, u]))


def rail_corner(fields, h, v):
    """window/stone_<tl|tr|bl|br>: the corner where side h (top / bottom) meets side v (left / right), its outer
    corner rounded. Each arm reads its edge's grain where the edge would go on: the top-left corner the end of the
    top and left edges' period (it joins their first pixel), the far corners its start."""
    x, y, px, py = grid(S, S)
    dh = py if h == "top" else S - py
    dv = px if v == "left" else S - px
    d = np.minimum(dh, dv)
    arc = (dh < R_CORNER) & (dv < R_CORNER)
    d = np.where(arc, R_CORNER - np.hypot(R_CORNER - dh, R_CORNER - dv), d)
    wh, wv = softmin_weights([dh, dv])
    k = wh * K[h] + wv * K[v]
    uh = (x - S) % EDGE if v == "left" else x % EDGE      # along the horizontal arm (x)
    uv = (y - S) % EDGE if h == "top" else y % EDGE       # along the vertical arm (y)
    row = np.clip(np.floor(d).astype(int), 0, S - 1)
    fh, fv = fields[h], fields[v]
    mult = wh * fh[0][row, uh] + wv * fv[0][row, uv]
    mitre = np.clip((np.abs(dh - dv) - 1.0) / 3.0, 0, 1)   # no crack cut by the joint
    crack = (wh * fh[1][row, uh] + wv * fv[1][row, uv]) * mitre
    lip = (wh * fh[2][row, uh] + wv * fv[2][row, uv]) * mitre
    return rgba(rail(d, k, mult, crack, lip))


# ------------------------------------------------------------------ the red ribbon

def ribbon(side, iron, cloth):
    """window/ribbon_<cap_l|mid|cap_r>: the cloth in its iron frame; a cap bends the frame round its end and raises
    an iron chevron from it over the ribbon's end."""
    w = EDGE if side == "mid" else RIB_CAP
    x, y, px, py = grid(w, H_STRIP)
    dt, db = py, H_STRIP - py
    if side == "cap_l":
        ds, u, ks = px, (x - RIB_CAP) % EDGE, K["left"]
    elif side == "cap_r":
        ds, u, ks = w - px, x % EDGE, K["right"]
    else:
        ds, u, ks = np.full(px.shape, 1e6), x % EDGE, 0.0
    d = np.minimum.reduce([dt, db, ds])
    rr = RIB_RADIUS
    for dy in (dt, db):
        arc = (ds < rr) & (dy < rr)
        d = np.where(arc, rr - np.hypot(rr - ds, rr - dy), d)
    wt, wb, ws = softmin_weights([dt, db, ds])
    k = wt * K["top"] + wb * K["bottom"] + ws * ks
    # the iron: the rail's stone, a lit / shaded bevel, a darker underside next to the dark line
    imult, cmult = iron[y, u], cloth
    base = C_STONE * (imult * (1 + 0.05 * k))[..., None]
    o, b, i, n = RIB_FRAME
    bevel = lean(base * 1.03, 0.14 + 0.30 * k)
    metal = base * np.where(d < o + b + i - 1, 1.0, 0.86)[..., None]
    # the cloth: its colour top to bottom, a faint sheen, its fibres, the frame's shadow on it (deeper under the
    # lit sides' iron: the light comes from the top left)
    t = np.clip((py - RIB_IN) / (H_STRIP - 2 * RIB_IN), 0, 1)[..., None]
    cl = C_RIB_TOP + (C_RIB_BOT - C_RIB_TOP) * t
    cl = cl * (1 + 0.05 * np.exp(-((py - 16) / 6.5) ** 2))[..., None]
    cl = cl * cmult[y, u][..., None]
    reach = 0.36 + 0.14 * k
    cl = cl * (1 - reach * np.exp(-np.clip(d - RIB_IN, 0, None) / 1.7))[..., None]
    chev = None
    if side != "mid":
        chev, shade = chevron(side, w, px, py)
        cl = cl * (1 - 0.5 * shade)[..., None]
    frame = stack(d, [(0, o, C_OUTLINE, 1.0), (o, o + b, bevel, 1.0), (o + b, o + b + i, metal, 1.0),
                      (o + b + i, RIB_IN, C_INNER, 1.0), (RIB_IN, 1e9, cl, 1.0)])
    if chev is not None:
        frame = over(chevron_paint(chev, imult), frame)
    return rgba(frame)


CHEV_BACK, CHEV_TIP, CHEV_HALF = 1.0, 17.0, 11.0   # px in from the cap's outer side: its back, its point; half its height


def chevron(side, w, px, py):
    """The chevron on a cap (a left cap's; a right cap's is it mirrored): its two faces' inside distances, how far
    a pixel is past its back, each face's light, and its soft shadow on the cloth (the shape nudged down and right)."""
    X = px if side == "cap_l" else w - px
    mirror = 1 if side == "cap_l" else -1
    cy = H_STRIP / 2
    run = CHEV_TIP - CHEV_BACK
    ln = math.hypot(CHEV_HALF, run)

    def faces(X, Y):
        # the upper face's edge runs (back, cy - half) -> (tip, cy), the lower's (back, cy + half) -> (tip, cy)
        eu = (-(X - CHEV_BACK) * CHEV_HALF + (Y - (cy - CHEV_HALF)) * run) / ln
        el = (-(X - CHEV_BACK) * CHEV_HALF - (Y - (cy + CHEV_HALF)) * run) / ln
        return eu, el

    eu, el = faces(X, py)
    ku = float(np.dot((mirror * CHEV_HALF / ln, -run / ln), _L))     # the faces' outward normals in the picture
    kl = float(np.dot((mirror * CHEV_HALF / ln, run / ln), _L))
    Xs = X - mirror * 1.5
    su, sl = faces(Xs, py - 2.0)
    m = np.clip(np.minimum.reduce([su, sl, Xs - CHEV_BACK]) + 0.5, 0, 1)
    shade = ndimage.gaussian_filter(m, 1.3, mode="nearest")
    return (eu, el, X - CHEV_BACK, ku, kl), shade


def chevron_paint(geo, imult):
    eu, el, inside_back, ku, kl = geo
    d = np.minimum(eu, el)
    wu, wl = softmin_weights([eu, el])
    kface = wu * ku + wl * kl
    body = C_STONE * (imult * (1 + 0.36 * kface))[..., None]
    bevel = lean(C_STONE * imult[..., None] * 1.05, 0.10 + 0.34 * kface)
    P, A = stack(d, [(0, 1.2, C_OUTLINE, 1.0), (1.2, 2.2, bevel, 1.0), (2.2, 1e9, body, 1.0)])
    back = np.clip(inside_back + 0.5, 0, 1)
    return P * back[..., None], A * back


# ------------------------------------------------------------------ the plain band

def band(side, field):
    """window/band_<cap_l|mid|cap_r>: the window's ground with a half-thickness rail line along the bottom; a cap
    rounds the line off."""
    w = EDGE if side == "mid" else BAND_CAP
    x, y, px, py = grid(w, H_STRIP)
    if side == "cap_l":
        dx, u = np.minimum(px - LINE_END, 0), (x - BAND_CAP) % EDGE
    elif side == "cap_r":
        dx, u = np.maximum(px - (w - LINE_END), 0), x % EDGE
    else:
        dx, u = np.zeros(px.shape), x % EDGE
    dy = py - LINE_C
    dist = np.hypot(dx, dy)
    d = LINE_R - dist                                    # in from the line's edge (a stadium)
    nx = np.where(dist > 1e-6, dx / np.maximum(dist, 1e-6), 0)
    ny = np.where(dist > 1e-6, dy / np.maximum(dist, 1e-6), -1)
    k = nx * _L[0] + ny * _L[1]
    mult, crack, lip = field
    row = np.clip(np.floor(py - LINE_TOP).astype(int), 0, mult.shape[0] - 1)
    m, c, lp = mult[row, u], crack[row, u], lip[row, u]
    base = C_STONE * m[..., None]
    g = np.clip(1.06 - 0.12 * (py - LINE_TOP) / (LINE_BOT - LINE_TOP), 0.9, 1.06)[..., None]
    stone = base * g * (1 - 0.42 * c[..., None]) + 20 * lp[..., None]
    bevel = lean(base * 1.03, 0.14 + 0.30 * k)
    line = stack(d, [(0, 1, C_OUTLINE, 1.0), (1, 2, bevel, 1.0), (2, 1e9, stone, 1.0)])
    # under it: the ground above the line's middle; below, its shadow on whatever the band sits on
    shift_x = 1.0
    sdx = dx if side == "mid" else (np.minimum(px - shift_x - LINE_END, 0) if side == "cap_l"
                                    else np.maximum(px - shift_x - (w - LINE_END), 0))
    sd = LINE_R - np.hypot(sdx, py - 1.6 - LINE_C)
    sm = np.clip(sd + 0.5, 0, 1)
    sh = ndimage.gaussian_filter(sm, 1.0, mode="wrap" if side == "mid" else "nearest") * 0.55
    ground = (py < LINE_C).astype(float)
    under = (C_GROUND * ground[..., None], ground + sh * (1 - ground))     # (premultiplied: the shadow is black)
    return rgba(over(line, under), empty=C_GROUND)


# ------------------------------------------------------------------ main

def pieces():
    rng = np.random.default_rng(SEED)
    fields = {}
    for side, inward in (("top", 1), ("left", 1), ("bottom", -1), ("right", -1)):
        fields[side] = stone_field(rng, S, 3, P_BAND, P_INNER, inward)
    out = {}
    for side, name in (("top", "t"), ("bottom", "b"), ("left", "l"), ("right", "r")):
        out["stone_" + name] = rail_edge(fields[side], side)
    for h in ("top", "bottom"):
        for v in ("left", "right"):
            out["stone_" + h[0] + v[0]] = rail_corner(fields, h, v)
    iron = stone_field(rng, H_STRIP, 0, 0, 0, 1)[0]
    fibres = periodic_noise(rng, (64, EDGE), 0.45, 5.0)[:H_STRIP]
    grain = periodic_noise(rng, (64, EDGE), 0.6, 0.6)[:H_STRIP]
    cloth = 1 + 0.03 * fibres + 0.018 * grain
    for side in ("cap_l", "mid", "cap_r"):
        out["ribbon_" + side] = ribbon(side, iron, cloth)
    line = stone_field(rng, int(LINE_BOT - LINE_TOP), 2, 2.0, LINE_BOT - LINE_TOP - 2.0, 1)
    for side in ("cap_l", "mid", "cap_r"):
        out["band_" + side] = band(side, line)
    return out


SIZES = {"stone_tl": (24, 24), "stone_tr": (24, 24), "stone_bl": (24, 24), "stone_br": (24, 24),
         "stone_t": (128, 24), "stone_b": (128, 24), "stone_l": (24, 128), "stone_r": (24, 128),
         "ribbon_cap_l": (48, 56), "ribbon_cap_r": (48, 56), "ribbon_mid": (128, 56),
         "band_cap_l": (24, 56), "band_cap_r": (24, 56), "band_mid": (128, 56)}
NOTES = {"stone": "the thin stone rail (24 px, rounded corner r 6)",
         "ribbon": "the red ribbon title strip in its iron frame",
         "band": "the plain header band, its half rail line along the bottom"}


def main():
    made = pieces()
    man = json.load(open(MANIFEST, encoding="utf-8"))
    for name, a in made.items():
        w, h = SIZES[name]
        assert a.shape[:2] == (h, w), (name, a.shape)
        Image.fromarray(a, "RGBA").save(os.path.join(SRC, "window", name + ".png"))
        man["v2_2x/window/" + name] = {"w": w, "h": h, "scale": 1.0,
                                       "src": "Tools/make_window_stone.py: painted in code, %s" % NOTES[name.split("_")[0]]}
        print("window/%-13s %3dx%-3d" % (name, w, h))
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    print("-> %s (+ manifest); next: python Tools/build_kit.py" % os.path.join(SRC, "window"))
    if "--preview" in sys.argv:
        preview(made)
        print("preview -> %s" % PREVIEW)


# ------------------------------------------------------------------ the preview

def _font(size):
    for f in ("segoeui.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def half(a):
    im = Image.fromarray(a, "RGBA")
    return im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)


def strip(w, cap_l, mid, cap_r):
    """A cap / mid / cap strip `w` px wide at 2x, the middle repeated from the left cap as the kit lays it."""
    h = mid.shape[0]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(Image.fromarray(cap_l), (0, 0))
    x = cap_l.shape[1]
    end = w - cap_r.shape[1]
    while x < end:
        n = min(mid.shape[1], end - x)
        out.alpha_composite(Image.fromarray(mid[:, :n].copy()), (x, 0))
        x += n
    out.alpha_composite(Image.fromarray(cap_r), (end, 0))
    return out


def frame(made, w, h):
    """The eight rail pieces round a w x h window at 2x."""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    t, b, l, r = made["stone_t"], made["stone_b"], made["stone_l"], made["stone_r"]
    for x in range(S, w - S, EDGE):
        n = min(EDGE, w - S - x)
        out.alpha_composite(Image.fromarray(t[:, :n].copy()), (x, 0))
        out.alpha_composite(Image.fromarray(b[:, :n].copy()), (x, h - S))
    for y in range(S, h - S, EDGE):
        n = min(EDGE, h - S - y)
        out.alpha_composite(Image.fromarray(l[:n].copy()), (0, y))
        out.alpha_composite(Image.fromarray(r[:n].copy()), (w - S, y))
    out.alpha_composite(Image.fromarray(made["stone_tl"]), (0, 0))
    out.alpha_composite(Image.fromarray(made["stone_tr"]), (w - S, 0))
    out.alpha_composite(Image.fromarray(made["stone_bl"]), (0, h - S))
    out.alpha_composite(Image.fromarray(made["stone_br"]), (w - S, h - S))
    return out


def preview(made):
    ground = tuple(int(c) for c in C_GROUND) + (255,)
    W, H = 1340, 900
    img = Image.new("RGBA", (W, H), ground)
    dr = ImageDraw.Draw(img)
    f, fs = _font(16), _font(12)
    ink, muted = (198, 175, 133, 255), (127, 104, 70, 255)
    dr.text((20, 14), "Thin stone window look (Tools/make_window_stone.py, all painted in code): shown at 1x, "
                      "half the painted 2x", font=f, fill=ink)
    # the 14 pieces at 1x, then as painted
    order = ["stone_tl", "stone_t", "stone_tr", "stone_l", "stone_r", "stone_bl", "stone_b", "stone_br",
             "ribbon_cap_l", "ribbon_mid", "ribbon_cap_r", "band_cap_l", "band_mid", "band_cap_r"]
    tray = (46, 41, 34, 255)                    # a lighter tray behind each piece: the band's fill shows on it
    dr.text((20, 46), "The 14 pieces at 1x (each on a lighter tray)", font=fs, fill=muted)
    x, y = 20, 68
    for name in order:
        im = half(made[name])
        dr.rectangle((x - 3, y - 3, x + im.width + 2, y + im.height + 2), fill=tray)
        img.alpha_composite(im, (x, y))
        dr.text((x, y + 70), name, font=fs, fill=muted)
        x += max(im.width, 70) + 18
    dr.text((20, 166), "... as painted (2x)", font=fs, fill=muted)
    x, y = 20, 188
    for name in order:
        im = Image.fromarray(made[name])
        dr.rectangle((x - 3, y - 3, x + im.width + 2, y + im.height + 2), fill=tray)
        img.alpha_composite(im, (x, y))
        x += max(im.width, 24) + 14
    # a rail frame, about 400 x 200 at 1x
    dr.text((20, 342), "Rail frame, 400 x 200 at 1x (the eight rail pieces; edges repeated from the top left)",
            font=fs, fill=muted)
    fr = frame(made, 800, 400)
    img.alpha_composite(fr.resize((400, 200), Image.LANCZOS), (20, 364))
    # the same frame's top left and bottom right corners as painted, for the joins
    dr.text((450, 342), "Its corners as painted (2x)", font=fs, fill=muted)
    img.alpha_composite(fr.crop((0, 0, 200, 140)), (450, 364))
    img.alpha_composite(fr.crop((600, 260, 800, 400)), (670, 364))
    # the two header strips at 600 wide (1x)
    dr.text((20, 590), "Header strips, 600 wide at 1x: the red ribbon (example 3), the plain band with its rail "
                       "line (example 4)", font=fs, fill=muted)
    rib = strip(1200, made["ribbon_cap_l"], made["ribbon_mid"], made["ribbon_cap_r"])
    bnd = strip(1200, made["band_cap_l"], made["band_mid"], made["band_cap_r"])
    img.alpha_composite(rib.resize((600, 28), Image.LANCZOS), (20, 612))
    img.alpha_composite(bnd.resize((600, 28), Image.LANCZOS), (20, 656))
    dr.text((650, 590), "Their ends as painted (2x)", font=fs, fill=muted)
    img.alpha_composite(rib.crop((0, 0, 160, 56)), (650, 612))
    img.alpha_composite(rib.crop((1040, 0, 1200, 56)), (820, 612))
    img.alpha_composite(bnd.crop((0, 0, 160, 56)), (990, 612))
    img.alpha_composite(bnd.crop((1040, 0, 1200, 56)), (1160, 612))
    # in place: a 620 x 150 window at 1x with each header under its top rail, a title on the strip
    for i, (label, st) in enumerate((("ribbon", rib), ("band", bnd))):
        ox, oy = 20 + i * 660, 730
        dr.text((ox, oy - 22), "In place: a 620 x 150 window at 1x, the %s under the top rail" % label, font=fs,
                fill=muted)
        win = frame(made, 1240, 300)
        body = Image.new("RGBA", (1240 - 2 * 18, 300 - 2 * 18), (17, 16, 13, 255))   # innerPanel-ish body
        canvas = Image.new("RGBA", (1240, 300), (0, 0, 0, 0))
        canvas.alpha_composite(body, (18, 18))
        hdr = strip(1240 - 2 * 19, *((made["ribbon_cap_l"], made["ribbon_mid"], made["ribbon_cap_r"])
                                            if label == "ribbon" else
                                            (made["band_cap_l"], made["band_mid"], made["band_cap_r"])))
        canvas.alpha_composite(hdr, (19, 19))
        canvas.alpha_composite(win, (0, 0))
        small = canvas.resize((620, 150), Image.LANCZOS)
        img.alpha_composite(small, (ox, oy))
        d2 = ImageDraw.Draw(img)
        title = "FAIRYELF MELLO"
        tf = _font(15)
        tw = d2.textlength(title, font=tf)
        d2.text((ox + 310 - tw / 2, oy + 11), title, font=tf, fill=(230, 214, 180, 255))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    img.convert("RGB").save(PREVIEW)


if __name__ == "__main__":
    main()
