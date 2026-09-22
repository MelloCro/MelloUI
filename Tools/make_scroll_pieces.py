"""
make_scroll_pieces.py -- the kit pieces a vertical scroll bar needs (the user's
pick T2 / H1: dark trough track, gem-slab thumb).

  bars/trough_v                      the bar trough stood upright (tiles in y)
  lists/scrollthumb_cap_t_<state>    the thumb's top gem cap
  lists/scrollthumb_mid_<state>      the slab between the gems (tiles in y)
  lists/scrollthumb_cap_b_<state>    the bottom gem cap
    states: normal (the dark slab), hover (the red slab; also used pressed)

Writes into kit/v2_2x and updates manifest.json; run build_kit.py after.
"""
import os, json
import numpy as np
from PIL import Image

KIT = r"C:\Users\mortu\Downloads\UITest\kit\v2_2x"
CAP = 46            # px at 2x: the gem cap of the 152 px thumb (gem + bezel)
THUMBS = { "normal": "scrollthumb_normal", "hover": "scrollthumb_hover_b" }


def main():
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))

    trough = Image.open(os.path.join(KIT, "bars", "trough.png")).convert("RGBA")
    v = trough.rotate(90, expand=True)                  # the left end at the bottom: irrelevant, it tiles
    v.save(os.path.join(KIT, "bars", "trough_v.png"))
    man["v2_2x/bars/trough_v"] = { "w": v.width, "h": v.height, "scale": man.get("v2_2x/bars/trough", {}).get("scale", 1), "src": "bars/trough turned upright" }
    print(f"bars/trough_v: {v.width}x{v.height}")

    for state, src in THUMBS.items():
        im = Image.open(os.path.join(KIT, "lists", src + ".png")).convert("RGBA")
        W, H = im.size
        parts = {
            "cap_t": im.crop((0, 0, W, CAP)),
            "mid": im.crop((0, CAP, W, H - CAP)),
            "cap_b": im.crop((0, H - CAP, W, H)),
        }
        for part, piece in parts.items():
            name = f"lists/scrollthumb_{part}_{state}"
            piece.save(os.path.join(KIT, name + ".png"))
            man["v2_2x/" + name] = { "w": piece.width, "h": piece.height, "scale": man.get("v2_2x/lists/" + src, {}).get("scale", 1), "src": f"{src} rows" }
            print(f"{name}: {piece.width}x{piece.height}")
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
