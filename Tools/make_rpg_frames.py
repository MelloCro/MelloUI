"""
make_rpg_frames.py -- the RPG UI pack's frames as the kit's border library styles (0.20.1; the user, 2026-10-10: "this
round border with its background as a reusable thing, and the borders also reusable as backdrop border, action bar
border, progress bar border etc with its background"; "the around the skull border and its background ... for
unitframes and nameplates, we dont need the skull"). The pack is used with its creator's permission. Its frames carry
their look in Photoshop effects, so they are cut from the full layout's merged image (LinkedFileLayout_4k.psd, 4096 x
3112, real alpha; docs/plans/rpg-frames.md), where the player portrait is clean:

    rings/rpg            the portrait ring's rim (opening r 152, outer 197 on the layout), in a canvas whose opening is
                         0.65 of it as the library's other rings (rings/r1, r3), so it stands on their rims
    rings/rpg_disc       its background: the dark ground falling into an inner shadow at the rim (measured), round
    buttons/orb_rpg      the small ring round the skull (opening r 60, outer 97.5) at the level orb's geometry
    buttons/orb_rpg_disc its background without the skull (the skull covered the middle: the ground measured beside it)
    borders/rpg          the health bar's frame: its 30 px rail (outer dark edge, two lit groove lines, the bevel), its
                         rounded outer corners, the clean right end (the left mirrored), an open middle
    borders/rpg_bg       its trough: dark, an inner shadow 18 px in from every side, the flat middle

The drop shadows are left out (the kit's UI shade draws its own). Run:
      python Tools/make_rpg_frames.py --preview      the board (MelloUI-BuildData/output/rpg_frames_sketch)
      python Tools/make_rpg_frames.py --write        the masters into pack_sources, then build_kit.py, texture_pack.py ship
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
MANIFEST = os.path.join(SRC, "manifest.json")
sys.path.insert(0, HERE)
from paths import SIBLING  # noqa: E402

LAYOUT_PSD = os.path.expanduser(r"~/Downloads/Addons/graphicriver-tHFzW0Sx-rpg-user-interface/Version2.0/"
                                r"LinkedFileLayout_4k/LinkedFileLayout_4k.psd")
CACHE = os.path.join(SIBLING, "output", "rpgui_study", "layout4k_composite.png")
SKETCH = os.path.join(SIBLING, "output", "rpg_frames_sketch")

BIG = {"c": (282.0, 247.5), "open": 152.0, "outer": 197.0, "mirror": True}
SMALL = {"c": (1572.5, 374.0), "open": 60.0, "outer": 97.5}
RAIL = {"x_end": 1143, "top": 122, "bottom": 243, "depth": 30, "corner_r": 12, "clean": (1000, 1100)}
RING_SHARE = 0.65      # the rings' opening over their canvas (rings/r1, r3)
ORB_OUTER = 47 / 49.0  # the level orb's ring over its half canvas (buttons/orb_*)


def composite():
    Image.MAX_IMAGE_PIXELS = None
    if os.path.exists(CACHE):
        return np.asarray(Image.open(CACHE).convert("RGBA")).astype(np.float32)
    im = Image.open(LAYOUT_PSD).convert("RGBA")
    im.save(CACHE)
    return np.asarray(im).astype(np.float32)


def smooth_step(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def ring_rim(a, g, half, size):
    """The rim from the layout, centred in a square of `half` layout px each way, resampled to `size`: transparent
    inside the opening and past the outer edge (soft over a pixel), the drop shadow left out."""
    cx, cy = g["c"]
    x0, y0 = int(round(cx - half)), int(round(cy - half))
    n = int(round(2 * half))
    crop = a[y0:y0 + n, x0:x0 + n].copy()
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    r = np.hypot(xx - (cx - x0), yy - (cy - y0))
    keep = smooth_step((r - (g["open"] - 1.0)) / 2.0) * smooth_step((g["outer"] + 0.5 - r) / 1.5)
    crop[..., 3] *= keep
    if g.get("mirror"):
        # (the big ring: the bars' fills lie over its right side in the layout -- its clean left half mirrored)
        crop[:, n // 2:] = crop[:, :n - n // 2][:, ::-1][:, :n - n // 2]
    img = Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8), "RGBA")
    return np.asarray(img.resize((size, size), Image.LANCZOS)).astype(np.float32)


def disc(size, radius_share, profile):
    """A round ground of `radius_share` x the half size: its colour by radius (a share of its own radius) from
    `profile` [(share, (r, g, b)), ...], transparent past it (soft over a pixel)."""
    c = size / 2.0
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    rr = np.hypot(xx - c, yy - c)
    R = radius_share * c
    s = rr / R
    xs = [p[0] for p in profile]
    rgb = np.stack([np.interp(s, xs, [p[1][k] for p in profile]) for k in range(3)], axis=2)
    alpha = np.clip(R + 0.5 - rr, 0, 1) * 255
    return np.dstack([rgb, alpha]).astype(np.float32)


# the grounds, measured (share of the opening's radius -> colour); past 1 they reach a little under the rim
BIG_DISC = [(0.0, (49, 47, 40)), (0.70, (48, 46, 39)), (0.82, (46, 44, 38)), (0.87, (42, 40, 35)), (0.92, (36, 34, 29)),
            (0.97, (29, 28, 23)), (1.0, (22, 21, 18)), (1.05, (18, 17, 14))]
SMALL_DISC = [(0.0, (41, 40, 35)), (0.73, (39, 38, 33)), (0.80, (34, 33, 29)), (0.87, (27, 26, 22)), (0.93, (24, 23, 20)),
              (1.0, (17, 16, 14)), (1.06, (13, 12, 11))]


def rail_master(a, size=128):
    """The bar frame's rail as a square master: its right end's corners (the left ones mirrored) and edges, its top
    and bottom rails' clean stretch along, an open middle; the outer edge a rounded rect, the drop shadow out."""
    R = RAIL
    D = R["depth"]
    C = D + 10                     # a corner's square: the rounded corner and the bevel's turn
    x1 = R["x_end"]
    top, bot = R["top"], R["bottom"]
    out = np.zeros((size, size, 4), np.float32)
    # corners (from the right end; the left mirrored)
    tr = a[top:top + C, x1 - C + 1:x1 + 1]
    br = a[bot - C + 1:bot + 1, x1 - C + 1:x1 + 1]
    out[:C, size - C:] = tr
    out[size - C:, size - C:] = br
    out[:C, :C] = tr[:, ::-1]
    out[size - C:, :C] = br[:, ::-1]
    # top and bottom edges: the clean stretch, repeated along the middle
    c0 = R["clean"][0]
    span = size - 2 * C
    out[:C, C:size - C] = a[top:top + C, c0:c0 + span]
    out[size - C:, C:size - C] = a[bot - C + 1:bot + 1, c0:c0 + span]
    # sides: the right end's rail down its middle (the trough's height), stretched to the span; the left mirrored
    mid = a[top + C:bot - C + 1, x1 - C + 1:x1 + 1]
    side = np.asarray(Image.fromarray(np.clip(mid, 0, 255).astype(np.uint8), "RGBA").resize((C, span), Image.LANCZOS)).astype(np.float32)
    out[C:size - C, size - C:] = side
    out[C:size - C, :C] = side[:, ::-1]
    # the open middle, and the outer edge a rounded rect (the shadow out)
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    depth = np.minimum(np.minimum(xx, size - xx), np.minimum(yy, size - yy))
    out[..., 3] *= smooth_step((D + 0.5 - depth) / 1.0)
    rc = R["corner_r"]
    qx = np.maximum(np.maximum(rc - xx, xx - (size - rc)), 0)
    qy = np.maximum(np.maximum(rc - yy, yy - (size - rc)), 0)
    rounded = np.clip(rc + 0.5 - np.hypot(qx, qy), 0, 1)
    out[..., 3] *= rounded
    return out


