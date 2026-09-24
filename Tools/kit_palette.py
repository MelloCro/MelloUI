"""
Recolour the painted UI kit to the palette (MelloUI.Palette, Core/Core.lua):
two looks the player chooses between in game (UI Modifications, Borders:
Kit Colours; user, 2026-09-23: "We can make A and B and let the users select
when in game"), beside the art in its painted colours.

The kit was painted in cool blue-grey iron and stone with bright reds; the
palette is warm dark brown, bronze-gold trim and a deep red. Each piece keeps
its light and dark (a gradient map on its luminance), so the painting, its
bevels and the rails' dark edge lines (kit-art-edge-shadows) stay; only the
colour moves:

  * warm   (A, warm iron): the metal stays metal, cool grey turned to the
           palette's browns (innerPanel, mainWindow, border, a light warm
           grey for its highlights);
  * bronze (B): the same browns, the bright bevels gold (trim,
           selectedTrim, text);
  * in both, red wherever it is painted (a selected row, an open tab, the
    title plate, the red button, a lit gem) becomes the palette's deep red
    (selectedTab), its highlights kept brighter so a lit gem still glints.

Not recoloured, and not copied (the game reads them from Media/Kit in every
look): pictures (backdrops, cards, icons), the tiles already in the palette's
warmth (parchment, vellum, leather) and the coloured quilts.

build_kit.py runs this after writing Media/Kit; or on its own:
    python Tools/kit_palette.py        (Media/Kit -> Media/KitWarm, Media/KitBronze;
                                        Media/Textures/GameMenuFrame -> _warm, _bronze)
All of it in the MASTERS (Tools/paths.py: MelloUI-BuildData/masters/Media);
`python Tools/texture_pack.py ship` then makes what the addon's Media ships.
"""
import os
import re
import sys

import numpy as np
from PIL import Image

from paths import master

KIT = master("Kit")


def _hex(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], float)


# MelloUI.Palette (Core/Core.lua): the swatches' own colours
P = {
    "mainWindow": _hex("#1F1B16"), "innerPanel": _hex("#11100D"), "raisedPanel": _hex("#2E1F14"),
    "border": _hex("#3D342A"), "trim": _hex("#8D642F"), "text": _hex("#C6AF85"),
    "mutedText": _hex("#7F6846"), "selectedTab": _hex("#4E1812"), "selectedTrim": _hex("#AE8546"),
    "hover": _hex("#5A3C24"),
}

# luminance (0..1) -> colour: the metal kept metal, turned warm
WARM = [(0.0, (0, 0, 0)), (0.10, P["innerPanel"]), (0.16, P["mainWindow"]), (0.26, P["border"]),
        (0.55, P["mutedText"] * 1.25), (1.0, (235, 226, 205))]
# ... and the trim: its bright bevels gold
BRONZE = [(0.0, (0, 0, 0)), (0.08, P["innerPanel"]), (0.15, P["mainWindow"]), (0.22, P["border"]),
          (0.38, P["trim"]), (0.55, P["selectedTrim"]), (0.8, P["text"]), (1.0, (245, 235, 210))]
# a red's own brightness -> the palette's deep red, its highlights kept
RED = [(0.0, (0, 0, 0)), (0.18, P["selectedTab"] * 0.7), (0.30, P["selectedTab"]), (0.5, P["selectedTab"] * 1.6),
       (1.0, (200, 120, 100))]

# pictures, the tiles already in the palette's warmth and the coloured quilts: left as painted
SKIP = re.compile(r"^(backdrops|cards|icons)/|^tiles/(vellum|parchment|leather|quilt_|crackle)")
# Page stones toned down (user, 2026-09-23: "tone down the concrete in Warm
# iron and Bronze"; the social window's lists on it were not readable): the
# tile's light remapped round a dark middle with little spread before the
# ramp -- calm dark stone a step lighter than the list stone (window bodies,
# ~0.10), its cracks a hint
TONED = re.compile(r"^tiles/concrete")
TONED_MID, TONED_SPREAD = 0.16, 0.09

# each look: its folder beside Media/Kit and its ramp (Kit.colourLooks in Kit.lua)
LOOKS = {"warm": ("KitWarm", WARM), "bronze": ("KitBronze", BRONZE)}


def _gradient(v, stops):
    xs = np.array([s[0] for s in stops])
    cs = np.array([s[1] for s in stops], float)
    return np.stack([np.interp(v, xs, cs[:, i]) for i in range(3)], -1)


def recoloured(name):
    """Whether the piece `name` ("window/frame_t") is recoloured (else read
    from Media/Kit in every look)."""
    return not SKIP.search(name)


