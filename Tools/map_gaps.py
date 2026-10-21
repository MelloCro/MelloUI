"""MelloUI Map's gaps (the user, 2026-10-21: "can we generate that ... with ChatGPT, that he generates me the missing
artwork to fill the gaps on the map?"): land a continent's painting shows that no zone's map covers, as MelloUI's map
draws them (Tools/build_map_data.py's soft outlines, where the client places each zone). For each gap a reference
sheet for ChatGPT's image editing: the neighbouring zones' own art around it at their own scale, fully explored, the
gap cut out transparent, in one of the sizes ChatGPT paints (1536 x 1024, 1024 x 1536, 1024 x 1024) so the painting
comes back on the same canvas; a contact sheet of them all; prompts.md, a prompt per gap.

Local only: the sheets hold the game's art (wow.export's files in F:/Download-Backup/WoWExport), so they go to
MelloUI-BuildData/output/map_gaps, never into the repository or a release.
    python Tools/map_gaps.py                every gap of Kalimdor and the Eastern Kingdoms
    python Tools/map_gaps.py --debug        also each continent's land, cover and gap masks
"""
import argparse
import csv
import json
import os
import sys
from collections import defaultdict

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_map_data as B  # noqa: E402  (the tables, the zones' places and their soft outlines)

EXPORT = "F:/Download-Backup/WoWExport/"
ART_DIRS = (("map_m2_png", ".png"), ("map_m3_png", ".png"), ("map_zoom_png", ".png"), ("map_gap_raw", ".blp"))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "MelloUI-BuildData", "output", "map_gaps")
CONTINENTS = {1414: "Kalimdor", 1415: "Eastern Kingdoms"}
AW, AH = B.ART_W, B.ART_H       # a map's art (1002 x 668): the continents' masks are worked out at this size
COVER = 0.5                     # a zone's outline covers its land from this alpha
MIN_AREA = 160                  # a gap smaller (art px, after the opening) is a seam, not land to paint
OPEN = 5                        # thin slivers along the zones' edges are opened away (art px)
THICK = 8                       # a gap at least this thick somewhere (art px): not a rim along a coast
ENCLOSED = 0.35                 # ... and at least this share of its edge on the zones' art, not the sea
SIZES = ((1536, 1024), (1024, 1024), (1024, 1536))   # ChatGPT's canvases
MARGIN = 0.45                   # the context round a gap, a share of its larger side each way
HOLE_GROW = 0.006               # the hole a little wider than the gap (a share of the sheet's width): blends in
SEAM = 600                      # a gap smaller (art px) is a seam the map's own blend closes: no painting


def art_file(fid):
    for d, ext in ART_DIRS:
        p = EXPORT + d + "/" + str(fid) + ext
        if os.path.exists(p):
            return p
    return None


