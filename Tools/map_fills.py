"""MelloUI Map's gap fills (the user, 2026-10-21: "extend the zones to the coast, chatgpt for the inland ones"): the
pictures the user had ChatGPT paint into Tools/map_gaps.py's sheets, made into the map's fills.
For each painting (MelloUI-BuildData/output/map_gaps/painted/gap_NN_painted.png):
  * its gap found again: the one of the land no zone covers now (Tools/map_gaps.py, the stretched coasts of
    Tools/build_map_data.py) that the sheet was made for -- its frozen box (painted/manifest.json, written from
    gaps.json the first time a painting is baked) laid over today's gaps;
  * the painting on its sheet's canvas (ChatGPT's answers come back at other sizes: resized, the framing kept),
    its colours matched to the zones' own art round the hole (ChatGPT's palette drifts);
  * only the hole kept, a margin past it fading out under the zones' soft outlines (the map lays the fills over
    the gap ground, under every zone): the painting's own pixels only, never the sheet's, which are the game's;
  * cut into 256 px tiles (32-bit TGA, the empty ones dropped): MelloUI_Map/Media/Fills/<name>.tga, and their
    place on the continent's painting (0..1): MelloUI_Map/MapFills.lua.
    python Tools/map_fills.py            bake every painting
    python Tools/map_fills.py --check    exit 1 unless the baked files are up to date
"""
import argparse
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_map_data as B  # noqa: E402
import map_gaps as G  # noqa: E402

ROOT = os.path.dirname(HERE)
GAPS = G.OUT
PAINTED = os.path.join(GAPS, "painted")
MANIFEST = os.path.join(PAINTED, "manifest.json")
MAP = os.path.join(ROOT, "MelloUI_Map")
DATA = os.path.join(MAP, "MapFills.lua")
FILLS = os.path.join(MAP, "Media", "Fills")
TILE = 256                      # a fill's tile (px of the sheet's canvas)
MARGIN = 0.022                  # the fill reaches this share of the sheet's width past its hole ...
FEATHER = 0.012                 # ... fading out over this share (under the zones' soft outlines)
RING = 0.03                     # the colours matched on a ring this wide round the hole (the zones' art there)
SPREAD = (0.75, 1.33)           # how far a colour's spread may be stretched to match


def tga(img):
    """32-bit uncompressed TGA, top-left origin (BGRA)"""
    w, h = img.size
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    a = np.asarray(img.convert("RGBA"))
    return head + a[..., [2, 1, 0, 3]].tobytes()


def manifest():
    """each painting's sheet as it was made (frozen: a later run of map_gaps.py renumbers or moves its gaps)"""
    got = json.load(open(MANIFEST)) if os.path.isfile(MANIFEST) else {}
    index = {g["n"]: g for g in json.load(open(os.path.join(GAPS, "gaps.json")))}
    changed = False
    for f in sorted(os.listdir(PAINTED)):
        if f.endswith("_painted.png") and f not in got:
            n = int(f.split("_")[1])
            g = index[n]
            got[f] = {k: g[k] for k in ("n", "continent", "name", "near", "box", "crop", "size")}
            changed = True
    if changed:
        json.dump(got, open(MANIFEST, "w"), indent=1, sort_keys=True)
    return got


def match(paint, sheet, ring):
    """the painting's colours moved to the sheet's on the ring, in Lab (OpenCV's: a true conversion): its lightness's
    mean and spread (within SPREAD), its two colour axes' means only -- stretching their spread made colours loud"""
    import cv2
    p = cv2.cvtColor(paint.astype(np.float32) / 255, cv2.COLOR_RGB2LAB)
    s = cv2.cvtColor(sheet.astype(np.float32) / 255, cv2.COLOR_RGB2LAB)
    if int(ring.sum()) < 50:
        return paint
    out = p.copy()
    for c in range(3):
        pv, sv = p[..., c][ring], s[..., c][ring]
        k = float(np.clip(sv.std() / max(pv.std(), 1e-3), *SPREAD)) if c == 0 else 1.0
        out[..., c] = (p[..., c] - pv.mean()) * k + sv.mean()
    rgb = cv2.cvtColor(out, cv2.COLOR_LAB2RGB)
    return (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)


