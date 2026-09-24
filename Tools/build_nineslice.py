"""
build_nineslice.py -- each rail family of the kit as ONE picture, for the
one-texture nine-slices (Kit:NineSlice while `/mellokit slices on`; user,
2026-09-24: stage 2 of the performance programme, behind a switch that is
off by default).

Today a window's rails are eight textures (four tiled edges, four corners).
The client can draw a nine-slice from one texture itself
(Texture:SetTextureSliceMargins + SetTextureSliceMode Tiled): the picture is
cut by four margins into corners, edges and a middle, the corners drawn once,
the edges and the middle repeated. This tool lays each family's eight pieces
into such a picture, texel for texel as the files hold them:

    +----+----------------+----+
    | tl | t  (repeats)   | tr |      corner = the pieces' side, in texels
    +----+----------------+----+      (the margins)
    | l  |  (empty)       | r  |      whole repeats of each edge: the middle
    |    |                |    |      column is as wide as both the top and the
    +----+----------------+----+      bottom edge repeat evenly in (their
    | bl | b              | br |      least common multiple, as many times as
    +----+----------------+----+      the power-of-two canvas holds), the middle
                                      row likewise for the side edges

The middle stays empty: a window's stone body is its own texture, a
BACKGROUND at the screen's one density (Kit:Retile), which a slice drawn at
the rails' density cannot be. Only the mitred corners are laid: a skin with
a gem corner (a window's outer rail) stays in pieces (Kit.lua says why).

Every pixel is copied, never resampled, so the rails' dark edge lines (their
shadow; kit-art-edge-shadows) come through as painted. Past the picture's
bottom and right the canvas holds what the edge pieces' files hold past
theirs (their outermost row / column again; the corners' files hold
nothing), which the client's filtering reads along those rails' outer lines.
A family is refused (left out of the data: the kit keeps drawing it in
pieces) unless its four corners are square and the same size, its edges as
thick as the corners, the top and bottom edges repeat across (tile "x") and
the sides down ("y"), and all eight pieces are held at one density.

All in the MASTERS (Tools/paths.py: MelloUI-BuildData/masters/Media, never
shipped; user, 2026-09-24):
Reads  Media/KitLayout.lua                       the pieces' geometry (w, h, uv, tile), each
                                                 piece in its own file (build_kit.py's)
       Media/<look>/window/<family>_*.tga       the eight pieces, in each look
Writes Media/<look>/slices/<family>.tga          the picture (32-bit TGA, power-of-two
                                                 canvas, picture at the top-left)
       Media/KitSlices.lua                       MelloUI_KitSlices: files, grid, margins,
                                                 and the geometry each was built from
                                                 (the kit falls back to pieces when a
                                                 piece's geometry is tuned or rebuilt)
Looks: Media/Kit (painted), Media/KitWarm, Media/KitBronze (Kit.colourLooks).
`python Tools/texture_pack.py ship` then puts the pictures (BLP where the
quality gate passes) and KitSlices.lua into the addon's Media; it keeps the
eight pieces of each family in their own files, as recorded here.

Run:   python Tools/build_nineslice.py           after Tools/build_kit.py
       python Tools/build_nineslice.py --check   the pictures still match the pieces
                                                  (exit 1 when one is stale)
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image

from paths import MASTER_MEDIA

MEDIA = MASTER_MEDIA
LAYOUT = os.path.join(MEDIA, "KitLayout.lua")
LUA = os.path.join(MEDIA, "KitSlices.lua")
LOOKS = ("Kit", "KitWarm", "KitBronze")   # Kit.colourLooks' folders (Kit = the painted one)
PARTS = ("tl", "t", "tr", "l", "r", "bl", "b", "br")
CORNERS = ("tl", "tr", "bl", "br")

PIECE = re.compile(r'^\s*\["(?P<name>[^"]+)"\] = \{ file = "(?P<file>[^"]+)", w = (?P<w>\d+), h = (?P<h>\d+), '
                   r'uv = \{ (?P<uv>[^}]*) \}(?:, tile = "(?P<tile>\w+)")?')


def read_layout(path=LAYOUT):
    """{ name: { file, w, h, uv, tile } } from the generated KitLayout.lua."""
    pieces = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = PIECE.match(line)
            if m:
                pieces[m["name"]] = {
                    "file": m["file"].replace("\\\\", "\\"),
                    "w": int(m["w"]), "h": int(m["h"]),
                    "uv": [float(v) for v in m["uv"].split(",")],
                    "tile": m["tile"] or "",
                }
    return pieces


def families(pieces):
    """Every rail family: a prefix with all eight parts (window/frame, window/single)."""
    out = []
    for name in sorted(pieces):
        m = re.fullmatch(r"(.+)_tl", name)
        if m and all(m[1] + "_" + part in pieces for part in PARTS):
            out.append(m[1])
    return out


def pot_up(n):
    return 1 << max(0, math.ceil(math.log2(max(n, 1))))


def num(v):
    """A number as build_kit.py writes one into KitLayout.lua."""
    return ("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def piece_file(look, piece):
    return os.path.join(MEDIA, look, piece["file"].replace("\\", os.sep) + ".tga")


def crop(look, piece):
    """The piece's texels, cut out of its power-of-two file by its uv."""
    a = np.array(Image.open(piece_file(look, piece)).convert("RGBA"))
    fh, fw = a.shape[:2]
    u1, u2, v1, v2 = piece["uv"]
    x1, x2, y1, y2 = round(u1 * fw), round(u2 * fw), round(v1 * fh), round(v2 * fh)
    return a[y1:y2, x1:x2]


