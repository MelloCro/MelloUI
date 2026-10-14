"""
kit_sharp.py -- round borders that stay sharp when they are drawn small.

The user, 2026-10-14: "make sure that the Borders and icon sizes are sharp, i dont want some cut of borders like i see
on the services tab" and "we need to do the same thing with all of the round border textures". The Services row's
rims (Round Border "Sunk": buttons/roundrimsunk, a 64 px file) are drawn at about 21 UI units -- some 25 screen px:
their 1 px gold line, sampled by the client's bilinear filter at 2.5 file px per screen px, shows as dots. Measured
in game (/rimtest, 2026-10-14): the same art with its line ~2.5 px wide is a solid, crisp ring at that size and at
1.5x; mipmaps alone (BLP DXT5, uncompressed BLP, or a TGA drawn TRILINEAR) only made the dots a soft, dim ring.

widen(a, min_line) -- a round piece's thin lines made at least min_line px wide, inside the same band: the ring's
profile read along its depth (from the outer edge in, the mean over every angle, alpha-weighted luminance), each
narrow light or dark line found in it given min_line px and the rest of the band squeezed to keep its width (the
opening, where the icon goes, stays where it was). Every angle is remapped alike (a stud or a gem on the ring moves
with the depth it stands at), each widened line drawn in its own colour at its angle. Pixels deeper than the band
and outside the ring are left as they were.

small_size -- the file size of the small copies of the ring styles (rings/<id>_s): the Round Border draws them on
round buttons (20-48 UI units), where the 176 px rings were shrunk 7-9 times.
"""
import numpy as np

MIN_LINE = 2.5          # file px: a line's width at 64 px, the width that stood solid in game at 21 UI units
CONTRAST = 18           # luminance steps a line stands out from both sides by (a 0..255 alpha-weighted luminance)
SMALL_SIZE = 64


def _lum(a):
    return (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) * a[..., 3] / 255.0


def profile(a, n_bins):
    """the ring's mean (alpha-weighted luminance, alpha) by whole px of depth from its outer edge"""
    h, w = a.shape[:2]
    c = ((w - 1) / 2, (h - 1) / 2)
    R = min(w, h) / 2
    yy, xx = np.mgrid[0:h, 0:w]
    d = R - np.hypot(xx - c[0], yy - c[1])
    lum, al = _lum(a.astype(np.float64)), a[..., 3].astype(np.float64)
    L, A = [], []
    for k in range(n_bins):
        m = (d >= k) & (d < k + 1)
        L.append(float(lum[m].mean()) if m.any() else 0.0)
        A.append(float(al[m].mean()) if m.any() else 0.0)
    return np.array(L), np.array(A)


def band_depth(L, A):
    """where the ring's band ends: past its last line, before the deep inner shade (alpha low or no light left)"""
    last = 0
    for k in range(1, len(L)):
        if A[k] > 64 and L[k] > 6:
            last = k
    return last + 1


def lines(L, D, contrast=CONTRAST, share=0.5):
    """the band's narrow light lines: one px of depth standing out from both neighbours, at its edge too, and at
    least `share` as light as the band's lightest (a faint bevel line under it stays as drawn: widened, it squeezed
    the dark between two lines away and the rim read as one heavy band)"""
    out = []
    top = max(L[:D]) if D > 0 else 0
    for k in range(0, D):
        if L[k] < share * top:
            continue
        lo = L[k - 1] if k > 0 else None
        hi = L[k + 1] if k + 1 < len(L) else None
        nb = [v for v in (lo, hi) if v is not None]
        if not nb:
            continue
        if L[k] - max(nb) >= contrast:
            out.append(k)
    return out


def remap(D, found, min_line):
    """old depth for each new depth: the found lines min_line wide, the rest squeezed to keep D"""
    segs = []               # (old start, old end, is a line)
    k = 0
    for ln in sorted(found):
        if ln > k:
            segs.append((k, ln, False))
        segs.append((ln, ln + 1, True))
        k = ln + 1
    if k < D:
        segs.append((k, D, False))
    line_total = min_line * sum(1 for s in segs if s[2])
    rest_old = sum(e - s for s, e, ln in segs if not ln)
    room = D - line_total
    if room <= 0 or rest_old <= 0:
        return None
    k_rest = room / rest_old
    out = []                # (new start, new end, old start, old end, is a line)
    n = 0.0
    for s, e, ln in segs:
        width = min_line if ln else (e - s) * k_rest
        out.append((n, n + width, s, e, ln))
        n += width
    return out


def family_plan(states, contrast=CONTRAST):
    """one plan for every state of a piece (normal, hover, pressed, checked): the band as deep as the deepest state's,
    the lines any state shows -- so a rim never changes its weight under the mouse or when pressed. Returns
    (depth, lines)."""
    D, found = 0, set()
    profiles = []
    for a in states:
        a = np.asarray(a)
        R = min(a.shape[:2]) / 2
        L, A = profile(a, int(R * 0.6))
        profiles.append(L)
        D = max(D, band_depth(L, A))
    for L in profiles:
        found.update(lines(L, D, contrast))
    return D, sorted(found)


def widen(a, min_line=MIN_LINE, contrast=CONTRAST, plan=None):
    """a: HxWx4 uint8, a round piece centred in its own square (the canvas's padding cut off by the caller); plan:
    family_plan()'s (depth, lines) for every state alike, or None to read this piece alone.
    Returns (the widened piece, the lines by depth)."""
    a = np.asarray(a)
    h, w = a.shape[:2]
    R = min(w, h) / 2
    if plan is None:
        L, A = profile(a, int(R * 0.6))
        D = band_depth(L, A)
        found = lines(L, D, contrast)
    else:
        D, found = plan
    plan = remap(D, found, min_line) if found else None
    if not plan:
        return a.copy(), found
    c = ((w - 1) / 2, (h - 1) / 2)
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - c[0], yy - c[1])
    d = R - r
    ang = np.arctan2(yy - c[1], xx - c[0])
    src_d = d.copy()
    is_line = np.zeros(d.shape, bool)
    for n0, n1, s, e, ln in plan:
        m = (d >= n0) & (d < n1)
        if ln:
            src_d[m] = s + 0.5           # the line's own middle: its colour, at this angle
            is_line[m] = True
        else:
            src_d[m] = s + (d[m] - n0) * (e - s) / max(n1 - n0, 1e-6)
    # the outer edge's anti-aliasing kept: a pixel half outside the ring samples as it did
    src_d[d < 0] = d[d < 0]
    rr = R - src_d
    sx, sy = c[0] + rr * np.cos(ang), c[1] + rr * np.sin(ang)
    af = a.astype(np.float64)
    x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = (sx - x0)[..., None], (sy - y0)[..., None]

    def px(x, y):
        return af[np.clip(y, 0, h - 1), np.clip(x, 0, w - 1)]
    out = (px(x0, y0) * (1 - fx) * (1 - fy) + px(x0 + 1, y0) * fx * (1 - fy)
           + px(x0, y0 + 1) * (1 - fx) * fy + px(x0 + 1, y0 + 1) * fx * fy)
    # a widened line's edges soft by half a px, its inside solid (the bilinear blur of a 1 px line would dim it)
    out = np.where((d > plan[-1][1])[..., None] | (d < 0)[..., None], af, out)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8), found
