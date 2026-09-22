"""
cut_panels.py -- full-bleed picture sheets (no magenta key): a row of panels
separated by dark seam columns, cut on the seams and written as kit pieces.

  backdrops/<name>        the painted panel (colour)
  backdrops/<name>_grey   the same panel in greyscale, for SetVertexColor tints

Each panel is resized to 512 x 1024 (power of two both ways: it goes into the
client as is). Sheet ids are the first 8 chars of ChatGPT's file names.
"""
import os, glob, json
import numpy as np
from PIL import Image

SRC = r"C:\Users\mortu\Downloads\UITest"
KIT = os.path.join(SRC, "kit", "v2_2x")
OUT_W, OUT_H = 512, 1024

SHEETS = {
    # profession still-lifes: cooking (cauldron), fishing (rod, net, fish), first aid (bandages, kit)
    "b1cfc38a": ("", ["backdrops/profession_cooking", "backdrops/profession_fishing", "backdrops/profession_firstaid"]),
    "7f170056": ("_grey", ["backdrops/profession_cooking", "backdrops/profession_fishing", "backdrops/profession_firstaid"]),
}


def seams(a):
    """column ranges darker than everything else: the painted dividers."""
    lum = a[..., :3].mean(axis=2).mean(axis=0)
    dark = np.where(lum < 4)[0]
    runs = []
    for c in dark:
        if runs and c == runs[-1][1] + 1:
            runs[-1][1] = c
        else:
            runs.append([c, c])
    return runs


def main():
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))
    for sid, (suffix, names) in SHEETS.items():
        files = glob.glob(os.path.join(SRC, sid + "*.png"))
        if not files:
            print(f"{sid}: sheet not found"); continue
        im = Image.open(files[0]).convert("RGBA")
        a = np.array(im)
        runs = seams(a)
        edges = [0] + [r[1] + 1 for r in runs] + [im.width]
        starts = [0] + [r[1] + 1 for r in runs]
        ends = [r[0] for r in runs] + [im.width]
        if len(starts) != len(names):
            print(f"{sid}: {len(starts)} panels found, {len(names)} names"); continue
        for name, x0, x1 in zip(names, starts, ends):
            panel = im.crop((x0, 0, x1, im.height)).resize((OUT_W, OUT_H), Image.LANCZOS)
            out = os.path.join(KIT, name + suffix + ".png")
            os.makedirs(os.path.dirname(out), exist_ok=True)
            panel.save(out)
            man[f"v2_2x/{name}{suffix}"] = { "w": OUT_W, "h": OUT_H, "scale": 1.0, "src": f"{sid} panel {x0}-{x1}" }
            print(f"{name}{suffix}: columns {x0}-{x1} -> {OUT_W}x{OUT_H}")
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
