"""
Build the kit's SHADOW PARTNERS: a soft, dark copy of a kit piece's own shape
that MelloUI lays under the piece (Kit:Shadow, Modules/Kit.lua). The
nameplates' "Whole plate" shade is the first user (user, 2026-09-25: the
bracket's caps and rail and the level orb, so the shade follows the plate's
shape); Route's World Marker gem is the second (user, 2026-09-25: its gem on
bright ground); 0.14.0 gives every kit piece one, by adding its name to
SHADOWED. (Route's direction arrow and the marker's edge arrow are the game's
own atlas, not a kit piece: no master to read here, so they take a round soft
band, MelloUI.Shade, instead.)

The game cannot blur what is behind a frame, so the blur is made here, once:
each piece's alpha (from its TGA master, at its painted 2x size) is grown by
DILATE px, blurred (a gaussian of SIGMA px), and stored WHITE with that alpha
at a quarter of the painted size (the blur loses nothing), all in one sheet.
The game tints it with a palette colour (innerPanel) at the chosen strength.
The shapes are the same in every Kit Colours look, so one set serves them all.

A strip (a bar bracket: <base>_cap_l, _mid, _cap_r, drawn side by side, the
middle repeated) is blurred WHOLE, so its parts join without a seam: a cap's
shadow reaches past its outer side only, the middle's is the rail's profile
across (one column, stretched along the rail in game), and a cap's inner end
is eased onto that profile. A red end gem's cap has its iron twin's shape: a
piece whose shadow is byte for byte another's is written as that piece's name.

Reads   the masters (Tools/paths.py): masters/Media/KitLayout.lua (each piece
        in its own file, build_kit.py's) and each piece's TGA master
Writes  masters/Media/Textures/KitShadows.tga   the sheet (32-bit TGA master)
        Media/Textures/KitShadows.tga           a byte copy, so it ships at once
                                                (texture_pack.py: STAY_TGA)
        Media/KitShadows.lua                    MelloUI_KitShadows: the sheet's
                                                path; per piece its uv in the
                                                sheet and its pad (painted px
                                                past the piece: left, top,
                                                right, bottom)
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

# The pieces that get a shadow (first match; a regex on the piece name)
SHADOWED = [
    r"^bars/[a-z]+_(cap_l|mid|cap_r)(_[a-z]+)?$",   # every bar bracket look (Bar Border / Nameplate Border)
    r"^buttons/orb_normal$",                        # the level orb (the nameplates' level circle)
    r"^deco/gem_large$",                            # Route's World Marker gem (over the destination)
]
STRIP = re.compile(r"^(?P<base>.+)_(?P<part>cap_l|mid|cap_r)(?:_(?P<state>[a-z]+))?$")

QUARTER = 4          # painted px per sheet texel
DILATE = 3           # painted px the shape grows before the blur
SIGMA = 8.0          # painted px: the blur's standard deviation
MARGIN = 28          # painted px past the piece: DILATE + 3 SIGMA, a multiple of QUARTER
MID_SPAN = 128       # painted px of repeated middle between the caps while a strip is blurred
MID_W = 4            # texels: a middle's shadow (its profile, the same in every column)
EASE = 16            # painted px over which a cap's inner end eases onto the middle's profile
GUTTER = 2           # texels round each shadow in the sheet, its edge texels repeated into them
SHEET_W = 128        # the sheet's width; its height the next power of two that holds it

# The banding gate (--gate): the sheet encoded as DXT5 (Tools/blp_dxt.py) and
# decoded; it passes only if no drawn texel's alpha moves by more than
# GATE_MAX levels and the mean moves by at most GATE_MEAN. A soft shadow is a
# smooth ramp: DXT5's eight alpha steps per 4 x 4 block turn a steep one into
# visible bands.
GATE_MAX = 4
GATE_MEAN = 1.0


def load_layout():
    import lupa
    lua = lupa.LuaRuntime()
    lua.execute(open(LAYOUT_LUA, encoding="utf-8").read())
    pieces = lua.globals().MelloUI_KitLayout.pieces
    out = {}
    for name in pieces:
        p = pieces[name]
        out[name] = {"file": p.file, "w": int(p.w), "h": int(p.h), "uv": [float(p.uv[i]) for i in range(1, 5)]}
    return out


def shadowed(name):
    return any(re.search(pat, name) for pat in SHADOWED)


def piece_alpha(p):
    """The piece's alpha at its painted size, 0..1."""
    path = os.path.join(KIT, p["file"].replace("\\", os.sep) + ".tga")
    with Image.open(path) as im:
        a = im.convert("RGBA").getchannel("A")
    cw, ch = a.size
    u0, u1, v0, v1 = p["uv"]
    a = a.crop((round(u0 * cw), round(v0 * ch), round(u1 * cw), round(v1 * ch)))
    a = a.resize((p["w"], p["h"]), Image.BILINEAR)
    return np.asarray(a, dtype=np.float64) / 255.0


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


