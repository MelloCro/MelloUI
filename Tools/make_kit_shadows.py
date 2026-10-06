"""
Build the kit's SHADOW PARTNERS: a soft, dark copy of a kit piece's own shape
that MelloUI lays under the piece (Kit:Shadow, Kit:ShadowNine, Modules/Kit.lua),
so every element of the UI stands off the world with a shade that follows its
outline (user, 2026-09-26: the whole-UI shade, outline pieces only). The
nameplates' "Whole plate" shade (user, 2026-09-25: the bracket's caps and rail
and the level orb) and Route's World Marker gem were the first users; their
shadows are made exactly as before (LEGACY: the same bytes). (Route's
direction arrow and the marker's edge arrow are the game's own atlas, not a
kit piece: they take a round soft band, MelloUI.Shade, instead.)

The game cannot blur what is behind a frame, so the blur is made here, once:
each piece's alpha (from its TGA master, at its painted 2x size) is grown by a
few px, blurred (a gaussian), and stored WHITE with that alpha at a quarter of
the painted size (the blur loses nothing), all in one sheet. The game tints it
with a palette colour at the chosen strength. The shapes are the same in every
palette and Kit Colours look, so one set serves them all.

What the sheet holds (MelloUI_KitShadows, version 2):
  pieces  the OUTLINE SET (SHADOWED): the pieces that stand against the world
          at an element's edge (window rails, gem corners, title plates, rings,
          bar brackets, action-bar frames and end caps, slot rims, header and
          edit plates, icon plates). A partner on an inner piece would only
          darken the window's own stone.
          - A STRIP (<base>_cap_l, _mid, _cap_r, and _end_l / _end_r where the
            kit has them) is blurred WHOLE, so its parts join without a seam: a
            cap's shadow reaches past its outer side only, the middle's is the
            rail's profile across (one column, stretched along the rail in
            game), and a cap's inner end is eased onto that profile. A middle
            also carries soft ENDS (endL, endR) for a strip drawn without a cap
            on that side (dropCap, capless): a partner just past the middle's
            end, fading outward, its inner column the middle's profile.
          - A NINE-SLICE family's pieces (window/frame_*, window/single_*) are
            parts of that family's nine (below): their uv lies in it.
          - Any other piece is blurred alone, reaching past all four sides.
          - OUTSIDE ONLY: a piece with an opening (its `open` box, or ring:
            a rim round an icon, the ring round a portrait) is one shape with
            what it holds, so the opening counts as filled for the blur (a
            hairline rim's shade is then about 30 levels stronger); then
            nothing is kept inward of the middle of its rim: nothing darkens a
            slot's icon or shows through a translucent body.
          - Pieces whose shadows differ by at most ALIAS_TOL levels (a rim's
            states, rim looks of one outline) share one: the piece is written
            as the name of the first. A strip's parts share only all together,
            so a cap still meets its own middle's profile. The LEGACY pieces
            share only exact twins (as in 0.13.7).
          - The marks' metal twins (TWINS: a level orb or a left cap in
            gold, silver or red-bronze, Tools/kit_marks.py) are their plain
            piece recoloured: written as that piece's name.
  nines   window/frame, window/single, deco/barframe_red|iron: the rails
          assembled (corners and repeated edges, the body inside them counted
          as filled: the element is one shape; that adds only a few levels to
          the outer profile, where a hairline rim round an opening gains
          about 30) and blurred whole, then kept as the four corners and one
          edge PROFILE per side (the same along the edge:
          stretched in game). Outside only: alpha 0 inward of the rails' middle
          line, where the body lies. `corner` and `margins` say where to cut
          the picture into nine.
  shapes  synthetic shade/square (a filled box, cut into nine), shade/capsule
          (a pill: its ends cut, its middle stretched) and shade/round (a disc):
          for frames that have no kit piece (the game's event widgets). These
          are FILLED (the drop shadow of a solid shape), the one exception to
          outside only: under a translucent body they darken its inside.
A family listed in FAMILY_SCALE (drawn at s x the kit's scale: the single
rail, 1.6 x) is blurred at SIGMA / s, so its reach on screen is the kit's.
Every other piece is blurred at the kit's scale, so one drawn larger or
smaller reaches that much further or less far on screen (a title plate at
1.4 - 1.5 x; the ring, whose size follows its host: roughly 0.8 - 1.4 x on
windows and unit frames, about 3 x round the minimap, by the Kit's sizing).

Reads   the masters (Tools/paths.py): masters/Media/KitLayout.lua (each piece
        in its own file, build_kit.py's) and each piece's TGA master
Writes  masters/Media/Textures/KitShadows.tga   the sheet (32-bit TGA master)
        Media/Textures/KitShadows.tga           a byte copy, so it ships at once
                                                (texture_pack.py: STAY_TGA)
        Media/KitShadows.lua                    MelloUI_KitShadows: the sheet's
                                                path; per piece its uv in the
                                                sheet and its pad (painted px
                                                past the piece: left, top,
                                                right, bottom); the nines and
                                                the shapes
Deterministic: the same masters give the same bytes. build_kit.py runs it
after the kit (so the shadows follow a rebuilt kit); then texture_pack.py
ship. New files need a full client restart.

The addon's two files (the sheet's copy and KitShadows.lua) are written only
from the default masters, the sibling MelloUI-BuildData's: a build against
another masters folder (MELLOUI_BUILD_DATA pointing elsewhere: a test's or a
sandbox's) writes the master alone and leaves what ships as it is, unless
--addon asks for them.

    python Tools/make_kit_shadows.py            write all three
    python Tools/make_kit_shadows.py --check    exit 1 unless all three are up to date
    python Tools/make_kit_shadows.py --addon    (with either: the addon's files too,
                                                whatever masters folder is used)
    python Tools/make_kit_shadows.py --gate     the DXT5 banding gate (texture_pack.py
                                                compresses the sheet only if it passes;
                                                it does not: STAY_TGA)
"""
import hashlib
import io
import math
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from paths import ADDON_MEDIA, MASTER_MEDIA, MASTERS, SIBLING, master  # noqa: E402

LAYOUT_LUA = os.path.join(MASTER_MEDIA, "KitLayout.lua")
KIT = os.path.join(MASTER_MEDIA, "Kit")
SHEET = ("Textures", "KitShadows.tga")
LUA = os.path.join(ADDON_MEDIA, "KitShadows.lua")
GAME_PATH = "Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Textures\\\\KitShadows"
VERSION = 2

