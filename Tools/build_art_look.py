"""
build_art_look.py -- a painted look's masters from its own art (user,
2026-10-04: Forged Steel, the v3 kit).

A palette with "art" in Tools/palettes.json (kit_palette.ART) has a kit
painted for it instead of one recoloured from Media/Kit. Its pieces come as
PNG at the painted 2x size Media/KitLayout.lua records (the same names,
sizes, plate rows and openings; Forged Steel's: MelloUI-BuildData/kit_v3/
v3_2x, made by kit_v3/tools/build_v3.py from the user's material sheets).

Each piece is written where the painted kit's master of the same piece lies
(masters/Media/<Folder>/<file>.tga), on the same power-of-two canvas, at the
same density and place, so the one KitLayout.lua (uv, atlas sheets) holds for
both. A tiled piece is resized round its wrap (still repeats exactly) and its
canvas padded as build_kit.py pads it. The pieces the looks share
(kit_palette.ART_SKIP: cards, icons, the profession backdrops, quilts) are not
written: Kit.lua reads them from Media/Kit (LOOK.ART_UNCOLOURED).

Run:  python Tools/build_art_look.py [palette id] [--src DIR] [--check]
      (the palette id: one of kit_palette.ART, default the first; --check
      builds nothing, exit 1 when a master is missing or differs)
      then python Tools/build_nineslice.py and python Tools/texture_pack.py ship
"""
import io
import os
import re
import sys

import numpy as np
from PIL import Image

import kit_palette
from paths import master, SIBLING

LAYOUT = master("KitLayout.lua")
SOURCES = {"kit_v3": os.path.join(SIBLING, "kit_v3", "v3_2x")}   # palettes.json "art" -> its pieces
PIECE = re.compile(r'^\s*\["(?P<name>[^"]+)"\] = \{ file = "(?P<file>[^"]+)", w = (?P<w>\d+), h = (?P<h>\d+), '
                   r'uv = \{ (?P<uv>[^}]*) \}(?:, tile = "(?P<tile>\w+)")?')


def read_layout():
    out = {}
    for line in open(LAYOUT, encoding="utf-8"):
        m = PIECE.match(line)
        if m:
            out[m["name"]] = {"file": m["file"].replace("\\\\", "/").replace("\\", "/"), "w": int(m["w"]),
                              "h": int(m["h"]), "uv": [float(v) for v in m["uv"].split(",")], "tile": m["tile"] or ""}
    return out


def wrap_resize(a, size, axes):
    """`a` resized to `size`; along a tiled axis round its wrap (three periods side by side, the middle kept),
    so the edges still meet."""
    w, h = size
    tx, ty = ("x" in axes), ("y" in axes)
    big = np.tile(a, (3 if ty else 1, 3 if tx else 1, 1))
    im = Image.fromarray(big).resize((w * (3 if tx else 1), h * (3 if ty else 1)), Image.LANCZOS)
    return np.array(im.crop((w if tx else 0, h if ty else 0, (2 if tx else 1) * w, (2 if ty else 1) * h)))


def master_of(piece, src, kit_file):
    """The look's master of `piece` (its layout entry) from its 2x art `src`, on the painted kit's canvas."""
    with Image.open(kit_file) as im:
        cw, ch = im.size
    sw, sh = round(piece["uv"][1] * cw), round(piece["uv"][3] * ch)
    axes = piece["tile"]
    a = np.array(Image.open(src).convert("RGBA"))
    small = wrap_resize(a, (sw, sh), axes) if axes else np.array(Image.fromarray(a).resize((sw, sh), Image.LANCZOS))
    arr = np.zeros((ch, cw, 4), np.uint8)
    arr[:sh, :sw] = small
    # build_kit.py's padding: a piece tiled along one axis repeats its own edge rows / columns past it (REPEAT wraps
    # both axes; empty texels would bleed into its edge through the filter)
    if "x" in axes and "y" not in axes and sh < ch:
        half = (sh + ch) // 2
        for r in range(sh, ch):
            arr[r] = arr[sh - 1] if r < half else arr[0]
    if "y" in axes and "x" not in axes and sw < cw:
        half = (sw + cw) // 2
        for c in range(sw, cw):
            arr[:, c] = arr[:, sw - 1] if c < half else arr[:, 0]
    return arr