# the trough by depth from its edge (px of the layout) -> colour; the corners take the two sides' shade multiplied
TROUGH = [(0, (6, 6, 5)), (1, (11, 10, 9)), (6, (11, 11, 10)), (9, (12, 12, 10)), (12, (14, 13, 11)), (15, (15, 15, 13)),
          (18, (18, 19, 17)), (21, (20, 20, 18))]


def trough(size=64):
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    d = np.minimum(np.minimum(xx, size - xx), np.minimum(yy, size - yy)) - 0.5
    dx = np.minimum(xx, size - xx) - 0.5
    dy = np.minimum(yy, size - yy) - 0.5
    xs = [p[0] for p in TROUGH]
    flat = np.array(TROUGH[-1][1], np.float32)

    def at(dd):
        return np.stack([np.interp(dd, xs, [p[1][k] for p in TROUGH]) for k in range(3)], axis=2)
    rgb = at(dx) * at(dy) / flat     # the two sides' shade multiplied
    return np.dstack([rgb, np.full((size, size), 255.0)]).astype(np.float32)


def pieces():
    a = composite()
    out = {}
    half = BIG["open"] / RING_SHARE
    out["rings/rpg"] = ring_rim(a, BIG, half, 236)
    out["rings/rpg_disc"] = disc(236, RING_SHARE * 1.03, BIG_DISC)
    half_s = SMALL["outer"] / ORB_OUTER
    out["buttons/orb_rpg"] = ring_rim(a, SMALL, half_s, 98)
    out["buttons/orb_rpg_disc"] = disc(98, SMALL["open"] / half_s * 1.04, SMALL_DISC)
    out["borders/rpg"] = rail_master(a)
    out["borders/rpg_bg"] = trough()
    return out