def bake():
    import cv2
    T = G.Tables()
    entries = manifest()
    today = {}
    fills, files = {}, {}
    for f in sorted(entries):
        e = entries[f]
        cont = e["continent"]
        if cont not in today:
            zones = T.zones(cont)
            today[cont] = G.gaps_of(B.terrain_land(T.assign, cont), G.cover_mask(zones))
        # (the gap of today the sheet was made for: the most of its frozen box)
        x0, y0, x1, y1 = e["box"]
        best, gap = 0, None
        for g in today[cont]:
            n = int(g["mask"][y0:y1, x0:x1].sum())
            if n > best:
                best, gap = n, g
        if gap is None:
            print("%s: its gap is gone (covered by the zones now): skipped" % f)
            continue
        W, H = e["size"]
        cx0, cy0, cx1, cy1 = e["crop"]
        sheet = np.asarray(Image.open(os.path.join(GAPS, "gap_%02d.png" % e["n"])).convert("RGBA").resize((W, H)))
        paint = np.asarray(Image.open(os.path.join(PAINTED, f)).convert("RGB").resize((W, H), Image.LANCZOS))
        hole = Image.fromarray((gap["mask"] * 255).astype(np.uint8)).transform(
            (W, H), Image.EXTENT, (cx0, cy0, cx1, cy1), Image.BILINEAR)
        hole = np.asarray(hole) > 100
        grow = max(3, int(MARGIN * W)) | 1
        reach = cv2.dilate(hole.astype(np.uint8), np.ones((grow, grow), np.uint8)) > 0
        rw = max(3, int(RING * W)) | 1
        ring = (cv2.dilate(hole.astype(np.uint8), np.ones((rw, rw), np.uint8)) > 0) & ~hole & (sheet[..., 3] > 250)
        rgb = match(paint, sheet[..., :3], ring)
        alpha = Image.fromarray((reach * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(max(1.0, FEATHER * W)))
        alpha = np.maximum(np.asarray(alpha), (hole * 255).astype(np.uint8))
        ys, xs = np.nonzero(alpha > 2)
        if not len(xs):
            continue
        bx0, by0 = (xs.min() // TILE) * TILE, (ys.min() // TILE) * TILE
        bx1, by1 = xs.max() + 1, ys.max() + 1
        cols, rows = (bx1 - bx0 + TILE - 1) // TILE, (by1 - by0 + TILE - 1) // TILE
        full = np.zeros((rows * TILE, cols * TILE, 4), np.uint8)
        part = np.dstack([rgb, alpha])[by0:by0 + rows * TILE, bx0:bx0 + cols * TILE]
        full[:part.shape[0], :part.shape[1]] = part
        name = "f%d_%02d" % (cont, e["n"])
        tiles = []
        for r in range(rows):
            for c in range(cols):
                t = full[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE]
                if t[..., 3].max() > 2:
                    tn = "%s_%d_%d" % (name, r, c)
                    files[tn + ".tga"] = tga(Image.fromarray(t, "RGBA"))
                    tiles.append((c, r, tn))
        # (its place on the continent's painting, 0..1: the sheet's crop is in its art px)
        sx, sy = (cx1 - cx0) / W, (cy1 - cy0) / H
        fills.setdefault(cont, []).append({
            "n": e["n"], "name": e["name"], "near": e["near"],
            "x": (cx0 + bx0 * sx) / B.ART_W, "y": (cy0 + by0 * sy) / B.ART_H,
            "w": cols * TILE * sx / B.ART_W, "h": rows * TILE * sy / B.ART_H, "cols": cols, "rows": rows,
            "tiles": tiles})
        print("%s: gap %d (%s), %d x %d tiles, %d kept" % (f, e["n"], ", ".join(e["near"]), cols, rows, len(tiles)))
    out = ["-- MelloUI Map's gap fills, made by Tools/map_fills.py from the paintings of the gaps between zones (painted",
           "-- for MelloUI, Tools/map_gaps.py's sheets): never edit by hand (run the tool). docs/plans/seamless-map.md.",
           "local _, ns = ...",
           "-- [continent uiMapID] = { { x, y, w, h: its place on the continent's painting (0..1), cols, rows: its grid of",
           "-- tiles, tiles = { column, row, file (Media\\\\Fills), ... } } }: under the continent's zones, over the ground",
           "ns.MapFills = {"]
    for cont in sorted(fills):
        out.append("\t[%d] = {" % cont)
        for fl in fills[cont]:
            out.append("\t\t{ x = %.6f, y = %.6f, w = %.6f, h = %.6f, cols = %d, rows = %d, tiles = {   -- gap %d: %s" % (
                fl["x"], fl["y"], fl["w"], fl["h"], fl["cols"], fl["rows"], fl["n"], ", ".join(fl["near"])))
            for i in range(0, len(fl["tiles"]), 4):
                out.append("\t\t\t" + " ".join('%d, %d, "%s",' % t for t in fl["tiles"][i:i + 4]))
            out.append("\t\t} },")
        out.append("\t},")
    out += ["}", ""]
    return "\n".join(out), files


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    lua, files = bake()
    want = [(DATA, lua.encode("utf-8"))] + [(os.path.join(FILLS, n), b) for n, b in sorted(files.items())]
    stale = [p for p, b in want if not os.path.isfile(p) or open(p, "rb").read() != b]
    extra = [os.path.join(FILLS, n) for n in (os.listdir(FILLS) if os.path.isdir(FILLS) else []) if n not in files]
    if a.check:
        print("map fills: %s" % ("up to date" if not stale and not extra else "%d stale, %d extra" % (len(stale), len(extra))))
        sys.exit(1 if stale or extra else 0)
    os.makedirs(FILLS, exist_ok=True)
    for p, b in want:
        if p in stale:
            io.open(p, "wb").write(b)
    for p in extra:
        os.remove(p)
    print("map fills: %d tiles, %d files written, %d removed" % (len(files), len(stale), len(extra)))


if __name__ == "__main__":
    main()