def recolour_toned(a, look):
    """A page stone in the look's colours, toned down (TONED)."""
    rgb = a[..., :3].astype(float) / 255
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    p5, p50, p95 = np.percentile(lum, [5, 50, 95])
    t = (lum - p50) / max(p95 - p5, 1e-6)
    lum2 = np.clip(TONED_MID + t * TONED_SPREAD, 0, 1)
    b = a.copy()
    b[..., :3] = np.clip(np.round(_gradient(lum2, LOOKS[look][1])), 0, 255).astype(np.uint8)
    return b


def recolour(a, look):
    """An RGBA uint8 array in the look's colours."""
    rgb = a[..., :3].astype(float) / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    red = (sat > 0.45) & (rgb[..., 0] >= rgb[..., 1]) & (rgb[..., 0] >= rgb[..., 2])
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    lum_red = 0.6 * rgb[..., 0] + 0.3 * rgb[..., 1] + 0.1 * rgb[..., 2]
    out = np.where(red[..., None], _gradient(lum_red, RED), _gradient(lum, LOOKS[look][1]))
    b = a.copy()
    b[..., :3] = np.clip(np.round(out), 0, 255).astype(np.uint8)
    return b


def build_looks(kit=KIT):
    """Every recoloured piece of Media/Kit into each look's folder (files of a
    look no longer in the kit removed). Returns { look: (files, bytes) }."""
    done = {}
    for look, (folder, _) in LOOKS.items():
        out_root = os.path.join(os.path.dirname(kit), folder)
        wanted = set()
        total = 0
        for dirpath, _, files in os.walk(kit):
            for f in files:
                if not f.lower().endswith(".tga"):
                    continue
                src = os.path.join(dirpath, f)
                name = os.path.relpath(src, kit)[:-4].replace(os.sep, "/")
                if not recoloured(name):
                    continue
                dst = os.path.join(out_root, name.replace("/", os.sep) + ".tga")
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                a = np.array(Image.open(src).convert("RGBA"))
                out = recolour_toned(a, look) if TONED.search(name) else recolour(a, look)
                Image.fromarray(out).save(dst)
                wanted.add(os.path.normcase(dst))
                total += os.path.getsize(dst)
        for dirpath, _, files in os.walk(out_root):
            for f in files:
                p = os.path.join(dirpath, f)
                if os.path.normcase(p) not in wanted:
                    os.remove(p)
        done[look] = (len(wanted), total)
    return done


# Whole painted frames outside the kit (Media/Textures), one file per look
# beside the painted one ("GameMenuFrame_warm.tga"; user, 2026-09-24: the
# Game Menu kept its painted colours in both looks). Their gold (the Game
# Menu's header plate) stays gold in the palette's trim, not the red ramp.
TEXTURES = ["GameMenuFrame"]
GOLD = [(0.0, (0, 0, 0)), (0.12, P["raisedPanel"]), (0.30, P["trim"] * 0.75), (0.48, P["trim"]),
        (0.65, P["selectedTrim"]), (0.85, P["text"]), (1.0, (245, 235, 210))]


def recolour_picture(a, look):
    """A whole frame in the look's colours: red to the deep red, gold to the
    trim's gold, the rest (iron, stone) on the look's ramp."""
    rgb = a[..., :3].astype(float) / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    coloured = (sat > 0.35) & (mx > 0.2)
    red = coloured & ((hue < 18) | (hue > 330))
    gold = coloured & (hue >= 18) & (hue <= 65)
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    lum_red = 0.6 * r + 0.3 * g + 0.1 * b
    out = _gradient(lum, LOOKS[look][1])
    out = np.where(gold[..., None], _gradient(lum, GOLD), out)
    out = np.where(red[..., None], _gradient(lum_red, RED), out)
    c = a.copy()
    c[..., :3] = np.clip(np.round(out), 0, 255).astype(np.uint8)
    return c


def build_textures(textures=os.path.join(os.path.dirname(KIT), "Textures")):
    """Each of TEXTURES in every look, beside it. Returns the files written."""
    written = []
    for base in TEXTURES:
        src = os.path.join(textures, base + ".tga")
        if not os.path.exists(src):
            continue
        a = np.array(Image.open(src).convert("RGBA"))
        for look in LOOKS:
            dst = os.path.join(textures, f"{base}_{look}.tga")
            Image.fromarray(recolour_picture(a, look)).save(dst)
            written.append(dst)
    return written


if __name__ == "__main__":
    for look, (n, total) in build_looks().items():
        print(f"{look}: {n} pieces -> masters Media/{LOOKS[look][0]} ({total / 1e6:.1f} MB)")
    for dst in build_textures():
        print("->", dst)
    print("next: python Tools/texture_pack.py ship (the addon's Media)")
