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

Run:  python Tools/build_kit.py            (then a full client restart)
"""
import os, re, json, math, sys
import numpy as np
from PIL import Image

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


def main():
    man = json.load(open(os.path.join(SRC, "manifest.json")))
    pieces = {}
    for key in sorted(man):
        name = key.split("/", 1)[1]                      # "window/frame_tl"
        a = np.array(Image.open(os.path.join(SRC, name + ".png")).convert("RGBA"))
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
        path = os.path.join(OUT, name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        canvas.save(path)
        arr2 = np.array(im)
        m = arr2[..., 3] > 128
        ys, xs = np.where(m)
        box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1) if len(ys) else (0, 0, pw, ph)
        entry = {
            "file": name.replace("/", "\\\\"),
            "w": pw, "h": ph,                             # piece px as painted (2x); the file may hold fewer (density)
            "uv": (0.0, sw / cw, 0.0, sh / ch),
            "tile": axes or None,
            "box": box,                                   # the opaque part of the piece, in piece px
        }
        op = opening(np.array(im))
        cap = re.search(r"^bars/.*_cap_([lr])$", name)
        if cap:
            op = cap_hollow(np.array(im), cap.group(1))
        if op and re.search(r"(slot_|roundslot_|portrait_ring|card_|/frame_mid|castbar_mid|frame_cap|castbar_cap|checkbox|orb_|cog_|arrow_|plus_|minus_|close_)", name):
            entry["open"] = op
        if "overhang" in man[key]:
            entry["overhang"] = int(man[key]["overhang"])   # oversized corners: how far past the frame's corner they reach
        if re.search(r"(portrait_ring|roundslot_|orb_)", name):
            entry["radius"] = body_radius(np.array(im))    # the round body without its compass gems
        pieces[name] = entry

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
    print(f"{len(pieces)} pieces -> Media/Kit ({total / 1e6:.1f} MB), Media/KitLayout.lua")
    if "--report" in sys.argv:
        for name in sorted(pieces):
            p = pieces[name]
            print(f"  {name:40} painted {p['w']}x{p['h']}  density {density(name)}")


if __name__ == "__main__":
    main()