# ------------------------------------------------------------------------------------------------ the board
def img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def nine(piece, w, h, corner, scale):
    """A square master cut at `corner` px and laid on w x h at `scale` (piece px -> board px), the edges stretched."""
    p = img(piece)
    n = p.width
    c = corner
    cs = max(1, round(c * scale))
    out = Image.new("RGBA", (w, h))
    boxes = {"tl": (0, 0, c, c), "tr": (n - c, 0, n, c), "bl": (0, n - c, c, n), "br": (n - c, n - c, n, n),
             "t": (c, 0, n - c, c), "b": (c, n - c, n - c, n), "l": (0, c, c, n - c), "r": (n - c, c, n, n - c),
             "m": (c, c, n - c, n - c)}
    place = {"tl": (0, 0, cs, cs), "tr": (w - cs, 0, cs, cs), "bl": (0, h - cs, cs, cs), "br": (w - cs, h - cs, cs, cs),
             "t": (cs, 0, w - 2 * cs, cs), "b": (cs, h - cs, w - 2 * cs, cs), "l": (0, cs, cs, h - 2 * cs),
             "r": (w - cs, cs, cs, h - 2 * cs), "m": (cs, cs, w - 2 * cs, h - 2 * cs)}
    for k, box in boxes.items():
        x, y, pw, ph = place[k]
        if pw > 0 and ph > 0:
            out.alpha_composite(p.crop(box).resize((pw, ph), Image.LANCZOS), (x, y))
    return out