# The OUTLINE SET: the pieces that get a shadow (a regex on the piece name),
# by where they stand against the world
SHADOWED = [
    # nameplates and unit frames: every bar bracket look (Bar Border / Nameplate
    # Border), the level orb; Route's World Marker gem (over the destination)
    r"^bars/[a-z]+_(cap_l|mid|cap_r)(_[a-z]+)?$",
    r"^buttons/orb_(normal|hover|pressed)$",
    r"^deco/gem_large$",
    # windows: the outer rail (its nine), its gem corners, the title plate
    # (open; title: the tracker's, the unit frames' name band, the minimap's
    # zone band), the corner ring (and the minimap's round frame)
    r"^window/frame_(t|b|l|r|tl|tr|bl|br)$",
    r"^window/frame_gem_(tl|tr|bl|br)$",
    r"^tabs/top_(cap_l|mid|cap_r)_(open|plain|title)$",
    r"^window/portrait_ring$",
    # the single rail (its nine): chat, whispers, the tracker, insets, tabs,
    # the party backdrop
    r"^window/single_(t|b|l|r|tl|tr|bl|br)$",
    # action bars: the backdrop frames (whole, and cut as nines), their joins,
    # the end caps; the square rims when a bar has no backdrop (and the auras')
    r"^deco/barframe_(red|iron)$",
    r"^deco/barjoin$",
    r"^deco/rail_cap_[lr]$",
    r"^buttons/(rim|rimgold|rimhair|rimround|rimsunk|slot)_(normal|hover|pressed|checked)$",
    # the round rims: the minimap's tracking button, the auras' and spells' round looks
    r"^buttons/(roundrim|roundrimgold|roundrimhair|roundrimsunk|roundslot)_(normal|hover|pressed|checked)$",
    # the cast bar's text plate and the header plates; the chat's edit box and icon plates
    r"^lists/header_(cap_l|mid|cap_r)$",
    r"^inputs/edit_(cap_l|cap_r|end_l|mid)_(normal|focused)$",
    r"^buttons/cog_(normal|hover|pressed)$",
    # the Elite / Rare / Boss marks (Tools/kit_marks.py): the unit frames' metal rings with their crest on
    # the top gem, the nameplates' crests before the name
    r"^marks/(ring|crest)_[a-z]+$",
    # the nameplates' mark on top (2026-10-05): its crest, a plain line's end gems, a boss's line ends and beads
    # (the line itself, thin and stretched, has none)
    r"^marks/top(crest_[a-z]+|gem_[a-z]+|end_boss_[lr]|bead_boss)$",
]
# The marks' metal twins (Tools/kit_marks.py): a piece recoloured, its shape its plain piece's, so it uses
# that piece's shadow (written as the plain piece's name): the level orb's, a Nameplate Border's left cap's
TWINS = [
    (r"^marks/orb_(gold|silver|boss)$", "buttons/orb_normal"),
    (r"^marks/cap_([a-z]+)_(gold|silver|boss)$", r"bars/\1_cap_l"),
]
# strip-named pieces drawn ALONE, not as a strip (the action bars' end caps,
# ActionBarPanel's gryphons): a shadow of their own, reaching past every side
ALONE = [r"^deco/rail_cap_[lr]$"]
# made exactly as in 0.13.7 (the nameplates' and Route's partners: the same
# bytes, the same reach; only exact twins share)
LEGACY = [r"^bars/", r"^buttons/orb_", r"^deco/gem_large$"]
# The nine-slice families: None = cut from its own corner and edge pieces
# (<family>_tl ... _br, _t, _b, _l, _r); a number = one piece cut into nine at
# that corner, its edges stretched between (ActionBarPanel's FRAME_CORNER,
# MinimapPanel's CORNER)
NINES = {
    "window/frame": None,
    "window/single": None,
    "deco/barframe_red": 40,
    "deco/barframe_iron": 40,
}
NINE_PARTS = ("tl", "t", "tr", "l", "r", "bl", "b", "br")
# how large a family is drawn, in the kit's scale (Kit.scale, 0.375 UI units
# per painted px): its blur is narrowed by it, so its reach on screen is the
# kit's (a piece drawn at several sizes, as the ring, keeps the kit's blur)
FAMILY_SCALE = [
    (r"^window/single", 1.6),   # Kit.frameScale: the single rail
]
STRIP = re.compile(r"^(?P<base>.+)_(?P<part>cap_l|mid|cap_r|end_l|end_r)(?:_(?P<state>[a-z]+))?$")
STRIP_PARTS = ("cap_l", "mid", "cap_r", "end_l", "end_r")

QUARTER = 4          # painted px per sheet texel
DILATE = 3           # painted px the shape grows before the blur (at the kit's scale)
SIGMA = 8.0          # painted px: the blur's standard deviation (at the kit's scale)
MARGIN = 28          # painted px past the piece: DILATE + 3 SIGMA, a multiple of QUARTER
MID_SPAN = 128       # painted px of repeated middle between the caps while a strip is blurred
MID_W = 4            # texels: a middle's (an edge's) shadow: its profile, the same in every column
EASE = 16            # painted px over which a cap's inner end eases onto the middle's profile
GUTTER = 2           # texels round each shadow in the sheet, its edge texels repeated into them
SHEET_W = 512        # the sheet's width; its height the next power of two that holds it
ALIAS_TOL = 8        # levels of 255: pieces whose shadows differ by no more share one
SHAPE_CORNER = 32    # painted px: shade/square's corner, shade/capsule's radius
SHAPE_SIZE = 64      # painted px: shade/round's diameter, shade/capsule's height

# The banding gate (--gate): the sheet encoded as DXT5 (Tools/blp_dxt.py) and
# decoded; it passes only if no drawn texel's alpha moves by more than
# GATE_MAX levels and the mean moves by at most GATE_MEAN. A soft shadow is a
# smooth ramp: DXT5's eight alpha steps per 4 x 4 block turn a steep one into
# visible bands.
GATE_MAX = 4
GATE_MEAN = 1.0


