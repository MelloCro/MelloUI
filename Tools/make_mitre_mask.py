"""
Build Textures/Masks/mitre: the mask that mitres two rails where an action
bar backdrop drawn in a border library style turns an inner corner (0.19.6,
border library stage 3; Modules/ActionBarPanel.lua, Mitre). The user picked
"mitred" of MelloUI-BuildData/output/bar_group_border_sketch (2026-10-06).

One 64 x 64 file: the top-left half of the square opaque, cut by the diagonal
from its top-right corner to its bottom-left one. A rail's slice laid over the
joint's square takes it turned to its half by its texture coordinates (both
ways mirrored: the other three halves). Each texel holds the exact share of
its square on the opaque side, so a half and its twin (the file turned half a
turn) add up to one everywhere: the two rails meet with no seam, dark or
light. White and opaque on black and clear (both colour and alpha say it, as
the other masks do).

Writes the TGA master (MelloUI-BuildData/masters/Media/Textures/Masks/,
Tools/paths.py) and a byte copy into the addon's Media; `texture_pack.py ship`
keeps it as that TGA (its STAY_TGA: 16 KB). Deterministic.

    python Tools/make_mitre_mask.py            write it
    python Tools/make_mitre_mask.py --check    exit 1 unless it is up to date
"""
import hashlib
import os
import struct
import sys

from paths import ADDON_MEDIA, master

FOLDER = ("Textures", "Masks")
NAME = "mitre.tga"
N = 64
SUB = 16            # samples a side per texel: the share on the opaque side, to 1 / 256


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


def share(x, y):
    """the share of texel (x, y) above-left of the line X + Y = N (texel units, y down), as 0..255"""
    if x + y + 2 <= N:
        return 255
    if x + y >= N:
        return 0
    # (in halves of a sample, exact: a sample on the line counts half to each side, so a texel and its twin across
    # the line hold every sample between them)
    inside, line = 0, N * 2 * SUB
    for i in range(SUB):
        for j in range(SUB):
            s = (2 * SUB * x + 2 * i + 1) + (2 * SUB * y + 2 * j + 1)
            inside += 2 if s < line else (1 if s == line else 0)
    return round(255 * inside / (2 * SUB * SUB))


def build():
    return tga(N, N, share)


def main():
    args = sys.argv[1:]
    bad = [a for a in args if a != "--check"]
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    data = build()
    paths = [os.path.join(master(*FOLDER), NAME), os.path.join(ADDON_MEDIA, *FOLDER, NAME)]
    digest = hashlib.sha256(data).hexdigest()
    if "--check" in args:
        stale = []
        for path in paths:
            try:
                with open(path, "rb") as f:
                    if f.read() != data:
                        stale.append(path)
            except OSError:
                stale.append(path)
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("mitre mask, sha256 %s %s" % (digest, "ok" if not stale else "STALE"))
        return 1 if stale else 0
    for path in paths:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        print("->", os.path.normpath(path))
    print("sha256", digest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
