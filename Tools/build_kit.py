"""
build_kit.py -- package the painted UI kit for the client.

Reads  Tools/pack_sources/kit/v2_2x/   (the cut, repaired, 2x-normalised PNG
                                        pieces; git-ignored, rebuilt from the
                                        ChatGPT sheets by the UITest tools)
Writes Media/Kit/<group>/<name>.tga     32-bit TGA, power-of-two canvas
       Media/KitLayout.lua              MelloUI_KitLayout: uv, sizes, openings

Piece kinds:
  * repeatable along an axis (window edges, body, cap/mid/cap middles, the bar
    trough, the tiles): the file is RESIZED to a power of two on that axis so
    the client's REPEAT wrap mode tiles it exactly (a uniform middle does not
    mind a small stretch); the other axis is padded.
  * everything else: padded to a power of two, piece at the top-left, uv given.

Density (2026-09-21 audit): the pieces are painted at 2x, and the windows
show most of them at a third of that (a 71 px row plate on a 24 px row, a
135 px slot rim on a 48 px slot) while Blizzard's atlases are drawn 1:1. So
the FILE holds each piece at a fraction of its painted size (DENSITY per
group: 0.5 for the kit's plates, rims, rails and tiles = still ~1.5 x the
on-screen size; pictures at what their on-screen size needs). The layout
keeps the painted 2x numbers (w, h, box, open) so every scale and offset in
the Lua stays as it is; only the uv is measured on the file.

The decorative red gems are toned to iron studs on the way (Tools/kit_gems.py,
user 2026-09-23: too many red diamonds); --red-gems builds the old art.

Then the palette's two looks are made from it (Tools/kit_palette.py, user
2026-09-23: Media/KitWarm and Media/KitBronze, chosen in game);
--no-looks skips them.

Run:  python Tools/build_kit.py            (then a full client restart)
"""
import os, re, json, math, sys
import numpy as np
from PIL import Image

import kit_gems
import kit_palette

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
OUT = os.path.join(ROOT, "Media", "Kit")
LUA = os.path.join(ROOT, "Media", "KitLayout.lua")

MID = re.compile(r"_mid(_[a-z]+)?$")


def tile_axes(name):
    group, base = name.split("/")
    if group == "tiles" or base == "frame_body":
        return "xy"
    if group == "window" and base.endswith("_body"):
        return "xy"
    if base == "scrolltrack_mid" or base == "trough_v" or base.startswith("scrollthumb_mid") or (group == "window" and base.endswith(("_l", "_r"))):
        return "y"                      # upright pieces: the scroll track, the trough stood up, the thumb's slab
    if MID.search(base) or base == "trough" or (group == "window" and base.endswith(("_t", "_b"))):
        return "x"
    return ""


def pot_up(n):
    return 1 << max(0, math.ceil(math.log2(max(n, 1))))


def pot_near(n):
    lo = 1 << int(math.floor(math.log2(max(n, 1))))
    hi = lo * 2
    return lo if n - lo <= hi - n else hi


def body_radius(a):
    """A round piece's outer radius in piece px, measured off the compass
    points (30, 45 and 60 degrees, the smallest), so the gems that stick out
    at the four points are not counted: the bars of a unit frame end on the
    ring's round body."""
    import math
    h, w = a.shape[:2]
    cx, cy = (w - 1) / 2, (h - 1) / 2
    best = None
    for quadrant in range(4):
        for deg in (30, 45, 60):
            t = math.radians(deg + 90 * quadrant)
            last = 0
            for rr in range(0, int(max(w, h))):
                x, y = int(round(cx + rr * math.cos(t))), int(round(cy + rr * math.sin(t)))
                if 0 <= x < w and 0 <= y < h and a[y, x, 3] > 100:
                    last = rr
            best = last if best is None else min(best, last)
    return int(best or 0)