def tga_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a).save(buf, format="TGA")
    return buf.getvalue()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    if not kit_palette.ART:
        raise SystemExit("no palette in Tools/palettes.json has \"art\"")
    pid = args[0] if args else kit_palette.ART[0]
    if pid not in kit_palette.ART:
        raise SystemExit("%s: not a painted palette (kit_palette.ART: %s)" % (pid, ", ".join(kit_palette.ART)))
    folder = kit_palette.LOOKS[pid].folder
    src_root = SOURCES.get(kit_palette.PALETTES[pid]["art"])
    if "--src" in sys.argv:
        src_root = sys.argv[sys.argv.index("--src") + 1]
    if not src_root or not os.path.isdir(src_root):
        raise SystemExit("%s: its art folder %r is not there" % (pid, src_root))
    layout = read_layout()
    out_root = master(folder)
    wanted, problems, total = set(), [], 0
    for name, piece in sorted(layout.items()):
        if not kit_palette.owns(folder, name):
            continue
        src = os.path.join(src_root, name.replace("/", os.sep) + ".png")
        kit_file = master("Kit", piece["file"].replace("/", os.sep) + ".tga")
        if not os.path.exists(src):
            problems.append("%s: no art (%s)" % (name, src))
            continue
        with Image.open(src) as im:
            if im.size != (piece["w"], piece["h"]):
                problems.append("%s: art is %dx%d, the layout's piece %dx%d" % (name, *im.size, piece["w"], piece["h"]))
                continue
        arr = master_of(piece, src, kit_file)
        dst = os.path.join(out_root, piece["file"].replace("/", os.sep) + ".tga")
        wanted.add(os.path.normcase(dst))
        if check:
            if not os.path.exists(dst):
                problems.append("%s/%s: missing" % (folder, piece["file"]))
            else:
                with open(dst, "rb") as fh:
                    if fh.read() != tga_bytes(arr):
                        problems.append("%s/%s: differs" % (folder, piece["file"]))
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.fromarray(arr).save(dst)
        total += os.path.getsize(dst)
    # its border styles (the Window Border and Inner Border choices, user 2026-10-04): beside the art, styles/<id>/
    # holds the window frame and inner frame families in one style and a preview; each is written as the pieces
    # are, under <Folder>/frames/<id>/ (Kit.lua reads a family from there while that style is chosen)
    styles_root = os.path.join(os.path.dirname(src_root), "styles")
    for sid in sorted(os.listdir(styles_root)) if os.path.isdir(styles_root) else []:
        sdir = os.path.join(styles_root, sid)
        if not os.path.isdir(sdir):
            continue
        for fn in sorted(os.listdir(os.path.join(sdir, "window"))) if os.path.isdir(os.path.join(sdir, "window")) else []:
            name = "window/" + fn[:-4]
            piece = layout.get(name)
            if not piece or not re.match(r"^window/(frame|single)_(tl|tr|bl|br|t|b|l|r)$", name):
                problems.append("styles/%s/%s: not a frame family piece" % (sid, fn))
                continue
            arr = master_of(piece, os.path.join(sdir, "window", fn), master("Kit", piece["file"].replace("/", os.sep) + ".tga"))
            dst = os.path.join(out_root, "frames", sid, piece["file"].replace("/", os.sep) + ".tga")
            wanted.add(os.path.normcase(dst))
            if not check:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                Image.fromarray(arr).save(dst)
                total += os.path.getsize(dst)
        pv = os.path.join(sdir, "preview.png")
        if os.path.exists(pv):
            dst = os.path.join(out_root, "frames", sid, "preview.tga")
            wanted.add(os.path.normcase(dst))
            if not check:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                Image.open(pv).convert("RGBA").save(dst)
    # what the look no longer holds (its slices/, and its styles' slices/, are build_nineslice's)
    for dirpath, _, files in os.walk(out_root):
        for f in files:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, out_root).replace(os.sep, "/")
            if rel.startswith("slices/") or "/slices/" in rel or os.path.normcase(p) in wanted:
                continue
            if check:
                problems.append("%s/%s: no longer made" % (folder, rel))
            else:
                os.remove(p)
    if problems:
        print("\n".join("  " + p for p in problems))
        sys.exit(1)
    if check:
        print("%s: %d masters match the art" % (folder, len(wanted)))
        return
    print("%d pieces -> masters Media/%s (%.1f MB)  [art: %s]" % (len(wanted), folder, total / 1e6, src_root))
    # its shadow sheet: its own shapes, laid as the painted kit's (Kit.lua swaps the sheet with the look)
    import make_kit_shadows
    digest = make_kit_shadows.write_look(pid, quiet=True)[:12]
    print("  shadows: Textures/KitShadows%s.tga (sha256 %s), masters and the addon's Media"
          % (kit_palette.LOOKS[pid].suffix, digest))
    # its whole frames (the Game Menu picture), from the palette's colours
    for dst in kit_palette.build_textures(looks=[pid]):
        print("  ->", os.path.relpath(dst, master()))
    print("next: python Tools/build_nineslice.py, then python Tools/texture_pack.py ship (the addon's Media)")


if __name__ == "__main__":
    main()
