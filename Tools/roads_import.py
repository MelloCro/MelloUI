#!/usr/bin/env python3
"""
Bring a road recording from the game into the road data: the capitals' own
maps draw no roads, so their streets are walked in game with the road
recorder (/route record, Modules/RouteRecorder.lua) and its Export text is
read here into Tools/roads/recorded.json, where Tools/trace_roads.py bake
lays them as the city's streets. docs/plans/city-road-recorder.md.

  python Tools/roads_import.py recording.txt                 each city in the text replaces its record
  python Tools/roads_import.py recording.txt --png out.png   and a preview over the city's map art
  python Tools/roads_import.py --list                        what is recorded, per city
  python Tools/roads_import.py --drop 1453                   forget a city's record

The text runs from "MelloUI road recording 1" to "end" (several cities may
follow each other): `city <id> <name>`, `done yes|no`, one `stretch <continent>
<x,y> ...` line per stretch, `mark <kind> <continent> <x,y> [note]`; x, y are
continent fractions times 1e6. A line of x,y pairs alone goes on the stretch
before it (a paste that broke a long line).

Then: python Tools/trace_roads.py bake
"""
import argparse
import json
import math
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
RECORDED = os.path.join(HERE, "roads", "recorded.json")
ROADDATA = os.path.join(ROOT, "MelloUI_Companion", "RoadData.lua")
SCALE = 1000000
HEADER = "MelloUI road recording"
VERSION = "1"
PAIR = re.compile(r"^-?\d+,-?\d+$")


def sizes():
    """The continents' sizes in yards, as the road data has them ({uiMapID: (width, height)})."""
    out = {}
    with open(ROADDATA, encoding="utf-8") as fh:
        head = fh.read(4000)
    block = head[head.index("sizes = {"):]
    for cid, w, h in re.findall(r"\[(\d+)\] = \{ ([\d.]+), ([\d.]+) \}", block[:block.index("},\n\twalk")]):
        out[int(cid)] = (float(w), float(h))
    return out


def parse(text):
    """The recordings in a text: [{id, name, done, stretches: [{cont, points}], marks: [{kind, cont, at, note}]}]."""
    out, cur = [], None
    for raw in text.splitlines():
        ln = raw.strip()
        if not ln:
            continue
        if ln.startswith(HEADER):
            if cur is not None:
                raise SystemExit("a recording starts before the one above it ended: copied whole?")
            if ln.split()[-1] != VERSION:
                raise SystemExit("unknown recording version: " + ln)
            cur = {"id": None, "name": "", "done": False, "stretches": [], "marks": []}
            continue
        if cur is None:
            continue
        word, _, rest = ln.partition(" ")
        if word == "city":
            cid, _, name = rest.partition(" ")
            cur["id"], cur["name"] = int(cid), name
        elif word == "done":
            cur["done"] = rest.strip() == "yes"
        elif word == "stretch":
            parts = rest.split()
            cur["stretches"].append({"cont": int(parts[0]), "points": [pair(p) for p in parts[1:]]})
        elif word == "mark":
            parts = rest.split(" ", 3)
            cur["marks"].append({"kind": parts[0], "cont": int(parts[1]), "at": pair(parts[2]),
                                 "note": parts[3] if len(parts) > 3 else ""})
        elif word == "end":
            if cur["id"] is None:
                raise SystemExit("a recording without its city line")
            cur["stretches"] = [s for s in cur["stretches"] if len(s["points"]) >= 2]
            out.append(cur)
            cur = None
        elif all(PAIR.match(p) for p in ln.split()) and cur["stretches"]:
            cur["stretches"][-1]["points"] += [pair(p) for p in ln.split()]
        else:
            raise SystemExit("a line the recorder never writes: " + ln[:80])
    if cur is not None:
        raise SystemExit("the text ends before its 'end' line: copied whole?")
    return out


def pair(text):
    x, y = text.split(",")
    return [int(x) / SCALE, int(y) / SCALE]


def length(points, size):
    w, h = size
    return sum(math.hypot((b[0] - a[0]) * w, (b[1] - a[1]) * h) for a, b in zip(points, points[1:]))


def load():
    if not os.path.exists(RECORDED):
        return {"cities": {}}
    with open(RECORDED, encoding="utf-8") as fh:
        return json.load(fh)


