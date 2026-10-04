"""
make_gemless_buttons.py -- the red button's caps without their gems (user, 2026-10-04: "i only want the buttons
to look like the second picture, no more diamonds on the sides").

buttons/redbtn_cap_{l,r}_<state> in Tools/pack_sources/kit/v2_2x are cut at the notch between the gem's
connector box and the plate's own rounded end bar: what is left is the plate's closed end, its gold bar and
rounded corners as painted (the columns where the two shapes meet are the narrowest, the notch). The mid is
unchanged; the caps' height (89) and their place in the strip stay, so the layout's numbers keep their meaning.

The originals are kept once in MelloUI-BuildData/pack_sources_archive/redbtn_gem_caps/ (pack_sources is
git-ignored), and the manifest's widths follow. A cap already cut (no wider than MAX_CUT) is left alone, so
running it again changes nothing.

A painted look's art (Forged Steel's v3 kit, build_art_look.SOURCES) is cut to the same widths, since one atlas
layout holds every look: its caps have no gem, so their OUTER end (the plate's closed end) is kept.

Run:  python Tools/make_gemless_buttons.py
      then build_kit.py, build_art_look.py, build_nineslice.py, texture_pack.py ship
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image

from paths import SIBLING

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
BUTTONS = os.path.join(SRC, "buttons")
MANIFEST = os.path.join(SRC, "manifest.json")
ARCHIVE = os.path.join(SIBLING, "pack_sources_archive", "redbtn_gem_caps")
STATES = ("normal", "hover", "pressed", "disabled")
SEARCH = 30        # the notch lies within this many columns of the plate's side
MAX_CUT = 24       # a cap this narrow is already its end bar


def notch(a, side):
    """The column where the connector box and the end bar meet: the fewest opaque rows near the plate's side
    (the left cap's right end, the right cap's left end)."""
    cov = (a[..., 3] > 40).sum(0)
    w = a.shape[1]
    cols = range(w - SEARCH, w) if side == "l" else range(0, SEARCH)
    return min(cols, key=lambda x: (cov[x], abs(x - (w - SEARCH // 2 if side == "l" else SEARCH // 2))))


def cut(name, side, width):
    """The cap `name` cut to `width` columns from the plate's side (its end bar); None when already cut."""
    path = os.path.join(BUTTONS, name + ".png")
    a = np.array(Image.open(path).convert("RGBA"))
    if a.shape[1] <= MAX_CUT:
        return None
    os.makedirs(ARCHIVE, exist_ok=True)
    keep = os.path.join(ARCHIVE, name + ".png")
    if not os.path.exists(keep):
        shutil.copy2(path, keep)
    out = a[:, a.shape[1] - width:] if side == "l" else a[:, :width]
    Image.fromarray(np.ascontiguousarray(out)).save(path)
    return width


def side_width(side):
    """One width for every state of a side (the strip swaps states into the same cap): the widest end bar."""
    widest = 0
    for state in STATES:
        a = np.array(Image.open(os.path.join(BUTTONS, "redbtn_cap_%s_%s.png" % (side, state))).convert("RGBA"))
        if a.shape[1] <= MAX_CUT:
            return None
        x = notch(a, side)
        widest = max(widest, a.shape[1] - x if side == "l" else x + 1)
    return widest


def cut_art(width_of):
    """A painted look's art (build_art_look.SOURCES: Forged Steel's v3 kit) on the same widths: one atlas layout
    holds every look, so its caps must be the painted kit's size. Its caps have no gem; their closed end is the
    OUTER end, so the outer columns are kept. The originals kept beside the painted kit's."""
    import build_art_look
    for art, root in sorted(build_art_look.SOURCES.items()):
        keep_dir = os.path.join(ARCHIVE, art)
        for side in ("l", "r"):
            for state in STATES:
                name = "redbtn_cap_%s_%s" % (side, state)
                path = os.path.join(root, "buttons", name + ".png")
                if not os.path.exists(path):
                    continue
                a = np.array(Image.open(path).convert("RGBA"))
                width = width_of[side]
                if a.shape[1] == width:
                    print("%-26s %s: already its end" % (name, art))
                    continue
                os.makedirs(keep_dir, exist_ok=True)
                keep = os.path.join(keep_dir, name + ".png")
                if not os.path.exists(keep):
                    shutil.copy2(path, keep)
                out = a[:, :width] if side == "l" else a[:, a.shape[1] - width:]
                Image.fromarray(np.ascontiguousarray(out)).save(path)
                print("%-26s %s: cut to %d px (its outer end)" % (name, art, width))


def main():
    with open(MANIFEST, encoding="utf-8") as fh:
        manifest = json.load(fh)
    changed = 0
    for side in ("l", "r"):
        width = side_width(side)
        for state in STATES:
            name = "redbtn_cap_%s_%s" % (side, state)
            w = cut(name, side, width) if width else None
            if w is None:
                print("%-26s already without its gem" % name)
                continue
            entry = manifest.get("v2_2x/buttons/" + name)
            if entry is not None:
                entry["w"] = w
            changed += 1
            print("%-26s cut to %d px (its end bar)" % (name, w))
    if changed:
        with open(MANIFEST, "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, indent=1, sort_keys=True)
        print("originals kept in", ARCHIVE)
    # the painted looks' caps on the painted kit's widths (one layout for every look)
    width_of = {side: Image.open(os.path.join(BUTTONS, "redbtn_cap_%s_normal.png" % side)).width for side in ("l", "r")}
    cut_art(width_of)
    print("next: build_kit.py, build_art_look.py, build_nineslice.py, texture_pack.py ship")
    return 0


if __name__ == "__main__":
    sys.exit(main())