def ceil_to(n, k):
    return -(-n // k) * k


class Recipe:
    """How a family is blurred: grown by `dilate` px, a gaussian of `sigma`
    px, reaching `margin` px past the piece (whole texels), a cap's or
    corner's inner end eased over `ease` px. `scale`: how large the family is
    drawn (FAMILY_SCALE), so its reach on screen is the kit's."""

    def __init__(self, scale=1.0):
        self.scale = scale
        self.dilate = max(1, int(round(DILATE / scale)))
        self.sigma = SIGMA / scale
        self.margin = ceil_to(int(math.ceil(self.dilate + 3 * self.sigma)), QUARTER)
        self.ease = max(2 * QUARTER, int(round(EASE / scale)))


_RECIPES = {}


def recipe(name):
    scale = next((s for pat, s in FAMILY_SCALE if re.search(pat, name)), 1.0)
    if scale not in _RECIPES:
        _RECIPES[scale] = Recipe(scale)
    return _RECIPES[scale]


def load_layout():
    import lupa
    lua = lupa.LuaRuntime()
    lua.execute(open(LAYOUT_LUA, encoding="utf-8").read())
    pieces = lua.globals().MelloUI_KitLayout.pieces
    out = {}
    for name in pieces:
        p = pieces[name]
        e = {"file": p.file, "w": int(p.w), "h": int(p.h), "uv": [float(p.uv[i]) for i in range(1, 5)]}
        for key in ("box", "open"):
            v = p[key]
            if v is not None:
                e[key] = [float(v[i]) for i in range(1, 5)]
        if p.radius is not None:
            e["radius"] = float(p.radius)
        out[name] = e
    return out


def matches(pats, name):
    return any(re.search(pat, name) for pat in pats)


def twin_of(name):
    """The plain piece a mark's metal twin recolours (TWINS), or None."""
    for pat, to in TWINS:
        m = re.match(pat, name)
        if m:
            return m.expand(to)
    return None


def shadowed(name):
    return matches(SHADOWED, name) or twin_of(name) is not None


def legacy(name):
    # (a mark's metal twin is its plain piece's: made as that one is)
    twin = twin_of(name)
    return matches(LEGACY, twin if twin is not None else name)


def nine_family(name):
    """The nine-slice family a piece is a part of (window/frame_t -> window/frame), or None."""
    fam, _, part = name.rpartition("_")
    return fam if NINES.get(fam, 0) is None and part in NINE_PARTS else None


_ALPHA = {}
_READ_FROM = None   # a painted look's masters folder while build_look reads its pieces


def piece_alpha(p):
    """The piece's alpha at its painted size, 0..1 (read once per build; from a
    painted look's folder while build_look reads it, where it has the piece)."""
    key = (p["file"], p["w"], p["h"], tuple(p["uv"]))
    if key not in _ALPHA:
        path = os.path.join(KIT, p["file"].replace("\\", os.sep) + ".tga")
        if _READ_FROM:
            own = os.path.join(_READ_FROM, p["file"].replace("\\", os.sep) + ".tga")
            if os.path.exists(own):
                path = own
        with Image.open(path) as im:
            a = im.convert("RGBA").getchannel("A")
        cw, ch = a.size
        u0, u1, v0, v1 = p["uv"]
        a = a.crop((round(u0 * cw), round(v0 * ch), round(u1 * cw), round(v1 * ch)))
        a = a.resize((p["w"], p["h"]), Image.BILINEAR)
        _ALPHA[key] = np.asarray(a, dtype=np.float64) / 255.0
    return _ALPHA[key]


def dilate(a, r=DILATE):
    """Each px takes the largest alpha within r px (a disc)."""
    out = a.copy()
    h, w = a.shape
    padded = np.pad(a, r)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out = np.maximum(out, padded[r + dy:r + dy + h, r + dx:r + dx + w])
    return out


def blur(a, sigma=SIGMA):
    """A separable gaussian, zero outside (the canvas' margin holds the spread)."""
    rad = int(math.ceil(3 * sigma))
    x = np.arange(-rad, rad + 1, dtype=np.float64)
    k = np.exp(-(x * x) / (2 * sigma * sigma))
    k /= k.sum()
    padded = np.pad(a, rad)
    h, w = a.shape
    rows = np.zeros((h + 2 * rad, w))
    for i, kv in enumerate(k):
        rows += kv * padded[:, i:i + w]
    out = np.zeros((h, w))
    for i, kv in enumerate(k):
        out += kv * rows[i:i + h, :]
    return out


def soften(a, rec=None):
    if rec is None:
        return np.clip(blur(dilate(a)), 0.0, 1.0)
    return np.clip(blur(dilate(a, rec.dilate), rec.sigma), 0.0, 1.0)


def to_quarter(a, pad):
    """Grow the image (on its padded sides, with nothing) to whole texels,
    then a quarter of it. pad: [left, top, right, bottom] painted px; the
    sides that grow are those whose pad is not 0 (right, then bottom first)."""
    h, w = a.shape
    ew, eh = (-w) % QUARTER, (-h) % QUARTER
    l, t, r, b = pad
    if ew:
        if r:
            a, r = np.pad(a, ((0, 0), (0, ew))), r + ew
        else:
            a, l = np.pad(a, ((0, 0), (ew, 0))), l + ew
    if eh:
        a, b = np.pad(a, ((0, eh), (0, 0))), b + eh
    return quarter(a), [l, t, r, b]


def quarter(a):
    h, w = a.shape
    q = a.reshape(h // QUARTER, QUARTER, w // QUARTER, QUARTER).mean(axis=(1, 3))
    return np.clip(np.floor(q * 255 + 0.5), 0, 255).astype(np.uint8)


# ------------------------------------------------------------------ 0.13.7's recipe (LEGACY)

def ease(cap, profile, side):
    """A cap's inner end eased onto the middle's profile over EASE px, so the
    two partners meet on the same column."""
    cap = cap.copy()
    w = cap.shape[1]
    for i in range(min(EASE, w)):
        t = (EASE - i) / EASE                      # 1 at the joint, falling inward
        t = t * t * (3 - 2 * t)
        col = w - 1 - i if side == "l" else i
        cap[:, col] = cap[:, col] * (1 - t) + profile * t
    return cap


def strip_name(layout, base, part, state):
    name = "%s_%s" % (base, part)
    if state and "%s_%s" % (name, state) in layout:
        return "%s_%s" % (name, state)
    return name


def strip_shadows(layout, base, state, profiles=None):
    """{piece name: (quarter image, pad)} for the strip base[_state]
    (0.13.7's bar brackets); `profiles`: the middle's profile is kept there,
    by the middle's name (its soft ends are eased onto it)."""
    names = {part: strip_name(layout, base, part, state) for part in ("cap_l", "mid", "cap_r")}
    if any(n not in layout for n in names.values()):
        return {}
    L, M, R = (piece_alpha(layout[names[k]]) for k in ("cap_l", "mid", "cap_r"))
    h = L.shape[0]
    if M.shape[0] != h or R.shape[0] != h:
        raise SystemExit("strip %s: its parts are not one height (%d, %d, %d)" % (base, h, M.shape[0], R.shape[0]))
    mw = M.shape[1]
    mid = np.tile(M, (1, max(1, -(-MID_SPAN // mw))))
    wl, wm = L.shape[1], mid.shape[1]
    A = soften(np.pad(np.concatenate([L, mid, R], axis=1), MARGIN))
    c0 = MARGIN + wl + (wm - mw) // 2
    profile = A[:, c0:c0 + mw].mean(axis=1)
    if profiles is not None:
        profiles[names["mid"]] = profile
    out = {}
    cap_l = ease(A[:, :MARGIN + wl], profile, "l")
    cap_r = ease(A[:, MARGIN + wl + wm:], profile, "r")
    mid_img = np.repeat(profile[:, None], MID_W * QUARTER, axis=1)
    out[names["cap_l"]] = to_quarter(cap_l, [MARGIN, MARGIN, 0, MARGIN])
    out[names["mid"]] = to_quarter(mid_img, [0, MARGIN, 0, MARGIN])
    out[names["cap_r"]] = to_quarter(cap_r, [0, MARGIN, MARGIN, MARGIN])
    return out


def piece_shadow(layout, name):
    A = soften(np.pad(piece_alpha(layout[name]), MARGIN))
    return to_quarter(A, [MARGIN, MARGIN, MARGIN, MARGIN])


# ------------------------------------------------------------------ version 2

def ease_weights(n, rec):
    """Per column of a block whose last column meets a profile: how much of
    the profile it takes. 1 over the last QUARTER px (so the last texel IS
    the profile: no seam), then a smoothstep to 0 over rec.ease px inward."""
    w = np.zeros(n)
    for i in range(n):
        d = n - 1 - i                              # px from the joint
        if d < QUARTER:
            t = 1.0
        else:
            t = min(1.0, max(0.0, 1.0 - (d - QUARTER + 1) / rec.ease))
            t = t * t * (3 - 2 * t)
        w[i] = t
    return w


def ease_end(block, profile, rec):
    """The block's right end eased onto `profile` (by row)."""
    w = ease_weights(block.shape[1], rec)[None, :]
    return block * (1 - w) + profile[:, None] * w


def ease_corner(block, p_right, p_bottom, rec):
    """A nine's corner (its outer sides top and left) eased onto the profile
    its right end meets (p_right, by row) and the one its bottom end meets
    (p_bottom, by column): a patch whose last QUARTER columns are p_right
    and whose last QUARTER rows are p_bottom, exactly (where those meet the
    two agree: both 0 inside the rails, both 1 inside a filled box), the
    corner's own blur further in, a smooth blend between."""
    wx = ease_weights(block.shape[1], rec)[None, :]
    wy = ease_weights(block.shape[0], rec)[:, None]
    pr, pb = p_right[:, None], p_bottom[None, :]
    a, b = wx * (1 - wy), wy * (1 - wx)
    s = np.where(a + b > 0, a / np.where(a + b > 0, a + b, 1.0), 0.5)
    k = pr * s + pb * (1 - s)
    v = (1 - wx) * (1 - wy) * block + a * pr + b * pb + wx * wy * k
    return np.clip(v, 0.0, 1.0)


def open_cut(p):
    """The part of a piece inward of the middle of its rim (between its
    painted box and its opening), in piece px: ("rect", x0, y0, x1, y1) or,
    for a round piece, ("ellipse", cx, cy, rx, ry); None without an opening."""
    o = p.get("open")
    if not o:
        return None
    b = p.get("box") or [0, 0, p["w"], p["h"]]
    if p.get("radius"):
        return ("ellipse", (o[0] + o[2]) / 2, (o[1] + o[3]) / 2,
                (p["radius"] + (o[2] - o[0]) / 2) / 2, (p["radius"] + (o[3] - o[1]) / 2) / 2)
    return ("rect", (b[0] + o[0]) / 2, (b[1] + o[1]) / 2, (b[2] + o[2]) / 2, (b[3] + o[3]) / 2)


def inside(shape, cut, m):
    """How much of each px of a canvas (the piece with m px round it) lies
    inward of the rim's middle (open_cut), 0..1."""
    h, w = shape
    if cut[0] == "rect":
        _, x0, y0, x1, y1 = cut
        out = np.zeros(shape)
        out[int(round(m + y0)):int(round(m + y1)), int(round(m + x0)):int(round(m + x1))] = 1.0
        return out
    _, cx, cy, rx, ry = cut
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx + 0.5 - m - cx) / rx) ** 2 + ((yy + 0.5 - m - cy) / ry) ** 2)
    return np.clip((1.0 - d) * min(rx, ry) + 0.5, 0.0, 1.0)


def piece_shadow_v2(layout, name, rec):
    """A piece blurred alone, reaching past all four sides. With an opening
    (a rim round an icon, the ring round a portrait, a frame round its
    stone) the element is one shape: the opening counts as filled for the
    blur, then nothing is kept inward of the rim's middle (outside only)."""
    p = layout[name]
    m = rec.margin
    a = np.pad(piece_alpha(p), m)
    cut = open_cut(p)
    if cut:
        within = inside(a.shape, cut, m)
        A = soften(np.maximum(a, within), rec) * (1.0 - within)
    else:
        A = soften(a, rec)
    return to_quarter(A, [m, m, m, m])


class Uneven(ValueError):
    """A strip whose parts are not one height (window/divider, window/title):
    it cannot be blurred whole. shadows() leaves it out with a warning, so a
    kit build that shadows it by mistake is never cut short."""


def tiled_mid(M, m):
    """The middle repeated to a run whose middle column lies clear of both ends' blur."""
    mw = M.shape[1]
    return np.tile(M, (1, max(1, -(-max(MID_SPAN, 2 * m + mw) // mw))))


def strip_shadows_v2(layout, names, rec):
    """{piece name: (quarter image, pad)} for a strip: names = {part: piece}
    (cap_l, mid, cap_r and, where the kit has them, end_l / end_r); and the
    middle's profile."""
    alpha = {part: piece_alpha(layout[n]) for part, n in names.items()}
    h = alpha["mid"].shape[0]
    if any(a.shape[0] != h for a in alpha.values()):
        raise Uneven("strip %s: its parts are not one height (%s)" % (
            names["mid"], ", ".join("%s %d" % (k, a.shape[0]) for k, a in sorted(alpha.items()))))
    m = rec.margin
    mw = alpha["mid"].shape[1]
    mid = tiled_mid(alpha["mid"], m)
    wm = mid.shape[1]

    def blurred(left, right):
        return soften(np.pad(np.concatenate([left, mid, right], axis=1), m), rec)

    A = blurred(alpha["cap_l"], alpha["cap_r"])
    wl = alpha["cap_l"].shape[1]
    c0 = m + wl + (wm - mw) // 2
    profile = A[:, c0:c0 + mw].mean(axis=1)
    out = {
        names["cap_l"]: to_quarter(ease_end(A[:, :m + wl], profile, rec), [m, m, 0, m]),
        names["mid"]: to_quarter(np.repeat(profile[:, None], MID_W * QUARTER, axis=1), [0, m, 0, m]),
        names["cap_r"]: to_quarter(ease_end(A[:, m + wl + wm:][:, ::-1], profile, rec)[:, ::-1], [0, m, m, m]),
    }
    if "end_l" in names:
        we = alpha["end_l"].shape[1]
        B = blurred(alpha["end_l"], alpha["cap_r"])
        out[names["end_l"]] = to_quarter(ease_end(B[:, :m + we], profile, rec), [m, m, 0, m])
    if "end_r" in names:
        we = alpha["end_r"].shape[1]
        B = blurred(alpha["cap_l"], alpha["end_r"])
        out[names["end_r"]] = to_quarter(ease_end(B[:, -(m + we):][:, ::-1], profile, rec)[:, ::-1], [0, m, m, m])
    return out, profile


def mid_ends(M, profile, rec):
    """A middle's soft ends, for a strip drawn without a cap on that side:
    the middle blurred alone, the part past its left (right) end, whose
    inner column is eased onto the middle's profile. {"endL": (image, pad),
    "endR": ...}; each reaches rec.margin px past the middle's end."""
    m = rec.margin
    A = soften(np.pad(tiled_mid(M, m), m), rec)
    return {
        "endL": to_quarter(ease_end(A[:, :m], profile, rec), [m, m, 0, m]),
        "endR": to_quarter(ease_end(A[:, -m:][:, ::-1], profile, rec)[:, ::-1], [0, m, m, m]),
    }


def lcm(a, b):
    return a * b // math.gcd(a, b)


def nine_parts(layout, family):
    """A nine-slice family's corners and edges as painted ({tl .. br, t, b,
    l, r}: an edge is one repeat, or one column / row for a stretched
    edge) and where each rail's middle line lies (px from its outer side:
    left, top, right, bottom)."""
    corner = NINES[family]
    if corner is None:
        parts = {k: piece_alpha(layout[family + "_" + k]) for k in NINE_PARTS}
        box = {k: layout[family + "_" + k].get("box") for k in ("t", "b", "l", "r")}
        h_b, w_r = parts["b"].shape[0], parts["r"].shape[1]
        mids = [(box["l"][0] + box["l"][2]) / 2, (box["t"][1] + box["t"][3]) / 2,
                w_r - (box["r"][0] + box["r"][2]) / 2, h_b - (box["b"][1] + box["b"][3]) / 2]
        return parts, mids
    p = layout[family]
    a, c = piece_alpha(p), corner
    parts = {
        "tl": a[:c, :c], "tr": a[:c, -c:], "bl": a[-c:, :c], "br": a[-c:, -c:],
        "t": a[:c, c:-c].mean(axis=1, keepdims=True), "b": a[-c:, c:-c].mean(axis=1, keepdims=True),
        "l": a[c:-c, :c].mean(axis=0, keepdims=True), "r": a[c:-c, -c:].mean(axis=0, keepdims=True),
    }
    b, o, w, h = p["box"], p["open"], p["w"], p["h"]
    mids = [(b[0] + o[0]) / 2, (b[1] + o[1]) / 2, ((w - b[2]) + (w - o[2])) / 2, ((h - b[3]) + (h - o[3])) / 2]
    return parts, mids


def nine_shadow(parts, mids, rec, fill=False, name="nine", body=True):
    """A nine's shadow: the rails assembled (corners, edges repeated whole
    periods), blurred whole; kept as the four corners (their inner ends
    eased onto the edges' profiles) and one profile per edge, MID_W texels
    long. mids: the rails' middle lines (px from each outer side); `fill`: a
    filled box, whose middle is kept; `body`: the body inward of the rails'
    middle line counted as filled for the blur (False: the rails alone).
    (quarter image, info): pad, corner, margins, size (painted px), blocks
    (texel rects of the eight parts)."""
    tl, tr, bl, br = parts["tl"], parts["tr"], parts["bl"], parts["br"]
    t, b, l, r = parts["t"], parts["b"], parts["l"], parts["r"]
    ct, cl = tl.shape
    cr, cb = tr.shape[1], bl.shape[0]
    if (tr.shape[0], bl.shape[1], br.shape, t.shape[0], b.shape[0], l.shape[1], r.shape[1]) != (
            ct, cl, (cb, cr), ct, cb, cl, cr):
        raise SystemExit("nine %s: its corners and edges do not meet (%s)" % (
            name, ", ".join("%s %dx%d" % (k, v.shape[1], v.shape[0]) for k, v in sorted(parts.items()))))
    m = rec.margin
    px, py = lcm(t.shape[1], b.shape[1]), lcm(l.shape[0], r.shape[0])
    sx = px * max(1, -(-(2 * m + px + MID_W * QUARTER) // px))
    sy = py * max(1, -(-(2 * m + py + MID_W * QUARTER) // py))
    W, H = cl + sx + cr, ct + sy + cb
    canvas = np.zeros((H, W))
    canvas[:ct, :cl], canvas[:ct, W - cr:], canvas[H - cb:, :cl], canvas[H - cb:, W - cr:] = tl, tr, bl, br
    canvas[:ct, cl:cl + sx] = np.tile(t, (1, sx // t.shape[1]))
    canvas[H - cb:, cl:cl + sx] = np.tile(b, (1, sx // b.shape[1]))
    canvas[ct:ct + sy, :cl] = np.tile(l, (sy // l.shape[0], 1))
    canvas[ct:ct + sy, W - cr:] = np.tile(r, (sy // r.shape[0], 1))
    # the element is one shape: the body inside the rails' middle line counts
    # as filled for the blur (it adds a few levels to the outer profile:
    # window/single 147 against 145 where its paint starts); then nothing is
    # kept there (outside only), unless `fill`
    x0, y0 = int(round(mids[0])), int(round(mids[1]))
    x1, y1 = W - int(round(mids[2])), H - int(round(mids[3]))
    if body:
        canvas[y0:y1, x0:x1] = 1.0
    A = soften(np.pad(canvas, m), rec)
    if not fill:
        A[m + y0:m + y1, m + x0:m + x1] = 0.0
    # each edge's profile from its outer side inward, over the middle period of its run
    xm, ym = m + cl + sx // 2 - px // 2, m + ct + sy // 2 - py // 2
    p_t = A[:m + ct, xm:xm + px].mean(axis=1)
    p_b = A[m + H - cb:, xm:xm + px].mean(axis=1)[::-1]
    p_l = A[ym:ym + py, :m + cl].mean(axis=0)
    p_r = A[ym:ym + py, m + W - cr:].mean(axis=0)[::-1]
    c_tl = ease_corner(A[:m + ct, :m + cl], p_t, p_l, rec)
    c_tr = ease_corner(A[:m + ct, m + W - cr:][:, ::-1], p_t, p_r, rec)[:, ::-1]
    c_bl = ease_corner(A[m + H - cb:, :m + cl][::-1, :], p_b, p_l, rec)[::-1, :]
    c_br = ease_corner(A[m + H - cb:, m + W - cr:][::-1, ::-1], p_b, p_r, rec)[::-1, ::-1]
    # whole texels: the corners grow on their outer sides (with nothing)
    el, et = (-(m + cl)) % QUARTER, (-(m + ct)) % QUARTER
    er, eb = (-(m + cr)) % QUARTER, (-(m + cb)) % QUARTER
    E = MID_W * QUARTER
    L, T, R, B = el + m + cl, et + m + ct, cr + m + er, cb + m + eb
    centre = float(A[m + H // 2, m + W // 2]) if fill else 0.0
    img = np.full((T + E + B, L + E + R), centre)
    img[:T, :L] = np.pad(c_tl, ((et, 0), (el, 0)))
    img[:T, L + E:] = np.pad(c_tr, ((et, 0), (0, er)))
    img[T + E:, :L] = np.pad(c_bl, ((0, eb), (el, 0)))
    img[T + E:, L + E:] = np.pad(c_br, ((0, eb), (0, er)))
    img[:T, L:L + E] = np.pad(p_t, (et, 0))[:, None]
    img[T + E:, L:L + E] = np.pad(p_b[::-1], (0, eb))[:, None]
    img[T:T + E, :L] = np.pad(p_l, (el, 0))[None, :]
    img[T:T + E, L + E:] = np.pad(p_r[::-1], (0, er))[None, :]
    q = quarter(img)
    tw, th = q.shape[1], q.shape[0]
    xs, ys = (0, L // QUARTER, (L + E) // QUARTER, tw), (0, T // QUARTER, (T + E) // QUARTER, th)
    blocks = {}
    for part, (i, j) in {"tl": (0, 0), "t": (1, 0), "tr": (2, 0), "l": (0, 1), "r": (2, 1),
                         "bl": (0, 2), "b": (1, 2), "br": (2, 2)}.items():
        blocks[part] = (xs[i], ys[j], xs[i + 1], ys[j + 1])
    pad = [el + m, et + m, er + m, eb + m]
    corner = cl if cl == ct == cr == cb else [cl, ct, cr, cb]
    return q, {"pad": pad, "corner": corner, "margins": [L, T, R, B], "size": [img.shape[1], img.shape[0]],
               "blocks": blocks}


def part_pad(pad, part):
    """The reach of one part of a nine: past its outer sides only."""
    l, t, r, b = pad
    return [l if part in ("tl", "l", "bl") else 0, t if part in ("tl", "t", "tr") else 0,
            r if part in ("tr", "r", "br") else 0, b if part in ("bl", "b", "br") else 0]


def coverage_disc(h, w, cx, cy, radius):
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt((xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2)
    return np.clip(radius - d + 0.5, 0.0, 1.0)


def shape_shadows():
    """The synthetic shapes: {name: (quarter image, info)}."""
    rec = Recipe(1.0)
    m, C, D = rec.margin, SHAPE_CORNER, SHAPE_SIZE
    E = MID_W * QUARTER
    out = {}
    one = {k: np.ones((C, C)) for k in ("tl", "tr", "bl", "br")}
    one.update(t=np.ones((C, 1)), b=np.ones((C, 1)), l=np.ones((1, C)), r=np.ones((1, C)))
    q, info = nine_shadow(one, [0, 0, 0, 0], rec, fill=True, name="shade/square")
    del info["blocks"]
    out["shade/square"] = (q, info)
    # a pill D tall: the ends half discs, the middle a run clear of both ends' blur
    run = max(MID_SPAN, 2 * m + E)
    W = D + run
    yy, xx = np.mgrid[0:D, 0:W]
    cx = np.clip(xx + 0.5, D / 2, W - D / 2)
    pill = np.clip(D / 2 - np.sqrt((xx + 0.5 - cx) ** 2 + (yy + 0.5 - D / 2) ** 2) + 0.5, 0.0, 1.0)
    A = soften(np.pad(pill, m), rec)
    c0 = m + W // 2 - E // 2
    profile = A[:, c0:c0 + E].mean(axis=1)
    img = np.concatenate([ease_end(A[:, :m + C], profile, rec), np.repeat(profile[:, None], E, axis=1),
                          ease_end(A[:, -(m + C):][:, ::-1], profile, rec)[:, ::-1]], axis=1)
    out["shade/capsule"] = (quarter(img), {"pad": [m, m, m, m], "corner": C, "margins": [m + C] * 4,
                                          "size": [img.shape[1], img.shape[0]]})
    disc = coverage_disc(D, D, D / 2, D / 2, D / 2)
    A = soften(np.pad(disc, m), rec)
    out["shade/round"] = (quarter(A), {"pad": [m, m, m, m], "size": [A.shape[1], A.shape[0]]})
    return out


def strip_units(layout, names):
    """The strips among `names`: {(base, state): {part: piece}}, with each
    part as the strip draws it (a state's own piece, else the base's)."""
    units = {}
    for name in names:
        m = STRIP.match(name)
        if not m or matches(ALONE, name):
            continue
        base, state = m.group("base"), m.group("state") or ""
        if (base, state) in units:
            continue
        parts = {}
        for part in STRIP_PARTS:
            n = strip_name(layout, base, part, state)
            if n in layout and (part in ("cap_l", "mid", "cap_r") or shadowed(n)):
                parts[part] = n
        if all(k in parts for k in ("cap_l", "mid", "cap_r")):
            units[(base, state)] = parts
    return units


def shadows(layout):
    """Every shadow the sheet holds, before any is shared:
    parts   {piece name: (quarter image, pad)}
    ends    {middle's name: {"endL": (image, pad), "endR": ...}}
    units   [(key, legacy, {role: piece name})]: pieces that share only together
    nines   {family: (image, info)}
    shapes  {name: (image, info)}"""
    # (a metal twin takes its plain piece's picture, below)
    names = sorted(n for n in layout if shadowed(n) and twin_of(n) is None)
    parts, ends, units = {}, {}, []
    profiles = {}
    left_out = set()
    for (base, state), roles in sorted(strip_units(layout, names).items()):
        old = legacy(roles["mid"])
        if old:
            got = strip_shadows(layout, base, state or None, profiles)
            profile = profiles.get(roles["mid"])
        else:
            try:
                got, profile = strip_shadows_v2(layout, roles, recipe(base))
            except Uneven as err:
                # no shadow at all (not each part alone: its parts would
                # overlap at the joins); the rest of the sheet as ever
                print("make_kit_shadows: warning: %s: left out of the sheet" % err, file=sys.stderr)
                left_out.update(roles.values())
                continue
        own = {}
        for role, n in sorted(roles.items()):
            if n in got and n not in parts and shadowed(n):
                parts[n] = got[n]
                own[role] = n
        mid = roles["mid"]
        if "mid" in own:
            rec = Recipe(1.0) if old else recipe(base)
            if profile is None:
                raise SystemExit("strip %s: no profile for its middle" % base)
            ends[mid] = mid_ends(piece_alpha(layout[mid]), profile, rec)
        units.append(((base, state), old, own))
    for name in names:
        if name in parts or name in left_out or nine_family(name):
            continue
        if legacy(name):
            parts[name] = piece_shadow(layout, name)
        else:
            parts[name] = piece_shadow_v2(layout, name, recipe(name))
        units.append(((name, ""), legacy(name), {"piece": name}))
    nines = {}
    for family in sorted(NINES):
        p, mids = nine_parts(layout, family)
        nines[family] = nine_shadow(p, mids, recipe(family), name=family)
    # the marks' metal twins: their plain piece's very picture (a recolour has the same shape), so each is
    # shared as an exact twin (share, below) and adds nothing to the sheet
    for name in sorted(layout):
        base = twin_of(name)
        if base is not None and base in parts:
            parts[name] = parts[base]
            if base in ends:
                ends[name] = ends[base]
    return parts, ends, units, nines, shape_shadows()


def close(a, b, tol=ALIAS_TOL):
    return a.shape == b.shape and int(np.abs(a.astype(np.int16) - b.astype(np.int16)).max()) <= tol


def part_key(parts, ends, n):
    img, pad = parts[n]
    e = ends.get(n)
    return (tuple(pad), img.shape, img.tobytes()) + ((tuple(e["endL"][1]), e["endL"][0].tobytes(),
                                                     tuple(e["endR"][1]), e["endR"][0].tobytes()) if e else ())


def share(parts, ends, units):
    """{piece: the piece whose shadow it uses}. First, the pieces of a new
    family share within ALIAS_TOL, a strip's parts only all together (so a
    cap still meets its own middle's profile); then any exact twins share
    (0.13.7's rule, the only one for LEGACY pieces)."""
    alias = {}
    canon = []
    for key, old, roles in sorted(units, key=lambda u: u[0]):
        if not roles:
            continue
        sig = tuple(sorted((role, tuple(parts[n][1]), parts[n][0].shape) for role, n in roles.items()))
        hit = None
        if not old:
            for csig, croles in canon:
                if csig == sig and all(close(parts[n][0], parts[croles[role]][0]) and (
                        n not in ends or all(close(ends[n][k][0], ends[croles[role]][k][0])
                                             and ends[n][k][1] == ends[croles[role]][k][1] for k in ("endL", "endR")))
                        for role, n in roles.items()):
                    hit = croles
                    break
        if hit:
            for role, n in roles.items():
                alias[n] = hit[role]
        else:
            canon.append((sig, roles))
    first = {}
    for n in sorted(parts):
        if n in alias:
            continue
        k = part_key(parts, ends, n)
        if k in first:
            alias[n] = first[k]
        else:
            first[k] = n
    # one step to the shadow (the game follows one name)
    for n in alias:
        while alias[n] in alias:
            alias[n] = alias[alias[n]]
    return alias


def pack(images):
    """Skyline-pack the distinct images into SHEET_W: {key: (x, y)} of each
    image's first texel, and the sheet's height. Tallest first, then widest,
    then by key; each at the lowest place it fits, then the leftmost."""
    cols = SHEET_W // QUARTER
    sky = [0] * cols
    at = {}

    def cell(k):
        h, w = images[k].shape
        return ceil_to(w + 2 * GUTTER, QUARTER), ceil_to(h + 2 * GUTTER, QUARTER)

    for k in sorted(images, key=lambda k: (-cell(k)[1], -cell(k)[0], k)):
        cw, ch = cell(k)
        n = cw // QUARTER
        if n > cols:
            raise SystemExit("a shadow is wider than the sheet: %s" % (k,))
        best = None
        for i in range(cols - n + 1):
            top = max(sky[i:i + n])
            if best is None or top < best[0]:
                best = (top, i)
        top, i = best
        at[k] = (i * QUARTER + GUTTER, top + GUTTER)
        for j in range(i, i + n):
            sky[j] = top + ch
    used = max(sky)
    return at, 1 << max(2, math.ceil(math.log2(max(used, 1))))


def plan():
    """The sheet's plan from the masters: every shadow, which share, and where
    each distinct one lies ({"layout", "parts", "ends", "nines", "shapes",
    "alias", "images", "at", "sheet_h"})."""
    layout = load_layout()
    parts, ends, units, nines, shapes = shadows(layout)
    alias = share(parts, ends, units)
    images = {}
    for n in parts:
        if n not in alias:
            images[n] = parts[n][0]
            for k in ("endL", "endR"):
                if n in ends:
                    images[n + "#" + k] = ends[n][k][0]
    # a nine or a shape whose picture is within ALIAS_TOL of an earlier one's shares it
    pictures = {}
    for group, table in (("nine", nines), ("shape", shapes)):
        for name in sorted(table):
            q = table[name][0]
            key = next((k for k in sorted(pictures) if k.startswith(group + ":") and close(pictures[k], q)), None)
            if key is None:
                key = group + ":" + name
                pictures[key] = q
                images[key] = q
            table[name][1]["image"] = key
    at, sheet_h = pack(images)
    return {"layout": layout, "parts": parts, "ends": ends, "nines": nines, "shapes": shapes, "alias": alias,
            "images": images, "at": at, "sheet_h": sheet_h}


def sheet_rgba(images, at, sheet_h):
    """The sheet: each image at its place, its edges repeated GUTTER texels outward, white with that alpha."""
    alpha = np.zeros((sheet_h, SHEET_W), np.uint8)
    for key, img in images.items():
        x, y = at[key]
        h, w = img.shape
        alpha[y - GUTTER:y + h + GUTTER, x - GUTTER:x + w + GUTTER] = np.pad(img, GUTTER, mode="edge")
    rgba = np.zeros((sheet_h, SHEET_W, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = alpha
    return rgba


def build_look(folder):
    """A painted look's sheet (kit_palette.ART, user 2026-10-04: Forged Steel): the shadows of ITS pieces (read
    from masters/Media/<folder>, the painted kit's where the look has none), each laid exactly where the painted
    kit's lies, so the one Media/KitShadows.lua (uv, pad) serves both and Kit.lua only takes the look's sheet
    (KitShadows<suffix>). Stops if a shadow's size differs from the kit's (the layout would). The TGA's bytes."""
    global _READ_FROM
    base = plan()
    _READ_FROM = os.path.join(MASTER_MEDIA, folder)
    _ALPHA.clear()
    try:
        parts, ends, _, nines, shapes = shadows(base["layout"])
    finally:
        _READ_FROM = None
        _ALPHA.clear()
    images = {}
    for key, img in base["images"].items():
        if key.startswith(("nine:", "shape:")):
            group, name = key.split(":", 1)
            new = (nines if group == "nine" else shapes)[name][0]
        elif "#" in key:
            n, k = key.split("#")
            new = ends[n][k][0]
        else:
            new = parts[key][0]
        if new.shape != img.shape:
            raise SystemExit("%s: its shadow in %s is %s, the painted kit's %s: the sheets' layouts would differ"
                             % (key, folder, new.shape, img.shape))
        images[key] = new
    buf = io.BytesIO()
    Image.fromarray(sheet_rgba(images, base["at"], base["sheet_h"]), "RGBA").save(buf, format="TGA")
    return buf.getvalue()


def write_look(pid, quiet=False):
    """A painted look's sheet (palette id `pid`, kit_palette.ART) to its master and the addon's Media (beside
    KitShadows.tga: the ship keeps it TGA); its sha256."""
    import kit_palette
    look = kit_palette.LOOKS[pid]
    tga = build_look(look.folder)
    name = SHEET[1][:-4] + look.suffix + ".tga"
    for path in (master(SHEET[0], name), os.path.join(ADDON_MEDIA, SHEET[0], name)):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(tga)
        if not quiet:
            print("->", os.path.normpath(path))
    return hashlib.sha256(tga).hexdigest()


def build():
    """(the sheet's TGA bytes, the Lua's bytes, the sheet (RGBA array),
    pieces {name: entry or the name of the piece it shares}, everything:
    {"pieces", "nines", "shapes", "rects": the drawn texel rects,
    "used": texels drawn})."""
    pl = plan()
    parts, ends, nines, shapes, alias = pl["parts"], pl["ends"], pl["nines"], pl["shapes"], pl["alias"]
    images, at, sheet_h = pl["images"], pl["at"], pl["sheet_h"]
    alpha = np.zeros((sheet_h, SHEET_W), np.uint8)
    for key, img in images.items():
        x, y = at[key]
        h, w = img.shape
        # the image with its edges repeated GUTTER texels outward: a bilinear
        # tap past a cap's inner end reads the cap, not the next shadow
        alpha[y - GUTTER:y + h + GUTTER, x - GUTTER:x + w + GUTTER] = np.pad(img, GUTTER, mode="edge")
    rgba = np.zeros((sheet_h, SHEET_W, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = alpha
    buf = io.BytesIO()
    Image.fromarray(rgba, "RGBA").save(buf, format="TGA")
    tga = buf.getvalue()

    def uv(key, rect=None):
        x, y = at[key]
        h, w = images[key].shape
        x0, y0, x1, y1 = rect or (0, 0, w, h)
        return ((x + x0) / SHEET_W, (x + x1) / SHEET_W, (y + y0) / sheet_h, (y + y1) / sheet_h)

    entries = {}
    for n in sorted(parts):
        if n in alias:
            entries[n] = alias[n]
            continue
        e = {"uv": uv(n), "pad": parts[n][1]}
        if n in ends:
            for k in ("endL", "endR"):
                e[k] = {"uv": uv(n + "#" + k), "pad": ends[n][k][1]}
        entries[n] = e
    nine_out = {}
    for family in sorted(nines):
        _, info = nines[family]
        key = info["image"]
        nine_out[family] = {"uv": uv(key), "pad": info["pad"], "corner": info["corner"], "margins": info["margins"],
                            "size": info["size"]}
        for part, rect in info["blocks"].items():
            name = family + "_" + part
            if shadowed(name):
                entries[name] = {"uv": uv(key, rect), "pad": part_pad(info["pad"], part)}
    shape_out = {}
    for name in sorted(shapes):
        _, info = shapes[name]
        shape_out[name] = dict({"uv": uv(info["image"])}, **{k: info[k] for k in ("pad", "corner", "margins", "size")
                                                             if k in info})
    rects = [(at[k][0], at[k][1], images[k].shape[1], images[k].shape[0]) for k in sorted(images)]
    data = {"pieces": entries, "nines": nine_out, "shapes": shape_out, "rects": rects,
            "used": sum(w * h for _, _, w, h in rects)}
    lua = lua_text(data, (SHEET_W, sheet_h), hashlib.sha256(tga).hexdigest())
    return tga, lua.encode("utf-8"), rgba, entries, data


def num(v):
    return ("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def nums(vs):
    return "{ %s }" % ", ".join(num(v) for v in vs)


def lua_text(data, size, digest):
    lines = [
        "-- Generated by Tools/make_kit_shadows.py from the kit's masters. Do not edit by hand.",
        "--",
        "-- The kit's shadow partners (Kit:Shadow, Kit:ShadowNine, Modules/Kit.lua): a soft copy of the",
        "-- shape of each piece on an element's outline (its alpha grown and blurred: sigma %g px at the" % SIGMA,
        "-- kit's scale, less for a family drawn larger: the single rail), white, in one sheet at a",
        "-- quarter of the painted size, the same for every palette and Kit Colours look.",
        "--   version  2",
        "--   file     the sheet (no extension)",
        "--   size     the sheet's width and height in texels",
        "--   pieces   by piece name: uv (left, right, top, bottom in the sheet) and pad (how far the",
        "--            shadow reaches past the piece on its left, top, right and bottom, in the piece's",
        "--            painted px); or the name of a piece whose shadow it uses (the same shape, within",
        "--            %d of 255). A strip's parts reach past their outer sides only (a cap_l left, a" % ALIAS_TOL,
        "--            cap_r right, a mid neither), so they join without a seam; a mid's shadow is its",
        "--            profile across the rail, stretched along it. A mid's endL / endR: the soft end of",
        "--            a strip drawn without a cap on that side, a partner just past the mid's end,",
        "--            pad[1] (endL) or pad[3] (endR) px wide, its other pads the mid's.",
        "--            window/frame_* and window/single_* lie in their family's nine (below). Outside",
        "--            only: nothing is shaded inward of the middle of a piece's rim round an opening.",
        "--   nines    by family (window/frame, window/single, deco/barframe_red, _iron): the rails'",
        "--            shadow as one picture to cut into nine. uv; pad (its reach past the frame's rect);",
        "--            corner (the rails' corner, painted px); margins (where to cut: px from the",
        "--            picture's left, top, right and bottom); size (the picture in painted px). The",
        "--            edges between the cuts are profiles (stretch them); the middle is empty (outside",
        "--            only: nothing inward of the rails' middle line).",
        "--   shapes   shade/square (a filled box; its middle filled) and shade/capsule (a pill, its",
        "--            middle rows none: scale it by its height) cut as the nines; shade/round (a disc,",
        "--            stretched whole): for frames that have no kit piece. All three are filled (the",
        "--            shadow of a solid shape), unlike the pieces and nines (outside only).",
        "-- sheet sha256 %s" % digest,
        "",
        "-- luacheck: globals MelloUI_KitShadows",
        "MelloUI_KitShadows = {",
        "\tversion = %d," % VERSION,
        "\tfile = \"%s\"," % GAME_PATH,
        "\tsize = { %d, %d }," % size,
        "\tpieces = {",
    ]
    for name in sorted(data["pieces"]):
        e = data["pieces"][name]
        if isinstance(e, str):
            lines.append("\t\t[\"%s\"] = \"%s\"," % (name, e))
            continue
        s = "\t\t[\"%s\"] = { uv = %s, pad = %s" % (name, nums(e["uv"]), nums(e["pad"]))
        for k in ("endL", "endR"):
            if k in e:
                s += ", %s = { uv = %s, pad = %s }" % (k, nums(e[k]["uv"]), nums(e[k]["pad"]))
        lines.append(s + " },")
    for group in ("nines", "shapes"):
        lines.append("\t},")
        lines.append("\t%s = {" % group)
        for name in sorted(data[group]):
            e = data[group][name]
            s = "\t\t[\"%s\"] = { uv = %s, pad = %s" % (name, nums(e["uv"]), nums(e["pad"]))
            if "corner" in e:
                c = e["corner"]
                s += ", corner = %s, margins = %s" % (nums(c) if isinstance(c, list) else num(c), nums(e["margins"]))
            lines.append(s + ", size = %s }," % nums(e["size"]))
    lines += ["\t},", "}", ""]
    return "\n".join(lines)


def gate(rgba, entries, rects=None):
    """The DXT5 banding gate on the drawn texels: (passes, max error, mean
    error). rects: the drawn texel rects (x, y, w, h), else the pieces' uv."""
    import blp_dxt
    data = blp_dxt.encode_blp(rgba, "dxt5")
    dec = blp_dxt.decode_blp(data)
    src, got = rgba[..., 3].astype(np.int32), dec[..., 3].astype(np.int32)
    h, w = src.shape
    mask = np.zeros((h, w), bool)
    if rects is not None:
        for x, y, rw, rh in rects:
            mask[y:y + rh, x:x + rw] = True
    else:
        for e in entries.values():
            if isinstance(e, str):
                continue
            u0, u1, v0, v1 = e["uv"]
            mask[round(v0 * h):round(v1 * h), round(u0 * w):round(u1 * w)] = True
    err = np.abs(src - got)[mask]
    worst, mean = int(err.max()), float(err.mean())
    return worst <= GATE_MAX and mean <= GATE_MEAN, worst, mean


def addon_writes():
    """True when the masters are the default ones (the sibling
    MelloUI-BuildData's): only then does a build refresh the addon's own
    files. A build against another masters folder must not overwrite what
    ships (review, 2026-09-25)."""
    default = os.path.join(SIBLING, "masters")
    return os.path.normcase(os.path.abspath(MASTERS)) == os.path.normcase(os.path.abspath(default))


def targets_of(tga, lua, addon=True):
    """Where the files go: the sheet's master, and with `addon` the addon's
    copy and Media/KitShadows.lua."""
    out = [(master(*SHEET), tga)]
    if addon:
        out += [(os.path.join(ADDON_MEDIA, *SHEET), tga), (LUA, lua)]
    return out


def write(quiet=False, addon=None):
    """Build and write the master and, from the default masters (addon=None)
    or with addon=True, the addon's two files (build_kit.py's step); the
    sheet's sha256."""
    if addon is None:
        addon = addon_writes()
    tga, lua = build()[:2]
    for path, data in targets_of(tga, lua, addon):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        if not quiet:
            print("->", os.path.normpath(path))
    if not addon and not quiet:
        print("masters from %s: the addon's Media/Textures/KitShadows.tga and Media/KitShadows.lua "
              "are left as they are (--addon writes them)" % os.path.normpath(MASTERS))
    return hashlib.sha256(tga).hexdigest()


def main():
    # an argument it does not know (--help, a typo) writes nothing: without
    # this it fell through to the write mode
    bad = [a for a in sys.argv[1:] if a not in ("--check", "--gate", "--addon")]
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    tga, lua, rgba, entries, data = build()
    addon = "--addon" in sys.argv or addon_writes()
    targets = targets_of(tga, lua, addon)
    digest = hashlib.sha256(tga).hexdigest()
    n = sum(1 for e in entries.values() if not isinstance(e, str))
    print("%d pieces (%d shadows, %d of the same shape), %d nines, %d shapes; sheet %dx%d, %d%% drawn" % (
        len(entries), n, len(entries) - n, len(data["nines"]), len(data["shapes"]), rgba.shape[1], rgba.shape[0],
        round(100 * data["used"] / (rgba.shape[0] * rgba.shape[1]))))
    if "--gate" in sys.argv:
        ok, worst, mean = gate(rgba, entries, data["rects"])
        print("DXT5 banding gate: largest alpha error %d (limit %d), mean %.2f (limit %.1f): %s" % (
            worst, GATE_MAX, mean, GATE_MEAN, "PASS (may be compressed)" if ok else "FAIL (stays TGA)"))
        return 0
    if "--check" in sys.argv:
        stale = []
        for path, blob in targets:
            try:
                with open(path, "rb") as f:
                    if f.read() != blob:
                        stale.append(path)
            except OSError:
                stale.append(path)
        for path in stale:
            print("stale:", os.path.normpath(path))
        if not addon:
            print("(masters from %s: the master only; --addon checks the addon's files too)" % os.path.normpath(MASTERS))
        print("sha256", digest, "ok" if not stale else "STALE")
        return 1 if stale else 0
    print("sha256", write(addon=addon))
    return 0


if __name__ == "__main__":
    sys.exit(main())