class Tables:
    def __init__(self):
        self.maps = {int(r["ID"]): r for r in B.rows("UiMap")}
        self.art_of = {}
        for r in B.rows("UiMapXMapArt"):
            self.art_of.setdefault(int(r["UiMapID"]), int(r["UiMapArtID"]))
        self.tiles = defaultdict(list)
        for r in B.rows("UiMapArtTile"):
            if r["LayerIndex"] == "0":
                self.tiles[int(r["UiMapArtID"])].append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
        self.overlays = defaultdict(list)
        for r in B.rows("WorldMapOverlay"):
            self.overlays[int(r["UiMapArtID"])].append(r)
        self.otiles = defaultdict(list)
        for r in B.rows("WorldMapOverlayTile"):
            if r["LayerIndex"] == "0":
                self.otiles[int(r["WorldMapOverlayID"])].append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
        self.assign = defaultdict(list)
        for r in B.rows("UiMapAssignment"):
            self.assign[int(r["UiMapID"])].append(r)
        self._art = {}

    def name(self, mid):
        return self.maps[mid]["Name_lang"]

    def zones(self, cont):
        """the zones of a continent with their place on it (x0, x1, y0, y1: 0..1) and their soft outline, as the map
        has them (Tools/build_map_data.py: the hit rectangles' outline, stretched to the coast)"""
        masks = {}
        for mid, r in sorted(self.maps.items()):
            if r["Type"] != str(B.ZONE) or int(r["ParentUiMapID"] or 0) != cont or mid not in self.art_of:
                continue
            mask = B.zone_mask(sorted(self.overlays.get(self.art_of[mid], []), key=lambda o: int(o["ID"])))
            if mask is not None and self.otiles_of(mid):
                masks[mid] = mask
        masks = B.coast_extend(self.assign, cont, masks)
        out = []
        for mid in sorted(masks):
            rect = B.rect_on(self.assign, mid, cont)
            if rect:
                out.append((mid, rect, masks[mid].resize((AW, AH), Image.BILINEAR)))
        return out

    def otiles_of(self, mid):
        """the zone's pieces have pictures (the map draws only such zones' outlines)"""
        return any(self.otiles[int(o["ID"])] for o in self.overlays.get(self.art_of[mid], []))

    def art(self, mid, explored=True):
        """a map's picture (1002 x 668 RGBA): its base tiles, every explored piece over them"""
        key = (mid, explored)
        if key in self._art:
            return self._art[key]
        im = Image.new("RGBA", (1024, 768), (0, 0, 0, 0))
        for row, col, fid in self.tiles[self.art_of[mid]]:
            p = art_file(fid)
            if p:
                im.paste(Image.open(p).convert("RGBA"), (col * 256, row * 256))
        if explored:
            for o in sorted(self.overlays.get(self.art_of[mid], []), key=lambda o: int(o["ID"])):
                w, h = int(o["TextureWidth"]), int(o["TextureHeight"])
                piece = Image.new("RGBA", (((w + 255) // 256) * 256, ((h + 255) // 256) * 256), (0, 0, 0, 0))
                for row, col, fid in self.otiles[int(o["ID"])]:
                    p = art_file(fid)
                    if p:
                        piece.paste(Image.open(p).convert("RGBA"), (col * 256, row * 256))
                im.alpha_composite(piece.crop((0, 0, w, h)), (int(o["OffsetX"]), int(o["OffsetY"])))
        im = im.crop((0, 0, AW, AH))
        self._art[key] = im
        return im


def cover_mask(zones):
    """the zones' outlines where the client places them on the continent: 0..1"""
    cover = np.zeros((AH, AW), np.float32)
    for _, (x0, x1, y0, y1), mask in zones:
        w, h = int(round((x1 - x0) * AW)), int(round((y1 - y0) * AH))
        if w < 2 or h < 2:
            continue
        m = np.asarray(mask.resize((w, h), Image.BILINEAR)).astype(np.float32) / 255
        X, Y = int(round(x0 * AW)), int(round(y0 * AH))
        xa, ya, xb, yb = max(X, 0), max(Y, 0), min(X + w, AW), min(Y + h, AH)
        if xb > xa and yb > ya:
            cover[ya:yb, xa:xb] = np.maximum(cover[ya:yb, xa:xb], m[ya - Y:yb - Y, xa - X:xb - X])
    return cover


def gaps_of(land, cover):
    """the land no zone covers: each piece big and thick enough, and mostly between zones (a coast's rim, where the
    painting's land reaches past a zone's soft outline, and the torn frame are not gaps)"""
    import cv2
    gap = land & (cover < COVER)
    g = Image.fromarray((gap * 255).astype(np.uint8))
    g = g.filter(ImageFilter.MinFilter(OPEN)).filter(ImageFilter.MaxFilter(OPEN))
    a = np.asarray(g) > 127
    n, lab, stats, cent = cv2.connectedComponentsWithStats(a.astype(np.uint8), 8)
    covered = cover >= COVER
    out = []
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] < MIN_AREA:
            continue
        m = lab == i
        thick = float(cv2.distanceTransform(m.astype(np.uint8), cv2.DIST_L2, 5).max()) * 2
        ring = (cv2.dilate(m.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0) & ~m
        enclosed = float((ring & covered).sum()) / max(1, int(ring.sum()))
        if thick < THICK or enclosed < ENCLOSED:
            continue
        x, y, w, h = stats[i, :4]
        out.append({"mask": m, "box": (int(x), int(y), int(x + w), int(y + h)), "area": int(stats[i, cv2.CC_STAT_AREA]),
                    "centre": (float(cent[i][0]), float(cent[i][1])), "thick": round(thick, 1),
                    "enclosed": round(enclosed, 2)})
    out.sort(key=lambda g: (round(g["centre"][1] / 40), g["centre"][0]))
    return out


def neighbours(gap, zones, T):
    """the zones whose outline is near the gap, nearest first by shared edge"""
    import cv2
    ring = cv2.dilate(gap["mask"].astype(np.uint8), np.ones((21, 21), np.uint8)) > 0
    found = []
    for mid, (x0, x1, y0, y1), mask in zones:
        w, h = int(round((x1 - x0) * AW)), int(round((y1 - y0) * AH))
        if w < 2 or h < 2:
            continue
        m = np.zeros((AH, AW), bool)
        sm = np.asarray(mask.resize((w, h), Image.BILINEAR)) > 128
        X, Y = int(round(x0 * AW)), int(round(y0 * AH))
        xa, ya, xb, yb = max(X, 0), max(Y, 0), min(X + w, AW), min(Y + h, AH)
        if xb <= xa or yb <= ya:
            continue
        m[ya:yb, xa:xb] = sm[ya - Y:yb - Y, xa - X:xb - X]
        touch = int((m & ring).sum())
        if touch:
            found.append((touch, mid))
    found.sort(reverse=True)
    return [T.name(mid) for _, mid in found[:4]]


def sheet_box(box):
    """the crop round a gap (art px of the continent) in the aspect of the closest ChatGPT canvas, and that canvas"""
    x0, y0, x1, y1 = box
    side = max(x1 - x0, y1 - y0)
    m = side * MARGIN + 12
    x0, y0, x1, y1 = x0 - m, y0 - m, x1 + m, y1 + m
    w, h = x1 - x0, y1 - y0
    size = min(SIZES, key=lambda s: abs(np.log((s[0] / s[1]) / (w / h))))
    aspect = size[0] / size[1]
    if w / h < aspect:
        grow = h * aspect - w
        x0, x1 = x0 - grow / 2, x1 + grow / 2
    else:
        grow = w / aspect - h
        y0, y1 = y0 - grow / 2, y1 + grow / 2
    # (kept on the painting: past its edge there is nothing, which would read as more hole)
    if x1 - x0 > AW or y1 - y0 > AH:
        k = min(AW / (x1 - x0), AH / (y1 - y0))
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        x0, x1, y0, y1 = cx - (cx - x0) * k, cx + (x1 - cx) * k, cy - (cy - y0) * k, cy + (y1 - cy) * k
    dx = -x0 if x0 < 0 else (AW - x1 if x1 > AW else 0)
    dy = -y0 if y0 < 0 else (AH - y1 if y1 > AH else 0)
    return (x0 + dx, y0 + dy, x1 + dx, y1 + dy), size


def render(T, cont, zones, painting, crop, size, hole=None, under=None):
    """the crop (continent art px) at `size`: the continent's painting (or `under`, a picture of the crop at that size:
    Tools/map_fills.py's preview, the fills laid on it) under the zones' art, each inside its soft outline (biggest
    first, as the map lays them); `hole` (a bool mask of the continent) cut out transparent"""
    x0, y0, x1, y1 = crop
    W, H = size
    sx, sy = W / (x1 - x0), H / (y1 - y0)
    base = under if under is not None else painting.convert("RGBA").transform((W, H), Image.EXTENT, (x0, y0, x1, y1), Image.BICUBIC)
    out = base.copy()
    for mid, (zx0, zx1, zy0, zy1), mask in sorted(zones, key=lambda z: -(z[1][1] - z[1][0]) * (z[1][3] - z[1][2])):
        px0, px1, py0, py1 = zx0 * AW, zx1 * AW, zy0 * AH, zy1 * AH
        if px1 < x0 or px0 > x1 or py1 < y0 or py0 > y1:
            continue
        w, h = int(round((px1 - px0) * sx)), int(round((py1 - py0) * sy))
        if w < 2 or h < 2:
            continue
        art = T.art(mid).resize((w, h), Image.LANCZOS)
        a = mask.resize((w, h), Image.BILINEAR)
        art.putalpha(Image.fromarray(np.minimum(np.asarray(art.getchannel("A")), np.asarray(a))))
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        layer.paste(art, (int(round((px0 - x0) * sx)), int(round((py0 - y0) * sy))), art)
        out = Image.alpha_composite(out, layer)
    if hole is not None:
        hm = Image.fromarray((hole * 255).astype(np.uint8)).transform((W, H), Image.EXTENT, (x0, y0, x1, y1), Image.BILINEAR)
        grow = max(3, int(HOLE_GROW * W)) | 1
        hm = hm.point(lambda v: 255 if v > 100 else 0).filter(ImageFilter.MaxFilter(grow))
        alpha = np.asarray(out.getchannel("A")).astype(np.int32)
        out.putalpha(Image.fromarray(np.where(np.asarray(hm) > 127, 0, alpha).astype(np.uint8)))
    return out


PROMPT = ("Edit this image: paint ONLY the transparent (empty) area and leave every other pixel exactly as it is. It "
          "is a piece of a hand-painted World of Warcraft (classic) world map{near}. The transparent area is wild, "
          "unmapped land: fill it with natural terrain only, continuing the mountains, hills, cliffs, forests, "
          "grassland, desert or snow that touch its edges, in the same painterly parchment style, brush texture, "
          "colours and lighting as the map around it; {what}. STRICTLY NO roads, paths, trails, tracks, bridges, "
          "buildings, towns, camps, ruins, walls or any other man-made marks (the player must not expect a road there); "
          "no new rivers or lakes unless one clearly flows in from the edge; no text, labels, borders, grid, icons or "
          "characters. Keep the same size ({w} x {h}) and framing, and return a PNG.")
# (the user, 2026-10-21: "chatgpt keeps drawing roads, that will confuse people and they will expect roads in those
# parts": the first prompt asked it to "carry on the ... roads"; this one forbids them)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--debug", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    T = Tables()
    index, prompts, n = [], ["# MelloUI map gaps: prompts for ChatGPT", "",
                             "Each sheet `gap_NN.png` has the gap cut out transparent. Upload it to ChatGPT's image "
                             "editing with its prompt; save the answer as `gap_NN_painted.png` in `painted/` (the same "
                             "size). `gap_NN_view.png` shows the gap in magenta for you.", ""], 0
    overview = {}
    for cont, cname in CONTINENTS.items():
        painting = T.art(cont, explored=False).convert("RGB")
        zones = T.zones(cont)
        land = B.terrain_land(T.assign, cont)
        cover = cover_mask(zones)
        gaps = gaps_of(land, cover)
        if a.debug:
            Image.fromarray((land * 255).astype(np.uint8)).save(os.path.join(OUT, "debug_%d_land.png" % cont))
            Image.fromarray((cover * 255).astype(np.uint8)).save(os.path.join(OUT, "debug_%d_cover.png" % cont))
        full = render(T, cont, zones, painting, (0, 0, AW, AH), (AW * 2, AH * 2))
        ov = full.convert("RGB")
        d = ImageDraw.Draw(ov)
        try:
            font = ImageFont.truetype("arialbd.ttf", 26)
        except OSError:
            font = ImageFont.load_default()
        for g in gaps:
            n += 1
            g["n"] = n
            crop, size = sheet_box(g["box"])
            near = neighbours(g, zones, T)
            sheet = render(T, cont, zones, painting, crop, size, hole=g["mask"])
            sheet.save(os.path.join(OUT, "gap_%02d.png" % n))
            view = Image.new("RGBA", sheet.size, (255, 0, 255, 255))
            view.alpha_composite(sheet)
            view.convert("RGB").save(os.path.join(OUT, "gap_%02d_view.png" % n), quality=90)
            # (on the overview: the gap in magenta, its number)
            edge = Image.fromarray((g["mask"] * 255).astype(np.uint8)).resize((AW * 2, AH * 2), Image.NEAREST)
            tint = Image.new("RGB", ov.size, (255, 0, 255))
            ov.paste(Image.blend(ov, tint, 0.55), (0, 0), edge)
            cx, cy = g["centre"]
            d.text((cx * 2 - 10, cy * 2 - 14), str(n), fill=(255, 255, 255), font=font, stroke_width=3, stroke_fill=(0, 0, 0))
            between = (" between " + ", ".join(near[:-1]) + " and " + near[-1]) if len(near) > 1 else (" beside " + near[0] if near else "")
            if g["enclosed"] >= B.HOLE_RINGED:
                what = "it lies inland between " + (", ".join(near) if near else cname)
            else:
                what = ("it lies beside " + (", ".join(near) if near else cname) + " and runs out to the sea: carry "
                        "the coastline on along the sea's edge, with the same coastal outline and hatched sea")
            prompt = PROMPT.format(near=" (" + cname + between + ")", what=what, w=size[0], h=size[1])
            seam = g["area"] < SEAM
            prompts += ["## %s %d: %s%s" % ("Seam" if seam else "Gap", n, cname, between), "",
                        "Sheet: `gap_%02d.png` (%d x %d). Area: %d px of the continent's 1002 x 668 painting." % (n, size[0], size[1], g["area"]), ""]
            if seam:
                prompts += ["A thin seam between zones: closed by the map's own blend, nothing to paint.", ""]
            else:
                prompts += ["```", prompt, "```", ""]
            index.append({"n": n, "continent": cont, "name": cname, "near": near, "box": g["box"], "area": g["area"],
                          "thick": g["thick"], "enclosed": g["enclosed"], "seam": g["area"] < SEAM,
                          "crop": [round(v, 2) for v in crop],
                          "size": list(size)})
        ov.save(os.path.join(OUT, "overview_%d.jpg" % cont), quality=88)
        overview[cont] = len(gaps)
        print("%s: %d gaps" % (cname, len(gaps)))
    open(os.path.join(OUT, "prompts.md"), "w", encoding="utf-8").write("\n".join(prompts))
    json.dump(index, open(os.path.join(OUT, "gaps.json"), "w"), indent=1)
    # the contact sheet: each gap's view, numbered, with its neighbours
    thumbs = []
    for g in index:
        im = Image.open(os.path.join(OUT, "gap_%02d_view.png" % g["n"])).convert("RGB")
        im.thumbnail((480, 480))
        cell = Image.new("RGB", (500, 540), (24, 22, 20))
        cell.paste(im, ((500 - im.width) // 2, 10))
        dd = ImageDraw.Draw(cell)
        try:
            f2 = ImageFont.truetype("arial.ttf", 18)
        except OSError:
            f2 = ImageFont.load_default()
        dd.text((10, 500), "%d %s  %s: %s" % (g["n"], "(seam)" if g["seam"] else "", g["name"], ", ".join(g["near"])[:46]),
                fill=(150, 145, 135) if g["seam"] else (235, 225, 200), font=f2)
        thumbs.append(cell)
    cols = 4
    for k in range(0, len(thumbs), cols * 3):
        page = thumbs[k:k + cols * 3]
        rows_ = (len(page) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 500, rows_ * 540), (24, 22, 20))
        for i, c in enumerate(page):
            sheet.paste(c, ((i % cols) * 500, (i // cols) * 540))
        sheet.save(os.path.join(OUT, "contact_%02d.jpg" % (k // (cols * 3) + 1)), quality=88)
    print("%d gaps -> %s" % (len(index), OUT))


if __name__ == "__main__":
    main()