def opening(a):
    """Transparent interior of a hollow piece (slot, ring, bar frame, card),
    read through the centre row and column: (left, top, right, bottom) in px."""
    m = a[..., 3] > 128
    H, W = m.shape
    col, row = m[:, W // 2], m[H // 2, :]
    ys, xs = np.where(col)[0], np.where(row)[0]
    if len(ys) == 0:
        return None
    iy = np.where(~col[ys.min():ys.max()])[0]
    if len(iy) < 4:
        return None
    top, bottom = int(ys.min() + iy.min()), int(ys.min() + iy.max() + 1)
    # a repeatable middle is open end to end: its centre row has no rail at all
    if len(xs) == 0:
        return (0, top, W, bottom)
    ix = np.where(~row[xs.min():xs.max()])[0]
    if len(ix) < 4:
        return (0, top, W, bottom)
    return (int(xs.min() + ix.min()), top, int(xs.min() + ix.max() + 1), bottom)


def cap_hollow(a, side):
    """A bar cap's hollow arm: the opening rows read at the joint column, then
    how far the opening runs into the cap. (left, top, right, bottom) in px."""
    m = a[..., 3] > 128
    H, W = m.shape
    col = m[:, W - 1] if side == "l" else m[:, 0]
    ys = np.where(col)[0]
    if len(ys) == 0:
        return None
    iy = np.where(~col[ys.min():ys.max()])[0]
    if len(iy) < 4:
        return None
    top, bottom = int(ys.min() + iy.min()), int(ys.min() + iy.max() + 1)
    mid = (top + bottom) // 2
    if side == "l":
        x = W - 1
        while x > 0 and not m[mid, x - 1]:
            x -= 1
        return (x, top, W, bottom)
    x = 0
    while x < W - 1 and not m[mid, x + 1]:
        x += 1
    return (0, top, x + 1, bottom)


# File density per piece: pixels in the file per painted (2x) pixel, chosen
# so each piece holds about 1.3-1.5 x the pixels it shows on screen (Blizzard
# draws 1:1 in UI px; a UI px is up to 1.33 screen px at common UI scales, so
# a little over 1:1 keeps the art crisp). The on-screen sizes are the game's
# rects the pieces are fitted to (docs/KIT-MAPPING.md). First match wins.
DENSITY = [
    (r"^window/single_body$", 1.0),        # 512 px stone shown at 307 px per repeat (frame scale 1.6)
    (r"^window/single_", 1.0),             # 11 px rails shown at 6.6 px: at 0.5 they were under-sampled
    (r"^window/portrait_ring$", 0.75),     # 197 px shown at 95
    (r"^window/frame_gem_", 0.5),          # 160 px corners shown at 60
    (r"^window/", 0.5),                    # 50 px edges shown at 19
    (r"^buttons/checkbox_", 1.0),          # 43 px shown at 26
    (r"^buttons/cog_", 0.75),              # 50 px shown at 23
    (r"^buttons/(redbtn|textbtn)_", 0.4),  # 89 px plates shown at 24
    (r"^buttons/", 0.5),                   # slot rims 135 px shown at 48-55, arrows 44 at 16, close 64 at 24
    (r"^lists/(catplate|category|row)_", 0.4),   # 101 / 71 px plates shown at 25
    (r"^lists/scrolltrack_", 0.35),
    (r"^lists/", 0.5),                     # row plates 71 at 24-30, headers 82 at 20-29, thumb 33 at 10
    (r"^bars/trough_v$", 0.35),            # 41 px shown at 8
    (r"^bars/", 0.5),                      # brackets 64 px shown at 23-29
    (r"^tabs/", 0.5),                      # title plate 89 px shown at 30
    (r"^inputs/", 0.5),                    # plates 57 px shown at 20
    (r"^tiles/", 0.5),                     # 512 px shown at 192 per repeat
    (r"^deco/rail_", 0.35),
    (r"^deco/gem", 1.0),                   # the 25 px gems: shown at 9-15 (route dots, joints) — at 0.5 the 12 px art in a 16 px file did not show on the map
    (r"^deco/", 0.5),
    (r"^backdrops/page_stone$", 0.75),     # 1024 px shown at 669 (768 in a 1024 file)
    (r"^backdrops/page_parchment$", 1.0),  # 1024 px shown at 806 (the spell book page)
    (r"^backdrops/profession_(cooking|fishing|firstaid)", 0.5),   # 512 px shown at 225 (columns cropped)
    (r"^backdrops/", 1.0),                 # the tall profession panels: 352 px shown at 360
    (r"^icons/", 0.5),                     # 192 px round icons shown at 62 (the portrait)
    (r"^cards/mining$", 0.6),              # 1024 px shown at 531
    (r"^cards/", 0.8),                     # 804 px shown at 531
]


def density(name):
    for pattern, d in DENSITY:
        if re.search(pattern, name):
            return d
    return 0.5


# The action buttons' thin rims (user, 2026-09-23: the action bar buttons "need
# to get a thinner border", the gems moving to one backdrop round the whole
# bar; then five looks to choose from, A B C D F of rim_options.png): the slot
# rim's own metal swept round a square, no gems. Each pixel takes the slot
# rim's pixel at the same relative depth on the same side, from the stretch
# of that edge between the corner gems, so the bevel's light and the iron's
# grain carry over; the corners mitre where the sides meet (or round off).
THIN_SIZE = 128
SLOT_RIM = {"top": (6, 27), "bottom": (124, 102), "left": (7, 28), "right": (127, 106)}   # outer, inner edge per side (first / last opaque px)
SLOT_CLEAR = (40, 95)          # along each edge, the stretch clear of the corner gems
# family -> look: t the rim's thickness (2x px; the slot's is 22), radius a
# rounded outer corner, gold a gold line on the inner edge, shadow a soft
# shadow inside the rim (kept under the opening's alpha 128, so the icon
# still fills the opening and the shadow lies over its edge)
THIN_RIMS = {
    "rim": {"t": 13},                       # A  Thin iron
    "rimhair": {"t": 8},                    # B  Hairline
    "rimround": {"t": 12, "radius": 20},    # C  Rounded corners
    "rimgold": {"t": 13, "gold": 3},        # D  Iron with a gold inner line
    "rimsunk": {"t": 13, "shadow": 12},     # F  Sunk: an inner shadow
}
GOLD = (222, 170, 58)                       # the checked slot's gold, a little lifted

# The thin rims as RINGS (buttons/roundrim<family>_<state>; user, 2026-09-23,
# stage 2 of one border per kind: "Round ... Borders"): a circle in the
# rim's thickness, its bevel the slot rail's own profile sampled by the
# distance in from the ring's outer edge (both dark edge lines kept), the
# outer edge anti-aliased; gold / shadow as the square looks. The rounded-
# corners look has no ring of its own (a ring is round already).
ROUND_RIMS = ("rim", "rimhair", "rimgold", "rimsunk")


def thin_ring(a, t=13, radius=0, gold=0, shadow=0):
    n = THIN_SIZE
    out = np.zeros((n, n, 4), np.uint8)
    c = (n - 1) / 2
    R = n / 2
    o, i = SLOT_RIM["top"]
    along = (SLOT_CLEAR[0] + SLOT_CLEAR[1]) // 2           # a clean column of the slot's top rail
    for y in range(n):
        for x in range(n):
            depth = R - math.hypot(x - c, y - c)             # px in from the ring's outer edge
            if depth < 0:
                continue
            if depth >= t:
                if shadow and depth < t + shadow:
                    out[y, x] = (0, 0, 0, int(120 * (1 - (depth - t) / shadow)))
                continue
            sd = band_px(o, i, int(depth), t)
            px = a[min(max(sd, 0), a.shape[0] - 1), along].copy()
            if gold and depth >= t - gold:
                px[:3] = (px[:3] * 0.15 + np.array(GOLD) * 0.85).astype(np.uint8)
                px[3] = 255
            if depth < 1:                                    # the outer edge anti-aliased
                px[3] = int(px[3] * depth)
            out[y, x] = px
    return out


# The thin rims as BAR brackets (bars/<family>_cap_l / _mid / _cap_r; user,
# 2026-09-23: "onto the Reputation Progress Bars next"): the rim's top and
# bottom rows (its rail and BAR_HOLLOW px of its hollow each) stacked into a
# band, cut into a left cap, a middle that repeats and a right cap. The
# opening is about the ornate bracket's share of its height (0.52), so the
# fill keeps its size whichever bracket a bar wears.
BAR_HOLLOW = 14
BAR_CAP = 32                                 # px: a cap's width (clear of a rounded corner)
BAR_MID = 32                                 # px: the repeating middle, from the rim's middle columns


def thin_bar(rim, t, part):
    n = rim.shape[0]
    k = t + BAR_HOLLOW
    band = np.concatenate((rim[:k], rim[n - k:]), axis=0)
    if part == "cap_l":
        return band[:, :BAR_CAP].copy()
    if part == "cap_r":
        return band[:, n - BAR_CAP:].copy()
    c = n // 2
    return band[:, c - BAR_MID // 2:c + BAR_MID // 2].copy()


def band_px(outer, inner, depth, size):
    """The source pixel at `depth` (0 .. size-1) across a rail that runs from
    `outer` to `inner` (both its own pixels, either way round): every pixel of
    it reachable, the dark line on each edge included (user, 2026-09-23:
    "some textures have a shadow effect" -- the rail's dark inner line is its
    shadow on the stone; a sweep that stopped one pixel short dropped it)."""
    n = abs(inner - outer) + 1
    step = 1 if inner >= outer else -1
    return outer + step * min(n - 1, int((depth + 0.5) * n / size))


def thin_rim(a, t=13, radius=0, gold=0, shadow=0):
    n = THIN_SIZE
    out = np.zeros((n, n, 4), np.uint8)
    span = SLOT_CLEAR[1] - SLOT_CLEAR[0]
    for y in range(n):
        for x in range(n):
            d = {"top": y, "bottom": n - 1 - y, "left": x, "right": n - 1 - x}
            side = min(d, key=d.get)
            depth = d[side]
            if radius and (x < radius or x > n - 1 - radius) and (y < radius or y > n - 1 - radius):
                cx = min(max(x, radius), n - 1 - radius)
                cy = min(max(y, radius), n - 1 - radius)
                dist = math.hypot(x - cx, y - cy)
                if dist > radius:
                    continue                                 # outside the rounded corner
                depth = radius - dist
            if depth >= t:
                if shadow and depth < t + shadow:
                    out[y, x] = (0, 0, 0, int(120 * (1 - (depth - t) / shadow)))
                continue
            o, i = SLOT_RIM[side]
            sd = band_px(o, i, int(depth), t)             # the source's depth, outer -> inner (both edge lines)
            along = SLOT_CLEAR[0] + int((x if side in ("top", "bottom") else y) * span / n)
            sy, sx = (sd, along) if side in ("top", "bottom") else (along, sd)
            px = a[min(max(sy, 0), a.shape[0] - 1), min(max(sx, 0), a.shape[1] - 1)].copy()
            if gold and depth >= t - gold:
                px[:3] = (px[:3] * 0.15 + np.array(GOLD) * 0.85).astype(np.uint8)
                px[3] = 255
            out[y, x] = px
    return out


# Seamless tiles cut from a page picture: tiles/concrete (user, 2026-09-23:
# "another Background texture ... the light cracked concrete", the page
# stone's plain middle, clear of its gothic columns) and tiles/vellum, made
# by image quilting rather than a straight cross-fade (user, 2026-09-23: the
# faded band showed as a line across the bag window, "make the breakup
# seamless like the picture has been generated"): the cut is taken with a
# margin of the page around it; where the tile wraps, the page's texture
# past one edge and before the other overlap by 2 x margin, and the seam
# between them runs along the path where they differ least (a minimum-error
# cut, feathered a few px), first across the columns, then across the rows.
# The cut is then brought down to the tile's 512 px, so its grain matches the
# window stone's (user: the concrete "still scaled up a bit" next to it).
QUILT_FEATHER = 3


def _min_cut(err):
    """Top-to-bottom path of least summed error through err (rows x cols)."""
    h, w = err.shape
    cost = err.copy()
    back = np.zeros((h, w), dtype=np.int64)
    for y in range(1, h):
        prev = cost[y - 1]
        left = np.concatenate(([np.inf], prev[:-1]))
        right = np.concatenate((prev[1:], [np.inf]))
        stack = np.stack((left, prev, right))
        k = stack.argmin(axis=0)
        back[y] = np.arange(w) + k - 1
        cost[y] += stack.min(axis=0)
    path = np.zeros(h, dtype=np.int64)
    path[-1] = int(cost[-1].argmin())
    for y in range(h - 1, 0, -1):
        path[y - 1] = back[y, path[y]]
    return path


def _wrap_columns(img, n, m):
    """img: rows x (n + 2m) cols; returns rows x n, seamless across its wrap."""
    tail = img[:, n:n + 2 * m]          # the page past the cut's right edge (continuing it)
    head = img[:, 0:2 * m]              # the page before the cut's left edge (leading into it)
    err = ((tail[..., :3] - head[..., :3]) ** 2).sum(axis=2)
    path = _min_cut(err)
    x = np.arange(2 * m)[None, :]
    t = np.clip((x - path[:, None]) / QUILT_FEATHER + 0.5, 0, 1)[..., None]   # 0: tail, 1: head
    band = tail * (1 - t) + head * t
    out = img[:, m:m + n].copy()
    out[:, n - m:] = band[:, :m]        # the band's left half ends the tile ...
    out[:, :m] = band[:, m:]            # ... its right half starts it (they meet on the wrap)
    return out


def quilt_tile(a, cut, margin, size=512):
    x0, y0, x1, y1 = cut
    n = x1 - x0
    src = a[y0 - margin:y1 + margin, x0 - margin:x1 + margin].astype(float)
    cols = _wrap_columns(src, n, margin)                                  # (n + 2m) x n
    rows = _wrap_columns(cols.transpose(1, 0, 2), n, margin).transpose(1, 0, 2)
    rows[..., 3] = 255
    im = Image.fromarray(np.clip(rows, 0, 255).astype(np.uint8))
    return np.array(im.resize((size, size), Image.LANCZOS))


# The painted background tiles (tiles/*, window/*_body) were drawn "seamless"
# but carry seam marks near their edges (tiles/stone: a dark line 7 px above
# its bottom edge, drawn as a straight line across every repeat -- user,
# 2026-09-23, the bag window: "i have marked you the visible line"; the
# window body 3 px above its bottom, the iron plate down its right edge):
# their outer SELF_TRIM px are dropped and the wrap made again by the same
# quilting, the tile's own texture past one edge overlapping its other edge.
SELF_TRIM = 12
SELF_MARGIN = 32


def self_quilt(a):
    t = a[SELF_TRIM:-SELF_TRIM, SELF_TRIM:-SELF_TRIM].astype(float)
    h, w = t.shape[:2]
    cols = _wrap_columns(t, w - 2 * SELF_MARGIN, SELF_MARGIN)
    rows = _wrap_columns(cols.transpose(1, 0, 2), h - 2 * SELF_MARGIN, SELF_MARGIN).transpose(1, 0, 2)
    rows[..., 3] = 255                  # a background is opaque
    return np.clip(rows, 0, 255).astype(np.uint8)


CONCRETE_QUILT = ((160, 88, 864, 792), 48)     # a 704 px square of the stone page, clear of its columns and rim
VELLUM_QUILT = ((192, 124, 832, 764), 48)      # a 640 px square of the parchment, clear of its burnt edge


# tiles/vellum (user, 2026-09-23: backgrounds keep one resolution across the
# UI, never stretched): the parchment page (backdrops/page_parchment) is a
# picture with darkened, burnt edges, fitted to each page by stretching; its
# plain middle made seamless the same way, then brought to the whole page's
# average brightness (the kit's one parchment tint was chosen on that)


def vellum_tile(a):
    opaque = a[..., 3] > 128
    lum = lambda px: (0.299 * px[..., 0] + 0.587 * px[..., 1] + 0.114 * px[..., 2])
    target = lum(a[opaque].astype(float)).mean()
    t = quilt_tile(a, *VELLUM_QUILT).astype(float)
    t[..., :3] *= target / lum(t).mean()
    return np.clip(t, 0, 255).astype(np.uint8)


# deco/barjoin (user, 2026-09-23: "when the backdrop is not equally wide ...
# make a L shapped texture that aplies here"): where a narrower backdrop meets
# a wider one (the bag bar on the micro menu, a bar snapped to Action Bar 1)
# the narrower one's side rail runs down into the wider one's top rail. This
# is the square where the two rails cross, mitred on its diagonal: the part
# nearer the vertical rail's inner side is that rail (the slot's left rail,
# sampled at its depth), the rest the horizontal rail (the slot's top rail).
# Drawn for the left-hand step with the narrower frame above; the Lua mirrors
# it for the others.
JOIN_SIZE = 44

# The backdrops' border (deco/barframe_red / _iron): the slot rim with its top
# and bottom rails HEAVIER than its sides (user, 2026-09-23: "across the whole
# UI thats the consistent theme, vertical borders ... are in general thiner
# than the horizontal ones", drawn on the L joint): each horizontal rail
# stretched inward by FRAME_HEAVY px (22 -> 28), its bevel spread over the new
# width; beside the corner gems only the empty pixels under the rail are
# filled (from a clean column of it), so the gems keep their shape.
FRAME_HEAVY = 6
FRAME_CLEAN_X = 36        # the first column past a corner gem: pure rail on the rows of the band
FRAME_SIDE = 29           # the side rails' inner edge: the columns left of it (and right of w - it) are theirs
GEM_R = 18                # the corner gems: diamonds of this radius on their corner (outline included)


def heavy_frame(a):
    h, w = a.shape[:2]
    out = a.copy()
    centres = [(GEM_R, GEM_R), (w - 1 - GEM_R, GEM_R), (GEM_R, h - 1 - GEM_R), (w - 1 - GEM_R, h - 1 - GEM_R)]

    def gem(x, y):
        return any(abs(x - cx) + abs(y - cy) <= GEM_R for cx, cy in centres)

    top_o, top_i = SLOT_RIM["top"]            # 6, 27: 22 px
    bot_o, bot_i = SLOT_RIM["bottom"]         # 124, 102: 23 px
    heavy_t = (top_i - top_o + 1) + FRAME_HEAVY
    heavy_b = (bot_o - bot_i + 1) + FRAME_HEAVY
    for x in range(FRAME_SIDE, w - FRAME_SIDE):
        # the rail's colour at a depth: this column's, or a clean column's
        # where the gem stands on the rail; each rail stretched by its own
        # depth, so both keep their dark edge lines
        clean = FRAME_CLEAN_X if x < w // 2 else w - 1 - FRAME_CLEAN_X
        for i in range(heavy_t):
            y, sy = top_o + i, band_px(top_o, top_i, i, heavy_t)
            if not gem(x, y):
                out[y, x] = a[sy, x] if not gem(x, sy) else a[sy, clean]
        for i in range(heavy_b):
            y, sy = bot_o - i, band_px(bot_o, bot_i, i, heavy_b)
            if not gem(x, y):
                out[y, x] = a[sy, x] if not gem(x, sy) else a[sy, clean]
    return out


def bar_join(a):
    """a: the heavy frame (its top rail FRAME_HEAVY px deeper than the slot's)."""
    n = JOIN_SIZE
    out = np.zeros((n, n, 4), np.uint8)
    top_o, top_i = SLOT_RIM["top"][0], SLOT_RIM["top"][1] + FRAME_HEAVY
    left_o, left_i = SLOT_RIM["left"]
    for j in range(n):              # down, from the horizontal rail's outer (top) edge
        for i in range(n):          # right, from the vertical rail's outer (left) edge
            if i > j:
                out[j, i] = a[62, band_px(left_o, left_i, i, n)]   # the slot's left rail, half way down
            else:
                out[j, i] = a[band_px(top_o, top_i, j, n), 67]     # the (heavy) top rail, half way along
    return out


def main():
    red_gems = "--red-gems" in sys.argv
    no_looks = "--no-looks" in sys.argv
    man = json.load(open(os.path.join(SRC, "manifest.json")))
    pieces = {}
    toned = 0
    # (manifest key of the source, piece written, how): "tone" the kit piece
    # (its decorative gems to iron), "keep" it as painted, "thin" the slot rim
    jobs = [(key, key.split("/", 1)[1], "tone") for key in sorted(man)]
    if not red_gems:
        # a red copy of a few toned pieces, for the places red is asked for
        # (the health bar's end gem: its "red" state, kit_gems.RED_VARIANTS)
        jobs += [(key, key.split("/", 1)[1] + "_red", "keep") for key in sorted(man)
                 if key.split("/", 1)[1] in kit_gems.RED_VARIANTS]
    # the backdrops' border, cut as a nine-slice round a bar (ActionBarPanel):
    # the slot rim with heavier top and bottom rails, its gems red as painted
    # or toned to iron
    jobs += [(key, "deco/barframe_red", "frame_red") for key in man if key.split("/", 1)[1] == "buttons/slot_normal"]
    jobs += [(key, "deco/barframe_iron", "frame_iron") for key in man if key.split("/", 1)[1] == "buttons/slot_normal"]
    # the thin rims: each look, in each state the slot is painted in
    for family in THIN_RIMS:
        jobs += [(key, "buttons/" + family + "_" + key.split("/", 1)[1].split("_", 1)[1], "thin:" + family) for key in sorted(man)
                 if re.fullmatch(r"buttons/slot_(normal|hover|pressed|checked)", key.split("/", 1)[1])]
    # the thin rims as rings: each look (not the rounded one) in each state the slot is painted in
    for family in ROUND_RIMS:
        jobs += [(key, "buttons/round" + family + "_" + key.split("/", 1)[1].split("_", 1)[1], "ring:" + family) for key in sorted(man)
                 if re.fullmatch(r"buttons/slot_(normal|hover|pressed|checked)", key.split("/", 1)[1])]
    # the thin rims as bar brackets: each look, its caps and middle
    for family in THIN_RIMS:
        jobs += [(key, "bars/" + family + "_" + part, "bar:" + family + ":" + part) for key in man
                 if key.split("/", 1)[1] == "buttons/slot_normal" for part in ("cap_l", "mid", "cap_r")]
    jobs += [(key, "tiles/concrete", "concrete") for key in man if key.split("/", 1)[1] == "backdrops/page_stone"]
    jobs += [(key, "tiles/vellum", "vellum") for key in man if key.split("/", 1)[1] == "backdrops/page_parchment"]
    jobs += [(key, "deco/barjoin", "join") for key in man if key.split("/", 1)[1] == "buttons/slot_normal"]
    for key, out_name, how in jobs:
        name = key.split("/", 1)[1]                      # "window/frame_tl": the source, whose rules the piece follows
        a = np.array(Image.open(os.path.join(SRC, name + ".png")).convert("RGBA"))
        if how == "tone" and not red_gems:
            a, changed = kit_gems.tone(name, a)
            toned += 1 if changed else 0
        logical = None
        if how in ("tone", "keep") and tile_axes(name) == "xy":
            # a background tile: its wrap made seamless again; its piece size
            # keeps the painting's scale (the file is still power-of-two)
            h0, w0 = a.shape[:2]
            a = self_quilt(a)
            logical = (round(a.shape[1] * pot_near(w0) / w0), round(a.shape[0] * pot_near(h0) / h0))
            a = np.array(Image.fromarray(a).resize(logical, Image.LANCZOS))
        elif how.startswith("thin:"):
            a = thin_rim(a, **THIN_RIMS[how[5:]])
        elif how.startswith("ring:"):
            family = how[5:]
            a = thin_ring(a, **THIN_RIMS[family])
        elif how.startswith("bar:"):
            _, family, part = how.split(":")
            a = thin_bar(thin_rim(a, **THIN_RIMS[family]), THIN_RIMS[family]["t"], part)
            name = out_name                  # a bar piece from here on (its middle tiled)
        elif how == "join":
            a = bar_join(heavy_frame(kit_gems.tone(name, a)[0]))
            name = out_name
        elif how == "frame_red":
            a = heavy_frame(a)
        elif how == "frame_iron":
            a = heavy_frame(kit_gems.tone(name, a)[0])
        elif how == "concrete":
            a = quilt_tile(a, *CONCRETE_QUILT)
            name = out_name                  # a tile from here on: tiled, at a tile's density
        elif how == "vellum":
            a = vellum_tile(a)
            name = out_name
        h, w = a.shape[:2]
        axes = tile_axes(name)
        fw = pot_near(w) if "x" in axes else pot_up(w)
        fh = pot_near(h) if "y" in axes else pot_up(h)
        im = Image.fromarray(a)
        if "x" in axes or "y" in axes:
            im = im.resize((fw if "x" in axes else w, fh if "y" in axes else h), Image.LANCZOS)
        pw, ph = im.size
        # the file: the piece at its density, on a power-of-two canvas (a
        # tiled axis stays exactly power-of-two: densities are 1, 1/2, 1/4
        # for tiled pieces)
        d = density(name)
        sw, sh = max(1, round(pw * d)), max(1, round(ph * d))
        # a tiled axis must fill its power-of-two file exactly (REPEAT wraps
        # the whole file): snap that axis to the nearest power of two
        if "x" in axes:
            sw = pot_near(sw)
        if "y" in axes:
            sh = pot_near(sh)
        small = im if (sw, sh) == (pw, ph) else im.resize((sw, sh), Image.LANCZOS)
        cw = sw if "x" in axes else pot_up(sw)
        ch = sh if "y" in axes else pot_up(sh)
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        canvas.paste(small, (0, 0))
        # a piece tiled along ONE axis is sampled with REPEAT on both (one
        # wrap mode per texture): the empty rows / columns past it would then
        # bleed into its outer edge through the filter (the title plate's
        # middle showed a thinner top rail than its caps, 2026-09-21). The
        # padding repeats the piece's own edge rows / columns instead, the
        # far half wrapping round to the first edge.
        arr = np.array(canvas)
        if "x" in axes and "y" not in axes and sh < ch:
            half = (sh + ch) // 2
            for r in range(sh, ch):
                arr[r] = arr[sh - 1] if r < half else arr[0]
        if "y" in axes and "x" not in axes and sw < cw:
            half = (sw + cw) // 2
            for c in range(sw, cw):
                arr[:, c] = arr[:, sw - 1] if c < half else arr[:, 0]
        canvas = Image.fromarray(arr)
        path = os.path.join(OUT, out_name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        canvas.save(path)
        arr2 = np.array(im)
        m = arr2[..., 3] > 128
        ys, xs = np.where(m)
        box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1) if len(ys) else (0, 0, pw, ph)
        if logical:
            pw, ph = logical
            box = (0, 0, pw, ph)
        entry = {
            "file": out_name.replace("/", "\\\\"),
            "w": pw, "h": ph,                             # piece px as painted (2x); the file may hold fewer (density)
            "uv": (0.0, sw / cw, 0.0, sh / ch),
            "tile": axes or None,
            "box": box,                                   # the opaque part of the piece, in piece px
        }
        op = opening(np.array(im))
        cap = re.search(r"^bars/.*_cap_([lr])$", name)
        if cap:
            op = cap_hollow(np.array(im), cap.group(1))
        if op and re.search(r"(slot_|roundslot_|portrait_ring|card_|/frame_mid|castbar_mid|frame_cap|castbar_cap|bars/rim[a-z]*_(cap_[lr]|mid)|buttons/roundrim|checkbox|orb_|cog_|arrow_|plus_|minus_|close_)", name):
            entry["open"] = op
        if "overhang" in man[key]:
            entry["overhang"] = int(man[key]["overhang"])   # oversized corners: how far past the frame's corner they reach
        if re.search(r"(portrait_ring|roundslot_|roundrim|orb_)", out_name):
            entry["radius"] = body_radius(np.array(im))    # the round body without its compass gems
        pieces[out_name] = entry

    # ---- Lua
    def num(v):
        return ("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)
    lines = [
        "-- Generated by Tools/build_kit.py from Tools/pack_sources/kit/v2_2x. Do not edit by hand.",
        "--",
        "-- One entry per painted kit piece (naming per docs/UI-KIT.md):",
        "--   file  path under Media\\Kit (no extension)",
        "--   w, h  size of the piece as painted (2x px); the file holds it at a lower density, the uv accounts for that",
        "--   uv    left, right, top, bottom of the piece inside its power-of-two file",
        "--   tile  \"x\", \"y\" or \"xy\": the file repeats exactly along that axis (use REPEAT wrap)",
        "--   box   left, top, right, bottom of the opaque part of the piece, in piece pixels (strips fit and centre by it)",
        "--   open  left, top, right, bottom of the transparent interior, in piece pixels",
        "--   overhang  an oversized corner: how far its rails' outer edges sit inside its canvas, in piece pixels (the gem reaches that far past the frame)",
        "--   radius  a round piece's body radius from its centre, in piece pixels, without the gems at its compass points",
        "",
        "MelloUI_KitLayout = {",
        "\troot = \"Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Kit\\\\\",",
        "\tpieces = {",
    ]
    for name in sorted(pieces):
        p = pieces[name]
        s = "\t\t[\"%s\"] = { file = \"%s\", w = %d, h = %d, uv = { %s }" % (
            name, p["file"], p["w"], p["h"], ", ".join(num(v) for v in p["uv"]))
        if p["tile"]:
            s += ", tile = \"%s\"" % p["tile"]
        s += ", box = { %s }" % ", ".join(str(v) for v in p["box"])
        if "open" in p:
            s += ", open = { %s }" % ", ".join(str(v) for v in p["open"])
        if "overhang" in p:
            s += ", overhang = %d" % p["overhang"]
        if "radius" in p:
            s += ", radius = %d" % p["radius"]
        lines.append(s + " },")
    lines += ["\t},", "}", ""]
    with open(LUA, "w", newline="\n") as f:
        f.write("\n".join(lines))
    total = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(OUT) for fn in fns)
    print(f"{len(pieces)} pieces -> Media/Kit ({total / 1e6:.1f} MB), Media/KitLayout.lua"
          + ("; red gems kept" if red_gems else f"; gems toned to iron in {toned}")
          )
    if not no_looks:
        for look, (n, size) in kit_palette.build_looks(OUT).items():
            print(f"  {look}: {n} pieces recoloured -> Media/{kit_palette.LOOKS[look][0]} ({size / 1e6:.1f} MB)")
    if "--report" in sys.argv:
        for name in sorted(pieces):
            p = pieces[name]
            print(f"  {name:40} painted {p['w']}x{p['h']}  density {density(name)}")


if __name__ == "__main__":
    main()