def save(data):
    """One line per stretch and mark, so a city walked again diffs by its streets."""
    out = ["{", '"cities": {']
    cities = sorted(data["cities"].items(), key=lambda kv: int(kv[0]))
    for ci, (cid, c) in enumerate(cities):
        out.append(f'"{cid}": {{"name": {json.dumps(c["name"])}, "done": {json.dumps(c["done"])}, '
                   f'"imported": {json.dumps(c.get("imported", ""))},')
        out.append('"stretches": [')
        for si, s in enumerate(c["stretches"]):
            pts = ",".join(f"[{x:.6f},{y:.6f}]" for x, y in s["points"])
            out.append(f'{{"cont": {s["cont"]}, "points": [{pts}]}}' + ("," if si < len(c["stretches"]) - 1 else ""))
        out.append("],")
        out.append('"marks": [')
        for mi, m in enumerate(c["marks"]):
            out.append(f'{{"kind": {json.dumps(m["kind"])}, "cont": {m["cont"]}, '
                       f'"at": [{m["at"][0]:.6f},{m["at"][1]:.6f}], "note": {json.dumps(m["note"])}}}'
                       + ("," if mi < len(c["marks"]) - 1 else ""))
        out.append("]}" + ("," if ci < len(cities) - 1 else ""))
    out += ["}", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)   # (never write what the bake could not read)
    with open(RECORDED, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def summary(c, size):
    total = sum(length(s["points"], size.get(s["cont"], (0, 0))) for s in c["stretches"])
    points = sum(len(s["points"]) for s in c["stretches"])
    kinds = {}
    for m in c["marks"]:
        kinds[m["kind"]] = kinds.get(m["kind"], 0) + 1
    marks = ", ".join(f"{n} {k}" for k, n in sorted(kinds.items())) or "no marks"
    return (f"{c['name']}: {len(c['stretches'])} stretches, {points} points, {total:.0f} yd, {marks}"
            + (", done" if c["done"] else ""))


def preview(c, path):
    """The city's stretches (red) and marks over its map art from the trace's cache."""
    sys.path.insert(0, HERE)
    import trace_roads as tr
    from PIL import Image, ImageDraw
    zones, conts = tr.load_zones({c["id"]})
    if not zones:
        raise SystemExit(f"no zone {c['id']} in the map data")
    z = zones[0]
    cont = conts[z["cont"]]
    art = tr.zone_image_path(z)
    img = Image.open(art).convert("RGB") if os.path.exists(art) else Image.new("RGB", (z["width"], z["height"]), (40, 36, 30))
    scale = min(1.0, 1600 / img.width)
    img = img.resize((int(img.width * scale), int(img.height * scale)))
    d = ImageDraw.Draw(img)

    def px(fx, fy):
        wy = cont["y1"] - fx * cont["width"]
        wx = cont["x1"] - fy * cont["height"]
        u = (z["y1"] - wy) / (z["y1"] - z["y0"])
        v = (z["x1"] - wx) / (z["x1"] - z["x0"])
        return u * img.width, v * img.height
    for s in c["stretches"]:
        pts = [px(*p) for p in s["points"]]
        d.line(pts, fill=(220, 40, 30), width=4)
        d.ellipse([pts[0][0] - 5, pts[0][1] - 5, pts[0][0] + 5, pts[0][1] + 5], outline=(255, 255, 255), width=2)
    for m in c["marks"]:
        x, y = px(*m["at"])
        d.rectangle([x - 6, y - 6, x + 6, y + 6], fill=(20, 20, 20))
        d.text((x + 9, y - 7), m["kind"] + (": " + m["note"] if m["note"] else ""), fill=(20, 20, 20))
    img.save(path)
    print(f"preview -> {path}" + ("" if os.path.exists(art) else " (no map art in the cache: trace_roads.py fetch/assemble)"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("text", nargs="?", help="a file with the recorder's Export text (- for stdin)")
    ap.add_argument("--png", help="a preview of the (last) city imported, over its map art")
    ap.add_argument("--list", action="store_true", help="what is recorded")
    ap.add_argument("--drop", type=int, action="append", help="forget this city's record (uiMapID)")
    a = ap.parse_args()
    size = sizes()
    data = load()
    if a.drop:
        for cid in a.drop:
            print(("dropped " if data["cities"].pop(str(cid), None) else "nothing recorded for ") + str(cid))
        save(data)
    if a.text:
        text = sys.stdin.read() if a.text == "-" else open(a.text, encoding="utf-8-sig").read()
        found = parse(text)
        if not found:
            raise SystemExit("no recording in the text (it starts with '" + HEADER + " 1')")
        for c in found:
            c["imported"] = time.strftime("%Y-%m-%d")
            data["cities"][str(c["id"])] = {k: c[k] for k in ("name", "done", "imported", "stretches", "marks")}
            print("imported " + summary(c, size))
        save(data)
        if a.png:
            preview(found[-1], a.png)
    if a.list or not (a.text or a.drop):
        for cid, c in sorted(data["cities"].items(), key=lambda kv: int(kv[0])):
            print(f"{cid} " + summary(c, size) + (f" (imported {c['imported']})" if c.get("imported") else ""))
        if not data["cities"]:
            print("nothing recorded yet")
    if a.text or a.drop:
        print("then: python Tools/trace_roads.py bake")


if __name__ == "__main__":
    main()
