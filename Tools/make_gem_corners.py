"""
make_gem_corners.py -- the window sheet's painted gem corners as oversized
nine-slice corners for the double-rail window frame (window/frame_*).

ChatGPT painted the four corners (kit/v2/window/corner_ornament_tl,
frame_tr_art, frame_bl_art, frame_br_art) with rails thinner than the sheet's
repeatable edges and the gem protruding by a different amount at each corner.
Each corner is scaled so the cross-section of its arms equals the 2x edge's
opaque thickness, then padded so the rails' outer edges sit OVERHANG px inside
the canvas on the two outer sides: the gem sticks out past the frame by that
much, and each arm's end fades out over RAMP px so the slightly different
bevels blend into the edge under it. Kit:NineSlice draws them over the edges, anchored OVERHANG*scale outside
the frame's corners (the mitred corners stay under them).

Writes kit/v2_2x/window/frame_gem_{tl,tr,bl,br}.png and manifest entries with
"overhang"; run build_kit.py after.
"""
import os, json
import numpy as np
from PIL import Image

KIT = r"C:\Users\mortu\Downloads\UITest\kit"
SRC = os.path.join(KIT, "v2", "window")
OUT = os.path.join(KIT, "v2_2x", "window")
OVERHANG = 12          # px at 2x: the gem past the rails' outer edge
RAMP = 24              # px at 2x: each arm's end fades out over the edge under it (the bevels differ slightly)

# corner -> (source, arm end for the horizontal rail, arm end for the vertical rail)
CORNERS = {
    "tr": ("frame_tr_art", "l", "b"),
    "tl": ("corner_ornament_tl", "r", None),      # the ornament stands in for the vertical arm

    "bl": ("frame_bl_art", "r", "t"),
    "br": ("frame_br_art", "l", "t"),
}


def extent(mask):
    idx = np.where(mask)[0]
    return (int(idx.min()), int(idx.max()) + 1) if len(idx) else None


def arm(a, side):
    """opaque cross-section (start, end) of the arm that ends at `side`."""
    al = a[..., 3] > 128
    H, W = al.shape
    if side == "l":
        return extent(al[:, 2:6].any(1))
    if side == "r":
        return extent(al[:, W - 6:W - 2].any(1))
    if side == "t":
        return extent(al[2:6].any(0))
    return extent(al[H - 6:H - 2].any(0))


def main():
    edge = np.array(Image.open(os.path.join(OUT, "frame_t.png")).convert("RGBA"))
    t0, t1 = extent((edge[..., 3] > 128)[:, edge.shape[1] // 2])
    thick = t1 - t0                         # the 2x edge's opaque thickness
    man_path = os.path.join(KIT, "v2_2x", "manifest.json")
    man = json.load(open(man_path))
    tr_right = 0
    for c, (src, hside, vside) in CORNERS.items():
        a = np.array(Image.open(os.path.join(SRC, src + ".png")).convert("RGBA"))
        H, W = a.shape[:2]
        h = arm(a, hside)
        v = arm(a, vside) if vside else None
        widths = [h[1] - h[0]] + ([v[1] - v[0]] if v else [])
        s = thick / (sum(widths) / len(widths))
        im = Image.fromarray(a).resize((round(W * s), round(H * s)), Image.LANCZOS)
        # where the rails' outer edges sit after scaling
        top = h[0] * s if c in ("tl", "tr") else None
        bot = (H - h[1]) * s if c in ("bl", "br") else None
        if v:
            left = v[0] * s if c in ("tl", "bl") else None
            right = (W - v[1]) * s if c in ("tr", "br") else None
        else:
            # the ornament corner has no vertical arm: its gem sits where the
            # top-right's does (same distance from the canvas edge), mirrored
            left, right = tr_right, None
        # pad the outer sides so the outer edges sit at OVERHANG
        def pad(side):
            d = { "top": top, "bottom": bot, "left": left, "right": right }[side]
            return max(0, round(OVERHANG - d)) if d is not None else 0
        pt, pb, pl, pr = pad("top"), pad("bottom"), pad("left"), pad("right")
        if c == "tr":
            tr_right = right
        arr = np.array(im).astype(float)
        ramp = np.linspace(1, 0, RAMP)
        if hside == "l":
            arr[:, :RAMP, 3] *= ramp[::-1]
        else:
            arr[:, -RAMP:, 3] *= ramp
        if vside == "t":
            arr[:RAMP, :, 3] *= ramp[::-1, None]
        elif vside == "b":
            arr[-RAMP:, :, 3] *= ramp[:, None]
        im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
        canvas = Image.new("RGBA", (im.width + pl + pr, im.height + pt + pb))
        canvas.paste(im, (pl, pt))
        name = f"frame_gem_{c}"
        canvas.save(os.path.join(OUT, name + ".png"))
        man[f"v2_2x/window/{name}"] = { "w": canvas.width, "h": canvas.height, "scale": round(s, 4), "overhang": OVERHANG,
                                         "src": f"{src} scaled to the edge's {thick} px rail" }
        print(f"{name}: {src} x{s:.3f} -> {canvas.width}x{canvas.height}, arms {widths} -> {thick}, pads t{pt} b{pb} l{pl} r{pr}")
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
