"""
make_single_rail.py -- a single-rail nine-slice family for the kit.

window/single_{t,b,l,r,tl,tr,bl,br,body}  from the bar frame's top rail:
the window's own edge is a double rail (two bevels with a channel); this is
one bevel, for frames that should read as a single line. Edges tile, corners
are mitred from the two edges, body = the window body (same stone).
Writes into kit/v2_2x/window/ and updates manifest.json; run build_kit.py after.
"""
import os, json
import numpy as np
from PIL import Image

KIT = r"C:\Users\mortu\Downloads\UITest\kit\v2_2x"
SRC = os.path.join(KIT, "bars", "frame_mid.png")       # a hollow bar: rails top and bottom
OUT = os.path.join(KIT, "window")


def top_rail(a):
    """rows of the top rail of a hollow bar (down to where the opening begins)."""
    al = a[..., 3] > 128
    col = al[:, a.shape[1] // 2]
    ys = np.where(col)[0]
    top = ys.min()
    y = top
    while y < a.shape[0] and col[y]:
        y += 1
    return top, y


def main():
    a = np.array(Image.open(SRC).convert("RGBA"))
    t0, t1 = top_rail(a)
    rail = a[t0:t1]                              # T x W, the horizontal rail, tiles in x
    T, W = rail.shape[:2]
    # pad the rail with 2 px of transparency on the outside so the bevel's edge stays soft
    pad = 2
    t = np.zeros((T + pad, W, 4), np.uint8); t[pad:] = rail            # outside edge at the top
    b = t[::-1].copy()
    l = np.rot90(t, k=1).copy()                                         # (W x T+pad): outside edge at the left
    r = l[:, ::-1].copy()
    H = T + pad
    # corners: the two edges meeting, split on the diagonal (outer corner to inner corner)
    yy, xx = np.mgrid[0:H, 0:H]
    def corner(hsq, vsq, flipx, flipy):
        x = (H - 1 - xx) if flipx else xx
        y = (H - 1 - yy) if flipy else yy
        return np.where((y <= x)[..., None], hsq, vsq).astype(np.uint8)
    tl = corner(t[:, :H], l[:H], False, False)
    tr = corner(t[:, -H:], r[:H], True, False)
    bl = corner(b[:, :H], l[-H:], False, True)
    br = corner(b[:, -H:], r[-H:], True, True)
    body = np.array(Image.open(os.path.join(OUT, "frame_body.png")).convert("RGBA"))
    pieces = { "single_t": t, "single_b": b, "single_l": l, "single_r": r, "single_tl": tl, "single_tr": tr, "single_bl": bl, "single_br": br, "single_body": body }
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))
    for name, arr in pieces.items():
        Image.fromarray(arr).save(os.path.join(OUT, name + ".png"))
        man["v2_2x/window/" + name] = { "w": int(arr.shape[1]), "h": int(arr.shape[0]), "scale": 1.0, "src": "synth from bars/frame_mid rail" }
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)
    print(f"single rail: {T} px rail (+{pad} pad) -> {H} px edge; pieces written")


if __name__ == "__main__":
    main()
