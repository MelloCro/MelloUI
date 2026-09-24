"""
make_plain_medallions.py -- the class medallions without their four diamonds.

Media/Icons/Class/<CLASS>.tga -> Media/Icons/Class/<CLASS>_plain.tga

The diamonds sit on the gold rim at the four cardinal points. The rim is
rotationally uniform, so each diamond is painted out by copying the rim from
the same radius at another angle (the medallion rotated 30 degrees), and
everything beyond the rim's outer radius (the diamonds' tips) is cleared.
Used by the character window's portrait, where the diamonds would sit under
the kit ring's rail (Modules/ClassIcons.lua, plain variant).
"""
import os, math
import numpy as np
from PIL import Image
from paths import OUTPUT
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
DIR = master("Icons", "Class")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
RIM_OUTER = 0.478        # the rim's outer radius as a fraction of the size (measured 0.473)
DIAMOND_IN = 0.30        # the diamonds reach this far in, as a fraction of the size
HALF_ANGLE = 11          # degrees either side of each cardinal point
ROTATE = 30              # the rim sample comes from this many degrees away


def plain(path):
    im = Image.open(path).convert("RGBA")
    a = np.array(im).astype(int)
    h, w = a.shape[:2]
    cy, cx = (h - 1) / 2, (w - 1) / 2
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - cx, yy - cy) / w
    ang = np.degrees(np.arctan2(yy - cy, xx - cx))                    # -180..180, 90 = bottom
    rr, gg, bb, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    red = (al > 128) & (rr > 110) & (rr > gg * 1.8) & (rr > bb * 1.8) & (r > 0.30)
    out = a.copy()
    donor = np.array(im.rotate(ROTATE, resample=Image.BICUBIC, center=(cx, cy))).astype(int)
    # only the cardinal points that carry a gem; the patch is the wedge around
    # that point, from the rim inwards no further than the gem itself reaches
    for card in (-90, 0, 90, 180):
        d = (ang - card + 180) % 360 - 180
        wedge = np.abs(d) < HALF_ANGLE
        gem = red & wedge
        if gem.sum() < 20:
            continue
        r_in = max(r[gem].min() - 0.01, 0.30)
        patch = wedge & (r >= r_in) & (r <= 0.6)
        out[patch] = donor[patch]
    edge = np.clip((RIM_OUTER + 0.006 - r) / 0.006, 0, 1)
    out[..., 3] = (out[..., 3] * edge).astype(int)
    return Image.fromarray(out.astype(np.uint8))


def main():
    n = 0
    for fn in sorted(os.listdir(DIR)):
        if fn.lower().endswith(".tga") and not fn.endswith("_plain.tga") and not fn.startswith("unmapped"):
            src = os.path.join(DIR, fn)
            dst = os.path.join(DIR, fn[:-4] + "_plain.tga")
            plain(src).save(dst)
            n += 1
    print(f"{n} plain medallions written to {DIR}")
    # preview of one
    prev = Image.new("RGBA", (512, 256), (60, 60, 60, 255))
    prev.alpha_composite(Image.open(os.path.join(DIR, "WARRIOR.tga")).convert("RGBA").resize((256, 256)), (0, 0))
    prev.alpha_composite(Image.open(os.path.join(DIR, "WARRIOR_plain.tga")).convert("RGBA").resize((256, 256)), (256, 0))
    prev.save(os.path.join(OUTPUT, "medallion_plain_preview.png")) if os.path.isdir(OUTPUT) else prev.save(os.path.join(HERE, "..", "..", "medallion_plain_preview.png"))


if __name__ == "__main__":
    main()