def soften(a):
    return np.clip(blur(dilate(a)), 0.0, 1.0)


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
    h, w = a.shape
    q = a.reshape(h // QUARTER, QUARTER, w // QUARTER, QUARTER).mean(axis=(1, 3))
    return np.clip(np.floor(q * 255 + 0.5), 0, 255).astype(np.uint8), [l, t, r, b]


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


def strip_shadows(layout, base, state):
    """{piece name: (quarter image, pad)} for the strip base[_state]."""
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


def shadows(layout):
    """{piece name: (image, pad)} for every SHADOWED piece, in a fixed order."""
    out = {}
    names = sorted(n for n in layout if shadowed(n))
    for name in names:
        if name in out:
            continue
        m = STRIP.match(name)
        if m and m.group("base").startswith("bars/"):
            got = strip_shadows(layout, m.group("base"), m.group("state"))
            for n in sorted(got):
                if n not in out and shadowed(n):
                    out[n] = got[n]
            if name in out:
                continue
        out[name] = piece_shadow(layout, name)
    return out


def ceil_to(n, k):
    return -(-n // k) * k


def pack(images):
    """Shelf-pack the distinct images: {key: (x, y)} of each image's first
    texel, and the sheet's height. Tallest first, then widest, then by key."""
    order = sorted(images, key=lambda k: (-images[k].shape[0], -images[k].shape[1], k))
    x = y = row_h = 0
    at = {}
    for k in order:
        h, w = images[k].shape
        cw, ch = ceil_to(w + 2 * GUTTER, 4), ceil_to(h + 2 * GUTTER, 4)
        if cw > SHEET_W:
            raise SystemExit("a shadow is wider than the sheet: %s" % (k,))
        if x + cw > SHEET_W:
            x, y, row_h = 0, y + row_h, 0
        at[k] = (x + GUTTER, y + GUTTER)
        x += cw
        row_h = max(row_h, ch)
    used = y + row_h
    return at, 1 << max(2, math.ceil(math.log2(max(used, 1))))


def build():
    layout = load_layout()
    made = shadows(layout)
    # one sheet slot per distinct shadow (same pad and bytes): the rest alias
    first = {}
    alias = {}
    for name in sorted(made):
        img, pad = made[name]
        key = (tuple(pad), img.shape, img.tobytes())
        if key in first:
            alias[name] = first[key]
        else:
            first[key] = name
    images = {name: made[name][0] for name in first.values()}
    at, sheet_h = pack(images)
    alpha = np.zeros((sheet_h, SHEET_W), np.uint8)
    for name, img in images.items():
        x, y = at[name]
        h, w = img.shape
        # the image with its edges repeated GUTTER texels outward: a bilinear
        # tap past a cap's inner end reads the cap, not the next shadow
        ext = np.pad(img, GUTTER, mode="edge")
        alpha[y - GUTTER:y + h + GUTTER, x - GUTTER:x + w + GUTTER] = ext
    rgba = np.zeros((sheet_h, SHEET_W, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = alpha
    buf = io.BytesIO()
    Image.fromarray(rgba, "RGBA").save(buf, format="TGA")
    tga = buf.getvalue()
    entries = {}
    for name in sorted(made):
        if name in alias:
            entries[name] = alias[name]
            continue
        x, y = at[name]
        h, w = images[name].shape
        entries[name] = {"uv": (x / SHEET_W, (x + w) / SHEET_W, y / sheet_h, (y + h) / sheet_h), "pad": made[name][1]}
    lua = lua_text(entries, (SHEET_W, sheet_h), hashlib.sha256(tga).hexdigest())
    return tga, lua.encode("utf-8"), rgba, entries


def num(v):
    return ("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def lua_text(entries, size, digest):
    lines = [
        "-- Generated by Tools/make_kit_shadows.py from the kit's masters. Do not edit by hand.",
        "--",
        "-- The kit's shadow partners (Kit:Shadow, Modules/Kit.lua): a soft copy of each",
        "-- listed piece's shape (its alpha grown by %d px and blurred, sigma %g px), white," % (DILATE, SIGMA),
        "-- in one sheet at a quarter of the painted size, the same for every Kit Colours look.",
        "--   file    the sheet (no extension)",
        "--   size    the sheet's width and height in texels",
        "--   pieces  by piece name: uv (left, right, top, bottom in the sheet) and pad (how",
        "--           far the shadow reaches past the piece on its left, top, right and",
        "--           bottom, in the piece's painted px); or the name of a piece whose",
        "--           shadow is the same",
        "--   A strip's parts reach past their outer sides only (a cap_l left, a cap_r right,",
        "--   a mid neither), so the three join without a seam; a mid's shadow is its profile",
        "--   across the rail, stretched along it.",
        "-- sheet sha256 %s" % digest,
        "",
        "-- luacheck: globals MelloUI_KitShadows",
        "MelloUI_KitShadows = {",
        "\tfile = \"%s\"," % GAME_PATH,
        "\tsize = { %d, %d }," % size,
        "\tpieces = {",
    ]
    for name in sorted(entries):
        e = entries[name]
        if isinstance(e, str):
            lines.append("\t\t[\"%s\"] = \"%s\"," % (name, e))
        else:
            lines.append("\t\t[\"%s\"] = { uv = { %s }, pad = { %s } }," % (
                name, ", ".join(num(v) for v in e["uv"]), ", ".join(str(v) for v in e["pad"])))
    lines += ["\t},", "}", ""]
    return "\n".join(lines)


def gate(rgba, entries):
    """The DXT5 banding gate on the drawn texels: (passes, max error, mean error)."""
    import blp_dxt
    data = blp_dxt.encode_blp(rgba, "dxt5")
    dec = blp_dxt.decode_blp(data)
    src, got = rgba[..., 3].astype(np.int32), dec[..., 3].astype(np.int32)
    h, w = src.shape
    mask = np.zeros((h, w), bool)
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
    tga, lua, _, _ = build()
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
    tga, lua, rgba, entries = build()
    addon = "--addon" in sys.argv or addon_writes()
    targets = targets_of(tga, lua, addon)
    digest = hashlib.sha256(tga).hexdigest()
    n = sum(1 for e in entries.values() if not isinstance(e, str))
    print("%d pieces (%d shadows, %d of the same shape), sheet %dx%d" % (
        len(entries), n, len(entries) - n, rgba.shape[1], rgba.shape[0]))
    if "--gate" in sys.argv:
        ok, worst, mean = gate(rgba, entries)
        print("DXT5 banding gate: largest alpha error %d (limit %d), mean %.2f (limit %.1f): %s" % (
            worst, GATE_MAX, mean, GATE_MEAN, "PASS (may be compressed)" if ok else "FAIL (stays TGA)"))
        return 0
    if "--check" in sys.argv:
        stale = []
        for path, data in targets:
            try:
                with open(path, "rb") as f:
                    if f.read() != data:
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
