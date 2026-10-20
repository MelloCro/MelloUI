"""Hold the shipped Edit Mode layout's frames to the screen's edges (1.0, the user's layout of 2026-10-20).

Edit Mode writes a dragged frame's anchor from wherever it was: the user's layout holds most frames from the screen's
centre and some from its top-left corner (the right-hand bars 2399 units from the left edge). The fitter keeps every
anchor and moves pieces by its rules, so on a narrower screen such a frame stays that far from its anchor and leaves
the screen. This tool holds every system held to UIParent (not in its default position), on each axis, to the edge
-- or the middle -- of the design screen's third it stands in (the middle column under the screen's middle to the
bottom: the bottom HUD, the bars, the frames and what stands on them), its own frame's point kept and its rect at the
design screen unchanged (proved by solving both strings: hud.solve, the fitter's own size model).

    python anchor_layout.py            what it would change in Media/EditModeLayout.lua's `layout`
    python anchor_layout.py --write    writes it there (then python golden.py for the bake's source.json)
    python anchor_layout.py --check    exit 1 when the layout holds a frame to an edge it does not stand by

Run it on every new layout the user exports. Oldschool's layout (MelloUI_Oldschool/Media/Shipped.lua) is the fitter's
reviewed design and stays as it is.
"""
import argparse
import copy
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "lib"))
import layoutcodec as C  # noqa: E402
import hud               # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
FILE = os.path.join(ROOT, "Media", "EditModeLayout.lua")
# the design screen in UIParent units (Core/LayoutFit.lua DESIGN_W, DESIGN_H: 3440 x 1440 at UI scale 0.64)
DESIGN_H = 768 / 0.64
DESIGN_W = DESIGN_H * 3440 / 1440
AXX = {"TOPLEFT": 0, "TOP": 0.5, "TOPRIGHT": 1, "LEFT": 0, "CENTER": 0.5, "RIGHT": 1, "BOTTOMLEFT": 0, "BOTTOM": 0.5,
       "BOTTOMRIGHT": 1}
AXY = {"TOPLEFT": 0, "TOP": 0, "TOPRIGHT": 0, "LEFT": 0.5, "CENTER": 0.5, "RIGHT": 0.5, "BOTTOMLEFT": 1, "BOTTOM": 1,
       "BOTTOMRIGHT": 1}
LAYOUT_RX = re.compile(r"(\blayout\s*=\s*\[(=*)\[)(.*?)(\]\2\])", re.S)


def point_name(hx, vy):
    name = {0: "TOP", 1: "BOTTOM"}.get(vy, "") + {0: "LEFT", 1: "RIGHT"}.get(hx, "")
    return name or "CENTER"


def wanted(rect, W=DESIGN_W, H=DESIGN_H):
    """(hx, vy): the edge or middle of the design screen's third the rect stands in, on each axis"""
    left, top, right, bottom = rect
    cx, cy = (left + right) / 2 / W, (top + bottom) / 2 / H
    hx = 0 if cx < 1 / 3 else 1 if cx > 2 / 3 else 0.5
    vy = 0 if cy < 1 / 3 else 1 if (cy > 2 / 3 or (hx == 0.5 and cy > 0.5)) else 0.5
    return hx, vy


def anchored(layout):
    """The layout (layoutcodec's shape) with every frame held to its third's edge; the changes as text."""
    rects, _ = hud.solve(layout, DESIGN_W, DESIGN_H)
    out = copy.deepcopy(layout)
    changes = []
    for s in out["systems"]:
        a = s["anchor"]
        if s["isInDefaultPosition"] or a["relativeTo"] != "UIParent" or a["point"] not in AXX or a["relativePoint"] not in AXX:
            continue
        rect = rects.get(s["key"])
        if not rect:
            continue
        hx, vy = wanted(rect)
        if hx == AXX[a["relativePoint"]] and vy == AXY[a["relativePoint"]]:
            continue
        left, top, right, bottom = rect
        w, h = right - left, bottom - top
        was = "%s->%s (%.1f, %.1f)" % (a["point"], a["relativePoint"], a["offsetX"], a["offsetY"])
        a["relativePoint"] = point_name(hx, vy)
        a["offsetX"] = round(left + AXX[a["point"]] * w - hx * DESIGN_W, 1) + 0.0
        a["offsetY"] = round(vy * DESIGN_H - (top + AXY[a["point"]] * h), 1) + 0.0
        changes.append("%-5s %-34s %s -> %s->%s (%.1f, %.1f)" % (s["key"], s["systemName"] + (
            "." + s["systemIndexName"] if s.get("systemIndexName") else ""), was, a["point"], a["relativePoint"],
            a["offsetX"], a["offsetY"]))
    return out, changes


def same_rects(a, b, tol=0.11):   # (the share string keeps offsets to a tenth; the solver rounds its rects to one)
    ra, _ = hud.solve(a, DESIGN_W, DESIGN_H)
    rb, _ = hud.solve(b, DESIGN_W, DESIGN_H)
    bad = [k for k in ra if k not in rb or any(abs(x - y) > tol for x, y in zip(ra[k], rb[k]))]
    return not bad and set(ra) == set(rb), bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    src = open(FILE, encoding="utf-8", newline="").read()
    m = LAYOUT_RX.search(src)
    if not m:
        raise SystemExit("no `layout = [[...]]` in " + FILE)
    old = m.group(3)
    layout = C.decode(old)
    new_layout, changes = anchored(layout)
    if a.check:
        if changes:
            print("the layout holds %d frames to an edge they do not stand by: python %s --write" % (len(changes), __file__))
            for c in changes:
                print("  " + c)
            raise SystemExit(1)
        print("every frame is held to the edge of its third")
        return
    new = C.encode(new_layout)
    ok, bad = same_rects(layout, C.decode(new))
    if not ok:
        raise SystemExit("the anchors moved frames at the design screen: %s" % bad)
    for c in changes:
        print(c)
    print("%d frames held to their third's edge; every rect at %.1f x %.1f the same" % (len(changes), DESIGN_W, DESIGN_H))
    if a.write and changes:
        out = src[:m.start(3)] + new + src[m.end(3):]
        with open(FILE, "w", encoding="utf-8", newline="") as fh:
            fh.write(out)
        print("wrote " + FILE)


if __name__ == "__main__":
    main()