class Refused(Exception):
    pass


def plan(prefix, pieces, look="Kit"):
    """The family's geometry, checked: corner side (texels), the edges' repeats,
    the grid, the density. Raises Refused with the reason."""
    p = {part: pieces[prefix + "_" + part] for part in PARTS}
    side = p["tl"]["w"]
    for c in CORNERS:
        if (p[c]["w"], p[c]["h"]) != (side, side):
            raise Refused(f"{prefix}_{c} is {p[c]['w']}x{p[c]['h']}, not {side}x{side} like the top-left corner")
    for e in ("t", "b"):
        if p[e]["tile"] != "x" or p[e]["h"] != side:
            raise Refused(f"{prefix}_{e} must repeat across (tile x) and be {side} thick")
    for e in ("l", "r"):
        if p[e]["tile"] != "y" or p[e]["w"] != side:
            raise Refused(f"{prefix}_{e} must repeat down (tile y) and be {side} thick")
    cut = {part: crop(look, p[part]) for part in PARTS}
    densities = set()
    for part in PARTS:
        h, w = cut[part].shape[:2]
        densities.add((w / p[part]["w"], h / p[part]["h"]))
    dx = {d[0] for d in densities} | {d[1] for d in densities}
    if len(dx) != 1:
        raise Refused(f"{prefix}: the pieces are held at different densities {sorted(dx)}")
    density = dx.pop()
    corner = cut["tl"].shape[1]
    if corner != side * density or corner != round(corner):
        raise Refused(f"{prefix}: a corner is not a whole number of texels")
    rep_w = math.lcm(cut["t"].shape[1], cut["b"].shape[1])
    rep_h = math.lcm(cut["l"].shape[0], cut["r"].shape[0])
    size = (pot_up(2 * corner + rep_w), pot_up(2 * corner + rep_h))
    # as many whole repeats as that power-of-two canvas holds anyway (and one
    # pixel of it spare past the picture): the client repeats the middle and the
    # edges at the middle's size, and where the filtering reads across a repeat
    # (a faint line, if it does) that is then as seldom as the canvas allows
    mid_w = rep_w * max(1, (size[0] - 1 - 2 * corner) // rep_w)
    mid_h = rep_h * max(1, (size[1] - 1 - 2 * corner) // rep_h)
    grid = (2 * corner + mid_w, 2 * corner + mid_h)
    return {
        "prefix": prefix, "pieces": p, "side": side, "density": density, "corner": corner,
        "mid": (mid_w, mid_h), "grid": grid, "size": size,
    }


def compose(info, look):
    """The picture of one family in one look, on its power-of-two canvas."""
    c = info["corner"]
    mw, mh = info["mid"]
    gw, gh = info["grid"]
    W, H = info["size"]
    cut = {part: crop(look, info["pieces"][part]) for part in PARTS}
    out = np.zeros((H, W, 4), np.uint8)
    out[0:c, 0:c] = cut["tl"]
    out[0:c, c + mw:gw] = cut["tr"]
    out[c + mh:gh, 0:c] = cut["bl"]
    out[c + mh:gh, c + mw:gw] = cut["br"]
    # each edge repeated from the start of its band, as Kit:Retile lays it
    for e, rows in (("t", slice(0, c)), ("b", slice(c + mh, gh))):
        tile = cut[e]
        for x in range(0, mw, tile.shape[1]):
            out[rows, c + x:c + x + tile.shape[1]] = tile
    for e, cols in (("l", slice(0, c)), ("r", slice(c + mw, gw))):
        tile = cut[e]
        for y in range(0, mh, tile.shape[0]):
            out[c + y:c + y + tile.shape[0], cols] = tile
    # Past the picture's bottom and right, what the edge pieces' own files hold
    # past theirs: their outermost row / column again (the corner files hold
    # nothing there). Never drawn; the client's filtering reads it along the
    # bottom and right rails' outer lines, as it reads the pieces' (their dark
    # edge lines keep their weight; kit-art-edge-shadows).
    if gh < H:
        out[gh, c:c + mw] = out[gh - 1, c:c + mw]
    if gw < W:
        out[c:c + mh, gw] = out[c:c + mh, gw - 1]
    return out


def slice_name(prefix):
    group, base = prefix.split("/")
    return "slices/" + group + "_" + base


def lua_text(plans):
    lines = [
        "-- Generated by Tools/build_nineslice.py from Media/KitLayout.lua and the rail pieces. Do not edit by hand.",
        "--",
        "-- One picture per rail family for the one-texture nine-slices (Kit:NineSlice while",
        "-- /mellokit slices is on): the four corners at the corners, whole repeats of each edge",
        "-- between them, an empty middle. The same files in every look (Media\\Kit,",
        "-- Media\\KitWarm, Media\\KitBronze), each made from that look's own pieces.",
        "--   texel   painted piece px per file texel (the pieces' 1 / density)",
        "--   corner  a corner's side in texels: all four margins",
        "--   grid    the picture's size in texels, at the top-left of its file",
        "--   size    the file's power-of-two size",
        "--   full    the file (under the look's folder, no extension)",
        "--   pieces  the geometry each picture was built from: a piece tuned or rebuilt",
        "--           since then puts that family back into pieces until this is run again",
        "",
        "-- luacheck: globals MelloUI_KitSlices",
        "MelloUI_KitSlices = {",
    ]
    for info in plans:
        prefix = info["prefix"]
        lines.append("\t[\"%s\"] = {" % prefix)
        lines.append("\t\ttexel = %s, corner = %d, grid = { %d, %d }, size = { %d, %d }," % (
            num(1 / info["density"]), info["corner"], info["grid"][0], info["grid"][1], info["size"][0], info["size"][1]))
        lines.append("\t\tfull = \"%s\"," % slice_name(prefix).replace("/", "\\\\"))
        lines.append("\t\tpieces = {")
        for part in PARTS:
            p = info["pieces"][part]
            lines.append("\t\t\t%s = { file = \"%s\", w = %d, h = %d, uv = { %s } }," % (
                part, p["file"].replace("\\", "\\\\"), p["w"], p["h"], ", ".join(num(v) for v in p["uv"])))
        lines.append("\t\t},")
        lines.append("\t},")
    lines += ["}", ""]
    return "\n".join(lines)


def main():
    check = "--check" in sys.argv
    pieces = read_layout()
    plans, stale, written = [], [], 0
    for prefix in families(pieces):
        try:
            info = plan(prefix, pieces)
        except Refused as why:
            print(f"  {prefix}: left in pieces ({why})")
            continue
        for look in LOOKS:
            # the same geometry in every look (the looks are recoloured copies)
            if plan(prefix, pieces, look)["grid"] != info["grid"]:
                raise SystemExit(f"{prefix}: {look} differs from Media/Kit in size; rebuild the looks")
            img = compose(info, look)
            path = os.path.join(MEDIA, look, slice_name(prefix).replace("/", os.sep) + ".tga")
            if check:
                ok = os.path.exists(path) and np.array_equal(np.array(Image.open(path).convert("RGBA")), img)
                if not ok:
                    stale.append(os.path.relpath(path, MEDIA))
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                Image.fromarray(img).save(path)
                written += 1
        plans.append(info)
        print(f"  {prefix}: corner {info['corner']} texels (density {num(info['density'])}), edges repeat "
              f"{info['mid'][0]} x {info['mid'][1]}, picture {info['grid'][0]}x{info['grid'][1]} in "
              f"{info['size'][0]}x{info['size'][1]}")
    text = lua_text(plans)
    if check:
        if not os.path.exists(LUA) or open(LUA, encoding="utf-8").read() != text:
            stale.append(os.path.relpath(LUA, MEDIA))
        if stale:
            print("stale (run Tools/build_nineslice.py):\n  " + "\n  ".join(stale))
            sys.exit(1)
        print("the slices match the pieces")
        return
    with open(LUA, "w", newline="\n", encoding="utf-8") as f:
        f.write(text)
    print(f"{written} pictures -> masters Media/<look>/slices, Media/KitSlices.lua  [{MEDIA}]")
    print("next: python Tools/texture_pack.py ship (the addon's Media)")


if __name__ == "__main__":
    main()
