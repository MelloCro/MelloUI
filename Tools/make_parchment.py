"""
make_parchment.py -- the parchment (0.20.1; the user, 2026-10-10: the RPG UI pack's parchment, used with its creator's
permission, in place of tiles/vellum and our own brush-stroke torn edges; "it has to be scaleable for different
elements"). The pack's parchment page (its QuestLog page layer, kept in pack_sources/kit/v2_2x/sources/
rpg_parchment.png: pack_sources is git-ignored) cut into two kit nine-slice families that Kit:NineSlice lays at any
size (Kit:ParchmentNine):

    parchment/sheet_*   a sheet (tooltips, chat, the trackers, popups): corners and edge depth 160 page px (80 painted)
        _body             512 x 512  the paper: the page's middle, its grain on the page's centre colour (the slow
                                     browning taken out), seamless by the kit's quilting, repeated at one density
        _t, _b            512 x 80   the top / bottom edge: the real paper -- browning, burnt rim, torn outline --
                                     opaque out to 100 page px, fading into the paper by 160 (the browning ends by
                                     ~150), repeated along x without a seam
        _l, _r            80 x 512   ... the sides, along y
        _tl, _tr, _bl, _br  80 x 80  the plain corners (the page's top right and bottom left, the other two mirrored)
    parchment/page_*    a big page with curled corners (the user's pick: the quest and spell book pages, the character
                        stats pane): corners and edge depth 300 page px (150 painted). The curls and the shading under
                        them reach ~225 px along the diagonal: a 160 px corner cut them off and its square showed (in
                        game, 2026-10-10); at 300 the corner holds them whole, and the paper under it, from half a
                        corner in, lies clear of the fold.
        _t, _b / _l, _r   256 x 150 / 150 x 256  the edges (opaque out to 220, fading by 300)
        _tl, _br          150 x 150  the curled corners
        _tr, _bl          150 x 150  plain corners; _tl_plain, _br_plain theirs mirrored (a page curled at one corner)
                        (its paper: the sheet's body)

No mask anywhere: each edge and corner carries the torn outline in its alpha and fades into the body on its inner part,
the body lying under them from half a corner in (Kit:NineSlice's inset). Painted px are the kit's 2x: the page's 4k
layout at 0.5. An edge strip longer than one side of the page is that side followed by the opposite side flipped onto
it, cross-faded at both joins, so top and bottom differ.

The pack's own tone (the user's pick): kit_palette.py leaves the family alone in every look.

Run:  python Tools/make_parchment.py [--src <png>]
      then python Tools/build_kit.py, python Tools/texture_pack.py ship (a full client restart)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
MANIFEST = os.path.join(SRC, "manifest.json")
DEFAULT_SOURCE = os.path.join(SRC, "sources", "rpg_parchment.png")

K = 0.5            # source (the pack's 4k layout) px -> painted px
FADE = 100         # source px: each cross-fade along an edge strip
CURL_CLEAR = 330   # source px: an edge strip starts this far from a curled corner (its shading reaches ~225 diagonally)
BODY = 512         # painted px: the paper tile
BODY_SRC = 740     # source px: the square of the page's middle the tile is cut from (the browning flattened out)
QUILT_MARGIN = 48  # source px: the overlap the quilting's seam path runs through
# the families: corner / edge depth T, opaque out to SOLID, an edge strip's painted length
FAMILIES = {"sheet": {"T": 160, "SOLID": 100, "LENGTH": 512},
            "page": {"T": 300, "SOLID": 220, "LENGTH": 256}}


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0


def ramp(d, f):
    """1 out to SOLID source px from the outer side, 0 by T: a smoothstep (a straight fade's ends showed as faint
    lines along the sheet)."""
    t = np.clip((f["T"] - d) / float(f["T"] - f["SOLID"]), 0, 1)
    return t * t * (3 - 2 * t)


def to_img(arr, size):
    im = Image.fromarray((np.clip(arr, 0, 1) * 255).round().astype(np.uint8), "RGBA")
    return np.asarray(im.resize(size, Image.LANCZOS)).astype(np.float32) / 255.0


def body_tile(a):
    """The page's grain (the page over its own slow colour field) on the centre colour, made seamless by the kit's
    quilting (build_kit.quilt_tile: the wrap cut along the path of least difference -- a plain cross-fade with
    itself shifted left a faint line through the middle of each repeat)."""
    sys.path.insert(0, HERE)
    from build_kit import quilt_tile
    rgb = a[..., :3]
    h, w = rgb.shape[:2]
    smooth = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(40))).astype(np.float32) / 255
    centre = np.median(smooth[h // 3:2 * h // 3, w // 3:2 * w // 3].reshape(-1, 3), axis=0)
    flat = np.clip(rgb / np.maximum(smooth, 1e-3) * centre, 0, 1)
    page = (np.dstack([flat, np.ones((h, w), np.float32)]) * 255).round().astype(np.uint8)
    n = BODY_SRC
    x0, y0 = w // 2 - n // 2, h // 2 - n // 2
    tile = quilt_tile(page, (x0, y0, x0 + n, y0 + n), QUILT_MARGIN, size=BODY)
    return tile.astype(np.float32) / 255.0, centre


def side_band(a, side, T):
    """A side's band, T deep, between its corners -- clear of a curled corner's shading (the page's top left and
    bottom right: CURL_CLEAR), else of the corner -- turned so row 0 is the outer edge and it runs along x."""
    h, w = a.shape[:2]
    near = max(T, CURL_CLEAR)
    if side == "t":
        return a[:T, near:w - T]
    if side == "b":
        return a[h - T:, T:w - near][::-1]
    if side == "l":
        return a[near:h - T, :T].transpose(1, 0, 2)
    return a[T:h - near, w - T:].transpose(1, 0, 2)[::-1]


def strip(first, second, f):
    """`first` followed by `second` (both outer-edge-up, along x), cross-faded at the join and at the wrap: a strip
    that repeats without a seam, LENGTH / K source px long."""
    need = int(round(f["LENGTH"] / K))
    j = first.shape[1]
    assert j + second.shape[1] >= need + 2 * FADE, (j, second.shape, need)
    wj = np.linspace(0, 1, FADE)[None, :, None]
    joined = np.concatenate([first[:, :j - FADE], first[:, j - FADE:] * (1 - wj) + second[:, :FADE] * wj,
                             second[:, FADE:]], axis=1)
    s = joined[:, :need + FADE]
    head = s[:, :FADE] * wj + s[:, need:need + FADE] * (1 - wj)
    s = np.concatenate([head, s[:, FADE:need]], axis=1).copy()
    s[..., 3] *= ramp(np.arange(f["T"]), f)[:, None]
    return s


def profile(band, centre):
    """A side band's colour by depth (row 0 the outer edge), over the paper's centre colour: the mean along it,
    scaled so its innermost rows are the paper's colour exactly (the body, the centre colour's tile, meets them)."""
    rgb = band[..., :3]
    a = band[..., 3:4]
    mean = (rgb * a).sum(axis=1) / np.maximum(a.sum(axis=1), 1e-3)
    p = mean / centre
    tail = p[-max(8, len(p) // 8):].mean(axis=0)
    return np.clip(p / tail, 0, 1.2)


EVEN = 61          # source px: the window along a strip its slow darkness is measured over (the burnt specks stay)


def even(s, prof, centre):
    """The strip (outer edge up, along x, repeating) with its band evened along its length: each pixel's colour over
    its neighbourhood's along the strip (a wrapped box mean), times the band's colour at its depth -- the slow
    darkening that changed along a side gone (in game, 2026-10-10: a step showed where a strip met a corner), its
    fine grain, burnt specks and torn outline kept."""
    rgb, a = s[..., :3], s[..., 3:4]
    k = EVEN // 2
    padded = np.concatenate([rgb[:, -k:] * a[:, -k:], rgb * a, rgb[:, :k] * a[:, :k]], axis=1)
    pa = np.concatenate([a[:, -k:], a, a[:, :k]], axis=1)
    cs = np.cumsum(np.pad(padded, ((0, 0), (1, 0), (0, 0))), axis=1)
    ca = np.cumsum(np.pad(pa, ((0, 0), (1, 0), (0, 0))), axis=1)
    n = rgb.shape[1]
    local = (cs[:, EVEN:EVEN + n] - cs[:, :n]) / np.maximum(ca[:, EVEN:EVEN + n] - ca[:, :n], 1e-3)
    out = s.copy()
    out[..., :3] = np.clip(rgb / np.maximum(local, 1e-3) * (prof * centre)[:, None, :], 0, 1)
    return out


def corner(a, c, f, centre, profiles):
    """A corner, T square: the page's own corner (its curl, burnt rim, torn outline) near its outer point, blended
    towards its inner sides into what the edges show there -- the two sides' colour by depth multiplied, on the
    corner's own grain -- so it meets them and the paper without a line (in game, 2026-10-10: a straight line where
    a corner cut from the page met edges cut from the sides' middles). Its alpha the page's, faded into the paper
    on its inner part."""
    T = f["T"]
    h, w = a.shape[:2]
    ys = slice(0, T) if c[0] == "t" else slice(h - T, h)
    xs = slice(0, T) if c[1] == "l" else slice(w - T, w)
    s = a[ys, xs].copy()
    y, x = np.mgrid[0:T, 0:T]
    dy = y if c[0] == "t" else T - 1 - y
    dx = x if c[1] == "l" else T - 1 - x
    rgb = s[..., :3]
    smooth = np.asarray(Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(12))).astype(np.float32) / 255
    grain = np.clip(rgb / np.maximum(smooth, 1e-3), 0.7, 1.3)
    pv = profiles["l" if c[1] == "l" else "r"]
    ph = profiles["t" if c[0] == "t" else "b"]
    model = centre * pv[dx] * ph[dy] * grain
    r = np.hypot(dx, dy)
    keep = np.clip((0.95 * T - r) / (0.4 * T), 0, 1)[..., None]   # 1 out to 0.55 T from the outer point, 0 by 0.95 T
    s[..., :3] = rgb * keep + model * (1 - keep)
    s[..., 3] *= np.maximum(ramp(dy, f), ramp(dx, f))
    return s


def family(a, name, f, centre):
    out = {}
    T = f["T"]
    bands = {s: side_band(a, s, T) for s in ("t", "b", "l", "r")}
    profiles = {s: profile(bands[s], centre) for s in bands}
    # (a strip of two sides: the first side's band by depth for both, the second evened onto it)
    depth = int(T * K)
    for side, (first, second) in {"t": ("t", "b"), "b": ("b", "t"), "l": ("l", "r"), "r": ("r", "l")}.items():
        s = to_img(even(strip(bands[first], bands[second], f), profiles[first], centre), (f["LENGTH"], depth))   # outer edge up, along x
        if side == "b":
            s = s[::-1]
        elif side == "l":
            s = s.transpose(1, 0, 2)
        elif side == "r":
            s = s[::-1].transpose(1, 0, 2)
        out[name + "_" + side] = s
    size = (depth, depth)
    tr, bl = corner(a, "tr", f, centre, profiles), corner(a, "bl", f, centre, profiles)
    out[name + "_tr"], out[name + "_bl"] = to_img(tr, size), to_img(bl, size)
    plain_tl, plain_br = to_img(tr[:, ::-1], size), to_img(bl[:, ::-1], size)
    if name == "page":
        out["page_tl"] = to_img(corner(a, "tl", f, centre, profiles), size)
        out["page_br"] = to_img(corner(a, "br", f, centre, profiles), size)
        out["page_tl_plain"], out["page_br_plain"] = plain_tl, plain_br
    else:
        out[name + "_tl"], out[name + "_br"] = plain_tl, plain_br
    return out


def pieces(a):
    out = {}
    out["sheet_body"], centre = body_tile(a)
    for name, f in FAMILIES.items():
        out.update(family(a, name, f, centre))
    return out, centre


NOTE = "Tools/make_parchment.py: the RPG UI pack's parchment page (used with its creator's permission), %s"
NOTES = {"sheet_body": "the paper tile", "sheet": "a sheet's edge or corner (torn outline in its alpha)",
         "page": "a big page's edge or corner (the curls whole)"}


def main():
    src = DEFAULT_SOURCE
    if "--src" in sys.argv:
        src = sys.argv[sys.argv.index("--src") + 1]
    a = load(src)
    made, centre = pieces(a)
    folder = os.path.join(SRC, "parchment")
    os.makedirs(folder, exist_ok=True)
    man = json.load(open(MANIFEST, encoding="utf-8"))
    # (pieces no longer made: their files and manifest entries go)
    for key in [k for k in man if k.startswith("v2_2x/parchment/")]:
        if key.split("/")[-1] not in made:
            del man[key]
            old = os.path.join(folder, key.split("/")[-1] + ".png")
            if os.path.exists(old):
                os.remove(old)
    for name, arr in sorted(made.items()):
        h, w = arr.shape[:2]
        Image.fromarray((np.clip(arr, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(os.path.join(folder, name + ".png"))
        note = NOTES.get(name) or NOTES[name.split("_")[0]]
        man["v2_2x/parchment/" + name] = {"w": w, "h": h, "scale": 1.0, "src": NOTE % note}
        print("parchment/%-14s %3dx%-3d" % (name, w, h))
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    print("paper centre colour", tuple(int(round(v * 255)) for v in centre))
    print("-> %s (+ manifest); next: python Tools/build_kit.py, python Tools/texture_pack.py ship" % folder)


if __name__ == "__main__":
    main()