def board(made):
    os.makedirs(SKETCH, exist_ok=True)
    Z = 3                                  # board px per UI unit
    font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 15)
    num = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 11 * Z)
    W, H = 1500, 1160
    b = Image.new("RGBA", (W, H), (31, 27, 22, 255))
    d = ImageDraw.Draw(b)
    weights = [("light", 4.9), ("medium", 7.3), ("heavy", 10.9)]
    # the rail on a progress bar, an action button and a backdrop, at each weight
    y = 20
    for wname, band in weights:
        s = band / RAIL["depth"] * Z
        d.text((20, y), "Rail, %s weight (band %.1f UI units)" % (wname, band), font=font, fill=(236, 230, 216))
        y += 26
        # a progress bar 200 x 18 units, the frame round it
        bw, bh = 200 * Z, 18 * Z
        pad = round(RAIL["depth"] * s)
        fr = nine(made["borders/rpg"], bw + 2 * pad, bh + 2 * pad, RAIL["depth"] + 10, s)
        bg = nine(made["borders/rpg_bg"], bw, bh, 22, s)
        b.alpha_composite(bg, (20 + pad, y + pad))
        fill = Image.new("RGBA", (int(bw * 0.7), bh), (200, 20, 20, 255))
        b.alpha_composite(fill, (20 + pad, y + pad))
        b.alpha_composite(fr, (20, y))
        # an action button 40 units, the frame on its rect, the icon in the opening
        ax = 20 + bw + 2 * pad + 40
        aw = 40 * Z
        fr = nine(made["borders/rpg"], aw, aw, RAIL["depth"] + 10, s)
        bg = nine(made["borders/rpg_bg"], aw - 2 * pad + 4, aw - 2 * pad + 4, 22, s)
        b.alpha_composite(bg, (ax + pad - 2, y + pad - 2))
        icon = Image.new("RGBA", (aw - 2 * pad, aw - 2 * pad), (70, 110, 160, 255))
        b.alpha_composite(icon, (ax + pad, y + pad))
        b.alpha_composite(fr, (ax, y))
        # a backdrop 260 x 60 units round a row of buttons
        bx = ax + aw + 40
        dw, dh = 260 * Z, 60 * Z
        if bx + dw > W:
            dw = W - bx - 20
        fr = nine(made["borders/rpg"], dw, dh, RAIL["depth"] + 10, s)
        bg = nine(made["borders/rpg_bg"], dw - 2 * pad, dh - 2 * pad, 22, s)
        b.alpha_composite(bg, (bx + pad, y + pad))
        b.alpha_composite(fr, (bx, y))
        y += max(bh + 2 * pad, aw, dh) + 24
    # the rings: a portrait (64 units: the ring stands on the portrait ring's rect) and the level orb (24 units)
    d.text((20, y), "Portrait ring with its ground (64 UI units), level orb with its ground (24 and 32 UI units)",
           font=font, fill=(236, 230, 216))
    y += 26
    for i, size in enumerate((64, 96)):
        n = size * Z
        g = img(made["rings/rpg_disc"]).resize((n, n), Image.LANCZOS)
        r = img(made["rings/rpg"]).resize((n, n), Image.LANCZOS)
        x = 20 + i * (n + 40)
        b.alpha_composite(g, (x, y))
        b.alpha_composite(r, (x, y))
    ox = 20 + 64 * Z + 96 * Z + 120
    for i, size in enumerate((24, 32)):
        n = size * Z
        g = img(made["buttons/orb_rpg_disc"]).resize((n, n), Image.LANCZOS)
        r = img(made["buttons/orb_rpg"]).resize((n, n), Image.LANCZOS)
        x = ox + i * (n + 40)
        b.alpha_composite(g, (x, y))
        b.alpha_composite(r, (x, y))
        dd = ImageDraw.Draw(b)
        dd.text((x + n / 2, y + n / 2), "60", font=num if size == 32 else
                ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 9 * Z), fill=(255, 210, 0), anchor="mm")
    b.save(os.path.join(SKETCH, "rpg_frames_board.png"))
    for k, v in made.items():
        img(v).save(os.path.join(SKETCH, k.replace("/", "_") + ".png"))
    print(os.path.join(SKETCH, "rpg_frames_board.png"))


def write(made):
    man = json.load(open(MANIFEST, encoding="utf-8"))
    for name, arr in made.items():
        path = os.path.join(SRC, name + ".png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img(arr).save(path)
        h, w = arr.shape[:2]
        man["v2_2x/" + name] = {"w": w, "h": h, "scale": 1.0,
                                "src": "Tools/make_rpg_frames.py: the RPG UI pack's frames (used with its creator's permission)"}
        print("%-22s %dx%d" % (name, w, h))
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    made = pieces()
    if "--write" in sys.argv:
        write(made)
    if "--preview" in sys.argv or "--write" not in sys.argv:
        board(made)
