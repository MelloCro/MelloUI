"""
Build Textures/Masks/Minimap/h128..h255 and v128..v255: the masks that crop
the square minimap to its Width x Height (Modules/MinimapPanel.lua,
Size.Crop; 0.15.0, user 2026-09-28: free Width and Height sliders instead of
the scale).

The game draws the minimap on a square canvas, max(W, H) on a side, and a
mask texture is stretched over the whole of it. Each file shows a band
across the canvas's middle: the band white and opaque, the rest black and
clear (both colour and alpha say it, as the other masks do):

    h<n>   a wide map (W > H): a horizontal band n / 256 of the canvas tall,
           4 x 512 px (the rows 256 - n .. 256 + n - 1 opaque)
    v<n>   a tall map (H > W): the same band standing, 512 x 4 px

n runs 128..255 (the short side at least half the long one; 256 is the
whole square, the game's own WHITE8X8): a step of 400 / 256 = 1.56 units at
the widest, under the sliders' 2, so every step of Height shows. The band's
edges lie on whole texels, so the half-light of the game's filtering falls
exactly on the crop's edge. Files of an older step (h32..h63 of 64ths) are
removed from both folders.

Writes each TGA master (MelloUI-BuildData/masters/Media/Textures/Masks/
Minimap/, Tools/paths.py) and a byte copy into the addon's Media so it ships
at once; `texture_pack.py ship` then makes them BLPs like the other masks.
Deterministic: the same script gives the same bytes.

    python Tools/make_minimap_masks.py            write them all
    python Tools/make_minimap_masks.py --check    exit 1 unless every file is up to date
"""
import hashlib
import os
import re
import struct
import sys

from paths import ADDON_MEDIA, master

FOLDER = ("Textures", "Masks", "Minimap")
STEPS = 256         # the band's height in 256ths of the canvas (MinimapPanel Size.STEPS)
LONG = 512          # px along the band's cut (2 a step)
SHORT = 4           # px across it (the band is the same all along)


def tga(width, height, value):
    """A 32-bit uncompressed TGA, top-left origin, every texel grey and alpha
    value(x, y) (BGRA)."""
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    body = bytearray()
    for y in range(height):
        for x in range(width):
            v = value(x, y)
            body += bytes((v, v, v, v))
    return head + bytes(body)


def build():
    """{ name: bytes } for every mask."""
    out = {}
    half = LONG // 2
    for n in range(STEPS // 2, STEPS):
        lo, hi = half - n, half + n     # the opaque texels: lo .. hi - 1 (2n of LONG = 2 x STEPS)

        def band(t):
            return 255 if lo <= t < hi else 0
        out["h%d.tga" % n] = tga(SHORT, LONG, lambda x, y: band(y))
        out["v%d.tga" % n] = tga(LONG, SHORT, lambda x, y: band(x))
    return out


def extra(root, files):
    """The mask files in `root` of another step (not in `files`)."""
    try:
        names = os.listdir(root)
    except OSError:
        return []
    return [os.path.join(root, n) for n in sorted(names) if re.match(r"^[hv]\d+\.tga$", n) and n not in files]


def main():
    args = sys.argv[1:]
    bad = [a for a in args if a != "--check"]
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    files = build()
    roots = [master(*FOLDER), os.path.join(ADDON_MEDIA, *FOLDER)]
    digest = hashlib.sha256(b"".join(files[k] for k in sorted(files))).hexdigest()
    if "--check" in args:
        stale = []
        for root in roots:
            for name, data in sorted(files.items()):
                path = os.path.join(root, name)
                try:
                    with open(path, "rb") as f:
                        if f.read() != data:
                            stale.append(path)
                except OSError:
                    stale.append(path)
            stale += extra(root, files)
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("%d masks, sha256 %s %s" % (len(files), digest, "ok" if not stale else "STALE"))
        return 1 if stale else 0
    for root in roots:
        os.makedirs(root, exist_ok=True)
        for name, data in sorted(files.items()):
            with open(os.path.join(root, name), "wb") as f:
                f.write(data)
        old = extra(root, files)
        for path in old:
            os.remove(path)
        print("-> %s (%d files, %d of another step removed)" % (os.path.normpath(root), len(files), len(old)))
    print("sha256", digest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
