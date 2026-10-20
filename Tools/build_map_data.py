"""MelloUI Map's data (docs/plans/seamless-map.md, stage M2; the user's picks 2026-10-20: C soft outlines, F slate
ground with our names, H places not explored yet dimmed), made from the client's own tables as wow.export wrote them
(F:/Download-Backup/WoWExport/db2): numbers only, never a picture of the game's.

  MelloUI_Map/MapData.lua
      outline[uiMapID] = { x, y }        where a zone's name goes (0..1 of its art): the middle of its outline
      pieces[uiMapArtID] = { { w, h, x, y, fileID ... }, ... }
                                         every piece of a zone's map (WorldMapOverlay + its tiles), the explored and
                                         the not explored alike: the map draws the ones the client calls explored
                                         full and the rest faint
  MelloUI_Map/Media/Outlines/<uiMapID>.tga
                                         a zone's soft outline, a mask over its art: the union of its pieces' hit
                                         rectangles (WorldMapOverlay.HitRect*, in the art's own pixels), widened and
                                         blurred -- our geometry from the table's numbers, 128 x 128 for the art's
                                         1002 x 668
  MelloUI_Map/Media/Outlines/city.tga    a soft-edged rectangle (a city's art, which has no pieces)
  MelloUI_Map/Media/Grain.tga            the land field's grain: our own noise, palette-tinted in the game

Masks as MelloUI's others: 32-bit TGA, top-left origin, white with the same alpha (colour and alpha both say it).
Deterministic: the same tables give the same bytes.

    python Tools/build_map_data.py            write them
    python Tools/build_map_data.py --check    exit 1 unless every file is up to date
"""
import csv
import io
import os
import random
import struct
import sys
from collections import defaultdict

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB2 = r"F:/Download-Backup/WoWExport/db2/"
MAP = os.path.join(ROOT, "MelloUI_Map")
DATA = os.path.join(MAP, "MapData.lua")
OUTLINES = os.path.join(MAP, "Media", "Outlines")
GRAIN = os.path.join(MAP, "Media", "Grain.tga")

ART_W, ART_H = 1002, 668        # a zone map's art layer
Q = 4                           # the outlines drawn at a quarter of it (the masks are 128 px: the same shapes, faster)
QW, QH = (ART_W + Q - 1) // Q, (ART_H + Q - 1) // Q
SIZE = 128                      # a mask's side
GROW, BLUR = 30, 24             # the outline: the hit rectangles widened, then softened (art px; the sketch's pick)
EDGE = 40                       # ... and faded out before the art's own edge (art px): a zone's land that reaches the
                                # border of its picture would end there in a hard line (the neighbour's picture covers it)
CITY_EDGE = 12                  # the city mask's soft edge (mask px)
ZONE = 3                        # UIMapType.Zone


def rows(name):
    return list(csv.DictReader(open(DB2 + name + ".csv", encoding="utf-8")))


def tga(img):
    """32-bit uncompressed TGA, top-left origin: white, the image's L as the alpha"""
    w, h = img.size
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    body = bytearray()
    px = img.load()
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            body += bytes((v, v, v, v))
    return head + bytes(body)


def grain():
    rnd = random.Random(1602)
    img = Image.new("L", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = 236 + rnd.randrange(20)
    w, h = img.size
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    body = bytearray()
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            body += bytes((v, v, v, 255))
    return head + bytes(body)


_fade = []


def edge_fade():
    """1 inside, falling to 0 over EDGE px toward the art's four edges (our geometry)"""
    if not _fade:
        e = EDGE / Q
        m = Image.new("L", (QW, QH), 0)
        ImageDraw.Draw(m).rectangle((e, e, QW - 1 - e, QH - 1 - e), fill=255)
        _fade.append(m.filter(ImageFilter.GaussianBlur(e / 2)))
    return _fade[0]


def city_mask():
    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).rectangle((CITY_EDGE, CITY_EDGE, SIZE - 1 - CITY_EDGE, SIZE - 1 - CITY_EDGE), fill=255)
    return m.filter(ImageFilter.GaussianBlur(CITY_EDGE / 2))


def build():
    maps = {int(r["ID"]): r for r in rows("UiMap")}
    art_of = {}
    for r in rows("UiMapXMapArt"):
        art_of.setdefault(int(r["UiMapID"]), int(r["UiMapArtID"]))
    overlays = defaultdict(list)
    for r in rows("WorldMapOverlay"):
        overlays[int(r["UiMapArtID"])].append(r)
    otiles = defaultdict(list)
    for r in rows("WorldMapOverlayTile"):
        if r["LayerIndex"] == "0":
            otiles[int(r["WorldMapOverlayID"])].append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
    files, outline, pieces = {}, {}, {}
    for mid in sorted(maps):
        if int(maps[mid]["Type"]) != ZONE or mid not in art_of:
            continue
        art = art_of[mid]
        ovs = sorted(overlays.get(art, []), key=lambda r: int(r["ID"]))
        if not ovs:
            continue
        mask = Image.new("L", (QW, QH), 0)
        d = ImageDraw.Draw(mask)
        plist = []
        for o in ovs:
            l, t, r, b = (int(o["HitRectLeft"]), int(o["HitRectTop"]), int(o["HitRectRight"]), int(o["HitRectBottom"]))
            if r > l and b > t:
                d.rectangle((l / Q, t / Q, r / Q, b / Q), fill=255)
            tl = [f for _, _, f in sorted(otiles[int(o["ID"])])]
            if tl:
                plist.append([int(o["TextureWidth"]), int(o["TextureHeight"]), int(o["OffsetX"]), int(o["OffsetY"])] + tl)
        if not mask.getbbox() or not plist:
            continue
        mask = mask.filter(ImageFilter.MaxFilter((GROW // Q) * 2 + 1)).filter(ImageFilter.GaussianBlur(BLUR / Q))
        mask = Image.composite(mask, Image.new("L", mask.size, 0), edge_fade())
        small = mask.resize((SIZE, SIZE), Image.LANCZOS)
        files["%d.tga" % mid] = tga(small)
        bb = mask.point(lambda v: 255 if v > 128 else 0).getbbox() or mask.getbbox()
        outline[mid] = (round((bb[0] + bb[2]) / 2 / QW, 3), round((bb[1] + bb[3]) / 2 / QH, 3))
        pieces[art] = plist
    files["city.tga"] = tga(city_mask())
    out = ["-- MelloUI Map's data, made by Tools/build_map_data.py from the client's own tables (WoWExport/db2):",
           "-- numbers only; never edit by hand (run the tool). docs/plans/seamless-map.md, stage M2.",
           "local _, ns = ...",
           "ns.MapData = {",
           "\t-- [uiMapID] = { x, y }: where a zone's name goes (0..1 of its art); a zone with one has an outline mask",
           "\toutline = {"]
    for mid in sorted(outline):
        out.append("\t\t[%d] = { %s, %s }," % (mid, outline[mid][0], outline[mid][1]))
    out += ["\t},",
            "\t-- [uiMapArtID] = { { w, h, x, y, fileID ... } }: every piece of the zone's map, explored or not",
            "\tpieces = {"]
    for art in sorted(pieces):
        out.append("\t\t[%d] = { %s }," % (art, ", ".join("{ " + ", ".join(str(v) for v in p) + " }" for p in pieces[art])))
    out += ["\t},", "}", ""]
    return "\n".join(out), files


def main():
    check = "--check" in sys.argv[1:]
    lua, files = build()
    stale = []
    want = [(DATA, lua.encode("utf-8"))] + [(os.path.join(OUTLINES, n), b) for n, b in sorted(files.items())]
    want.append((GRAIN, grain()))
    for path, data in want:
        old = open(path, "rb").read() if os.path.isfile(path) else None
        if old != data:
            stale.append(os.path.relpath(path, ROOT))
            if not check:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, "wb").write(data)
    if check:
        print("map data: %s" % ("up to date" if not stale else "%d stale: %s" % (len(stale), ", ".join(stale[:5]))))
        sys.exit(1 if stale else 0)
    print("map data: %d outlines, %d files written" % (len(files) - 1, len(stale)))


if __name__ == "__main__":
    main()
